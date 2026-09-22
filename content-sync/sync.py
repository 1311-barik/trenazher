#!/usr/bin/env python3
"""Синхронизация контента тренажёра: Google-таблица + папки Drive → manifest.json + медиа.

Запускается на сервере по таймеру (раз в 10 минут). Женя правит таблицу и папки как раньше —
через несколько минут изменения видны в приложении Андрея.

Что делает:
1. Читает таблицу «Дрон тренировка» (Sheets API) и три папки (Drive API) по read-only API-ключу.
2. Собирает манифест по тем же правилам, что нативная версия (trenazher_content.py).
3. Готовит медиа: фото — уменьшенные JPEG и миниатюры; видео с iPhone (MOV, до ~100 МБ) —
   лёгкий H.264 MP4 и обложка. Файлы с версией в имени: замена файла на Drive = новый файл.
4. Пишет manifest.json атомарно; сначала с фото, затем дописывает видео по мере готовности.
   Если прервали — следующий запуск продолжит с недостающих файлов.

Примеры:
  python3 sync.py                                   # боевой режим, настройки из переменных окружения
  python3 sync.py --csv sheet.csv --files files.json --out ./content --skip-media   # из выгрузки, без сети

Переменные окружения: TRENAZHER_API_KEY, TRENAZHER_SPREADSHEET_ID, TRENAZHER_FOLDER_ID,
TRENAZHER_OUT (папка, которую отдаёт nginx), TRENAZHER_WORK (кэш оригиналов и отчёт).
"""

import argparse
import csv
import fcntl
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Dict, List, Optional

from trenazher_content import (DriveFile, Snapshot, VIDEO_EXTENSIONS, all_media, build_manifest, issue,
                               report_markdown, stable_hash, text_key)

PHOTO_MAX = 1400
THUMB_MAX = 400
VIDEO_MAX = 1280
DOWNLOAD_PAUSE = 3  # секунд между скачиваниями с Drive
FOLDER_NAMES = {"photos": "Фото упражнений", "own": "Женя видео", "other": "Чужие видео"}


def log(message: str) -> None:
    print(time.strftime("%Y-%m-%d %H:%M:%S"), message, flush=True)


# ---------------------------------------------------------------------------
# Google API


class GoogleError(Exception):
    pass


class GoogleThrottled(GoogleError):
    """Google временно ограничил скачивание с этого сервера («Sorry…» вместо файла).
    Продолжать бессмысленно — оставшиеся файлы докачает следующий запуск."""


class GoogleClient:
    def __init__(self, api_key: str):
        self.api_key = api_key

    def _url(self, base: str, query: Dict[str, str]) -> str:
        params = dict(query)
        params["key"] = self.api_key
        return base + "?" + urllib.parse.urlencode(params, quote_via=urllib.parse.quote)

    def get_json(self, base: str, query: Dict[str, str]) -> Dict:
        request = urllib.request.Request(self._url(base, query), headers={"User-Agent": "trenazher-sync"})
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as error:
            body = error.read().decode("utf-8", "replace")[:500]
            if error.code in (401, 403) and "API key" not in body and "API_KEY" not in body:
                raise GoogleError("Нет доступа к таблице или папке: включите «Все, у кого есть ссылка → Читатель».") from error
            if error.code in (400, 401, 403):
                raise GoogleError(f"Google отклонил API-ключ ({error.code}): {body}") from error
            raise GoogleError(f"Google ответил ошибкой {error.code}: {body}") from error
        except urllib.error.URLError as error:
            raise GoogleError(f"Нет связи с Google: {error.reason}") from error

    def download(self, file_id: str, destination: str) -> None:
        """Скачивает файл во временный и атомарно переименовывает."""
        url = self._url(f"https://www.googleapis.com/drive/v3/files/{urllib.parse.quote(file_id)}",
                        {"alt": "media", "acknowledgeAbuse": "true", "supportsAllDrives": "true"})
        partial = destination + ".part"
        request = urllib.request.Request(url, headers={"User-Agent": "trenazher-sync"})
        try:
            with urllib.request.urlopen(request, timeout=300) as response, open(partial, "wb") as out:
                shutil.copyfileobj(response, out, length=1024 * 1024)
        except Exception as error:
            # Недокачанный кусок не оставляем — следующий запуск начнёт этот файл заново.
            if os.path.exists(partial):
                os.remove(partial)
            if isinstance(error, urllib.error.HTTPError):
                if error.code in (403, 429) and "text/html" in (error.headers.get("Content-Type") or ""):
                    raise GoogleThrottled("Google временно ограничил скачивание с сервера") from error
                raise GoogleError(f"Файл {file_id}: ошибка {error.code}") from error
            raise
        os.replace(partial, destination)

    def sheet_titles(self, spreadsheet_id: str) -> List[str]:
        data = self.get_json(f"https://sheets.googleapis.com/v4/spreadsheets/{spreadsheet_id}",
                             {"fields": "sheets.properties(title,index)"})
        sheets = sorted(data.get("sheets", []), key=lambda s: s["properties"].get("index", 0))
        return [s["properties"]["title"] for s in sheets]

    def sheet_values(self, spreadsheet_id: str, title: str) -> List[List[str]]:
        sheet_range = "'" + title.replace("'", "''") + "'"
        data = self.get_json(f"https://sheets.googleapis.com/v4/spreadsheets/{spreadsheet_id}/values/"
                             + urllib.parse.quote(sheet_range, safe=""),
                             {"majorDimension": "ROWS", "valueRenderOption": "FORMATTED_VALUE"})
        return data.get("values", [])

    def list_folder(self, folder_id: str) -> List[DriveFile]:
        files: List[DriveFile] = []
        token: Optional[str] = None
        while True:
            query = {"q": f"'{folder_id}' in parents and trashed = false",
                     "fields": "nextPageToken,files(id,name,mimeType,md5Checksum,modifiedTime,size)",
                     "pageSize": "1000", "supportsAllDrives": "true", "includeItemsFromAllDrives": "true"}
            if token:
                query["pageToken"] = token
            data = self.get_json("https://www.googleapis.com/drive/v3/files", query)
            files += [DriveFile.from_json(item) for item in data.get("files", [])]
            token = data.get("nextPageToken")
            if not token:
                return files


def fetch_snapshot(client: GoogleClient, spreadsheet_id: str, folder_id: str) -> Snapshot:
    issues = []
    titles = client.sheet_titles(spreadsheet_id)
    if not titles:
        raise GoogleError("В таблице нет листов.")
    exercise_rows = client.sheet_values(spreadsheet_id, titles[0])
    workout_sheet = next((t for t in titles[1:] if "трениров" in text_key(t)), None)
    workout_rows = client.sheet_values(spreadsheet_id, workout_sheet) if workout_sheet else []

    root = client.list_folder(folder_id)

    def files_in(name: str) -> List[DriveFile]:
        folder = next((f for f in root if f.is_folder and text_key(f.name) == text_key(name)), None)
        if folder is None:
            issues.append(issue("error", f"В папке на Drive не найдена подпапка «{name}»."))
            return []
        return [f for f in client.list_folder(folder.id) if not f.is_folder]

    return Snapshot(exercise_rows=exercise_rows, workout_rows=workout_rows, photos=files_in(FOLDER_NAMES["photos"]),
                    own_videos=files_in(FOLDER_NAMES["own"]), other_videos=files_in(FOLDER_NAMES["other"]), issues=issues)


def snapshot_from_files(csv_path: str, files_path: Optional[str], workouts_csv: Optional[str]) -> Snapshot:
    with open(csv_path, encoding="utf-8") as f:
        rows = list(csv.reader(f))
    workout_rows: List[List[str]] = []
    if workouts_csv:
        with open(workouts_csv, encoding="utf-8") as f:
            workout_rows = list(csv.reader(f))
    listing = {"photos": [], "ownVideos": [], "otherVideos": []}
    if files_path:
        with open(files_path, encoding="utf-8") as f:
            listing = json.load(f)
    to_files = lambda items: [DriveFile.from_json(i) for i in items]  # noqa: E731
    return Snapshot(exercise_rows=rows, workout_rows=workout_rows, photos=to_files(listing["photos"]),
                    own_videos=to_files(listing["ownVideos"]), other_videos=to_files(listing["otherVideos"]))


# ---------------------------------------------------------------------------
# Медиа


def media_stem(item: Dict) -> str:
    return f"{item['driveFileId']}_{stable_hash(item['version'])}"


def media_paths(item: Dict) -> Dict[str, str]:
    """Пути относительно папки контента. Имя с версией — кэш на устройстве не устаревает."""
    stem = media_stem(item)
    if item["kind"] == "photo":
        return {"url": f"media/photos/{stem}.jpg", "thumbUrl": f"media/thumbs/{stem}.jpg"}
    return {"url": f"media/videos/{stem}.mp4", "posterUrl": f"media/posters/{stem}.jpg"}


def process_photo(original: str, out_dir: str, paths: Dict[str, str]) -> None:
    from PIL import Image, ImageOps  # на сервере: apt install python3-pil

    with Image.open(original) as image:
        image = ImageOps.exif_transpose(image).convert("RGB")
        for key, limit in (("url", PHOTO_MAX), ("thumbUrl", THUMB_MAX)):
            copy = image.copy()
            copy.thumbnail((limit, limit))
            target = os.path.join(out_dir, paths[key])
            os.makedirs(os.path.dirname(target), exist_ok=True)
            tmp = target + ".tmp.jpg"
            copy.save(tmp, "JPEG", quality=82, progressive=True, optimize=True)
            os.replace(tmp, target)


def process_video(original: str, out_dir: str, paths: Dict[str, str]) -> None:
    """MOV/HEVC с iPhone → H.264 MP4 (длинная сторона ≤ 1280) + обложка. С низким приоритетом:
    на сервере живут и другие сайты."""
    target = os.path.join(out_dir, paths["url"])
    poster = os.path.join(out_dir, paths["posterUrl"])
    os.makedirs(os.path.dirname(target), exist_ok=True)
    os.makedirs(os.path.dirname(poster), exist_ok=True)
    tmp = target + ".tmp.mp4"
    scale = (f"scale='if(gt(iw,ih),min({VIDEO_MAX},iw),-2)':'if(gt(iw,ih),-2,min({VIDEO_MAX},ih))'")
    subprocess.run(["nice", "-n", "19", "ffmpeg", "-y", "-loglevel", "error", "-i", original,
                    "-vf", scale, "-c:v", "libx264", "-preset", "veryfast", "-crf", "27", "-pix_fmt", "yuv420p",
                    "-c:a", "aac", "-b:a", "96k", "-movflags", "+faststart", "-threads", "2", tmp], check=True)
    os.replace(tmp, target)
    tmp_poster = poster + ".tmp.jpg"
    for seek in ("1", "0"):
        result = subprocess.run(["nice", "-n", "19", "ffmpeg", "-y", "-loglevel", "error", "-ss", seek, "-i", target,
                                 "-frames:v", "1", "-vf", f"scale='min({THUMB_MAX * 2},iw)':-2", "-q:v", "4", tmp_poster])
        if result.returncode == 0 and os.path.exists(tmp_poster):
            os.replace(tmp_poster, poster)
            return


def is_ready(item: Dict, out_dir: str) -> bool:
    return all(os.path.exists(os.path.join(out_dir, p)) for p in media_paths(item).values())


def decorate(manifest: Dict, out_dir: str) -> Dict:
    """Добавляет к медиа адреса файлов и признак готовности; размер — уже обработанного файла."""
    for exercise in manifest["exercises"]:
        for item in exercise["photos"] + exercise["videos"]:
            item.update(media_paths(item))
            item["ready"] = is_ready(item, out_dir)
            if item["ready"]:
                item["byteSize"] = os.path.getsize(os.path.join(out_dir, item["url"]))
    return manifest


def write_json_atomic(path: str, data: Dict) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".manifest-", suffix=".json")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)


def remove_unreferenced(manifest: Dict, out_dir: str, work_dir: str) -> None:
    keep = set()
    keep_originals = set()
    for item in all_media(manifest):
        keep.update(os.path.normpath(os.path.join(out_dir, p)) for p in media_paths(item).values())
        keep_originals.add(media_stem(item))
    for sub in ("photos", "thumbs", "videos", "posters"):
        folder = os.path.join(out_dir, "media", sub)
        for name in os.listdir(folder) if os.path.isdir(folder) else []:
            path = os.path.normpath(os.path.join(folder, name))
            if path not in keep:
                os.remove(path)
    originals = os.path.join(work_dir, "originals")
    for name in os.listdir(originals) if os.path.isdir(originals) else []:
        if os.path.splitext(name)[0] not in keep_originals:
            os.remove(os.path.join(originals, name))


def process_media(client: Optional[GoogleClient], manifest: Dict, out_dir: str, work_dir: str) -> int:
    """Фото, потом видео (сначала Женины и маленькие). Манифест переписывается по мере готовности."""
    media = [m for m in all_media(manifest) if not is_ready(m, out_dir)]
    photos = [m for m in media if m["kind"] == "photo"]
    videos = sorted([m for m in media if m["kind"] != "photo"],
                    key=lambda m: (m["kind"] != "ownVideo", m.get("byteSize") or 0))
    failures = 0
    originals = os.path.join(work_dir, "originals")
    os.makedirs(originals, exist_ok=True)
    manifest_path = os.path.join(out_dir, "manifest.json")

    for index, item in enumerate(photos + videos):
        photos_done = index == len(photos) and videos
        if photos_done:
            # Все фото обработаны — публикуем манифест сразу, не дожидаясь долгого пережатия видео.
            write_json_atomic(manifest_path, decorate(manifest, out_dir))
        original = os.path.join(originals, f"{media_stem(item)}.{item['fileExtension'] or 'bin'}")
        try:
            if not os.path.exists(original):
                if client is None:
                    raise GoogleError("нет API-ключа для скачивания")
                client.download(item["driveFileId"], original)
                time.sleep(DOWNLOAD_PAUSE)  # не частим — иначе Google временно блокирует скачивание
            if item["kind"] == "photo" and item["fileExtension"] not in VIDEO_EXTENSIONS:
                process_photo(original, out_dir, media_paths(item))
            else:
                process_video(original, out_dir, media_paths(item))
                write_json_atomic(manifest_path, decorate(manifest, out_dir))
            log(f"готово {index + 1}/{len(media)}: {item['title']}")
        except GoogleThrottled:
            left = len(media) - index
            failures += left
            manifest["issues"].append(issue("info", f"Google временно ограничил скачивание: {left} файлов докачаются при следующей синхронизации."))
            log(f"Google временно ограничил скачивание — осталось {left}, продолжу при следующем запуске")
            break
        except Exception as error:  # один файл не должен останавливать остальные
            failures += 1
            manifest["issues"].append(issue("warning", f"Файл «{item['title']}» не обработан: {error}. Повторю при следующей синхронизации."))
            log(f"ошибка: {item['title']}: {error}")
    return failures


# ---------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", default=os.environ.get("TRENAZHER_OUT", "./content"))
    parser.add_argument("--work", default=os.environ.get("TRENAZHER_WORK", "./work"))
    parser.add_argument("--csv", help="выгрузка листа упражнений вместо Google")
    parser.add_argument("--workouts-csv", help="выгрузка листа «Тренировки»")
    parser.add_argument("--files", help="JSON со списком файлов папок (для --csv)")
    parser.add_argument("--skip-media", action="store_true", help="только манифест, без скачивания и обработки медиа")
    args = parser.parse_args()

    os.makedirs(args.work, exist_ok=True)
    lock = open(os.path.join(args.work, "sync.lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        log("предыдущая синхронизация ещё идёт — пропускаю")
        return 0

    client: Optional[GoogleClient] = None
    try:
        if args.csv:
            snapshot = snapshot_from_files(args.csv, args.files, args.workouts_csv)
        else:
            api_key = os.environ.get("TRENAZHER_API_KEY", "")
            spreadsheet = os.environ.get("TRENAZHER_SPREADSHEET_ID", "")
            folder = os.environ.get("TRENAZHER_FOLDER_ID", "")
            if not (api_key and spreadsheet and folder):
                log("не заданы TRENAZHER_API_KEY / TRENAZHER_SPREADSHEET_ID / TRENAZHER_FOLDER_ID")
                return 2
            client = GoogleClient(api_key)
            snapshot = fetch_snapshot(client, spreadsheet, folder)
    except GoogleError as error:
        # Прежний manifest.json остаётся — приложение продолжает работать со старым контентом.
        log(f"не удалось прочитать Google: {error}")
        return 1

    manifest = build_manifest(snapshot)
    log(f"манифест: {len(manifest['exercises'])} упражнений, {len(manifest['workouts'])} тренировок, "
        f"{len(manifest['issues'])} замечаний")
    failures = 0
    if not args.skip_media:
        failures = process_media(client, manifest, args.out, args.work)
    write_json_atomic(os.path.join(args.out, "manifest.json"), decorate(manifest, args.out))
    with open(os.path.join(args.work, "content-report.md"), "w", encoding="utf-8") as f:
        f.write(report_markdown(manifest))
    if failures == 0 and not args.skip_media:
        remove_unreferenced(manifest, args.out, args.work)
    log(f"готово, ошибок файлов: {failures}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
