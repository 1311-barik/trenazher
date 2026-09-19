// Формат manifest.json — его собирает content-sync/sync.py на сервере
// (тот же формат, что ContentManifest в нативной версии, плюс адреса обработанных файлов).

export type MediaKind = "photo" | "ownVideo" | "otherVideo";

export interface MediaItem {
  driveFileId: string;
  title: string;
  kind: MediaKind;
  version: string;
  byteSize?: number | null;
  /** Адрес относительно папки контента: фото 1400px или видео MP4. */
  url: string;
  /** Миниатюра фото (400px). */
  thumbUrl?: string;
  /** Обложка видео. */
  posterUrl?: string;
  /** Файл уже обработан на сервере (видео пережимается не мгновенно). */
  ready: boolean;
}

export interface Exercise {
  id: string;
  name: string;
  bodyPart: string;
  muscleGroup?: string | null;
  equipment?: string | null;
  details: string;
  sets?: number | null;
  photos: MediaItem[];
  videos: MediaItem[];
  version: string;
}

export interface Workout {
  id: string;
  title: string;
  summary?: string | null;
  exerciseIds: string[];
  version: string;
}

export interface ContentIssue {
  severity: "error" | "warning" | "info";
  message: string;
}

export interface Manifest {
  schemaVersion: number;
  generatedAt: string;
  bodyParts: string[];
  exercises: Exercise[];
  workouts: Workout[];
  issues: ContentIssue[];
  contentVersion: string;
}

export type WorkoutKind = "ready" | "custom";

export interface FavoriteItem {
  itemId: string;
  type: "exercise" | "workout";
  /** Название на момент добавления — чтобы показать запись, даже если упражнение переименуют. */
  title: string;
  createdAt: number;
}

export interface HistoryEntry {
  id: string;
  startedAt: number;
  finishedAt: number;
  kind: WorkoutKind;
  title: string;
  bodyParts: string[];
  exerciseIds: string[];
  /** Снимок названий на момент тренировки. */
  exerciseNames: string[];
}

export interface Settings {
  restTimerEnabled: boolean;
  /** 30 или 60 секунд; по умолчанию 60. */
  restDurationSeconds: number;
  reminderHour: number;
  reminderMinute: number;
  /** 1 — понедельник … 7 — воскресенье. */
  reminderWeekdays: number[];
}

export const defaultSettings: Settings = {
  restTimerEnabled: true,
  restDurationSeconds: 60,
  reminderHour: 19,
  reminderMinute: 0,
  reminderWeekdays: [1, 3, 5],
};
