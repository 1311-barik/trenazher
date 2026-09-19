import { useEffect } from "react";
import { playRestFinished } from "../lib/platform";
import * as store from "../lib/store";
import { useStore } from "../lib/store";
import { Toast, VideoPlayer } from "./components";
import { Icon } from "./icons";
import { useRoute } from "./router";
import { Home } from "./screens/Home";
import { ExercisePage, Favorites, History, HistoryDetail } from "./screens/Lists";
import { BodyParts, ExercisePicker, ReadyWorkouts, WorkoutDetail } from "./screens/Pickers";
import { Issues, Settings } from "./screens/Settings";
import { WorkoutFlow } from "./screens/Workout";

export function App({ onUpdate }: { onUpdate: () => void }) {
  const route = useRoute();
  const updateAvailable = useStore((s) => s.updateAvailable);
  const rest = useStore((s) => s.rest);

  // Тикер таймера отдыха живёт на уровне приложения: отдых кончится, даже если открыт другой экран.
  useEffect(() => {
    if (!rest || rest === "finished") return;
    const timer = setInterval(() => {
      if (store.checkRest()) playRestFinished();
    }, 250);
    return () => clearInterval(timer);
  }, [rest]);

  return (
    <>
      {updateAvailable ? (
        <div className="card banner" style={{ margin: "calc(var(--safe-top) + 8px) 16px 0" }}>
          <Icon name="download" />
          <div className="grow small">Вышла новая версия приложения.</div>
          <button className="btn-text blue" onClick={onUpdate}>Обновить</button>
        </div>
      ) : null}
      <Screen route={route} />
      <VideoPlayer />
      <Toast />
    </>
  );
}

function Screen({ route }: { route: string[] }) {
  const [first, second] = route;
  switch (first) {
    case "ready": return <ReadyWorkouts />;
    case "workout": return second ? <WorkoutDetail id={second} /> : <ReadyWorkouts />;
    case "custom": return second === "exercises" ? <ExercisePicker mode="draft" /> : <BodyParts />;
    case "exercise": return <ExercisePage id={second ?? ""} />;
    case "favorites": return <Favorites />;
    case "history": return second ? <HistoryDetail id={second} /> : <History />;
    case "settings": return second === "issues" ? <Issues /> : <Settings />;
    case "session": return <WorkoutFlow />;
    default: return <Home />;
  }
}
