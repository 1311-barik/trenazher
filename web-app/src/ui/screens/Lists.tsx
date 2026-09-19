import { useState } from "react";
import * as store from "../../lib/store";
import { useStore } from "../../lib/store";
import { durationText, exercisesText, formatDayTime, formatMonth } from "../../lib/text";
import type { FavoriteItem, HistoryEntry } from "../../lib/types";
import { BottomBar, Chip, EmptyState, ExerciseRow, FavoriteButton, Header } from "../components";
import { Icon } from "../icons";
import { go, link } from "../router";
import { ExerciseDetail, Missing } from "./Pickers";

// --- Избранное ---

export function Favorites() {
  const favorites = useStore((s) => s.favorites);
  const manifest = useStore((s) => s.content.manifest);
  const [tab, setTab] = useState<FavoriteItem["type"]>("exercise");
  const { byId, workoutsById } = store.contentIndex(manifest);
  const items = favorites.filter((f) => f.type === tab);

  return (
    <div className="screen">
      <Header title="Избранное" back="/" />
      <div className="content">
        <div className="segmented" role="tablist">
          <button role="tab" aria-selected={tab === "exercise"} className={tab === "exercise" ? "on" : ""} onClick={() => setTab("exercise")}>Упражнения</button>
          <button role="tab" aria-selected={tab === "workout"} className={tab === "workout" ? "on" : ""} onClick={() => setTab("workout")}>Тренировки</button>
        </div>
        {items.length === 0 ? (
          <EmptyState icon="heart" title={tab === "exercise" ? "Нет избранных упражнений" : "Нет избранных тренировок"}
            message="Нажмите ♡ на карточке упражнения или тренировки — она появится здесь." />
        ) : null}
        {items.map((item) => {
          const exercise = item.type === "exercise" ? byId.get(item.itemId) : undefined;
          const workout = item.type === "workout" ? workoutsById.get(item.itemId) : undefined;
          if (!exercise && !workout) {
            // Не прячем молча: упражнение могли переименовать или убрать из таблицы.
            return (
              <div key={item.type + item.itemId} className="card pad row-with-action">
                <div>
                  <div className="muted" style={{ fontWeight: 700 }}>{item.title}</div>
                  <div className="tiny faint">Сейчас нет в таблице — возможно, переименовано или убрано</div>
                </div>
                <button className="btn-text blue" onClick={() => store.toggleFavorite(item.itemId, item.type, item.title)}>Убрать</button>
              </div>
            );
          }
          return (
            <div key={item.type + item.itemId} className="row-with-action">
              <button className="tappable" style={{ background: "none", border: "none", padding: 0, color: "inherit" }}
                onClick={() => go(exercise ? link("exercise", exercise.id) : link("workout", workout!.id))}>
                {exercise ? <ExerciseRow exercise={exercise} /> : (
                  <div className="card pad">
                    <div style={{ fontWeight: 800 }}>{workout!.title}</div>
                    <div className="tiny muted">{exercisesText(workout!.exerciseIds.length)}</div>
                  </div>
                )}
              </button>
              <FavoriteButton itemId={item.itemId} type={item.type} title={item.title} />
            </div>
          );
        })}
      </div>
    </div>
  );
}

export function ExercisePage({ id }: { id: string }) {
  const manifest = useStore((s) => s.content.manifest);
  const exercise = store.contentIndex(manifest).byId.get(id);
  if (!exercise) return <Missing back="/favorites" />;
  return <ExerciseDetail exercise={exercise} back="/favorites" />;
}

// --- История ---

export function History() {
  const history = useStore((s) => s.history);
  const monthAgo = Date.now() - 30 * 86400000;
  const groups: Array<{ title: string; entries: HistoryEntry[] }> = [];
  for (const entry of history) {
    const title = formatMonth(entry.finishedAt);
    if (groups.length && groups[groups.length - 1].title === title) groups[groups.length - 1].entries.push(entry);
    else groups.push({ title, entries: [entry] });
  }
  return (
    <div className="screen">
      <Header title="История" back="/" />
      <div className="content">
        {history.length === 0 ? (
          <EmptyState icon="history" title="Здесь появятся тренировки" message="Каждая завершённая тренировка сохраняется здесь автоматически." />
        ) : (
          // Спокойная сводка: факты, без «серий» и штрафов за перерывы.
          <div className="stats">
            <div className="card stat"><b>{history.length}</b><span className="small muted">всего</span></div>
            <div className="card stat"><b>{history.filter((h) => h.finishedAt >= monthAgo).length}</b><span className="small muted">за 30 дней</span></div>
          </div>
        )}
        {groups.map((group) => (
          <section key={group.title} style={{ display: "flex", flexDirection: "column", gap: 10 }}>
            <div className="section-title"><h2>{group.title}</h2><span className="muted small">{group.entries.length}</span></div>
            {group.entries.map((entry) => (
              <button key={entry.id} className="card pad tappable" style={{ color: "inherit", display: "flex", alignItems: "center", gap: 8 }}
                onClick={() => go(link("history", entry.id))}>
                <span style={{ flex: 1 }}>
                  <span className="tiny faint" style={{ display: "block" }}>{formatDayTime(entry.finishedAt)}</span>
                  <span style={{ display: "block", fontWeight: 800 }}>{entry.title}</span>
                  <span className="tiny muted">{entry.kind === "ready" ? "Готовая" : "Своя"} · {exercisesText(entry.exerciseIds.length)} · {durationText(entry.finishedAt - entry.startedAt)}</span>
                </span>
                <span className="faint"><Icon name="forward" /></span>
              </button>
            ))}
          </section>
        ))}
      </div>
    </div>
  );
}

export function HistoryDetail({ id }: { id: string }) {
  const entry = useStore((s) => s.history.find((h) => h.id === id));
  if (!entry) return <Missing back="/history" />;
  const remove = () => {
    if (window.confirm("Удалить запись из истории? Сразу после удаления её можно вернуть кнопкой «Отменить».")) {
      go("/history", true);
      store.deleteHistory(entry);
    }
  };
  return (
    <div className="screen">
      <Header title="Тренировка" back="/history" />
      <div className="content with-bar">
        <h2 className="title-l">{entry.title}</h2>
        <div className="muted small">{formatDayTime(entry.startedAt)} · {durationText(entry.finishedAt - entry.startedAt)}</div>
        <div className="chips">
          <Chip>{entry.kind === "ready" ? "Готовая тренировка" : "Своя тренировка"}</Chip>
          {entry.bodyParts.map((p) => <Chip key={p}>{p}</Chip>)}
        </div>
        <div className="card pad">
          {entry.exerciseNames.map((name, i) => <div key={i} className="muted" style={{ padding: "3px 0" }}>{i + 1}. {name}</div>)}
        </div>
        <button className="btn-text accent" onClick={remove}>Удалить из истории</button>
      </div>
      <BottomBar>
        <button className="btn btn-primary" onClick={() => { if (store.repeatFromHistory(entry)) go("/session"); }}>Повторить эту тренировку</button>
      </BottomBar>
    </div>
  );
}
