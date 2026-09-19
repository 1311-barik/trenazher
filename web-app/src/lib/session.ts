import type { HistoryEntry, WorkoutKind } from "./types";

// Идущая тренировка — чистые функции без UI (порт WorkoutSession из нативной версии).
// Сохраняется после каждого действия: закрыли приложение — продолжим с того же упражнения.

export type Phase = "exercising" | "askingMore" | "pickingMore";

export interface WorkoutSession {
  id: string;
  kind: WorkoutKind;
  workoutId?: string;
  title: string;
  bodyParts: string[];
  /** Упражнения в порядке выполнения; при доборе дописываются в конец, повторы допустимы. */
  queue: string[];
  currentIndex: number;
  /** Отмеченные подходы — по позиции в очереди. */
  setsDone: number[];
  /** Пройденные упражнения — по позиции в очереди. */
  completed: boolean[];
  phase: Phase;
  startedAt: number;
  updatedAt: number;
}

export function createSession(params: {
  kind: WorkoutKind;
  workoutId?: string;
  title: string;
  bodyParts: string[];
  exerciseIds: string[];
  now?: number;
  id?: string;
}): WorkoutSession {
  if (params.exerciseIds.length === 0) throw new Error("Тренировка без упражнений");
  const now = params.now ?? Date.now();
  return {
    id: params.id ?? makeId(),
    kind: params.kind,
    workoutId: params.workoutId,
    title: params.title,
    bodyParts: [...params.bodyParts],
    queue: [...params.exerciseIds],
    currentIndex: 0,
    setsDone: params.exerciseIds.map(() => 0),
    completed: params.exerciseIds.map(() => false),
    phase: "exercising",
    startedAt: now,
    updatedAt: now,
  };
}

export function makeId(): string {
  const random = Math.random().toString(36).slice(2, 10);
  return `${Date.now().toString(36)}-${random}`;
}

export const currentExerciseId = (s: WorkoutSession): string | undefined => s.queue[s.currentIndex];
export const isLastInQueue = (s: WorkoutSession) => s.currentIndex >= s.queue.length - 1;
export const canGoBack = (s: WorkoutSession) => s.currentIndex > 0;
export const currentSetsDone = (s: WorkoutSession) => s.setsDone[s.currentIndex] ?? 0;
export const position = (s: WorkoutSession) => ({ index: s.currentIndex + 1, total: s.queue.length });
export const completedExerciseIds = (s: WorkoutSession) => s.queue.filter((_, i) => s.completed[i]);

const touch = (s: WorkoutSession, now: number): WorkoutSession => ({ ...s, updatedAt: now });

/** «Подход выполнен». Если число подходов известно — не больше него. */
export function markSetDone(s: WorkoutSession, totalSets?: number | null, now = Date.now()): WorkoutSession {
  if (s.phase !== "exercising") return s;
  const done = currentSetsDone(s);
  if (totalSets && done >= totalSets) return s;
  const setsDone = [...s.setsDone];
  setsDone[s.currentIndex] = done + 1;
  return touch({ ...s, setsDone }, now);
}

/** Снять последнюю отметку подхода. */
export function undoSet(s: WorkoutSession, now = Date.now()): WorkoutSession {
  if (s.phase !== "exercising" || currentSetsDone(s) === 0) return s;
  const setsDone = [...s.setsDone];
  setsDone[s.currentIndex] -= 1;
  return touch({ ...s, setsDone }, now);
}

/** «Следующее упражнение»; после последнего — вопрос «Ещё хочешь?». */
export function next(s: WorkoutSession, now = Date.now()): WorkoutSession {
  if (s.phase !== "exercising") return s;
  const completed = [...s.completed];
  completed[s.currentIndex] = true;
  if (isLastInQueue(s)) return touch({ ...s, completed, phase: "askingMore" }, now);
  return touch({ ...s, completed, currentIndex: s.currentIndex + 1 }, now);
}

/** Назад: к предыдущему упражнению или из «Ещё хочешь?» — к последнему. */
export function previous(s: WorkoutSession, now = Date.now()): WorkoutSession {
  if (s.phase === "askingMore") return touch({ ...s, phase: "exercising" }, now);
  if (s.phase === "exercising" && canGoBack(s)) return touch({ ...s, currentIndex: s.currentIndex - 1 }, now);
  return s;
}

export function wantMore(s: WorkoutSession, now = Date.now()): WorkoutSession {
  return s.phase === "askingMore" ? touch({ ...s, phase: "pickingMore" }, now) : s;
}

export function cancelPicking(s: WorkoutSession, now = Date.now()): WorkoutSession {
  return s.phase === "pickingMore" ? touch({ ...s, phase: "askingMore" }, now) : s;
}

/** Добавить упражнения при доборе и продолжить с первого из них. */
export function append(s: WorkoutSession, ids: string[], newParts: string[] = [], now = Date.now()): WorkoutSession {
  if (s.phase !== "pickingMore") return s;
  if (ids.length === 0) return touch({ ...s, phase: "askingMore" }, now);
  const bodyParts = [...s.bodyParts, ...newParts.filter((p) => !s.bodyParts.includes(p))];
  return touch({
    ...s,
    queue: [...s.queue, ...ids],
    setsDone: [...s.setsDone, ...ids.map(() => 0)],
    completed: [...s.completed, ...ids.map(() => false)],
    bodyParts,
    currentIndex: s.queue.length,
    phase: "exercising",
  }, now);
}

/** Запись для истории. Текущее упражнение при досрочном завершении засчитывается,
 *  только если по нему отмечен хотя бы один подход. Пустая тренировка — null. */
export function historyEntry(s: WorkoutSession, names: (id: string) => string | undefined, now = Date.now()): HistoryEntry | null {
  const ids = completedExerciseIds(s);
  const current = currentExerciseId(s);
  if (s.phase === "exercising" && currentSetsDone(s) > 0 && current && !s.completed[s.currentIndex]) ids.push(current);
  if (ids.length === 0) return null;
  return {
    id: s.id,
    startedAt: s.startedAt,
    finishedAt: now,
    kind: s.kind,
    title: s.title,
    bodyParts: s.bodyParts,
    exerciseIds: ids,
    exerciseNames: ids.map((id) => names(id) ?? "Упражнение"),
  };
}

/** Оценка для подсказки при выборе: 4–6 минут на упражнение. */
export const recommendedRange = { min: 10, max: 12 };

export function estimateText(count: number): string {
  return count > 0 ? `≈ ${count * 4}–${count * 6} мин` : "";
}
