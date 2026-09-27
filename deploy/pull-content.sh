#!/bin/zsh
# Подтянуть контент Жени по команде: синхронизация таблицы и папок Drive на сервере.
# С 2026-09-27 автоматического таймера нет — изменения попадают к Андрею только после этого скрипта.
# Запуск с Mac: ./deploy/pull-content.sh
set -euo pipefail
cd "$(dirname "$0")/.."
SERVER=root@135.181.197.13
SSH=(ssh -o BatchMode=yes -i ~/.ssh/familybot)
MANIFEST_URL=https://trenazher-135-181-197-13.nip.io/content/manifest.json
BEFORE=$(mktemp) AFTER=$(mktemp)
trap 'rm -f "$BEFORE" "$AFTER"' EXIT

curl -fsS "$MANIFEST_URL" -o "$BEFORE"

# Google временно блокирует массовое скачивание (~30 файлов подряд) — тогда ждём и докачиваем.
# Больше шести заходов не делаем: если не докачалось за час, разбираться руками.
for attempt in 1 2 3 4 5 6; do
  echo "Синхронизация, заход $attempt…"
  "${SSH[@]}" "$SERVER" 'systemctl start trenazher-sync.service'
  LOG=$("${SSH[@]}" "$SERVER" 'journalctl -u trenazher-sync -n 15 -o cat')
  print -r -- "$LOG" | grep -E "манифест|готово,|не удалось|ошибк" | tail -3
  if print -r -- "$LOG" | grep -q "ограничил скачивание"; then
    echo "Google притормозил скачивание — жду 10 минут и докачиваю остальное."
    sleep 600
    continue
  fi
  break
done

curl -fsS "$MANIFEST_URL" -o "$AFTER"
python3 - "$BEFORE" "$AFTER" <<'PY'
import json, sys
before, after = (json.load(open(p)) for p in sys.argv[1:3])

def names(m, key, field):
    return {x[field] for x in m[key]}

print("\n=== Что изменилось ===")
for key, field, title in (("exercises", "name", "Упражнения"), ("workouts", "title", "Тренировки")):
    added = sorted(names(after, key, field) - names(before, key, field))
    removed = sorted(names(before, key, field) - names(after, key, field))
    if added: print(f"{title}: добавлены — {', '.join(added)}")
    if removed: print(f"{title}: убраны — {', '.join(removed)}")
media = lambda m: {(x["driveFileId"], x["version"]) for e in m["exercises"] for x in e["photos"] + e["videos"]}
new_media = media(after) - media(before)
print(f"Новых или заменённых файлов: {len(new_media)}")
if before.get("contentVersion") == after.get("contentVersion"):
    print("Контент не менялся.")

ex = after["exercises"]
print("\n=== Сейчас у Андрея ===")
print(f"Упражнений: {len(ex)}; тренировки: " + ", ".join(f"«{w['title']}» — {len(w['exerciseIds'])}" for w in after["workouts"]))
print(f"Фото: {sum(len(e['photos']) for e in ex)}, видео: {sum(len(e['videos']) for e in ex)}; "
      f"без фото: {sum(1 for e in ex if not e['photos'])}, без видео: {sum(1 for e in ex if not e['videos'])}")
pending = sum(1 for e in ex for x in e["photos"] + e["videos"] if not x.get("ready"))
if pending: print(f"Ещё обрабатываются на сервере: {pending}")

warnings = [i["message"] for i in after["issues"] if i["severity"] in ("error", "warning")]
print(f"\n=== Нужно поправить ({len(warnings)}) ===")
for w in warnings: print("•", w)
PY
