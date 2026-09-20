import { useEffect, useRef, useState, type ReactNode } from "react";
import { cacheVideo, cachedVideoUrls, mediaUrl } from "../lib/platform";
import * as store from "../lib/store";
import { useStore } from "../lib/store";
import { exercisesText, formatRelative, megabytes } from "../lib/text";
import type { Exercise, FavoriteItem, MediaItem } from "../lib/types";
import { Icon } from "./icons";
import { go } from "./router";

// --- Каркас ---

export function Header({ title, back, right }: { title: string; back?: string; right?: ReactNode }) {
  return (
    <header className="header">
      {back !== undefined ? (
        <button className="btn-icon plain" onClick={() => go(back)} aria-label="Назад">
          <Icon name="back" />
        </button>
      ) : <span className="spacer" />}
      <h1>{title}</h1>
      {right ?? <span className="spacer" />}
    </header>
  );
}

export function BottomBar({ children }: { children: ReactNode }) {
  return <div className="bottom-bar">{children}</div>;
}

export function EmptyState({ icon, title, message, actionTitle, onAction }: {
  icon: string; title: string; message: string; actionTitle?: string; onAction?: () => void;
}) {
  return (
    <div className="card empty">
      <span className="muted"><Icon name={icon} size={40} /></span>
      <div className="title-m">{title}</div>
      <div className="muted small">{message}</div>
      {actionTitle && onAction ? <button className="btn btn-secondary" onClick={onAction}>{actionTitle}</button> : null}
    </div>
  );
}

export function Chip({ children }: { children: ReactNode }) {
  return <span className="chip">{children}</span>;
}

export function Switch({ on, onChange, label }: { on: boolean; onChange: (value: boolean) => void; label: string }) {
  return (
    <label className="switch-row">
      <span>{label}</span>
      <button type="button" role="switch" aria-checked={on} aria-label={label} className={`switch ${on ? "on" : ""}`} onClick={() => onChange(!on)} />
    </label>
  );
}

export function Toast() {
  const toast = useStore((s) => s.toast);
  if (!toast) return null;
  return (
    <div className="toast" role="status" aria-live="polite" key={toast.id}>
      <span>{toast.message}</span>
      {toast.actionTitle ? <button className="btn-text blue" onClick={store.toastAction}>{toast.actionTitle}</button> : null}
    </div>
  );
}

export function FavoriteButton({ itemId, type, title }: { itemId: string; type: FavoriteItem["type"]; title: string }) {
  const on = useStore((s) => store.isFavorite(s, itemId, type));
  return (
    <button className={`btn-icon ${on ? "on" : ""}`} onClick={() => store.toggleFavorite(itemId, type, title)}
      aria-label={on ? "Убрать из избранного" : "Добавить в избранное"} aria-pressed={on}>
      <Icon name="heart" filled={on} />
    </button>
  );
}

// --- Медиа ---

export function MediaImage({ item, full = false, fit = false, className = "" }: { item?: MediaItem | null; full?: boolean; fit?: boolean; className?: string }) {
  const [failed, setFailed] = useState(false);
  const path = item?.ready ? (item.kind === "photo" ? (full ? item.url : item.thumbUrl ?? item.url) : item.posterUrl) : undefined;
  useEffect(() => {
    setFailed(false);
  }, [path]);
  return (
    <div className={`media ${fit ? "fit" : ""} ${className}`}>
      {path && !failed
        ? <img src={mediaUrl(path)} alt="" loading="lazy" onError={() => setFailed(true)} />
        : <Icon name={item && item.kind !== "photo" ? "film" : "photo"} size={24} />}
    </div>
  );
}

export function PhotoCarousel({ photos }: { photos: MediaItem[] }) {
  const [page, setPage] = useState(0);
  const track = useRef<HTMLDivElement>(null);
  if (photos.length === 0) {
    return (
      <div className="carousel media" aria-label="Фото пока нет">
        <div className="empty"><Icon name="photo" size={30} /><span className="small">Фото пока нет</span></div>
      </div>
    );
  }
  return (
    <div className="carousel" aria-label={`Фото упражнения, ${photos.length} шт.`}>
      <div className="carousel-track" ref={track}
        onScroll={(e) => setPage(Math.round(e.currentTarget.scrollLeft / e.currentTarget.clientWidth))}>
        {photos.map((p) => <MediaImage key={p.driveFileId + p.version} item={p} full fit />)}
      </div>
      {photos.length > 1 ? <div className="dots">{photos.map((p, i) => <span key={p.driveFileId} className={i === page ? "on" : ""} />)}</div> : null}
    </div>
  );
}

// Плеер один на всё приложение: элемент <video> существует заранее, чтобы запустить его прямо
// в обработчике нажатия (иначе iPhone не даст включить видео со звуком).
let playerElement: HTMLVideoElement | null = null;
let showPlayer: ((title: string | null) => void) | null = null;

export function openVideo(item: MediaItem): void {
  if (!playerElement || !showPlayer) return;
  playerElement.src = mediaUrl(item.url);
  showPlayer(item.title);
  void playerElement.play().catch(() => undefined); // не вышло — кнопка ▶ в самом плеере
}

export function VideoPlayer() {
  const ref = useRef<HTMLVideoElement>(null);
  const [title, setTitle] = useState<string | null>(null);
  useEffect(() => {
    playerElement = ref.current;
    showPlayer = setTitle;
    return () => {
      playerElement = null;
      showPlayer = null;
    };
  }, []);
  const close = () => {
    ref.current?.pause();
    setTitle(null);
  };
  return (
    <div className={`player ${title ? "" : "hidden"}`} role="dialog" aria-label={title ?? "Видео"} aria-hidden={!title}>
      <video ref={ref} controls playsInline preload="none" />
      <button className="btn-icon close" onClick={close} aria-label="Закрыть видео"><Icon name="close" /></button>
    </div>
  );
}

/** Видео упражнения. Ничего не запускается само — только по нажатию на конкретное видео. */
export function VideoList({ videos }: { videos: MediaItem[] }) {
  const online = useStore((s) => s.online);
  const [cached, setCached] = useState<Set<string>>(new Set());
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const pathOf = (item: MediaItem) => new URL(mediaUrl(item.url), document.baseURI).pathname;

  useEffect(() => {
    void cachedVideoUrls().then(setCached);
  }, [videos]);

  const play = (item: MediaItem) => {
    setError(null);
    if (!item.ready) {
      setError("Это видео ещё обрабатывается на сервере — загляните через несколько минут.");
      return;
    }
    if (!online && !cached.has(pathOf(item))) {
      setError("Это видео не скачано для офлайна, а интернета нет. Остальное работает; видео откроется, когда появится связь.");
      return;
    }
    openVideo(item);
  };

  const download = async (item: MediaItem) => {
    setBusy(item.driveFileId);
    setError(null);
    try {
      await cacheVideo(item);
      setCached(await cachedVideoUrls());
    } catch (e) {
      setError(`Не удалось скачать видео: ${(e as Error).message}. Попробуйте ещё раз.`);
    } finally {
      setBusy(null);
    }
  };

  return (
    <section style={{ display: "flex", flexDirection: "column", gap: 10 }}>
      <div className="section-title"><h2>Видео</h2>{videos.length ? <span className="muted small">{videos.length}</span> : null}</div>
      {videos.length === 0 ? <div className="muted small">Видео к этому упражнению пока нет.</div> : null}
      {videos.map((v) => {
        const isCached = cached.has(pathOf(v));
        return (
          <div className="card row-with-action" key={v.driveFileId + v.version}>
            <button className="video-row tappable" style={{ background: "none", border: "none" }} onClick={() => play(v)}
              aria-label={`${v.kind === "ownVideo" ? "Видео Жени" : "Обучающее видео"}: ${v.title}. Смотреть`}>
              <div className="poster">
                <MediaImage item={v} className="poster" />
                <span className="play"><Icon name="play" size={18} filled /></span>
              </div>
              <div className="grow" style={{ minWidth: 0 }}>
                <div className="tiny" style={{ fontWeight: 800, color: v.kind === "ownVideo" ? "var(--accent-text)" : "var(--blue)" }}>
                  {v.kind === "ownVideo" ? "Видео Жени" : "Обучающее видео"}
                </div>
                <div className="small" style={{ fontWeight: 650 }}>{v.title}</div>
                <div className="tiny muted">
                  {!v.ready ? "Обрабатывается на сервере…" : isCached ? "Скачано · работает без интернета" : v.byteSize ? `Смотреть · ${megabytes(v.byteSize)}` : "Смотреть"}
                </div>
              </div>
            </button>
            {v.ready && !isCached ? (
              <button className="btn-icon plain" onClick={() => download(v)} disabled={busy !== null || !online}
                aria-label={`Скачать для офлайна: ${v.title}`}>
                {busy === v.driveFileId ? <span className="spinner" /> : <Icon name="download" />}
              </button>
            ) : null}
          </div>
        );
      })}
      {error ? <div className="warn small" role="alert">{error}</div> : null}
    </section>
  );
}

// --- Упражнение ---

/** Карточка в порядке из ТЗ: название → 1–2 фото → описание → видео. */
export function ExerciseCardContent({ exercise }: { exercise: Exercise }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 18 }}>
      <div style={{ display: "flex", gap: 8, alignItems: "flex-start" }}>
        <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: 8 }}>
          <h2 className="title-l">{exercise.name}</h2>
          <div className="chips">
            <Chip>{exercise.bodyPart}</Chip>
            {exercise.muscleGroup && exercise.muscleGroup !== exercise.bodyPart ? <Chip>{exercise.muscleGroup}</Chip> : null}
            {exercise.equipment ? <Chip>Гантели + {exercise.equipment}</Chip> : null}
            {exercise.sets ? <Chip>Подходов: {exercise.sets}</Chip> : null}
          </div>
        </div>
        <FavoriteButton itemId={exercise.id} type="exercise" title={exercise.name} />
      </div>
      <PhotoCarousel photos={exercise.photos} />
      {exercise.details ? (
        <section>
          <div className="section-title"><h2>Техника</h2></div>
          <p className="muted pre" style={{ marginTop: 8 }}>{exercise.details}</p>
        </section>
      ) : null}
      <VideoList videos={exercise.videos} />
    </div>
  );
}

export function ExerciseRow({ exercise, number, badge, trailing, selected }: {
  exercise: Exercise; number?: number; badge?: string; trailing?: ReactNode; selected?: boolean;
}) {
  const subtitle = [exercise.muscleGroup, exercise.equipment ? `+ ${exercise.equipment}` : null].filter(Boolean).join(" · ");
  return (
    <div className={`card ex-row ${selected ? "selected" : ""}`}>
      <MediaImage item={exercise.photos[0]} className="thumb" />
      <div className="grow">
        <div className="name">{number ? `${number}. ` : ""}{exercise.name}</div>
        {subtitle ? <div className="tiny muted">{subtitle}</div> : null}
        {badge ? <div className="tiny ok" style={{ fontWeight: 800 }}>✓ {badge}</div> : null}
      </div>
      {trailing}
    </div>
  );
}

// --- Состояние контента ---

export function SyncStatus({ withButton = false, onRefresh }: { withButton?: boolean; onRefresh?: () => void }) {
  const content = useStore((s) => s.content);
  const online = useStore((s) => s.online);
  const count = content.manifest?.exercises.length ?? 0;
  return (
    <div className="small muted" style={{ display: "flex", flexDirection: "column", gap: 8 }}>
      {!online ? (
        <span>Нет интернета — работает всё, что уже загружено.</span>
      ) : content.error && content.manifest ? (
        <span className="warn">{content.error} Показываю последнюю загруженную версию.</span>
      ) : content.fetchedAt ? (
        <span>Упражнения обновлены {formatRelative(content.fetchedAt)} · {exercisesText(count)}</span>
      ) : null}
      {withButton && onRefresh ? (
        <button className="btn btn-secondary" onClick={onRefresh} disabled={!online}>Обновить упражнения</button>
      ) : null}
    </div>
  );
}
