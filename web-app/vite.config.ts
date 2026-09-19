/// <reference types="vitest" />
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { VitePWA } from "vite-plugin-pwa";

// Относительные пути: приложение работает и в корне домена, и в подпапке.
export default defineConfig({
  base: "./",
  build: { target: ["es2020", "safari14"] },
  plugins: [
    react(),
    VitePWA({
      strategies: "injectManifest",
      srcDir: "src",
      filename: "sw.ts",
      registerType: "prompt",
      injectRegister: false,
      includeAssets: ["icons/apple-touch-icon.png"],
      manifest: {
        name: "Тренажёр",
        short_name: "Тренажёр",
        description: "Тренировки с гантелями: готовые и свои, карточки упражнений с фото и видео",
        lang: "ru",
        start_url: "./",
        scope: "./",
        display: "standalone",
        background_color: "#06142F",
        theme_color: "#06142F",
        icons: [
          { src: "icons/icon-192.png", sizes: "192x192", type: "image/png" },
          { src: "icons/icon-512.png", sizes: "512x512", type: "image/png" },
          { src: "icons/icon-maskable-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
        ],
      },
      injectManifest: { globPatterns: ["**/*.{js,css,html,png,svg,webmanifest}"] },
    }),
  ],
  // Локальная разработка на живом контенте: /content и календарь — с боевого сервера.
  server: {
    host: true,
    proxy: {
      "/content": { target: "https://trenazher-135-181-197-13.nip.io", changeOrigin: true },
      "/reminder.ics": { target: "https://trenazher-135-181-197-13.nip.io", changeOrigin: true },
    },
  },
  test: { environment: "node" },
});
