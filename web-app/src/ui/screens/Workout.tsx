import { useEffect, useState } from "react";
import { keepScreenOn, unlockAudio } from "../../lib/platform";
import * as S from "../../lib/session";
import type { WorkoutSession } from "../../lib/session";
import * as store from "../../lib/store";
import { useStore } from "../../lib/store";
import { durationText, exercisesText, plural, timerText } from "../../lib/text";
import type { Exercise, HistoryEntry } from "../../lib/types";
import { BottomBar, EmptyState, ExerciseCardContent } from "../components";
import { Icon } from "../icons";
import { go } from "../router";
import { ExercisePicker } from "./Pickers";

/** Полноэкранная тренировка: карточки → «Ещё хочешь?» → добор или итог. */
export function WorkoutFlow() {
  const session = useStore((s) => s.session);
  const finished = useStore((s) => s.finished);

  // Экран не гаснет, пока идёт тренировка (если браузер это умеет).
  useEffect(() => {
    void keepScreenOn(true);
    const again = () => document.visibilityState === "visible" && void keepScreenOn(true);
    document.addEventListener("visibilitychange", again);
    return () => {
      document.removeEventListener("visibilitychange", again);
      void keepScreenOn(false);
    };
  }, []);

  useEffect(() => {
    if (!session && !finished) go("/", true);
  }, [session, finished]);

  if (finished) return <Finished entry={finished} />;
  if (!session) return null;
  if (session.phase === "askingMore") return <MoreQuestion session={session} />;
  if (session.phase === "pickingMore") return <ExercisePicker mode="addMore" />;
  return <ExerciseStep session={session} />;
}

function ExerciseStep({ session }: { session: WorkoutSession }) {
  const manifest = useStore((s) => s.content.manifest);
  const exercise = store.contentIndex(manifest).byId.get(S.currentExerciseId(session) ?? "");
  const [menu, setMenu] = useState(false);
  const pos = S.position(session);

  useEffect(() => {
    window.scrollTo(0, 0);
  }, [session.currentIndex]);

  const discard = () => {
    setMenu(false);
    if (window.confirm("Прервать без сохранения? Отмеченные упражнения и подходы не попадут в историю. Это нельзя отменить.")) {
      store.discardSession();
    }
  };

  return (
    <div className="screen">
      <div className="session-header">
        <div className="top">
          <button className="btn-icon" onClick={() => go("/")} aria-label="Свернуть тренировку — прогресс сохранится, продолжить можно с главного экрана">
            <Icon name="down" />
          </button>
          <div className="center">
            <div style={{ fontWeight: 800, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{session.title}</div>
            <div className="tiny muted">Упражнение {pos.index} из {pos.total}</div>
          </div>
          <button className="btn-icon" onClick={() => setMenu((v) => !v)} aria-label="Завершить тренировку" aria-expanded={menu}>
            <Icon name="more" />
          </button>
        </div>
        <div className="progress" role="progressbar" aria-valuemin={0} aria-valuemax={pos.total} aria-valuenow={pos.index}
          aria-label="Прогресс тренировки"><div style={{ width: `${(pos.index / pos.total) * 100}%` }} /></div>
        {menu ? (
          <div className="card raised menu" role="menu">
            <button role="menuitem" onClick={() => { setMenu(false); store.finishSession(); }}>Завершить и сохранить</button>
            <button role="menuitem" className="danger" onClick={discard}>Прервать без сохранения</button>
          </div>
        ) : null}
      </div>
      <div className="content with-bar">
        {exercise
          ? <ExerciseCardContent key={session.currentIndex} exercise={exercise} />
          : <EmptyState icon="alert" title="Упражнение убрано из таблицы" message="Его удалили при обновлении. Переходите к следующему — прогресс сохранён." />}
      </div>
      <SetsPanel session={session} exercise={exercise} />
    </div>
  );
}

/** Подходы, таймер отдыха и переход к следующему упражнению. */
function SetsPanel({ session, exercise }: { session: WorkoutSession; exercise?: Exercise }) {
  const settings = useStore((s) => s.settings);
  const rest = useStore((s) => s.rest);
  const total = exercise?.sets ?? null;
  const done = S.currentSetsDone(session);
  const allDone = total ? done >= total : false;
  const seconds = settings.restDurationSeconds;

  const markSet = () => {
    unlockAudio(); // звук окончания отдыха разрешён только после нажатия
    store.updateSession((s) => S.markSetDone(s, total));
    // Отдых — только между подходами: после последнего известного подхода не нужен.
    const lastKnown = total ? done + 1 >= total : false;
    if (settings.restTimerEnabled && !lastKnown) store.startRest(seconds);
  };

  return (
    <BottomBar>
      {rest && rest !== "finished" ? <RestCountdown /> : rest === "finished" ? (
        <div className="ok" role="status" style={{ fontWeight: 800, minHeight: 44, display: "flex", alignItems: "center", justifyContent: "center", gap: 8 }}>
          <Icon name="bell" /> Отдых окончен — следующий подход!
        </div>
      ) : (
        <>
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            {total ? (
              <span className="sets" aria-label={`Сделано подходов: ${done} из ${total}`}>
                {Array.from({ length: total }, (_, i) => <i key={i} className={i < done ? "done" : ""} />)}
                <span>Подход {Math.min(done + 1, total)} из {total}</span>
              </span>
            ) : <span style={{ fontWeight: 700 }}>{done ? `Отмечено подходов: ${done}` : "Подходы"}</span>}
            <span style={{ flex: 1 }} />
            {done > 0 ? (
              <button className="btn-icon" onClick={() => store.updateSession(S.undoSet)} aria-label="Снять отметку последнего подхода"><Icon name="undo" /></button>
            ) : null}
            {settings.restTimerEnabled ? (
              <button className="btn-pill" onClick={() => { unlockAudio(); store.startRest(seconds); }} aria-label="Запустить таймер отдыха вручную">
                <Icon name="timer" size={18} /> Отдых {seconds} с
              </button>
            ) : null}
          </div>
          {!allDone ? (
            <button className="btn btn-primary" onClick={markSet}>
              <Icon name="check" /> {settings.restTimerEnabled ? `Подход выполнен · отдых ${seconds} с` : "Подход выполнен"}
            </button>
          ) : null}
        </>
      )}
      <div className="row-buttons">
        {S.canGoBack(session) ? (
          <button className="btn-icon" style={{ width: 52, height: 52 }} onClick={() => store.updateSession(S.previous)} aria-label="Предыдущее упражнение">
            <Icon name="back" />
          </button>
        ) : null}
        <button className={`btn ${allDone ? "btn-primary" : "btn-secondary"}`} onClick={() => store.updateSession(S.next)}>
          {S.isLastInQueue(session) ? "Закончить список" : "Следующее упражнение"} <Icon name="forward" />
        </button>
      </div>
    </BottomBar>
  );
}

function RestCountdown() {
  const rest = useStore((s) => s.rest);
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 250);
    return () => clearInterval(timer);
  }, []);
  if (!rest || rest === "finished") return null;
  const left = Math.max(0, Math.ceil((rest.endsAt - now) / 1000));
  const progress = 1 - left / rest.total;
  return (
    <div className="rest">
      <div className="rest-top">
        <span className="small muted" style={{ fontWeight: 700 }}>Отдых</span>
        <span className="rest-digits" aria-label={`Осталось ${left} секунд`}>{timerText(left)}</span>
      </div>
      <div className="progress blue"><div style={{ width: `${progress * 100}%` }} /></div>
      <div className="row-buttons">
        <button className="btn btn-secondary" onClick={() => store.extendRest(15)} aria-label="Добавить 15 секунд">+15 с</button>
        <button className="btn btn-secondary" onClick={store.stopRest}>Пропустить</button>
      </div>
    </div>
  );
}

function MoreQuestion({ session }: { session: WorkoutSession }) {
  const count = S.completedExerciseIds(session).length;
  return (
    <div className="screen">
      <div className="center-screen" style={{ paddingTop: "calc(var(--safe-top) + 24px)" }}>
        <span style={{ color: "var(--accent-text)" }}><Icon name="flame" size={56} filled /></span>
        <h1 className="title-xl">Ещё хочешь?</h1>
        <p className="muted">
          Список закончился: {exercisesText(count)} за {durationText(Date.now() - session.startedAt)}.
          Если силы остались — добери упражнения из общего списка.
        </p>
        <button className="btn btn-primary" onClick={() => store.updateSession(S.wantMore)}>Да, хочу ещё</button>
        <button className="btn btn-secondary" onClick={() => store.finishSession()}>Нет, закончить</button>
        <button className="btn-text" onClick={() => store.updateSession(S.previous)}>‹ Вернуться к последнему упражнению</button>
      </div>
    </div>
  );
}

function Finished({ entry }: { entry: HistoryEntry }) {
  const close = () => {
    store.closeFinished();
    go("/", true);
  };
  return (
    <div className="screen">
      <div className="content with-bar" style={{ alignItems: "center", textAlign: "center", paddingTop: "calc(var(--safe-top) + 40px)" }}>
        <span className="ok"><Icon name="check" size={64} /></span>
        <h1 className="title-xl">Тренировка завершена</h1>
        <div className="stats">
          <div className="card stat"><b>{entry.exerciseIds.length}</b>
            <span className="small muted">{plural(entry.exerciseIds.length, "упражнение", "упражнения", "упражнений")}</span></div>
          <div className="card stat"><b>{durationText(entry.finishedAt - entry.startedAt)}</b><span className="small muted">время</span></div>
        </div>
        {entry.bodyParts.length ? <div className="muted" style={{ fontWeight: 700 }}>{entry.bodyParts.join(" · ")}</div> : null}
        <div className="card pad" style={{ width: "100%", textAlign: "left" }}>
          {entry.exerciseNames.map((name, i) => <div key={i} className="muted small" style={{ padding: "3px 0" }}>{i + 1}. {name}</div>)}
        </div>
        <div className="faint small">Сохранено в историю на этом устройстве</div>
      </div>
      <BottomBar><button className="btn btn-primary" onClick={close}>На главный экран</button></BottomBar>
    </div>
  );
}
