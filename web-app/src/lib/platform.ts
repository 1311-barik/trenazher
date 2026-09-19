import { applyManifest, contentFailed, getState, setState } from "./store";
import type { Manifest, MediaItem } from "./types";

// Связь с браузером: загрузка контента, офлайн-кэш видео, звук таймера, «не гасить экран».

export const CONTENT_BASE = "content/";
export const mediaUrl = (path: string) => CONTENT_BASE + path;

const IMAGE_CACHE = "trenazher-images";
const VIDEO_CACHE = "trenazher-videos";

export async function loadManifest(): Promise<void> {
  try {
    const response = await fetch(`${CONTENT_BASE}manifest.json`, { cache: "no-cache" });
    if (!response.ok) throw new Error(`сервер ответил ${response.status}`);
    const manifest = (await response.json()) as Manifest;
    const current = getState().content.manifest;
    if (!current || current.contentVersion !== manifest.contentVersion || current.generatedAt !== manifest.generatedAt) {
      applyManifest(manifest);
    } else {
      applyManifest(current);
    }
    void prefetchImages(manifest);
  } catch (error) {
    const offline = typeof navigator !== "undefined" && !navigator.onLine;
    contentFailed(offline ? "Нет интернета — работает всё, что уже загружено." : `Не удалось обновить упражнения: ${(error as Error).message}.`);
  }
}

/** Фото и обложки небольшие — докачиваем все, чтобы без интернета карточки были с картинками. */
async function prefetchImages(manifest: Manifest): Promise<void> {
  if (typeof caches === "undefined" || !navigator.onLine) return;
  const urls = new Set<string>();
  for (const e of manifest.exercises) {
    for (const p of e.photos) if (p.ready) [p.url, p.thumbUrl].forEach((u) => u && urls.add(mediaUrl(u)));
    for (const v of e.videos) if (v.ready && v.posterUrl) urls.add(mediaUrl(v.posterUrl));
  }
  const cache = await caches.open(IMAGE_CACHE);
  const queue = [...urls];
  const worker = async () => {
    for (let url = queue.shift(); url; url = queue.shift()) {
      try {
        if (!(await cache.match(url))) await cache.add(url);
      } catch {
        // следующая загрузка попробует снова
      }
    }
  };
  await Promise.all([worker(), worker(), worker(), worker()]);
}

// --- Видео без интернета ---

export async function isVideoCached(item: MediaItem): Promise<boolean> {
  if (typeof caches === "undefined") return false;
  const cache = await caches.open(VIDEO_CACHE);
  return Boolean(await cache.match(mediaUrl(item.url)));
}

export async function cacheVideo(item: MediaItem): Promise<void> {
  if (typeof caches === "undefined") throw new Error("Браузер не умеет хранить файлы");
  await requestPersistentStorage();
  const cache = await caches.open(VIDEO_CACHE);
  const response = await fetch(mediaUrl(item.url));
  if (!response.ok) throw new Error(`сервер ответил ${response.status}`);
  await cache.put(mediaUrl(item.url), response);
}

export async function removeCachedVideos(): Promise<void> {
  if (typeof caches !== "undefined") await caches.delete(VIDEO_CACHE);
}

export async function cachedVideoUrls(): Promise<Set<string>> {
  if (typeof caches === "undefined") return new Set();
  const cache = await caches.open(VIDEO_CACHE);
  const keys = await cache.keys();
  return new Set(keys.map((r) => new URL(r.url).pathname));
}

export async function storageEstimate(): Promise<{ usage: number; quota: number } | null> {
  if (typeof navigator === "undefined" || !navigator.storage?.estimate) return null;
  const { usage = 0, quota = 0 } = await navigator.storage.estimate();
  return { usage, quota };
}

/** Просим браузер не удалять данные при нехватке места. */
export async function requestPersistentStorage(): Promise<void> {
  try {
    if (navigator.storage?.persist && !(await navigator.storage.persisted())) await navigator.storage.persist();
  } catch {
    // не критично
  }
}

// --- Сеть ---

export function watchConnection(onBack: () => void): void {
  window.addEventListener("online", () => {
    setState({ online: true });
    onBack();
  });
  window.addEventListener("offline", () => setState({ online: false }));
}

// --- Звук окончания отдыха (Web Audio; разблокируется нажатием на кнопку) ---

let audio: AudioContext | null = null;

export function unlockAudio(): void {
  try {
    const Context = window.AudioContext ?? (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
    if (!audio && Context) audio = new Context();
    void audio?.resume();
  } catch {
    audio = null;
  }
}

export function playRestFinished(): void {
  if (!audio) return;
  const start = audio.currentTime;
  for (let i = 0; i < 3; i += 1) {
    const osc = audio.createOscillator();
    const gain = audio.createGain();
    osc.frequency.value = 880;
    gain.gain.setValueAtTime(0.0001, start + i * 0.25);
    gain.gain.exponentialRampToValueAtTime(0.4, start + i * 0.25 + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.0001, start + i * 0.25 + 0.18);
    osc.connect(gain).connect(audio.destination);
    osc.start(start + i * 0.25);
    osc.stop(start + i * 0.25 + 0.2);
  }
  navigator.vibrate?.([200, 100, 200]);
}

// --- Не гасить экран во время тренировки ---

let wakeLock: WakeLockSentinel | null = null;

export async function keepScreenOn(enabled: boolean): Promise<void> {
  try {
    if (enabled && "wakeLock" in navigator && !wakeLock) {
      wakeLock = await navigator.wakeLock.request("screen");
      wakeLock.addEventListener("release", () => {
        wakeLock = null;
      });
    } else if (!enabled && wakeLock) {
      await wakeLock.release();
      wakeLock = null;
    }
  } catch {
    wakeLock = null;
  }
}

export const isStandalone = () =>
  (typeof window !== "undefined" && window.matchMedia?.("(display-mode: standalone)").matches) ||
  Boolean((navigator as unknown as { standalone?: boolean }).standalone);

export const getSettings = () => getState().settings;
