import { beforeEach, describe, expect, it } from "vitest";
import { firstOccurrence, icsText, reminderQuery, scheduleText } from "./calendar";
import * as S from "./session";
import * as store from "./store";
import { plural } from "./text";
import type { Manifest } from "./types";
import { defaultSettings } from "./types";

// Те же сценарии, что в тестах нативной версии: у каждого шага есть обратный.

const make = (ids = ["a", "b", "c"]) =>
  S.createSession({ kind: "custom", title: "Руки", bodyParts: ["Руки"], exerciseIds: ids, now: 0, id: "s1" });

describe("сессия тренировки", () => {
  it("проходит список и спрашивает «Ещё хочешь?»", () => {
    let s = make();
    s = S.next(S.next(s));
    expect(S.currentExerciseId(s)).toBe("c");
    s = S.next(s);
    expect(s.phase).toBe("askingMore");
    expect(S.completedExerciseIds(s)).toEqual(["a", "b", "c"]);
  });

  it("у каждого шага есть обратный", () => {
    let s = make();
    s = S.undoSet(S.markSetDone(S.markSetDone(s, 3), 3));
    expect(S.currentSetsDone(s)).toBe(1);
    s = S.previous(S.next(s));
    expect(S.currentExerciseId(s)).toBe("a");
    expect(S.currentSetsDone(s)).toBe(1);
    s = S.next(S.next(S.next(s)));
    expect(s.phase).toBe("askingMore");
    s = S.previous(s);
    expect([s.phase, S.currentExerciseId(s)]).toEqual(["exercising", "c"]);
    s = S.cancelPicking(S.wantMore(S.next(s)));
    expect(s.phase).toBe("askingMore");
  });

  it("подходы не больше известного числа", () => {
    let s = make();
    for (let i = 0; i < 5; i += 1) s = S.markSetDone(s, 3);
    expect(S.currentSetsDone(s)).toBe(3);
  });

  it("добор продолжает с первого нового упражнения", () => {
    let s = S.wantMore(S.next(make(["a"])));
    s = S.append(s, ["b", "a"], ["Попа"]);
    expect([s.phase, S.currentExerciseId(s)]).toEqual(["exercising", "b"]);
    expect(s.bodyParts).toEqual(["Руки", "Попа"]);
    s = S.next(S.next(s));
    expect(S.completedExerciseIds(s)).toEqual(["a", "b", "a"]);
    expect(S.append(S.wantMore(s), []).phase).toBe("askingMore");
  });

  it("в историю — только начатое", () => {
    let s = S.next(make());
    const names = (id: string) => id.toUpperCase();
    expect(S.historyEntry(s, names)?.exerciseIds).toEqual(["a"]);
    s = S.markSetDone(s, null);
    expect(S.historyEntry(s, names)?.exerciseNames).toEqual(["A", "B"]);
    expect(S.historyEntry(make(), names)).toBeNull();
  });
});

const manifest: Manifest = {
  schemaVersion: 1,
  generatedAt: "2026-09-19T00:00:00Z",
  bodyParts: ["Руки", "Попа"],
  exercises: [
    { id: "руки/молот", name: "Молот", bodyPart: "Руки", details: "", photos: [], videos: [], version: "1" },
    { id: "попа/сумо", name: "Сумо", bodyPart: "Попа", details: "", photos: [], videos: [], version: "1" },
  ],
  workouts: [],
  issues: [],
  contentVersion: "v1",
};

describe("хранилище", () => {
  beforeEach(() => {
    store.resetForTests();
    store.applyManifest(manifest, 0);
  });

  it("черновик: порядок таблицы и чистка удалённого", () => {
    store.toggleDraftPart("Попа");
    store.toggleDraftPart("Руки");
    expect(store.getState().draft.bodyParts).toEqual(["Руки", "Попа"]);
    store.toggleDraftExercise("попа/сумо");
    store.toggleDraftExercise("руки/молот");
    store.toggleDraftExercise("руки/удалённое");
    expect(store.orderedDraft()).toEqual(["руки/молот", "попа/сумо"]);
    store.pruneDraft();
    expect(store.getState().draft.exerciseIds).toHaveLength(2);
  });

  it("избранное и удаление истории отменяются", () => {
    store.toggleFavorite("руки/молот", "exercise", "Молот");
    store.toggleFavorite("руки/молот", "exercise", "Молот");
    expect(store.getState().favorites).toHaveLength(0);
    store.toastAction();
    expect(store.getState().favorites).toHaveLength(1);

    store.toggleDraftPart("Руки");
    store.toggleDraftExercise("руки/молот");
    store.startCustom();
    store.updateSession((s) => S.next(s));
    const entry = store.finishSession()!;
    expect(store.getState().history).toHaveLength(1);
    store.deleteHistory(entry);
    expect(store.getState().history).toHaveLength(0);
    store.toastAction();
    store.addHistory(entry);
    expect(store.getState().history).toEqual([entry]);
  });

  it("после начала тренировки выбор сбрасывается — следующая собирается с нуля", () => {
    // Наблюдение Жени 2026-09-20: новая тренировка открывалась с отметками предыдущей.
    store.toggleDraftPart("Руки");
    store.toggleDraftExercise("руки/молот");
    expect(store.startCustom()).toBe(true);
    expect(store.getState().draft).toEqual({ bodyParts: [], exerciseIds: [] });
    expect(store.getState().session?.queue).toEqual(["руки/молот"]);
  });

  it("резервная копия объединяется без дублей", () => {
    store.addHistory({ id: "h1", startedAt: 0, finishedAt: 1, kind: "custom", title: "Руки", bodyParts: [], exerciseIds: ["x"], exerciseNames: ["X"] });
    const backup = store.exportBackup();
    store.resetForTests();
    expect(store.importBackup(backup)).toEqual({ history: 1, favorites: 0 });
    expect(store.importBackup(backup)).toEqual({ history: 0, favorites: 0 });
    expect(() => store.importBackup({ foo: 1 })).toThrow();
  });

  it("таймер считает от времени окончания", () => {
    store.startRest(60, 1000);
    store.extendRest(15);
    expect(store.checkRest(1000 + 60_000)).toBe(false);
    expect(store.checkRest(1000 + 75_000)).toBe(true);
    expect(store.getState().rest).toBe("finished");
  });
});

describe("напоминание в календарь", () => {
  it("первое событие — ближайший выбранный день", () => {
    // Пятница 18.09.2026, 20:00 — после 19:00, поэтому следующее — понедельник 21.09.
    const now = new Date(2026, 8, 18, 20, 0);
    const first = firstOccurrence({ ...defaultSettings, reminderWeekdays: [1, 3, 5] }, now);
    expect([first.getDate(), first.getHours()]).toEqual([21, 19]);
    expect(reminderQuery(defaultSettings, now)).toBe("days=MO,WE,FR&start=20260921T190000&end=20260921T200000");
  });

  it("файл напоминания содержит повтор, время и будильник", () => {
    const now = new Date(2026, 8, 18, 20, 0);
    const text = icsText({ ...defaultSettings, reminderWeekdays: [1, 3, 5] }, now);
    expect(text).toContain("RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR");
    expect(text).toContain("DTSTART:20260921T190000");
    expect(text).toContain("BEGIN:VALARM");
    expect(text.split("\r\n")[0]).toBe("BEGIN:VCALENDAR");
    expect(scheduleText({ ...defaultSettings, reminderWeekdays: [1, 5] })).toBe("понедельник, пятница в 19:00");
  });

  it("склонения", () => {
    expect([1, 3, 5, 11, 22].map((n) => plural(n, "а", "б", "в"))).toEqual(["а", "б", "в", "в", "б"]);
  });
});
