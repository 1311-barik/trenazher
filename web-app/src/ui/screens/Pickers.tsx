import { useState } from "react";
import * as S from "../../lib/session";
import * as store from "../../lib/store";
import { useStore } from "../../lib/store";
import { exercisesText } from "../../lib/text";
import type { Exercise, Workout } from "../../lib/types";
import { BottomBar, EmptyState, ExerciseCardContent, ExerciseRow, FavoriteButton, Header, MediaImage } from "../components";
import { Icon, SelectionMark } from "../icons";
import { go, link } from "../router";

// --- Готовые тренировки ---

export function ReadyWorkouts() {
  const manifest = useStore((s) => s.content.manifest);
  const workouts = manifest?.workouts ?? [];
  return (
    <div className="screen">
      <Header title="Готовые тренировки" back="/" />
      <div className="content">
        {workouts.length === 0 ? (
          <EmptyState icon="list" title="Готовых тренировок пока нет"
            message="Женя добавит их в таблицу на лист «Тренировки» — они появятся здесь сами. А пока можно собрать свою."
            actionTitle="Собрать свою тренировку" onAction={() => go("/custom")} />
        ) : null}
        {workouts.map((w) => <WorkoutCard key={w.id} workout={w} />)}
      </div>
    </div>
  );
}

function start(workout: Workout) {
  if (store.startWorkout(workout)) go("/session");
}

function WorkoutCard({ workout }: { workout: Workout }) {
  const manifest = useStore((s) => s.content.manifest);
  const { byId } = store.contentIndex(manifest);
  const exercises = workout.exerciseIds.map((id) => byId.get(id)).filter(Boolean) as Exercise[];
  const cover = exercises.find((e) => e.photos[0])?.photos[0];
  return (
    <div className="card pad" style={{ display: "flex", flexDirection: "column", gap: 12 }}>
      <button className="tappable" style={{ display: "flex", gap: 12, background: "none", border: "none", padding: 0, color: "inherit" }}
        onClick={() => go(link("workout", workout.id))}>
        <MediaImage item={cover} className="thumb" />
        <span style={{ flex: 1 }}>
          <span className="title-m" style={{ display: "block" }}>{workout.title}</span>
          {workout.summary ? <span className="muted small" style={{ display: "block" }}>{workout.summary}</span> : null}
          <span className="faint tiny" style={{ fontWeight: 700 }}>{exercisesText(exercises.length)} · {S.estimateText(exercises.length)}</span>
        </span>
      </button>
      <div className="row-buttons">
        <button className="btn btn-primary" disabled={!exercises.length} onClick={() => start(workout)}>Начать</button>
        <FavoriteButton itemId={workout.id} type="workout" title={workout.title} />
      </div>
    </div>
  );
}

export function WorkoutDetail({ id }: { id: string }) {
  const manifest = useStore((s) => s.content.manifest);
  const { byId, workoutsById } = store.contentIndex(manifest);
  const workout = workoutsById.get(id);
  const [detail, setDetail] = useState<Exercise | null>(null);
  if (!workout) return <Missing back="/ready" />;
  const exercises = workout.exerciseIds.map((x) => byId.get(x)).filter(Boolean) as Exercise[];
  if (detail) return <ExerciseDetail exercise={detail} onClose={() => setDetail(null)} />;
  return (
    <div className="screen">
      <Header title={workout.title} back="/ready" right={<FavoriteButton itemId={workout.id} type="workout" title={workout.title} />} />
      <div className="content with-bar">
        {workout.summary ? <div className="muted">{workout.summary}</div> : null}
        <div className="faint small" style={{ fontWeight: 700 }}>{exercisesText(exercises.length)} · {S.estimateText(exercises.length)}</div>
        {exercises.length < workout.exerciseIds.length ? <div className="warn small">Часть упражнений убрана из таблицы — они пропущены.</div> : null}
        {exercises.map((e, i) => (
          <button key={e.id + i} className="tappable" style={{ background: "none", border: "none", padding: 0, color: "inherit" }} onClick={() => setDetail(e)}>
            <ExerciseRow exercise={e} number={i + 1} trailing={<span className="faint"><Icon name="info" /></span>} />
          </button>
        ))}
      </div>
      <BottomBar><button className="btn btn-primary" disabled={!exercises.length} onClick={() => start(workout)}>Начать тренировку</button></BottomBar>
    </div>
  );
}

// --- Своя тренировка: шаг 1 — части тела ---

export function BodyParts() {
  const manifest = useStore((s) => s.content.manifest);
  const draft = useStore((s) => s.draft);
  const { byPart } = store.contentIndex(manifest);
  if (!manifest) return <Missing back="/" />;
  return (
    <div className="screen">
      <Header title="Части тела" back="/" />
      <div className="content with-bar">
        <div className="muted small">Рекомендуем выбрать 2–3 части тела — иначе упражнений будет слишком много. Можно выбрать и больше.</div>
        <div className="parts-grid">
          {manifest.bodyParts.map((part) => {
            const exercises = byPart.get(part) ?? [];
            const on = draft.bodyParts.includes(part);
            return (
              <button key={part} className={`card part-tile ${on ? "selected" : ""}`} onClick={() => store.toggleDraftPart(part)}
                aria-pressed={on} aria-label={`${part}, ${exercisesText(exercises.length)}`}>
                <MediaImage item={exercises.find((e) => e.photos[0])?.photos[0]} />
                <SelectionMark on={on} />
                <div className="caption" style={{ textAlign: "left" }}>
                  <div style={{ fontWeight: 800 }}>{part}</div>
                  <div className="tiny muted">{exercisesText(exercises.length)}</div>
                </div>
              </button>
            );
          })}
        </div>
      </div>
      <BottomBar>
        <button className="btn btn-primary" disabled={!draft.bodyParts.length} onClick={() => go("/custom/exercises")}>
          {draft.bodyParts.length ? `Далее: упражнения (${draft.bodyParts.length})` : "Выберите часть тела"}
        </button>
        {draft.bodyParts.length || draft.exerciseIds.length ? <button className="btn-text" onClick={store.resetDraft}>Сбросить выбор</button> : null}
      </BottomBar>
    </div>
  );
}

// --- Шаг 2 и добор после «Ещё хочешь?» ---

export function ExercisePicker({ mode }: { mode: "draft" | "addMore" }) {
  const manifest = useStore((s) => s.content.manifest);
  const draft = useStore((s) => s.draft);
  const session = useStore((s) => s.session);
  const [extra, setExtra] = useState<string[]>([]);
  const [detail, setDetail] = useState<Exercise | null>(null);
  const { byPart } = store.contentIndex(manifest);
  if (!manifest) return <Missing back="/" />;
  if (detail) return <ExerciseDetail exercise={detail} onClose={() => setDetail(null)} />;

  // В своей тренировке — выбранные части; при доборе — общий список, сначала части этой тренировки.
  const sessionParts = session?.bodyParts ?? [];
  const parts = mode === "draft"
    ? draft.bodyParts
    : [...manifest.bodyParts.filter((p) => sessionParts.includes(p)), ...manifest.bodyParts.filter((p) => !sessionParts.includes(p))];
  const selection = mode === "draft" ? draft.exerciseIds : extra;
  const doneToday = new Set(mode === "addMore" && session ? S.completedExerciseIds(session) : []);
  const toggle = (id: string) => {
    if (mode === "draft") store.toggleDraftExercise(id);
    else setExtra((list) => (list.includes(id) ? list.filter((x) => x !== id) : [...list, id]));
  };
  const count = selection.length;
  const inRange = count >= S.recommendedRange.min && count <= S.recommendedRange.max;

  const continueWithExtra = () => {
    const ordered = parts.flatMap((p) => (byPart.get(p) ?? []).map((e) => e.id)).filter((id) => extra.includes(id));
    store.updateSession((s) => S.append(s, ordered, store.bodyPartsFor(ordered)));
  };

  return (
    <div className="screen">
      {mode === "draft"
        ? <Header title="Упражнения" back="/custom" />
        : (
          <header className="header">
            <button className="btn-icon plain" onClick={() => store.updateSession(S.cancelPicking)} aria-label="Назад к вопросу"><Icon name="back" /></button>
            <h1>Добери упражнения</h1><span className="spacer" />
          </header>
        )}
      <div className="content with-bar" style={{ paddingTop: 0 }}>
        {parts.map((part) => {
          const exercises = byPart.get(part) ?? [];
          const selected = exercises.filter((e) => selection.includes(e.id)).length;
          return (
            <section key={part} style={{ display: "flex", flexDirection: "column", gap: 10 }}>
              <div className="sticky-part">
                <h2>{part}</h2>
                <span className="small muted">{selected ? `выбрано ${selected} из ${exercises.length}` : exercises.length}</span>
              </div>
              {exercises.map((e) => {
                const on = selection.includes(e.id);
                return (
                  <div className="row-with-action" key={e.id}>
                    <button className="tappable" style={{ background: "none", border: "none", padding: 0, color: "inherit" }}
                      onClick={() => toggle(e.id)} aria-pressed={on}>
                      <ExerciseRow exercise={e} selected={on} badge={doneToday.has(e.id) ? "Сделано сегодня" : undefined} trailing={<SelectionMark on={on} />} />
                    </button>
                    <button className="btn-icon plain" onClick={() => setDetail(e)} aria-label={`Описание: ${e.name}`}><Icon name="info" /></button>
                  </div>
                );
              })}
            </section>
          );
        })}
      </div>
      <BottomBar>
        {mode === "draft" ? (
          <>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 8 }}>
              <span style={{ fontWeight: 700 }}>{count ? `Выбрано: ${count} · ${S.estimateText(count)}` : "Отметьте упражнения"}</span>
              {/* Рекомендация — нейтральным цветом: это подсказка, а не ошибка. */}
              <span className={`small ${inRange ? "ok" : "faint"}`}>рекомендуем 10–12</span>
            </div>
            <button className="btn btn-primary" disabled={!count} onClick={() => { if (store.startCustom()) go("/session"); }}>
              {count ? `Начать тренировку (${count})` : "Начать тренировку"}
            </button>
          </>
        ) : (
          <>
            <button className="btn btn-primary" disabled={!count} onClick={continueWithExtra}>{count ? `Продолжить (${count})` : "Выберите упражнения"}</button>
            <button className="btn-text" onClick={() => store.finishSession()}>Нет, закончить тренировку</button>
          </>
        )}
      </BottomBar>
    </div>
  );
}

// --- Карточка упражнения вне тренировки ---

export function ExerciseDetail({ exercise, onClose, back }: { exercise: Exercise; onClose?: () => void; back?: string }) {
  return (
    <div className="screen">
      {onClose ? (
        <header className="header">
          <span className="spacer" /><h1>{exercise.name}</h1>
          <button className="btn-icon plain" onClick={onClose} aria-label="Закрыть"><Icon name="close" /></button>
        </header>
      ) : <Header title={exercise.name} back={back ?? "/"} />}
      <div className="content with-bar"><ExerciseCardContent exercise={exercise} /></div>
      {!onClose ? (
        <BottomBar>
          <button className="btn btn-primary" onClick={() => { store.startSingle(exercise); go("/session"); }}>Начать с этого упражнения</button>
        </BottomBar>
      ) : null}
    </div>
  );
}

export function Missing({ back }: { back: string }) {
  return (
    <div className="screen">
      <Header title="Не найдено" back={back} />
      <div className="content">
        <EmptyState icon="alert" title="Этого больше нет в таблице" message="Возможно, упражнение или тренировку переименовали или убрали. Вернитесь назад." />
      </div>
    </div>
  );
}
