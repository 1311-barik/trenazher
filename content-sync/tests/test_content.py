"""Тесты разбора и сопоставления — те же случаи, что в Swift-тестах нативной версии.
Запуск: cd content-sync && python3 -m unittest discover -s tests -v
"""

import csv
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from trenazher_content import (Aliases, DriveFile, ExerciseRow, MediaMatcher, Snapshot, build_manifest, load_aliases,  # noqa: E402
                               parse_exercise_sheet,
                               parse_media_cell, plural, report_markdown)

FIXTURES = os.path.join(HERE, "fixtures")


def sheet_rows():
    with open(os.path.join(FIXTURES, "drone-trenirovka-2026-09-18.csv"), encoding="utf-8") as f:
        return list(csv.reader(f))


def listing():
    with open(os.path.join(FIXTURES, "drive-files-2026-09-18.json"), encoding="utf-8") as f:
        data = json.load(f)
    return {k: [DriveFile.from_json(i) for i in v] for k, v in data.items()}


def row(body_part, muscle_group, name, number=1):
    return ExerciseRow(row_number=number, body_part=body_part, muscle_group=muscle_group, name=name, equipment=None,
                       details="", sets=None, photo_cell="", other_video_cell="", own_video_cell="")


def real_snapshot(workout_rows=None):
    files = listing()
    return Snapshot(exercise_rows=sheet_rows(), workout_rows=workout_rows or [], photos=files["photos"],
                    own_videos=files["ownVideos"], other_videos=files["otherVideos"])


class SheetParserTests(unittest.TestCase):
    def test_real_sheet(self):
        rows, issues = parse_exercise_sheet(sheet_rows())
        self.assertEqual(len(rows), 40)
        self.assertEqual(issues, [])
        hammer = next(r for r in rows if r.name == "Молот")
        self.assertEqual((hammer.body_part, hammer.muscle_group), ("Руки", "Бицепс"))
        # Новый раздел сбрасывает группу мышц.
        self.assertIsNone(next(r for r in rows if r.name == "Жим гантелей лёжа — обычный").muscle_group)
        self.assertTrue(any(r.name == "Медвежья планка в динамике" for r in rows))
        self.assertEqual(next(r for r in rows if r.name == "Подъем гантели из-за головы").equipment, "стул")

    def test_body_parts_in_sheet_order(self):
        manifest = build_manifest(real_snapshot())
        self.assertEqual(manifest["bodyParts"], ["Руки", "Попа", "Ноги", "Живот", "Плечи", "Грудь", "Спина", "Смесь мышц"])

    def test_columns_by_header(self):
        rows, issues = parse_exercise_sheet([["Упражнение", "Подходы", "Часть тела", "Текст описания"],
                                             ["Молот", "3", "Руки", "Описание"], ["Классика", "4 подхода", "", "Ещё"]])
        self.assertEqual(issues, [])
        self.assertEqual([r.sets for r in rows], [3, 4])
        self.assertEqual([r.body_part for r in rows], ["Руки", "Руки"])


class MediaTests(unittest.TestCase):
    def test_cell_directives(self):
        self.assertEqual(parse_media_cell(""), ("auto", False))
        self.assertEqual(parse_media_cell(" есть "), ("auto", True))
        self.assertEqual(parse_media_cell("нет и не будет"), ("none",))
        self.assertEqual(parse_media_cell("Бицепс. Молот; Бицепс. Молот 2"),
                         ("explicit", [("name", "Бицепс. Молот"), ("name", "Бицепс. Молот 2")]))
        self.assertEqual(parse_media_cell("https://drive.google.com/file/d/1Mj3NYgGAkacWrYlBO1Y9GscOlASpNxLk/view?usp=drivesdk"),
                         ("explicit", [("id", "1Mj3NYgGAkacWrYlBO1Y9GscOlASpNxLk")]))

    def test_auto_match(self):
        matcher = MediaMatcher([DriveFile("1", "Бицепс. Молот 2.JPG"), DriveFile("2", "Бицепс. Молот.JPG"),
                                DriveFile("3", "Бицепс. Диагональный молот.JPG"), DriveFile("4", "Попа. Болгарские выпады. 1.mov"),
                                DriveFile("5", "Попа. Румынка вар 2.mov")])
        hammer = row("Руки", "Бицепс", "Молот")
        self.assertEqual([f.id for f in matcher.auto_matches(hammer)], ["2", "1"])
        self.assertEqual([f.id for f in matcher.auto_matches(row("Попа", "Ягодицы", "Болгарские выпады"))], ["4"])
        self.assertEqual([f.id for f in matcher.auto_matches(row("Попа", "Ягодицы", "Румынка"))], ["5"])

    def test_auto_match_is_two_sided(self):
        """Приставка чужого раздела отводит файл; одноимённые упражнения требуют приставку своего."""
        hammer = row("Руки", "Бицепс", "Молот")
        triceps = row("Руки", "Трицепс", "Разгибание")
        shoulder_hammer = row("Плечи", "Средняя дельта", "Молот")
        matcher = MediaMatcher([DriveFile("1", "Трицепс. Молот.JPG"), DriveFile("2", "Молот.JPG"), DriveFile("3", "Бицепс. Молот.JPG")])
        # «Трицепс. Молот» называет чужую группу мышц — бицепсовому «Молоту» не достаётся.
        self.assertEqual([f.id for f in matcher.auto_matches(hammer, [hammer, triceps])], ["3", "2"])
        # Два «Молота» в разных разделах: файл без приставки не привязывается ни к одному,
        # «Бицепс. Молот» — только к своему.
        self.assertEqual([f.id for f in matcher.auto_matches(hammer, [hammer, shoulder_hammer])], ["3"])
        self.assertEqual([f.id for f in matcher.auto_matches(shoulder_hammer, [hammer, shoulder_hammer])], [])
        # Приставка «Пресс» у упражнения раздела «Живот» с группой «Косые» — свободная, не чужая.
        obliques = row("Живот", "Косые", "Наклоны в бок")
        abs_low = row("Живот", "Пресс. Низ", "Мертвый жук")
        matcher = MediaMatcher([DriveFile("9", "Пресс. Косые. Наклоны в бок.JPG")])
        self.assertEqual([f.id for f in matcher.auto_matches(obliques, [obliques, abs_low])], ["9"])

    def test_explicit_name(self):
        matcher = MediaMatcher([DriveFile("1", "Бицепс. Молот 2.JPG"), DriveFile("2", "Трицепс. Молот 2.JPG"),
                                DriveFile("3", "Трицепс. Французский жим.JPG")])
        self.assertEqual(matcher.resolve(("name", "бицепс. молот 2.jpg"))[1].id, "1")
        self.assertEqual(matcher.resolve(("name", "Французский жим"))[1].id, "3")
        self.assertEqual(matcher.resolve(("name", "Молот 2"))[0], "ambiguous")
        self.assertEqual(matcher.resolve(("name", "Жим лёжа"))[0], "not_found")

    def test_real_content(self):
        manifest = build_manifest(real_snapshot())
        by_name = {e["name"]: e for e in manifest["exercises"]}
        self.assertEqual([p["title"] for p in by_name["Мертвый жук"]["photos"]], ["Пресс. Мертвый жук"])
        self.assertEqual([v["kind"] for v in by_name["Мертвый жук"]["videos"]], ["ownVideo", "otherVideo"])
        self.assertEqual([p["title"] for p in by_name["Молот"]["photos"]], ["Бицепс. Молот", "Бицепс. Молот 2"])
        # Ячейка «есть» + однозначный файл, названный по-своему — привязывается и объясняется в отчёте.
        self.assertEqual([p["title"] for p in by_name["Классика подъем гантели со сгибанием локтя"]["photos"]],
                         ["Бицепс. Классика"])
        self.assertEqual([p["title"] for p in by_name["Шраги с гантелями"]["photos"]], ["Спина. Шраги"])
        self.assertTrue(any("«Шраги с гантелями», колонка «Фото»" in i["message"] and "подобран файл «Спина. Шраги»"
                            in i["message"] and i["severity"] == "info" for i in manifest["issues"]))
        # Те же ID, что в нативной версии: избранное и история совместимы.
        self.assertIn("руки/молот", {e["id"] for e in manifest["exercises"]})
        self.assertEqual(sum(1 for i in manifest["issues"] if i["severity"] == "warning"), 43)

    def test_version_changes_when_file_replaced(self):
        rows = [["Часть тела", "Упражнение"], ["Руки", "Молот"]]
        old = build_manifest(Snapshot(rows, photos=[DriveFile("1", "Руки. Молот.jpg", md5="aaa")]))
        new = build_manifest(Snapshot(rows, photos=[DriveFile("1", "Руки. Молот.jpg", md5="bbb")]))
        self.assertEqual(old["exercises"][0]["id"], new["exercises"][0]["id"])
        self.assertNotEqual(old["contentVersion"], new["contentVersion"])


class ConfidentMatchTests(unittest.TestCase):
    """Ячейка «есть» + файл, названный по-своему: привязка только при однозначности с обеих сторон."""

    def setUp(self):
        self.manifest = build_manifest(real_snapshot())
        self.by_name = {e["name"]: e for e in self.manifest["exercises"]}

    def test_short_file_name_is_bound(self):
        classic = self.by_name["Классика подъем гантели со сгибанием локтя"]
        self.assertEqual([m["title"] for m in classic["photos"]], ["Бицепс. Классика"])
        picked = next(i["message"] for i in self.manifest["issues"]
                      if "подобран файл «Бицепс. Классика»" in i["message"])
        self.assertIn("впиши в ячейку нужное имя", picked)

    def test_file_fitting_two_exercises_is_not_bound(self):
        """«Бицепс. Молот» подходит и «Молоту», и «Диагональному молоту» — значит никому."""
        titles = [m["title"] for m in self.by_name["Диагональный молот"]["videos"]]
        self.assertNotIn("Бицепс. Молот", titles)

    def test_ambiguous_cell_still_asks_to_fill_in(self):
        self.assertTrue(any("написано «есть», но файл с таким названием не найден" in i["message"]
                            for i in self.manifest["issues"]))


def snapshot_0926():
    with open(os.path.join(FIXTURES, "snapshot-2026-09-26.json"), encoding="utf-8") as f:
        data = json.load(f)
    files = lambda key: [DriveFile.from_json(item) for item in data[key]]
    return Snapshot(exercise_rows=data["exercise_rows"], workout_rows=data["workout_rows"], photos=files("photos"),
                    own_videos=files("ownVideos"), other_videos=files("otherVideos"))


ALIASES = os.path.join(os.path.dirname(HERE), "aliases.json")


class FinalContentTests(unittest.TestCase):
    """Приёмка контента 2026-09-26: Женя сказала «всё, других файлов не будет».
    Проверяем её же словами: 37 упражнений, у всех чужое видео, три тренировки по 12."""

    def setUp(self):
        self.manifest = build_manifest(snapshot_0926(), aliases=load_aliases(ALIASES))
        self.by_name = {e["name"]: e for e in self.manifest["exercises"]}

    def test_every_exercise_has_other_video(self):
        self.assertEqual(len(self.manifest["exercises"]), 37)
        without = [e["name"] for e in self.manifest["exercises"] if not any(v["kind"] == "otherVideo" for v in e["videos"])]
        self.assertEqual(without, [])

    def test_photos_everywhere_but_one_really_missing(self):
        # В папке «Фото упражнений» нет ни одного файла про обычный жим лёжа — это честная дыра, не ошибка сопоставления.
        without = [e["name"] for e in self.manifest["exercises"] if not e["photos"]]
        self.assertEqual(without, ["Жим гантелей лёжа — обычный"])

    def test_three_workouts_by_twelve(self):
        self.assertEqual([(w["title"], len(w["exerciseIds"])) for w in self.manifest["workouts"]],
                         [("Как за каменной спиной+", 12), ("Пресс-аташе", 12), ("Ноги и крылья", 12)])

    def test_every_file_in_folders_is_used(self):
        used = {(m["kind"], m["driveFileId"]) for e in self.manifest["exercises"] for m in e["photos"] + e["videos"]}
        snap = snapshot_0926()
        free = [f.name for kind, files in (("photo", snap.photos), ("ownVideo", snap.own_videos), ("otherVideo", snap.other_videos))
                for f in files if (kind, f.id) not in used]
        self.assertEqual(free, [])

    def test_aliased_file_goes_only_to_its_exercise(self):
        """«Попа. Приседания» по названию подходит и «Сумо», и «Простым» — таблица отдаёт его только «Простым»."""
        simple = [m["title"] for m in self.by_name["Простые приседания"]["photos"]]
        sumo = [m["title"] for m in self.by_name["Приседание сумо"]["photos"]]
        self.assertEqual(simple, ["Попа. Приседания"])
        self.assertEqual(sumo, ["Попа. Сумо"])

    def test_no_video_marker_respected(self):
        """«нет и не будет» в колонке Жени — никаких её видео и никаких замечаний по этой ячейке."""
        bulgarian = self.by_name["Болгарские выпады"]
        self.assertFalse(any(v["kind"] == "ownVideo" for v in bulgarian["videos"]))
        self.assertFalse(any("Болгарские выпады" in i["message"] and "Женя видео" in i["message"] for i in self.manifest["issues"]))

    def test_alias_to_unknown_exercise_is_reported(self):
        aliases = Aliases(files={"попа сумо": "Попа / Такого нет"}, exercises={"мертый жук": "Живот / Тоже нет"})
        manifest = build_manifest(snapshot_0926(), aliases=aliases)
        messages = [i["message"] for i in manifest["issues"]]
        self.assertTrue(any("«Попа / Такого нет»" in m for m in messages))
        self.assertTrue(any("«Живот / Тоже нет»" in m for m in messages))

    def test_lone_section_row_is_a_header(self):
        """Строка «Попа» без упражнения — заголовок раздела, а не упражнение «Попа»."""
        messages = [i["message"] for i in self.manifest["issues"]]
        self.assertFalse(any("«Попа» не найдено" in m for m in messages))
        self.assertFalse(any("показана не полностью" in m for m in messages))

    def test_only_genuine_gaps_remain(self):
        """После таблицы соответствий в отчёте остаются только настоящие дыры контента."""
        warnings = [i["message"] for i in self.manifest["issues"] if i["severity"] in ("warning", "error")]
        self.assertEqual(len(warnings), 2, warnings)
        self.assertTrue(any("«Жим гантелей лёжа — обычный», колонка «Фото»" in w for w in warnings))
        self.assertTrue(any("«Тяга 90 градусов с опорой», колонка «Женя видео»" in w for w in warnings))

    def test_hint_never_offers_a_file_of_another_exercise(self):
        """Ни файл, названный как другое упражнение, ни файл, уже привязанный к другому упражнению
        (узкий хват подобран по ячейке «есть»), не предлагаются к обычному жиму."""
        press = next(i["message"] for i in self.manifest["issues"] if "«Жим гантелей лёжа — обычный», колонка «Фото»" in i["message"])
        self.assertNotIn("Разведение", press)
        self.assertNotIn("узким хватом", press)

    def test_summary_has_no_developer_paths(self):
        """Сводка видна в приложении — без путей к файлам и служебных кавычек."""
        summary = next(i["message"] for i in self.manifest["issues"] if "таблице соответствий" in i["message"] and "назначено" not in i["message"])
        self.assertNotIn("`", summary)
        self.assertNotIn(".json", summary)

    def test_real_aliases_all_resolve(self):
        broken = [i["message"] for i in self.manifest["issues"] if "таблице соответствий" in i["message"] and "назначено" in i["message"]]
        self.assertEqual(broken, [])
        summary = next(i for i in self.manifest["issues"] if "таблице соответствий" in i["message"] and "назначено" not in i["message"])
        self.assertEqual(summary["severity"], "info")


class WorkoutTests(unittest.TestCase):
    def test_workout_sheet(self):
        manifest = build_manifest(real_snapshot([
            ["Тренировка", "Описание", "Упражнение"], ["Руки и пресс", "40 минут", "Молот"], ["", "", "Мертвый жук"],
            ["", "", "Несуществующее"], [], ["Спина v2", "", "Спина. Вокруг света"]]))
        self.assertEqual([w["title"] for w in manifest["workouts"]], ["Руки и пресс", "Спина v2"])
        self.assertEqual(manifest["workouts"][0]["exerciseIds"], ["руки/молот", "живот/мертвый жук"])
        self.assertTrue(any("«Несуществующее» не найдено" in i["message"] for i in manifest["issues"]))
        self.assertIn("Руки и пресс", report_markdown(manifest))

    def test_workout_blocks_as_zhenya_keeps_them(self):
        """Реальная раскладка листа «тренировки»: название в кавычках, ниже раздел,
        своё название упражнения и точное название из главного списка в третьей колонке."""
        manifest = build_manifest(real_snapshot([
            ['Тренировка "Как за каменной спиной+"'],
            ["", "", "Ссылка на главный список"],
            ["Спина", "Вокруг света"],
            ["", "Пуловер лежа", "Пуловер с гантелью лёжа на полу"],
            [],
            ["Пресс", "Мертвый жук"],
            ["", "Планка с перекладыванием гантели между руками"],
            [],
            [],
            ['Тренировка "Пресс-аташе" '],
            ["Руки", "Бицепс. Молот"],
        ]))
        titles = [w["title"] for w in manifest["workouts"]]
        self.assertEqual(titles, ["Как за каменной спиной+", "Пресс-аташе"])
        self.assertEqual(manifest["workouts"][0]["exerciseIds"],
                         ["спина/вокруг света", "смесь мышц/пуловер с гантелью лежа на полу", "живот/мертвый жук"])
        # «Бицепс. Молот» — группа мышц перед названием, а не раздел.
        self.assertEqual(manifest["workouts"][1]["exerciseIds"], ["руки/молот"])
        # Описание карточки — разделы автора по порядку, без повторов.
        self.assertEqual(manifest["workouts"][0]["summary"], "Спина · Пресс")
        self.assertEqual(manifest["workouts"][1]["summary"], "Руки")
        # Ненайденное упражнение объясняет, куда вписать точное название, и предлагает похожие.
        missing = next(i["message"] for i in manifest["issues"]
                       if "Планка с перекладыванием гантели между руками" in i["message"])
        self.assertIn("Ссылка на главный список", missing)
        self.assertIn("Похоже на:", missing)
        self.assertTrue(any("показана не полностью" in i["message"] for i in manifest["issues"]))

    def test_workout_sheet_without_recognisable_layout(self):
        manifest = build_manifest(real_snapshot([["что-то своё"], ["и ещё"]]))
        self.assertEqual(manifest["workouts"], [])
        self.assertTrue(any("не удалось разобрать ни одной тренировки" in i["message"] for i in manifest["issues"]))

    def test_plural(self):
        self.assertEqual([plural(n, "а", "б", "в") for n in (1, 3, 5, 11, 22)], ["а", "б", "в", "в", "б"])


@unittest.skipUnless(shutil.which("ffmpeg"), "ffmpeg не установлен")
class MediaProcessingTests(unittest.TestCase):
    """Сквозной прогон sync.py без сети: оригиналы подкладываются в кэш, как будто уже скачаны."""

    def test_photos_and_videos_processed_and_manifest_written(self):
        from PIL import Image

        work = tempfile.mkdtemp()
        out = tempfile.mkdtemp()
        try:
            rows = [["Часть тела", "Упражнение"], ["Руки", "Молот"]]
            files = {"photos": [{"id": "p1", "name": "Руки. Молот.jpg", "mimeType": "image/jpeg", "md5Checksum": "m1"}],
                     "ownVideos": [{"id": "v1", "name": "Руки. Молот.mov", "mimeType": "video/quicktime", "md5Checksum": "m2"}],
                     "otherVideos": []}
            with open(os.path.join(work, "sheet.csv"), "w", encoding="utf-8") as f:
                csv.writer(f).writerows(rows)
            with open(os.path.join(work, "files.json"), "w", encoding="utf-8") as f:
                json.dump(files, f)
            snapshot = build_manifest(Snapshot(rows, photos=[DriveFile.from_json(files["photos"][0])],
                                               own_videos=[DriveFile.from_json(files["ownVideos"][0])]))
            import sync
            os.makedirs(os.path.join(work, "originals"))
            for item in snapshot["exercises"][0]["photos"]:
                Image.new("RGB", (3000, 2000), (200, 30, 40)).save(os.path.join(work, "originals", f"{sync.media_stem(item)}.jpg"))
            for item in snapshot["exercises"][0]["videos"]:
                subprocess.run(["ffmpeg", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc=duration=2:size=1080x1920:rate=30",
                                "-f", "lavfi", "-i", "sine=duration=2", "-shortest",
                                os.path.join(work, "originals", f"{sync.media_stem(item)}.mov")], check=True)

            result = subprocess.run([sys.executable, os.path.join(os.path.dirname(HERE), "sync.py"),
                                     "--csv", os.path.join(work, "sheet.csv"), "--files", os.path.join(work, "files.json"),
                                     "--out", out, "--work", work], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            with open(os.path.join(out, "manifest.json"), encoding="utf-8") as f:
                manifest = json.load(f)
            photo = manifest["exercises"][0]["photos"][0]
            video = manifest["exercises"][0]["videos"][0]
            self.assertTrue(photo["ready"] and video["ready"])
            with Image.open(os.path.join(out, photo["url"])) as image:
                self.assertEqual(max(image.size), 1400)
            with Image.open(os.path.join(out, photo["thumbUrl"])) as image:
                self.assertEqual(max(image.size), 400)
            probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                    "stream=codec_name,width,height", "-of", "csv=p=0", os.path.join(out, video["url"])],
                                   capture_output=True, text=True).stdout.strip()
            self.assertEqual(probe, "h264,720,1280")
            self.assertTrue(os.path.exists(os.path.join(out, video["posterUrl"])))
        finally:
            shutil.rmtree(work)
            shutil.rmtree(out)


if __name__ == "__main__":
    unittest.main()
