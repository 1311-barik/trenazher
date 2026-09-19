/// <reference lib="webworker" />
import { CacheableResponsePlugin } from "workbox-cacheable-response";
import { clientsClaim } from "workbox-core";
import { ExpirationPlugin } from "workbox-expiration";
import { cleanupOutdatedCaches, precacheAndRoute } from "workbox-precaching";
import { RangeRequestsPlugin } from "workbox-range-requests";
import { registerRoute } from "workbox-routing";
import { CacheFirst, NetworkFirst } from "workbox-strategies";

// Офлайн-режим:
// - оболочка приложения — заранее в кэше;
// - manifest.json — сначала сеть, без сети — последняя сохранённая версия;
// - фото и обложки — из кэша (имена с версией, поэтому не устаревают);
// - видео — из кэша, если Андрей скачал их для офлайна (с поддержкой перемотки), иначе потоком из сети.

declare const self: ServiceWorkerGlobalScope & { __WB_MANIFEST: Array<{ url: string; revision: string | null }> };

precacheAndRoute(self.__WB_MANIFEST);
cleanupOutdatedCaches();

registerRoute(
  ({ url }) => url.pathname.endsWith("/content/manifest.json"),
  new NetworkFirst({ cacheName: "trenazher-content", networkTimeoutSeconds: 5 }),
);

registerRoute(
  ({ url }) => /\/content\/media\/(photos|thumbs|posters)\//.test(url.pathname),
  new CacheFirst({
    cacheName: "trenazher-images",
    plugins: [new CacheableResponsePlugin({ statuses: [200] }), new ExpirationPlugin({ maxEntries: 800 })],
  }),
);

// Видео в кэш попадают только по кнопке «Скачать для офлайна» (целиком, ответ 200).
// Частичные ответы (206) при просмотре онлайн не кэшируются.
registerRoute(
  ({ url }) => url.pathname.includes("/content/media/videos/"),
  new CacheFirst({
    cacheName: "trenazher-videos",
    plugins: [new CacheableResponsePlugin({ statuses: [200] }), new RangeRequestsPlugin()],
  }),
);

self.addEventListener("message", (event) => {
  if (event.data?.type === "SKIP_WAITING") void self.skipWaiting();
});

clientsClaim();
