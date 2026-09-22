import { useSyncExternalStore } from "react";
import * as S from "./session";
import type { WorkoutSession } from "./session";
import type { Exercise, FavoriteItem, HistoryEntry, Manifest, Settings, Workout } from "./types";
import { defaultSettings } from "./types";

// Всё состояние приложения. Данные Андрея хранятся на устройстве (localStorage),
// сохраняются после каждого действия и переживают закрытие приложения.

export interface Toast {
  id: number;
  message: string;
  actionTitle?: string;
  action?: () => void;
}

export interface ContentState {
  manifest: Manifest | null;
  status: "loading" | "ready" | "error";
  error?: string;
  /** Когда манифест последний раз пришёл с сервера. */
  fetchedAt?: number;
}

export type RestState = { endsAt: number; total: number } | "finished" | null;

export interface Draft {
  bodyParts: string[];
  exerciseIds: string[];
}

export interface AppState {
  favorites: FavoriteItem[];
  history: HistoryEntry[];
  settings: Settings;
  draft: Draft;
  session: WorkoutSession | null;
  /** Итог только что завершённой тренировки — экран завершения. */
  finished: HistoryEntry | null;
  rest: RestState;
  toast: Toast | null;
  content: ContentState;
  online: boolean;
  updateAvailable: boolean;
  storageError?: string;
}

// --- Хранилище с защитой от приватного режима и переполнения ---

const PREFIX = "trenazher.v1.";
const memory = new Map<string, string>();

function read<T>(key: string, fallback: T): T {
  try {
    const raw = typeof localStorage !== "undefined" ? localStorage.getItem(PREFIX + key) : memory.get(PREFIX + key) ?? null;
    return raw ? (JSON.parse(raw) as T) : fallback;
  } catch {
    return fallback;
  }
}

function write(key: string, value: unknown): string | undefined {
  const raw = JSON.stringify(value);
  try {
    if (typeof localStorage !== "undefined") {
      if (value === null || value === undefined) localStorage.removeItem(PREFIX + key);
      else localStorage.setItem(PREFIX + key, raw);
    } else {
      memory.set(PREFIX + key, raw);
    }
    return undefined;
  } catch {
    return "Не удалось сохранить данные на устройстве — возможно, закончилось место. Последнее действие может не сохраниться.";
  }
}

const PERSISTED = ["favorites", "history", "settings", "draft", "session"] as const;

function initialState(): AppState {
  const cachedManifest = read<Manifest | null>("manifest", null);
  return {
    favorites: read("favorites", []),
    history: read("history", []),
    settings: { ...defaultSettings, ...read<Partial<Settings>>("settings", {}) },
    draft: read("draft", { bodyParts: [], exerciseIds: [] }),
    session: read("session", null),
    finished: null,
    rest: null,
    toast: null,
    content: { manifest: cachedManifest, status: cachedManifest ? "ready" : "loading", fetchedAt: read<number | undefined>("fetchedAt", undefined) },
    online: typeof navigator === "undefined" ? true : navigator.onLine,
    updateAvailable: false,
  };
}

let state: AppState = initialState();
const listeners = new Set<() => void>();

export function getState(): AppState {
  return state;
}

export function setState(patch: Partial<AppState>): void {
  const next = { ...state, ...patch };
  let storageError: string | undefined;
  for (const key of PERSISTED) {
    if (key in patch && patch[key] !== state[key]) storageError = write(key, next[key]) ?? storageError;
  }
  if (storageError) next.storageError = storageError;
  state = next;
  listeners.forEach((l) => l());
}

export function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function useStore<T>(selector: (s: AppState) => T): T {
  return useSyncExternalStore(subscribe, () => selector(state), () => selector(state));
}

/** Только для тестов. */
export function resetForTests(): void {
  memory.clear();
  state = initialState();
}

// --- Контент ---

export interface ContentIndex {
  byId: Map<string, Exercise>;
  byPart: Map<string, Exercise[]>;
  workoutsById: Map<string, Workout>;
}

let indexCache: { manifest: Manifest | null; index: ContentIndex } | null = null;

export function contentIndex(manifest: Manifest | null): ContentIndex {
  if (indexCache && indexCache.manifest === manifest) return indexCache.index;
  const byId = new Map<string, Exercise>();
  const byPart = new Map<string, Exercise[]>();
  for (const e of manifest?.exercises ?? []) {
    byId.set(e.id, e);
    byPart.set(e.bodyPart, [...(byPart.get(e.bodyPart) ?? []), e]);
  }
  const workoutsById = new Map((manifest?.workouts ?? []).map((w) => [w.id, w] as const));
  const index = { byId, byPart, workoutsById };
  indexCache = { manifest, index };
  return index;
}

export function applyManifest(manifest: Manifest, fetchedAt = Date.now()): void {
  write("manifest", manifest);
  write("fetchedAt", fetchedAt);
  setState({ content: { manifest, status: "ready", fetchedAt } });
  pruneDraft();
}

export function contentFailed(error: string): void {
  // Прежний контент остаётся — приложение работает с тем, что уже скачано.
  const current = state.content;
  setState({ content: { ...current, status: current.manifest ? "ready" : "error", error } });
}

export const bodyPartsFor = (ids: string[]): string[] => {
  const { byId } = contentIndex(state.content.manifest);
  const parts = new Set(ids.map((id) => byId.get(id)?.bodyPart).filter(Boolean) as string[]);
  return (state.content.manifest?.bodyParts ?? []).filter((p) => parts.has(p));
};

// --- Тосты с «Отменить» ---

let toastTimer: ReturnType<typeof setTimeout> | undefined;
let toastSeq = 0;

export function showToast(message: string, actionTitle?: string, action?: () => void): void {
  toastSeq += 1;
  const toast: Toast = { id: toastSeq, message, actionTitle, action };
  setState({ toast });
  if (toastTimer) clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    if (state.toast?.id === toast.id) setState({ toast: null });
  }, action ? 4500 : 2500);
}

export function toastAction(): void {
  state.toast?.action?.();
  setState({ toast: null });
}

// --- Избранное ---

export const isFavorite = (s: AppState, itemId: string, type: FavoriteItem["type"]) =>
  s.favorites.some((f) => f.itemId === itemId && f.type === type);

export function toggleFavorite(itemId: string, type: FavoriteItem["type"], title: string): void {
  if (isFavorite(state, itemId, type)) {
    const removed = state.favorites.find((f) => f.itemId === itemId && f.type === type)!;
    setState({ favorites: state.favorites.filter((f) => f !== removed) });
    showToast("Убрано из избранного", "Отменить", () => {
      if (!isFavorite(state, itemId, type)) setState({ favorites: [removed, ...state.favorites] });
    });
  } else {
    setState({ favorites: [{ itemId, type, title, createdAt: Date.now() }, ...state.favorites] });
    showToast("Добавлено в избранное");
  }
}

// --- История ---

function sortHistory(entries: HistoryEntry[]): HistoryEntry[] {
  return [...entries].sort((a, b) => b.finishedAt - a.finishedAt);
}

export function addHistory(entry: HistoryEntry): void {
  // Та же запись повторно (например, после «Отменить») не создаёт дубль.
  setState({ history: sortHistory([entry, ...state.history.filter((h) => h.id !== entry.id)]) });
}

export function deleteHistory(entry: HistoryEntry): void {
  setState({ history: state.history.filter((h) => h.id !== entry.id) });
  showToast("Тренировка удалена из истории", "Отменить", () => addHistory(entry));
}

// --- Настройки ---

export function updateSettings(patch: Partial<Settings>): void {
  setState({ settings: { ...state.settings, ...patch } });
}

// --- Черновик своей тренировки (переживает выход и перезапуск) ---

export function toggleDraftPart(part: string): void {
  const order = state.content.manifest?.bodyParts ?? [];
  const parts = state.draft.bodyParts.includes(part)
    ? state.draft.bodyParts.filter((p) => p !== part)
    : [...state.draft.bodyParts, part].sort((a, b) => order.indexOf(a) - order.indexOf(b));
  setState({ draft: { ...state.draft, bodyParts: parts } });
}

export function toggleDraftExercise(id: string): void {
  const ids = state.draft.exerciseIds.includes(id)
    ? state.draft.exerciseIds.filter((x) => x !== id)
    : [...state.draft.exerciseIds, id];
  setState({ draft: { ...state.draft, exerciseIds: ids } });
}

export function resetDraft(): void {
  setState({ draft: { bodyParts: [], exerciseIds: [] } });
}

/** Упражнения черновика в порядке показа: по разделам, внутри — как в таблице. */
export function orderedDraft(): string[] {
  const { byPart } = contentIndex(state.content.manifest);
  const selected = new Set(state.draft.exerciseIds);
  return state.draft.bodyParts.flatMap((p) => (byPart.get(p) ?? []).map((e) => e.id)).filter((id) => selected.has(id));
}

/** После обновления контента убираем из черновика то, чего больше нет. */
export function pruneDraft(): void {
  const manifest = state.content.manifest;
  if (!manifest) return;
  const { byPart } = contentIndex(manifest);
  const parts = state.draft.bodyParts.filter((p) => manifest.bodyParts.includes(p));
  const valid = new Set(parts.flatMap((p) => (byPart.get(p) ?? []).map((e) => e.id)));
  const ids = state.draft.exerciseIds.filter((id) => valid.has(id));
  if (parts.length !== state.draft.bodyParts.length || ids.length !== state.draft.exerciseIds.length) {
    setState({ draft: { bodyParts: parts, exerciseIds: ids } });
  }
}

// --- Тренировка ---

function begin(session: WorkoutSession): void {
  setState({ session, finished: null, rest: null });
}

export function startWorkout(workout: Workout): boolean {
  const { byId } = contentIndex(state.content.manifest);
  const ids = workout.exerciseIds.filter((id) => byId.has(id));
  if (ids.length === 0) return false;
  begin(S.createSession({ kind: "ready", workoutId: workout.id, title: workout.title, bodyParts: bodyPartsFor(ids), exerciseIds: ids }));
  return true;
}

export function startCustom(): boolean {
  const ids = orderedDraft();
  if (ids.length === 0) return false;
  const parts = state.draft.bodyParts;
  begin(S.createSession({ kind: "custom", title: parts.length ? parts.join(" + ") : "Своя тренировка", bodyParts: parts, exerciseIds: ids }));
  // Черновик нужен, пока тренировку собирают: вышел с экрана — выбор не потерялся.
  // Как только тренировка началась, выбор «израсходован»: следующая собирается с нуля.
  // Повторить прежний набор можно из Истории — «Повторить эту тренировку».
  resetDraft();
  return true;
}

export function startSingle(exercise: Exercise): void {
  begin(S.createSession({ kind: "custom", title: exercise.name, bodyParts: [exercise.bodyPart], exerciseIds: [exercise.id] }));
}

export function repeatFromHistory(entry: HistoryEntry): boolean {
  const { byId } = contentIndex(state.content.manifest);
  const ids = entry.exerciseIds.filter((id) => byId.has(id));
  if (ids.length === 0) {
    showToast("Этих упражнений больше нет в таблице");
    return false;
  }
  begin(S.createSession({ kind: entry.kind, title: entry.title, bodyParts: bodyPartsFor(ids), exerciseIds: ids }));
  return true;
}

export function updateSession(change: (s: WorkoutSession) => WorkoutSession): void {
  if (state.session) setState({ session: change(state.session) });
}

/** Завершить с сохранением в историю. Пустую тренировку не сохраняем. */
export function finishSession(): HistoryEntry | null {
  const session = state.session;
  if (!session) return null;
  const { byId } = contentIndex(state.content.manifest);
  const entry = S.historyEntry(session, (id) => byId.get(id)?.name);
  if (entry) addHistory(entry);
  else showToast("Тренировка закрыта без записи: ни одного подхода не отмечено");
  setState({ session: null, finished: entry, rest: null });
  resetDraft(); // выбор при доборе, если он был, больше не нужен
  return entry;
}

export function discardSession(): void {
  setState({ session: null, finished: null, rest: null });
  resetDraft();
}

export function closeFinished(): void {
  setState({ finished: null });
}

// --- Таймер отдыха: считает от времени окончания, поэтому не отстаёт в фоне ---

export function startRest(seconds: number, now = Date.now()): void {
  setState({ rest: { endsAt: now + seconds * 1000, total: seconds } });
}

export function extendRest(seconds: number): void {
  const rest = state.rest;
  if (rest && rest !== "finished") setState({ rest: { endsAt: rest.endsAt + seconds * 1000, total: rest.total + seconds } });
}

export function stopRest(): void {
  setState({ rest: null });
}

/** Вызывается тикером; возвращает true, если отдых только что закончился. */
export function checkRest(now = Date.now()): boolean {
  const rest = state.rest;
  if (!rest || rest === "finished" || now < rest.endsAt) return false;
  setState({ rest: "finished" });
  setTimeout(() => {
    if (state.rest === "finished") setState({ rest: null });
  }, 3000);
  return true;
}

// --- Резервная копия (перенос на другое устройство или адрес) ---

export interface Backup {
  app: "trenazher";
  version: 1;
  exportedAt: number;
  favorites: FavoriteItem[];
  history: HistoryEntry[];
  settings: Settings;
}

export function exportBackup(): Backup {
  return { app: "trenazher", version: 1, exportedAt: Date.now(), favorites: state.favorites, history: state.history, settings: state.settings };
}

/** Настройки ещё никто не трогал — на новом устройстве их можно взять из копии. */
function settingsUntouched(settings: Settings): boolean {
  return JSON.stringify(settings) === JSON.stringify(defaultSettings);
}

/** Объединяет копию с текущими данными: ничего не удаляет, дубли не создаёт.
 *  Настройки берутся из копии только на нетронутом устройстве — иначе перезапись без спроса
 *  нарушила бы обещание «ничего не удалено». Весь импорт можно отменить одним нажатием. */
export function importBackup(data: unknown): { history: number; favorites: number; settings: boolean } {
  const backup = data as Partial<Backup>;
  if (!backup || backup.app !== "trenazher" || !Array.isArray(backup.history) || !Array.isArray(backup.favorites)) {
    throw new Error("Это не файл резервной копии Тренажёра.");
  }
  const before = { history: state.history, favorites: state.favorites, settings: state.settings };
  const historyIds = new Set(state.history.map((h) => h.id));
  const newHistory = backup.history.filter((h) => h && h.id && !historyIds.has(h.id));
  const newFavorites = backup.favorites.filter((f) => f && f.itemId && !isFavorite(state, f.itemId, f.type));
  const takeSettings = Boolean(backup.settings) && settingsUntouched(state.settings);
  setState({
    history: sortHistory([...state.history, ...newHistory]),
    favorites: [...state.favorites, ...newFavorites],
    settings: takeSettings ? { ...defaultSettings, ...backup.settings } : state.settings,
  });
  if (newHistory.length || newFavorites.length || takeSettings) {
    showToast("Копия восстановлена", "Отменить", () => setState(before));
  }
  return { history: newHistory.length, favorites: newFavorites.length, settings: takeSettings };
}
