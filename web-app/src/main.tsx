import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { registerSW } from "virtual:pwa-register";
import { loadManifest, requestPersistentStorage, watchConnection } from "./lib/platform";
import { getState, setState } from "./lib/store";
import { App } from "./ui/App";
import { ErrorBoundary } from "./ui/ErrorBoundary";
import "./styles.css";

// Обновление приложения не перезагружает страницу посреди подхода: показываем «Обновить».
const updateSW = registerSW({
  onNeedRefresh() {
    setState({ updateAvailable: true });
  },
});

watchConnection(() => void loadManifest());
void loadManifest();
void requestPersistentStorage();

// Вернулись в приложение — подтягиваем свежие упражнения (не чаще раза в 10 минут).
document.addEventListener("visibilitychange", () => {
  const fetchedAt = getState().content.fetchedAt ?? 0;
  if (document.visibilityState === "visible" && Date.now() - fetchedAt > 10 * 60 * 1000) void loadManifest();
});

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <ErrorBoundary>
      <App onUpdate={() => void updateSW(true)} />
    </ErrorBoundary>
  </StrictMode>,
);
