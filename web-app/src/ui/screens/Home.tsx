import { useState } from "react";
import { isStandalone, loadManifest } from "../../lib/platform";
import * as S from "../../lib/session";
import * as store from "../../lib/store";
import { useStore } from "../../lib/store";
import { formatRelative, workoutsText } from "../../lib/text";
import { EmptyState, SyncStatus } from "../components";
import { Icon } from "../icons";
import { go } from "../router";

export function Home() {
  const content = useStore((s) => s.content);
  const session = useStore((s) => s.session);
  const historyCount = useStore((s) => s.history.length);
  const favoritesCount = useStore((s) => s.favorites.length);
  const storageError = useStore((s) => s.storageError);
  const manifest = content.manifest;

  return (
    <div className="screen">
      <div className="content" style={{ paddingTop: "calc(var(--safe-top) + 16px)" }}>
        <div>
          <h1 className="title-xl">ТРЕНАЖЁР</h1>
          <div className="muted small">
            {historyCount ? `Тренировок завершено: ${historyCount}` : "Выбери готовую тренировку или собери свою"}
          </div>
        </div>

        <InstallHint />
        {session ? <ResumeCard /> : null}

        {!manifest ? (
          <FirstLoad />
        ) : (
          <>
            <button className="main-action tappable" onClick={() => go("/ready")}>
              <span className="badge blue"><Icon name="list" size={28} /></span>
              <span className="text">
                <span className="title-m" style={{ display: "block" }}>Готовая тренировка</span>
                <span className="muted small">{manifest.workouts.length ? `В списке: ${workoutsText(manifest.workouts.length)}` : "Список скоро появится"}</span>
              </span>
              <span className="faint"><Icon name="forward" /></span>
            </button>
            <button className="main-action tappable" onClick={() => go("/custom")}>
              <span className="badge gold"><Icon name="grid" size={28} /></span>
              <span className="text">
                <span className="title-m" style={{ display: "block" }}>Собрать свою тренировку</span>
                <span className="muted small">Выбрать части тела и отметить упражнения</span>
              </span>
              <span className="faint"><Icon name="forward" /></span>
            </button>
          </>
        )}

        <div className="tiles">
          <button className="tile" onClick={() => go("/favorites")}>
            <Icon name="heart" filled /><span className="small muted" style={{ fontWeight: 650 }}>Избранное</span>
            {favoritesCount ? <span className="tiny faint">{favoritesCount}</span> : null}
          </button>
          <button className="tile" onClick={() => go("/history")}>
            <Icon name="history" /><span className="small muted" style={{ fontWeight: 650 }}>История</span>
            {historyCount ? <span className="tiny faint">{historyCount}</span> : null}
          </button>
          <button className="tile" onClick={() => go("/settings")}>
            <Icon name="gear" /><span className="small muted" style={{ fontWeight: 650 }}>Настройки</span>
          </button>
        </div>

        {storageError ? <div className="warn small" role="alert">{storageError}</div> : null}
        <SyncStatus />
      </div>
    </div>
  );
}

/** «Продолжить тренировку» — если приложение закрыли посреди тренировки. */
function ResumeCard() {
  const session = useStore((s) => s.session)!;
  const manifest = useStore((s) => s.content.manifest);
  const current = store.contentIndex(manifest).byId.get(S.currentExerciseId(session) ?? "")?.name ?? "—";
  const pos = S.position(session);

  const discard = () => {
    if (window.confirm("Удалить тренировку без сохранения? Отмеченные упражнения и подходы не попадут в историю. Это нельзя отменить.")) {
      store.discardSession();
    }
  };

  return (
    <div className="card selected pad" style={{ display: "flex", flexDirection: "column", gap: 12 }}>
      <div className="title-m">▶ Незавершённая тренировка</div>
      <div className="muted small">
        {session.title} · начата {formatRelative(session.startedAt)}<br />
        Сейчас: {current} ({pos.index} из {pos.total})
      </div>
      <div className="row-buttons">
        <button className="btn btn-primary green" onClick={() => go("/session")}>Продолжить</button>
        <button className="btn btn-secondary" onClick={() => { store.finishSession(); go("/session"); }}>Завершить</button>
      </div>
      <button className="btn-text" onClick={discard}>Удалить без сохранения</button>
    </div>
  );
}

function FirstLoad() {
  const content = useStore((s) => s.content);
  const online = useStore((s) => s.online);
  if (content.status === "loading") {
    return (
      <div className="card empty"><span className="spinner" /><span className="muted small">Загружаю упражнения из таблицы Жени…</span></div>
    );
  }
  if (!online) {
    return <EmptyState icon="wifiOff" title="Нужен интернет" message="Для первой загрузки упражнений нужен интернет. Потом всё загруженное работает без него."
      actionTitle="Повторить" onAction={() => void loadManifest()} />;
  }
  return <EmptyState icon="alert" title="Упражнения ещё не загружены" message={content.error ?? "Попробуйте ещё раз через минуту."}
    actionTitle="Повторить" onAction={() => void loadManifest()} />;
}

/** Подсказка установки — пока приложение открыто в Safari, а не с экрана «Домой». Скрывается навсегда. */
function InstallHint() {
  const [hidden, setHidden] = useState(() => {
    try {
      return isStandalone() || localStorage.getItem("trenazher.installHintHidden") === "1";
    } catch {
      return isStandalone();
    }
  });
  if (hidden) return null;
  const hide = () => {
    try {
      localStorage.setItem("trenazher.installHintHidden", "1");
    } catch {
      // не страшно — просто покажем ещё раз
    }
    setHidden(true);
  };
  return (
    <div className="card banner">
      <span className="muted"><Icon name="share" /></span>
      <div className="grow small">
        <b>Установите на экран «Домой»</b><br />
        <span className="muted">В Safari: кнопка «Поделиться» → «На экран „Домой“». Так приложение откроется на весь экран и будет работать без интернета.</span>
      </div>
      <button className="btn-icon plain" onClick={hide} aria-label="Скрыть подсказку"><Icon name="close" size={18} /></button>
    </div>
  );
}
