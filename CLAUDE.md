# CLAUDE.md — Тренажёр для Андрея

Правила работы с этим репозиторием для Claude и других агентов. Общие правила Александра — `~/Claude-Workspace/CLAUDE.md` (общение по-русски, «действуй → докладывай», без заглушек).

## Перед началом

1. `docs/HANDOFF.md` — состояние, сервер, частые проблемы.
2. `docs/CHANGELOG.md` — что и почему уже решено. Принятые решения без нового повода не пересматривать: веб вместо нативной версии, без платного Apple Developer.
3. Для любых изменений интерфейса — `docs/PRODUCT_USABILITY_PROFILE.md` и стандарт `docs/USABILITY_STANDARD.md`; цвета, шрифты и визуальные приёмы — `design-system/trenazher/MASTER.md` (там же сказано, что из рекомендаций скилла принято, а что заменено).

## Стек и команды

| Часть | Стек | Проверка |
|---|---|---|
| `web-app/` | React 18 + TypeScript + Vite 5 + vite-plugin-pwa (injectManifest). Цель сборки `safari14` | `npm test`, `npm run build` (включает `tsc`) |
| `content-sync/` | Python 3.9+ (Mac) / 3.12 (сервер), только stdlib + Pillow + ffmpeg | `python3 -m unittest discover -s tests -v` |
| `ios-app/` | SwiftUI, iOS 14+, пакет TrenazherKit + XcodeGen. Заморожено | `ios-app/TrenazherKit/run-tests.sh` |

Выкладка — `./deploy/deploy.sh` (сборка + rsync на `root@135.181.197.13`, ключ `~/.ssh/familybot`).

## Правила

- Код — английские имена, комментарии — по-русски. Тексты интерфейса — по-русски, без канцелярита.
- Секреты не коммитить и не просить в чат. API-ключ Google вводит владелец сам командой `trenazher-set-key` на сервере. Никогда не вписывать ключи и пароли за пользователя.
- Формат `manifest.json` и ID упражнений общие для Python (`trenazher_content.py`) и Swift (`TrenazherKit`). Меняешь правило разбора или сопоставления — меняешь в обоих местах и в тестах.
- Сопоставление файлов только однозначное. Похожие названия — подсказки в отчёте, не автопривязка (стандарт §8.7).
- React-эффекты — только с блочным телом `useEffect(() => { … })`: выражение-тело уже роняло приложение.
- У каждого прямого действия пользователя есть обратное (стандарт §4). Сбой не должен оставлять пустой экран.
- Сервер общий с другими сайтами: трогаем только своё (`/var/www/trenazher`, `/opt/trenazher`, `/var/lib/trenazher`, `sites-available/trenazher`), `nginx -t` перед `reload`.
- Не качать с Drive массово в обход паузы в `sync.py` — Google временно блокирует сервер.

## Agent skills

Настройка инженерных скиллов (набор mattpocock/skills, стоят в `~/.claude/skills/`). Что для чего — `/ask-matt`.

### Issue tracker

Задачи и спеки — GitHub Issues репозитория `1311-barik/trenazher`, через `gh`. See `docs/agents/issue-tracker.md`.

### Triage labels

Пять стандартных ролей без переименований: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: один `CONTEXT.md` и `docs/adr/` в корне; создаются по мере надобности через `/domain-modeling`. See `docs/agents/domain.md`.

### Usability standard

Поведение интерфейса подчиняется стандарту юзабилити. See `docs/agents/usability.md`.

## После работы

1. Запись в `docs/CHANGELOG.md`: что, почему, какие проблемы.
2. Обновить `docs/HANDOFF.md` и профиль юзабилити, если менялось поведение.
3. Переносимые уроки — в стандарт `~/Claude-Workspace/СТАНДАРТ-ЮЗАБИЛИТИ-ДЛЯ-НОВЫХ-ПРОДУКТОВ.md` (новая версия + changelog), копию — в `docs/USABILITY_STANDARD.md`.
4. Скопировать `docs/` и `README.md` в `~/Claude-Workspace/projects/2026/razovye-proekty/trenazher-dlya-andreya/docs/`.
5. Коммит на русском, осмысленный; `git push`.
