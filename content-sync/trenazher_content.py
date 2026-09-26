"""Разбор таблицы «Дрон тренировка» и сопоставление файлов Drive — чистая логика без сети.

Порт Swift-модуля TrenazherKit (ios-app/TrenazherKit/Sources/TrenazherKit/Content) с тем же
поведением: те же правила сопоставления, те же ID упражнений, те же тексты замечаний.
Совместимо с Python 3.9 (Mac) и 3.12 (сервер), только стандартная библиотека.
"""

import json
import os
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Dict, List, NamedTuple, Optional, Sequence, Set, Tuple

SCHEMA_VERSION = 1


# ---------------------------------------------------------------------------
# Текст


def text_key(text: str) -> str:
    """Ключ сравнения: регистр, «ё», пунктуация и лишние пробелы не важны."""
    lowered = text.lower().replace("ё", "е")
    chars = [ch if ch.isalnum() else " " for ch in lowered]
    return " ".join("".join(chars).split())


def display_name(text: str) -> str:
    """Название для показа: без пробелов и точек в конце («Медвежья планка в динамике.»)."""
    value = text.strip()
    while value.endswith("."):
        value = value[:-1]
    return value.strip()


def non_empty(text: str) -> Optional[str]:
    value = text.strip()
    return value or None


def paragraph_text(text: str) -> str:
    """Описание: пробелы по краям строк убраны, 3+ переноса схлопнуты в одну пустую строку."""
    lines = [line.strip() for line in text.replace("\r\n", "\n").split("\n")]
    result: List[str] = []
    for line in lines:
        if not line and (not result or not result[-1]):
            continue
        result.append(line)
    while result and not result[-1]:
        result.pop()
    return "\n".join(result)


def stable_hash(*parts: str) -> str:
    """FNV-1a 64 — детерминированный короткий хеш для версий и имён файлов."""
    value = 0xCBF29CE484222325
    for byte in "\x1f".join(parts).encode("utf-8"):
        value ^= byte
        value = (value * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return format(value, "x")


def natural_key(text: str):
    """Сортировка «как в Finder»: «Молот 2» < «Молот 10»."""
    return [int(part) if part.isdigit() else part.lower() for part in re.split(r"(\d+)", text)]


def plural(count: int, one: str, few: str, many: str) -> str:
    n = abs(count) % 100
    n1 = n % 10
    if 10 < n < 20:
        return many
    if 1 < n1 < 5:
        return few
    if n1 == 1:
        return one
    return many


# ---------------------------------------------------------------------------
# Замечания


def issue(severity: str, message: str) -> Dict[str, str]:
    return {"severity": severity, "message": message}


SEVERITY_RANK = {"error": 0, "warning": 1, "info": 2}


# ---------------------------------------------------------------------------
# Лист упражнений


@dataclass
class ExerciseRow:
    row_number: int
    body_part: str
    muscle_group: Optional[str]
    name: str
    equipment: Optional[str]
    details: str
    sets: Optional[int]
    photo_cell: str
    other_video_cell: str
    own_video_cell: str


FALLBACK_LAYOUT = {
    "body_part": 0, "muscle_group": 1, "name": 2, "equipment": 3,
    "details": 4, "photos": 5, "other_videos": 6, "own_videos": 7,
}


def column_for_header(header: str) -> Optional[str]:
    """Колонка по заголовку. Порядок проверок важен: «Фото упражнений» — это фото, а не название."""
    key = text_key(header)
    if not key:
        return None
    if "фото" in key:
        return "photos"
    if "чуж" in key:
        return "other_videos"
    if "жен" in key:
        return "own_videos"
    if "описан" in key or "техник" in key:
        return "details"
    if "подход" in key:
        return "sets"
    if "тела" in key or "раздел" in key:
        return "body_part"
    if "мышц" in key:
        return "muscle_group"
    if "гантел" in key or "инвентар" in key or "оборудован" in key:
        return "equipment"
    if "упражнен" in key or key == "название":
        return "name"
    return None


def leading_integer(text: str) -> Optional[int]:
    match = re.search(r"\d+", text)
    return int(match.group(0)) if match else None


def parse_exercise_sheet(rows: Sequence[Sequence[str]]) -> Tuple[List[ExerciseRow], List[Dict[str, str]]]:
    """Лист в том виде, как его ведёт Женя: часть тела и группа мышц — только в первой строке раздела."""
    issues: List[Dict[str, str]] = []
    layout: Dict[str, int] = {}
    header_index: Optional[int] = None
    for index, row in enumerate(rows[:10]):
        candidate: Dict[str, int] = {}
        for column_index, cell in enumerate(row):
            column = column_for_header(cell)
            if column and column not in candidate:
                candidate[column] = column_index
        if "name" in candidate:
            layout, header_index = candidate, index
            break
    if header_index is None:
        layout = dict(FALLBACK_LAYOUT)
        issues.append(issue("warning", "В таблице упражнений не найдена строка заголовков с колонкой «Упражнение» — "
                                       "использую порядок колонок по умолчанию (A–H)."))

    result: List[ExerciseRow] = []
    current_part: Optional[str] = None
    current_group: Optional[str] = None
    first_data_row = (header_index if header_index is not None else -1) + 1

    for index in range(first_data_row, len(rows)):
        row = rows[index]

        def cell(column: str) -> str:
            position = layout.get(column)
            if position is None or position >= len(row):
                return ""
            return row[position]

        part = cell("body_part").strip()
        group = cell("muscle_group").strip()
        if part:
            current_part = part
            current_group = group or None
        elif group:
            current_group = group

        name = display_name(cell("name"))
        if not name:
            continue
        row_number = index + 1
        if current_part is None:
            issues.append(issue("warning", f"Строка {row_number}: у упражнения «{name}» не указана часть тела — упражнение пропущено."))
            continue

        sets: Optional[int] = None
        raw_sets = non_empty(cell("sets"))
        if raw_sets:
            sets = leading_integer(raw_sets)
            if not sets:
                sets = None
                issues.append(issue("warning", f"Строка {row_number}, «{name}»: не понял число подходов «{raw_sets}» — "
                                               "таймер будет без счётчика."))

        result.append(ExerciseRow(
            row_number=row_number, body_part=current_part, muscle_group=current_group, name=name,
            equipment=non_empty(cell("equipment")), details=paragraph_text(cell("details")), sets=sets,
            photo_cell=cell("photos"), other_video_cell=cell("other_videos"), own_video_cell=cell("own_videos"),
        ))

    if not result:
        issues.append(issue("error", "В таблице не найдено ни одного упражнения."))
    return result, issues


# ---------------------------------------------------------------------------
# Лист «Тренировки»


class WorkoutEntry(NamedTuple):
    row_number: int
    name: str
    section: Optional[str]  # раздел, под которым упражнение стоит в тренировке


@dataclass
class WorkoutRow:
    title: str
    summary: Optional[str]
    exercises: List[WorkoutEntry] = field(default_factory=list)


TITLE_PREFIX = re.compile(r"^\s*трениров\w*", re.IGNORECASE)
QUOTED = re.compile(r"[«\"\u201c\u2018\']\s*(.+?)\s*[»\"\u201d\u2019\']")
LEGEND_KEYS = ("ссылка на главный список", "главный список")


def workout_title(cell: str) -> Optional[str]:
    """«Тренировка "Пресс-аташе"» → «Пресс-аташе». Пустое название — не заголовок тренировки."""
    if not TITLE_PREFIX.match(cell):
        return None
    quoted = QUOTED.search(cell)
    if quoted:
        return display_name(quoted.group(1))
    rest = TITLE_PREFIX.sub("", cell, count=1).strip(" :—-–\t")
    return display_name(rest) or None


def parse_workout_blocks(rows: Sequence[Sequence[str]]) -> List[WorkoutRow]:
    """Раскладка блоками, как её ведёт Женя: строка «Тренировка "…"», ниже — раздел,
    название упражнения по-своему и точное название из главного списка в третьей колонке."""
    workouts: List[WorkoutRow] = []
    section: Optional[str] = None
    for index, row in enumerate(rows):
        cells = [cell.strip() for cell in row]
        if not any(cells):
            continue
        title = workout_title(cells[0]) if cells[0] else None
        if title:
            workouts.append(WorkoutRow(title=title, summary=None))
            section = None
            continue
        if any(key in text_key(cell) for cell in cells for key in LEGEND_KEYS):
            continue
        if not workouts:
            continue
        first = cells[0] if cells else ""
        own = cells[1] if len(cells) > 1 else ""
        exact = cells[2] if len(cells) > 2 else ""
        if first and not (own or exact):
            # Только раздел («Попа») — заголовок для следующих строк, не упражнение.
            section = first
            continue
        if first:
            section = first
        name = display_name(exact or own)
        if name:
            workouts[-1].exercises.append(WorkoutEntry(index + 1, name, non_empty(section or "")))
    for workout in workouts:
        # Краткое описание на карточке (ТЗ 4.2): разделы тренировки в том порядке, как их записал автор.
        sections: List[str] = []
        for entry in workout.exercises:
            if entry.section and entry.section not in sections:
                sections.append(entry.section)
        workout.summary = " · ".join(sections) or None
    return workouts


def parse_workout_sheet(rows: Sequence[Sequence[str]]) -> Tuple[List[WorkoutRow], List[Dict[str, str]]]:
    """Две раскладки: таблица с заголовками «Тренировка»/«Упражнение» и блоки Жени."""
    title_col = summary_col = exercise_col = header = None
    for index, row in enumerate(rows[:10]):
        title_col = summary_col = exercise_col = None
        for column_index, cell in enumerate(row):
            key = text_key(cell)
            if "упражнен" in key and exercise_col is None:
                exercise_col = column_index
            elif "описан" in key and summary_col is None:
                summary_col = column_index
            elif ("трениров" in key or key == "название") and title_col is None:
                title_col = column_index
        if title_col is not None and exercise_col is not None:
            header = index
            break

    if header is None:
        has_content = any(cell.strip() for row in rows for cell in row)
        if not has_content:
            return [], []
        blocks = parse_workout_blocks(rows)
        if blocks:
            return blocks, []
        return [], [issue("warning", "Лист «Тренировки»: не удалось разобрать ни одной тренировки. Нужна либо строка "
                                     "заголовков «Тренировка» и «Упражнение», либо строка «Тренировка \"Название\"» "
                                     "и список упражнений под ней.")]

    workouts: List[WorkoutRow] = []
    for index in range(header + 1, len(rows)):
        row = rows[index]

        def cell(column: Optional[int]) -> str:
            if column is None or column >= len(row):
                return ""
            return row[column].strip()

        title = display_name(cell(title_col))
        summary = non_empty(cell(summary_col))
        if title:
            workouts.append(WorkoutRow(title=title, summary=summary))
        elif summary and workouts and workouts[-1].summary is None:
            workouts[-1].summary = summary
        exercise = display_name(cell(exercise_col))
        if exercise and workouts:
            workouts[-1].exercises.append(WorkoutEntry(index + 1, exercise, None))
    return workouts, []


# ---------------------------------------------------------------------------
# Файлы Drive и ячейки с файлами

MEDIA_EXTENSIONS = {"jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "mov", "mp4", "m4v"}
VIDEO_EXTENSIONS = {"mov", "mp4", "m4v"}


@dataclass(frozen=True)
class DriveFile:
    id: str
    name: str
    mime_type: str = ""
    md5: Optional[str] = None
    modified_time: Optional[str] = None
    size: Optional[int] = None

    @property
    def base_name(self) -> str:
        stem, ext = os.path.splitext(self.name)
        if ext[1:].lower() in MEDIA_EXTENSIONS:
            return stem.strip()
        return self.name.strip()

    @property
    def extension(self) -> str:
        ext = os.path.splitext(self.name)[1][1:].lower()
        if ext in MEDIA_EXTENSIONS:
            return ext
        if "quicktime" in self.mime_type:
            return "mov"
        if "mp4" in self.mime_type:
            return "mp4"
        if "png" in self.mime_type:
            return "png"
        if self.mime_type.startswith("image/"):
            return "jpg"
        return ext

    @property
    def is_folder(self) -> bool:
        return self.mime_type == "application/vnd.google-apps.folder"

    @property
    def version(self) -> str:
        return self.md5 or self.modified_time or self.id

    @staticmethod
    def from_json(data: Dict) -> "DriveFile":
        size = data.get("size")
        return DriveFile(id=data["id"], name=data["name"], mime_type=data.get("mimeType", ""),
                         md5=data.get("md5Checksum"), modified_time=data.get("modifiedTime"),
                         size=int(size) if size not in (None, "") else None)


PRESENT_MARKERS = {"есть", "да", "есть файл", "yes"}
DRIVE_ID_PATTERNS = [re.compile(r"/d/([A-Za-z0-9_-]{10,})"), re.compile(r"[?&]id=([A-Za-z0-9_-]{10,})")]
BARE_ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]{25,}$")


def drive_id_in(text: str) -> Optional[str]:
    if "google.com" in text:
        for pattern in DRIVE_ID_PATTERNS:
            match = pattern.search(text)
            if match:
                return match.group(1)
        return None
    if BARE_ID_PATTERN.match(text) and " " not in text:
        return text
    return None


def parse_media_cell(cell: str):
    """('auto', expected) — пусто или «есть»; ('none',) — «нет»; ('explicit', [('id'|'name', value)])."""
    text = cell.strip()
    if not text:
        return ("auto", False)
    if text == "+":
        return ("auto", True)
    if text in ("-", "—", "–"):
        return ("none",)
    key = text_key(text)
    if key in PRESENT_MARKERS:
        return ("auto", True)
    if key == "нет" or key.startswith("нет "):
        return ("none",)
    tokens = [token.strip() for token in re.split(r"[\n;]", text) if token.strip()]
    references = []
    for token in tokens:
        file_id = drive_id_in(token)
        references.append(("id", file_id) if file_id else ("name", token))
    return ("explicit", references) if references else ("auto", False)


NUMBERING_SUFFIX = re.compile(r"[\s.]*((вар|вариант)\.?\s*)?\d+\s*$", re.IGNORECASE)
STOP_WORDS = {"в", "во", "с", "со", "на", "из", "за", "под", "от", "к", "ко", "и", "для", "по", "до", "у"}


def title_keys(title: str, strip_numbering: bool) -> Set[str]:
    """Ключи имени файла: целиком и без ведущих «Раздел.» приставок."""
    base = NUMBERING_SUFFIX.sub("", title) if strip_numbering else title
    segments = [segment.strip() for segment in base.split(".") if segment.strip()]
    keys = set()
    for start in range(len(segments)):
        key = text_key(" ".join(segments[start:]))
        if key:
            keys.add(key)
    return keys


def stems(text: str) -> Set[str]:
    """Грубые основы слов: «гантелей» и «гантели» → «ганте»."""
    result = set()
    for word in text_key(text).split():
        if word in STOP_WORDS or word.isdigit():
            continue
        length = len(word) if len(word) <= 3 else max(3, min(5, len(word) - 1))
        result.add(word[:length])
    return result


@dataclass
class Aliases:
    """Таблица соответствий, которую ведёт разработчик (`aliases.json`): как автор контента называет
    файлы и упражнения в тренировках → точное упражнение главного списка в виде «Раздел / Упражнение».
    Явная и проверенная человеком, поэтому главнее эвристик (стандарт §8.3), но слабее имени,
    которое автор сам вписал в ячейку. Ключи — `text_key` исходного названия."""
    files: Dict[str, str] = field(default_factory=dict)
    exercises: Dict[str, str] = field(default_factory=dict)


def load_aliases(path: str) -> Aliases:
    """Нет файла — пустая таблица: синхронизация работает и без неё."""
    if not os.path.exists(path):
        return Aliases()
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    return Aliases(files={text_key(k): v for k, v in data.get("files", {}).items()},
                   exercises={text_key(k): v for k, v in data.get("exercises", {}).items()})


def split_reference(reference: str) -> Tuple[str, str]:
    """«Раздел / Упражнение» → ключи раздела и названия."""
    part, _, name = reference.partition("/")
    return text_key(part), text_key(name)


class MediaMatcher:
    """Однозначное сопоставление файлов папки с упражнением: явная ссылка в ячейке главнее,
    затем таблица соответствий, затем точное совпадение имени без приставки раздела и номера."""

    def __init__(self, files: Sequence[DriveFile]):
        self.files = sorted([f for f in files if not f.is_folder], key=lambda f: natural_key(f.base_name))
        self.by_id = {f.id: f for f in self.files}
        # id файла → номер строки упражнения, за которым его закрепила таблица соответствий.
        self.assigned: Dict[str, int] = {}
        # id файла → строки упражнений, которым он достанется при сборке (заполняется предварительным проходом).
        self.claimed: Dict[str, Set[int]] = {}

    def free_for(self, f: DriveFile, row: "ExerciseRow") -> bool:
        owner = self.assigned.get(f.id)
        return owner is None or owner == row.row_number

    def assigned_to(self, row: "ExerciseRow") -> List[DriveFile]:
        return [f for f in self.files if self.assigned.get(f.id) == row.row_number]

    def auto_matches(self, row: "ExerciseRow", rows: Sequence["ExerciseRow"] = ()) -> List[DriveFile]:
        """Файлы, названные точно как упражнение (с приставкой раздела или без, номер не в счёт).
        Однозначность с обеих сторон: приставка, называющая чужой раздел или группу мышц,
        отводит файл («Трицепс. Молот» — не для бицепсового «Молота»); если упражнение с таким
        названием есть и в другом разделе, файл привязывается только с приставкой своего раздела."""
        target = text_key(row.name)
        if not target:
            return []
        others = [r for r in rows if r is not row]
        own_words = set((text_key(row.body_part) + " " + text_key(row.muscle_group or "")).split())
        foreign = {text_key(r.body_part) for r in others} | {text_key(r.muscle_group or "") for r in others}
        foreign = {k for k in foreign if k and not set(k.split()) & own_words}
        namesakes = any(text_key(r.name) == target for r in others)
        found = []
        for f in self.files:
            if not self.free_for(f, row):
                continue
            base = NUMBERING_SUFFIX.sub("", f.base_name)
            segments = [segment.strip() for segment in base.split(".") if segment.strip()]
            prefix: Optional[List[str]] = None
            for start in range(len(segments)):
                if text_key(" ".join(segments[start:])) == target:
                    prefix = segments[:start]
                    break
            if prefix is None:
                continue
            prefix_keys = [text_key(segment) for segment in prefix]
            prefix_words = set(" ".join(prefix_keys).split())
            if any(key in foreign for key in prefix_keys):
                continue
            if namesakes and not prefix_words & own_words:
                continue
            found.append(f)
        return found

    def resolve(self, reference: Tuple[str, str]):
        """('found', file) | ('not_found', None) | ('ambiguous', [files])."""
        kind, value = reference
        if kind == "id":
            found = self.by_id.get(value)
            return ("found", found) if found else ("not_found", None)
        stem, ext = os.path.splitext(value)
        target = text_key(stem if ext[1:].lower() in MEDIA_EXTENSIONS else value)
        exact = [f for f in self.files if text_key(f.base_name) == target]
        if len(exact) == 1:
            return ("found", exact[0])
        if len(exact) > 1:
            return ("ambiguous", exact)
        partial = [f for f in self.files if target in title_keys(f.base_name, strip_numbering=False)]
        if len(partial) == 1:
            return ("found", partial[0])
        if len(partial) > 1:
            return ("ambiguous", partial)
        return ("not_found", None)

    def fits_section(self, f: DriveFile, row: "ExerciseRow") -> bool:
        """Файл назван «Группа мышц. Короткое название» (так их ведёт автор контента).
        Подходит упражнению, если приставка — его раздел или группа мышц, а все значимые
        слова названия файла есть в названии упражнения."""
        segments = [s.strip() for s in f.base_name.split(".") if s.strip()]
        if len(segments) < 2:
            return False
        prefix, rest = segments[0], " ".join(segments[1:])
        if text_key(prefix) not in (text_key(row.body_part), text_key(row.muscle_group or "")):
            return False
        rest_stems = stems(rest)
        return bool(rest_stems) and rest_stems <= stems(row.name)

    def confident_match(self, row: "ExerciseRow", rows: Sequence["ExerciseRow"]) -> Optional[DriveFile]:
        """Для ячейки «есть»: файл привязывается, только если он единственный подходящий
        и сам подходит единственному упражнению. Однозначность с обеих сторон — иначе
        «Бицепс. Молот» уехал бы и в «Молот», и в «Диагональный молот» (стандарт §8.7)."""
        found = [f for f in self.files if self.free_for(f, row) and self.fits_section(f, row)]
        if len(found) != 1:
            return None
        if sum(1 for other in rows if self.fits_section(found[0], other)) > 1:
            return None
        return found[0]

    def taken_elsewhere(self, f: DriveFile, row: "ExerciseRow", rows: Sequence["ExerciseRow"]) -> bool:
        """Файл уже чей-то: закреплён таблицей, достанется другому упражнению или назван точно как другое."""
        if not self.free_for(f, row):
            return True
        owners = self.claimed.get(f.id)
        if owners and row.row_number not in owners:
            return True
        keys = title_keys(f.base_name, strip_numbering=True)
        return any(r is not row and text_key(r.name) in keys for r in rows)

    def suggestions(self, exercise_name: str, limit: int = 2, row: Optional["ExerciseRow"] = None,
                    rows: Sequence["ExerciseRow"] = ()) -> List[DriveFile]:
        """Похожие файлы — только подсказка человеку, автоматически не привязываются.
        Чужие файлы не предлагаются: подсказать фото разведения к жиму — хуже, чем промолчать."""
        target = stems(exercise_name)
        if not target:
            return []
        scored = []
        for f in self.files:
            if row is not None and self.taken_elsewhere(f, row, rows):
                continue
            segments = [s.strip() for s in f.base_name.split(".") if s.strip()]
            best = 0.0
            for start in range(len(segments)):
                candidate = stems(" ".join(segments[start:]))
                if not candidate:
                    continue
                common = len(target & candidate)
                dice = 2 * common / (len(target) + len(candidate))
                coverage = common / len(candidate)
                best = max(best, (dice + coverage) / 2)
            if best >= 0.5:
                scored.append((f, best))
        scored.sort(key=lambda item: (-item[1], natural_key(item[0].base_name)))
        return [f for f, _ in scored[:limit]]


# ---------------------------------------------------------------------------
# Манифест

FOLDER_TITLES = {"photo": "Фото упражнений", "ownVideo": "Женя видео", "otherVideo": "Чужие видео"}
COLUMN_TITLES = {"photo": "Фото", "ownVideo": "Женя видео", "otherVideo": "Чужое видео"}


@dataclass
class Snapshot:
    exercise_rows: List[List[str]]
    workout_rows: List[List[str]] = field(default_factory=list)
    photos: List[DriveFile] = field(default_factory=list)
    own_videos: List[DriveFile] = field(default_factory=list)
    other_videos: List[DriveFile] = field(default_factory=list)
    issues: List[Dict[str, str]] = field(default_factory=list)


def media_item(drive_file: DriveFile, kind: str) -> Dict:
    return {
        "driveFileId": drive_file.id,
        "title": drive_file.base_name,
        "fileExtension": drive_file.extension,
        "kind": kind,
        "version": drive_file.version,
        "byteSize": drive_file.size,
    }


def _describe(reference: Tuple[str, str]) -> str:
    kind, value = reference
    return f"ссылка …{value[-6:]}" if kind == "id" else value


def _resolve_cell(cell: str, kind: str, row: ExerciseRow, matcher: MediaMatcher, issues: List[Dict[str, str]],
                  rows: Sequence[ExerciseRow] = ()) -> List[DriveFile]:
    place = f"Строка {row.row_number}, «{row.name}», колонка «{COLUMN_TITLES[kind]}»"
    directive = parse_media_cell(cell)
    if directive[0] == "none":
        return []
    if directive[0] == "auto":
        found = matcher.auto_matches(row, rows)
        found += [f for f in matcher.assigned_to(row) if f not in found]
        if not found and directive[1]:
            picked = matcher.confident_match(row, rows)
            if picked is None and any(r is not row and text_key(r.name) == text_key(row.name) for r in rows):
                issues.append(issue("warning", f"{place}: упражнение «{row.name}» есть и в другом разделе, поэтому файл "
                                               f"без приставки раздела не привязывается. Назови файл "
                                               f"«{row.body_part}. {row.name}» или впиши имя файла в ячейку."))
                return []
            if picked is not None:
                issues.append(issue("info", f"{place}: по ячейке «есть» подобран файл «{picked.base_name}» — "
                                            "совпали группа мышц и слова названия. Если это не тот файл, "
                                            "впиши в ячейку нужное имя."))
                return [picked]
            hint = " или ".join(f"«{f.base_name}»" for f in matcher.suggestions(row.name, row=row, rows=rows))
            suggestion = f" Возможно, подходит: {hint}." if hint else ""
            issues.append(issue("warning", f"{place}: написано «есть», но файл с таким названием не найден.{suggestion} "
                                           "Впиши в ячейку имя файла или ссылку на него."))
        return found
    files: List[DriveFile] = []
    for reference in directive[1]:
        status, value = matcher.resolve(reference)
        if status == "found":
            if value not in files:
                files.append(value)
        elif status == "not_found":
            issues.append(issue("warning", f"{place}: файл «{_describe(reference)}» не найден в папке «{FOLDER_TITLES[kind]}»."))
        else:
            names = ", ".join(f"«{f.base_name}»" for f in value[:3])
            issues.append(issue("warning", f"{place}: под «{_describe(reference)}» подходит несколько файлов ({names}) — уточни имя."))
    return files


def build_manifest(snapshot: Snapshot, now: Optional[datetime] = None, aliases: Optional[Aliases] = None) -> Dict:
    """Манифест в том же формате, что у нативной версии (ContentManifest)."""
    now = now or datetime.now(timezone.utc)
    aliases = aliases or Aliases()
    issues = list(snapshot.issues)
    rows, parse_issues = parse_exercise_sheet(snapshot.exercise_rows)
    issues += parse_issues

    matchers = {
        "photo": MediaMatcher(snapshot.photos),
        "ownVideo": MediaMatcher(snapshot.own_videos),
        "otherVideo": MediaMatcher(snapshot.other_videos),
    }
    rows_by_ref = {(text_key(r.body_part), text_key(r.name)): r for r in rows}
    broken: Set[str] = set()
    for matcher in matchers.values():
        for f in matcher.files:
            reference = aliases.files.get(text_key(f.base_name))
            if reference is None:
                continue
            target = rows_by_ref.get(split_reference(reference))
            if target is None:
                if reference not in broken:
                    broken.add(reference)
                    issues.append(issue("warning", f"В таблице соответствий файлу «{f.base_name}» назначено «{reference}», "
                                                   "но такого упражнения в таблице нет — файл сопоставляется как обычно."))
                continue
            matcher.assigned[f.id] = target.row_number
    # Предварительный проход: кому какой файл достанется. Нужен подсказкам в отчёте — предлагать
    # файл, который уже привязан к другому упражнению, значит путать автора.
    for kind, matcher in matchers.items():
        for row in rows:
            cell = {"photo": row.photo_cell, "ownVideo": row.own_video_cell, "otherVideo": row.other_video_cell}[kind]
            directive = parse_media_cell(cell)
            found: List[DriveFile] = []
            if directive[0] == "explicit":
                for reference in directive[1]:
                    status, value = matcher.resolve(reference)
                    if status == "found":
                        found.append(value)
            elif directive[0] == "auto":
                found = matcher.auto_matches(row, rows) + matcher.assigned_to(row)
                if not found and directive[1]:
                    picked = matcher.confident_match(row, rows)
                    found = [picked] if picked is not None else []
            for f in found:
                matcher.claimed.setdefault(f.id, set()).add(row.row_number)

    used_ids: Set[str] = set()
    exercises: List[Dict] = []
    body_parts: List[str] = []
    taken_ids: Set[str] = set()

    for row in rows:
        if row.body_part not in body_parts:
            body_parts.append(row.body_part)
        cells = {"photo": row.photo_cell, "ownVideo": row.own_video_cell, "otherVideo": row.other_video_cell}
        media: Dict[str, List[Dict]] = {}
        for kind in ("photo", "ownVideo", "otherVideo"):
            files = _resolve_cell(cells[kind], kind, row, matchers[kind], issues, rows)
            used_ids.update(f.id for f in files)
            media[kind] = [media_item(f, kind) for f in files]

        exercise_id = f"{text_key(row.body_part)}/{text_key(row.name)}"
        if exercise_id in taken_ids:
            issues.append(issue("warning", f"Строка {row.row_number}: упражнение «{row.name}» в разделе «{row.body_part}» встречается повторно."))
            exercise_id += f"#{row.row_number}"
        taken_ids.add(exercise_id)

        photos = media["photo"]
        videos = media["ownVideo"] + media["otherVideo"]
        version = stable_hash(row.name, row.body_part, row.muscle_group or "", row.equipment or "", row.details,
                              str(row.sets) if row.sets else "",
                              *[f"{m['driveFileId']}:{m['version']}" for m in photos + videos])
        exercises.append({
            "id": exercise_id, "name": row.name, "bodyPart": row.body_part, "muscleGroup": row.muscle_group,
            "equipment": row.equipment, "details": row.details, "sets": row.sets,
            "photos": photos, "videos": videos, "version": version,
        })

    aliased_files = sum(len(m.assigned) for m in matchers.values())
    workouts = _build_workouts(snapshot.workout_rows, exercises, issues, aliases)
    if aliased_files or aliases.exercises:
        issues.append(issue("info", f"Файлы и упражнения в тренировках, названные по-своему, сопоставлены вручную по "
                                    f"таблице соответствий: файлов — {aliased_files}. Если вписать имя файла в ячейку, "
                                    "оно главнее таблицы."))

    for kind, matcher in matchers.items():
        for f in matcher.files:
            if f.id not in used_ids:
                issues.append(issue("info", f"Файл «{f.base_name}» в папке «{FOLDER_TITLES[kind]}» не привязан ни к одному упражнению."))

    content_version = stable_hash(*[e["version"] for e in exercises], *[w["version"] for w in workouts], *body_parts)
    ordered_issues = [item for _, item in sorted(enumerate(issues), key=lambda pair: (SEVERITY_RANK[pair[1]["severity"]], pair[0]))]
    return {
        "schemaVersion": SCHEMA_VERSION,
        "generatedAt": now.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "bodyParts": body_parts,
        "exercises": exercises,
        "workouts": workouts,
        "issues": ordered_issues,
        "contentVersion": content_version,
    }


def _build_workouts(rows: List[List[str]], exercises: List[Dict], issues: List[Dict[str, str]],
                    aliases: Optional[Aliases] = None) -> List[Dict]:
    aliases = aliases or Aliases()
    if not rows:
        return []
    parsed, parse_issues = parse_workout_sheet(rows)
    issues += parse_issues
    by_name: Dict[str, List[Dict]] = {}
    for exercise in exercises:
        by_name.setdefault(text_key(exercise["name"]), []).append(exercise)

    def lookup(name: str, section: Optional[str]) -> Optional[Dict]:
        found = by_name.get(text_key(name))
        if found:
            if len(found) > 1 and section:
                for exercise in found:
                    if text_key(exercise["bodyPart"]) == text_key(section):
                        return exercise
            return found[0]
        parts = [p.strip() for p in name.split(".") if p.strip()]
        if len(parts) < 2:
            return None
        # «Бицепс. Молот» — раздел или группа мышц перед названием.
        prefix, exercise_name = text_key(parts[0]), text_key(" ".join(parts[1:]))
        for exercise in exercises:
            if text_key(exercise["name"]) != exercise_name:
                continue
            if prefix in (text_key(exercise["bodyPart"]), text_key(exercise["muscleGroup"] or "")):
                return exercise
        return None

    def lookup_with_aliases(name: str, section: Optional[str]) -> Optional[Dict]:
        found = lookup(name, section)
        if found is not None:
            return found
        reference = aliases.exercises.get(text_key(name))
        if reference is None:
            return None
        part, exercise_name = split_reference(reference)
        for exercise in exercises:
            if text_key(exercise["bodyPart"]) == part and text_key(exercise["name"]) == exercise_name:
                return exercise
        issues.append(issue("warning", f"В таблице соответствий «{name}» назначено «{reference}», но такого упражнения "
                                       "в таблице нет."))
        return None

    def suggestions(name: str) -> List[str]:
        """Похожие названия из главного списка — подсказка Жене, не автопривязка (§8.7 стандарта)."""
        wanted = stems(name)
        if not wanted:
            return []
        scored = []
        for exercise in exercises:
            overlap = len(wanted & stems(exercise["name"]))
            if overlap:
                scored.append((overlap, exercise["name"]))
        scored.sort(key=lambda pair: (-pair[0], pair[1]))
        return [n for _, n in scored[:3]]

    workouts: List[Dict] = []
    taken: Set[str] = set()
    for row in parsed:
        ids = []
        missing = 0
        for row_number, name, section in row.exercises:
            exercise = lookup_with_aliases(name, section)
            if exercise:
                if exercise["id"] not in ids:
                    ids.append(exercise["id"])
                continue
            missing += 1
            similar = suggestions(name)
            hint = (" Похоже на: " + "; ".join(f"«{s}»" for s in similar) + ".") if similar else ""
            issues.append(issue("warning", f"Тренировка «{row.title}», строка {row_number}: упражнение «{name}» не найдено "
                                           f"в главном списке. Впиши точное название из главного списка в третью колонку "
                                           f"(«Ссылка на главный список»).{hint}"))
        if not ids:
            issues.append(issue("warning", f"Тренировка «{row.title}» пропущена: в ней нет ни одного найденного упражнения."))
            continue
        if missing:
            total = len(ids) + missing
            issues.append(issue("warning", f"Тренировка «{row.title}» показана не полностью: найдено "
                                           f"{len(ids)} {plural(len(ids), 'упражнение', 'упражнения', 'упражнений')} "
                                           f"из {total}. Остальные появятся, когда названия совпадут."))
        workout_id = f"workout/{text_key(row.title)}"
        if workout_id in taken:
            issues.append(issue("warning", f"Тренировка «{row.title}» встречается дважды — названия должны отличаться."))
            workout_id += f"#{len(workouts)}"
        taken.add(workout_id)
        workouts.append({"id": workout_id, "title": row.title, "summary": row.summary, "exerciseIds": ids,
                         "version": stable_hash(row.title, row.summary or "", *ids)})
    return workouts


def all_media(manifest: Dict) -> List[Dict]:
    """Все медиа манифеста без повторов (один файл может быть у нескольких упражнений)."""
    seen: Set[Tuple[str, str]] = set()
    result = []
    for exercise in manifest["exercises"]:
        for item in exercise["photos"] + exercise["videos"]:
            key = (item["driveFileId"], item["version"])
            if key not in seen:
                seen.add(key)
                result.append(item)
    return result


# ---------------------------------------------------------------------------
# Отчёт


def report_markdown(manifest: Dict) -> str:
    """Отчёт для Жени: что приложение поняло из таблицы и что поправить."""
    exercises = manifest["exercises"]
    lines = ["# Отчёт по контенту тренажёра", "", f"Собрано: {manifest['generatedAt']}", ""]
    parts = ", ".join(f"{p} — {sum(1 for e in exercises if e['bodyPart'] == p)}" for p in manifest["bodyParts"])
    lines.append(f"- Упражнений: **{len(exercises)}** в {len(manifest['bodyParts'])} разделах: {parts}.")
    lines.append(f"- Готовых тренировок: **{len(manifest['workouts'])}**.")
    with_photo = sum(1 for e in exercises if e["photos"])
    with_own = sum(1 for e in exercises if any(v["kind"] == "ownVideo" for v in e["videos"]))
    with_other = sum(1 for e in exercises if any(v["kind"] == "otherVideo" for v in e["videos"]))
    lines += [f"- С фото: {with_photo}, с видео Жени: {with_own}, с чужими видео: {with_other}.", "",
              "## Упражнения и привязанные файлы", "",
              "| Раздел | Упражнение | Фото | Видео Жени | Чужие видео |", "|---|---|---|---|---|"]

    def cell(items: List[Dict]) -> str:
        return "<br>".join(i["title"] for i in items) if items else "—"

    for e in exercises:
        own = [v for v in e["videos"] if v["kind"] == "ownVideo"]
        other = [v for v in e["videos"] if v["kind"] == "otherVideo"]
        lines.append(f"| {e['bodyPart']} | {e['name']} | {cell(e['photos'])} | {cell(own)} | {cell(other)} |")
    lines.append("")

    if manifest["workouts"]:
        lines += ["## Готовые тренировки", ""]
        by_id = {e["id"]: e["name"] for e in exercises}
        for w in manifest["workouts"]:
            names = [by_id[i] for i in w["exerciseIds"] if i in by_id]
            lines.append(f"- **{w['title']}** ({len(names)} {plural(len(names), 'упражнение', 'упражнения', 'упражнений')}): {', '.join(names)}")
        lines.append("")

    groups = [("error", "Ошибки — без исправления контент не загрузится"), ("warning", "Нужно поправить в таблице"),
              ("info", "Для сведения")]
    lines += [f"## Замечания ({len(manifest['issues'])})", ""]
    if not manifest["issues"]:
        lines.append("Замечаний нет.")
    for severity, title in groups:
        items = [i for i in manifest["issues"] if i["severity"] == severity]
        if items:
            lines += [f"### {title} ({len(items)})", ""] + [f"- {i['message']}" for i in items] + [""]
    return "\n".join(lines)
