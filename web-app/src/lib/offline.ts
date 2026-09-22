/** Пакетное скачивание видео для офлайна. Логика вынесена из экрана, чтобы её можно было проверить без браузера. */

export type DownloadResult = { done: number; failed: number; outOfSpace: boolean };

/** Нехватка места: современный `QuotaExceededError` или старый код 22 в Safari. */
export function isOutOfSpace(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const { name, code } = error as { name?: string; code?: number };
  return name === "QuotaExceededError" || code === 22;
}

/**
 * Качает по одному. Обычная ошибка — пропускаем файл и идём дальше, чтобы докачать остальное.
 * Кончилось место — останавливаемся сразу: дальше будет то же самое, а пользователю нужно
 * освободить место, а не ждать конца списка (ТЗ 6.5).
 */
export async function downloadVideos<T>(
  items: T[],
  cacheOne: (item: T) => Promise<void>,
  onProgress?: (done: number, total: number) => void,
): Promise<DownloadResult> {
  const result: DownloadResult = { done: 0, failed: 0, outOfSpace: false };
  for (const [index, item] of items.entries()) {
    try {
      await cacheOne(item);
      result.done += 1;
    } catch (error) {
      result.failed += 1;
      if (isOutOfSpace(error)) {
        result.outOfSpace = true;
        onProgress?.(index + 1, items.length);
        break;
      }
    }
    onProgress?.(index + 1, items.length);
  }
  return result;
}
