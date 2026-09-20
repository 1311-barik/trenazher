import { useEffect, useRef, useState, type ReactNode } from "react";
import { icsText, scheduleText } from "../../lib/calendar";
import { cacheVideo, cachedVideoUrls, loadManifest, mediaUrl, removeCachedVideos, storageEstimate } from "../../lib/platform";
import * as store from "../../lib/store";
import { useStore } from "../../lib/store";
import { megabytes } from "../../lib/text";
import type { ContentIssue, MediaItem } from "../../lib/types";
import { EmptyState, Header, Switch, SyncStatus } from "../components";
import { Icon } from "../icons";
import { go } from "../router";

const DAYS = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"];

function Section({ title, icon, children }: { title: string; icon: string; children: ReactNode }) {
  return (
    <section className="card pad" style={{ display: "flex", flexDirection: "column", gap: 12 }}>
      <h2 className="title-m" style={{ display: "flex", alignItems: "center", gap: 8 }}><Icon name={icon} size={20} /> {title}</h2>
      {children}
    </section>
  );
}

export function Settings() {
  const settings = useStore((s) => s.settings);
  const manifest = useStore((s) => s.content.manifest);
  const online = useStore((s) => s.online);
  const issuesCount = (manifest?.issues ?? []).filter((i) => i.severity !== "info").length;

  return (
    <div className="screen">
      <Header title="Настройки" back="/" />
      <div className="content">
        <Section title="Таймер отдыха" icon="timer">
          <Switch label="Таймер между подходами" on={settings.restTimerEnabled} onChange={(v) => store.updateSettings({ restTimerEnabled: v })} />
          {settings.restTimerEnabled ? (
            <>
              <div className="segmented" role="radiogroup" aria-label="Длительность отдыха">
                {[30, 60].map((s) => (
                  <button key={s} role="radio" aria-checked={settings.restDurationSeconds === s} className={settings.restDurationSeconds === s ? "on" : ""}
                    onClick={() => store.updateSettings({ restDurationSeconds: s })}>{s} секунд</button>
                ))}
              </div>
              <div className="small muted">Запускается после «Подход выполнен» и кнопкой «Отдых». Можно продлить на 15 секунд или пропустить. При заблокированном экране сигнал не прозвучит — держите приложение открытым.</div>
            </>
          ) : null}
        </Section>

        <Reminders />

        <Section title="Упражнения и видео" icon="download">
          <SyncStatus withButton onRefresh={() => void loadManifest()} />
          <OfflineVideos />
          <button className="tappable" style={{ background: "none", border: "none", padding: 0, color: "inherit", display: "flex", alignItems: "center", minHeight: 44 }}
            onClick={() => go("/settings/issues")}>
            <span style={{ flex: 1 }}>Проверка контента</span>
            <span className={`small ${issuesCount ? "warn" : "ok"}`}>{issuesCount ? `замечаний: ${issuesCount}` : "всё в порядке"}</span>
            <span className="faint"><Icon name="forward" /></span>
          </button>
        </Section>

        <Backup />

        {!online ? <div className="small faint">Сейчас нет интернета: работают настройки и всё, что уже загружено.</div> : null}
      </div>
    </div>
  );
}

function Reminders() {
  const settings = useStore((s) => s.settings);
  const [status, setStatus] = useState<string | null>(null);

  // Приложение при этом никуда не уходит: файл готовится на телефоне и отдаётся системе.
  const addToCalendar = async () => {
    setStatus(null);
    const file = new File([icsText(settings)], "trenazher.ics", { type: "text/calendar" });
    try {
      if (navigator.canShare?.({ files: [file] })) {
        await navigator.share({ files: [file], title: "Напоминание о тренировке" });
        setStatus("В появившемся окне выберите «Календарь» — событие повторится каждую неделю.");
        return;
      }
    } catch (error) {
      if ((error as Error).name === "AbortError") return;
    }
    const url = URL.createObjectURL(file);
    const link = document.createElement("a");
    link.href = url;
    link.download = "trenazher.ics";
    document.body.appendChild(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 2000);
    setStatus("Файл напоминания сохранён. Откройте его — iPhone предложит добавить событие в Календарь.");
  };
  const toggleDay = (day: number) => {
    const days = settings.reminderWeekdays.includes(day)
      ? settings.reminderWeekdays.filter((d) => d !== day)
      : [...settings.reminderWeekdays, day].sort((a, b) => a - b);
    store.updateSettings({ reminderWeekdays: days });
  };
  const time = `${String(settings.reminderHour).padStart(2, "0")}:${String(settings.reminderMinute).padStart(2, "0")}`;
  return (
    <Section title="Напоминания" icon="bell">
      <div className="small muted">Напоминание ставится повторяющимся событием в Календарь iPhone — сработает, даже если приложение закрыто.</div>
      <label className="switch-row">
        <span>Время</span>
        <input type="time" value={time} onChange={(e) => {
          const [h, m] = e.target.value.split(":").map(Number);
          if (!Number.isNaN(h) && !Number.isNaN(m)) store.updateSettings({ reminderHour: h, reminderMinute: m });
        }} />
      </label>
      <div className="days" role="group" aria-label="Дни недели">
        {DAYS.map((label, i) => {
          const on = settings.reminderWeekdays.includes(i + 1);
          return <button key={label} className={on ? "on" : ""} aria-pressed={on} onClick={() => toggleDay(i + 1)}>{label}</button>;
        })}
      </div>
      {settings.reminderWeekdays.length ? (
        <button className="btn btn-secondary" onClick={() => void addToCalendar()}>
          <Icon name="calendar" /> Добавить в Календарь
        </button>
      ) : <div className="small warn">Выберите хотя бы один день.</div>}
      {status ? <div className="small" role="status">{status}</div> : null}
      <div className="tiny faint">
        Поменяли время или дни — добавьте событие заново, а старое удалите в Календаре.
        Если окно не появилось, поставьте напоминание вручную — {scheduleText(settings)}.
      </div>
    </Section>
  );
}

function OfflineVideos() {
  const manifest = useStore((s) => s.content.manifest);
  const online = useStore((s) => s.online);
  const [cached, setCached] = useState<Set<string>>(new Set());
  const [progress, setProgress] = useState<{ done: number; total: number } | null>(null);
  const [usage, setUsage] = useState<{ usage: number; quota: number } | null>(null);
  const [error, setError] = useState<string | null>(null);

  const videos: MediaItem[] = [];
  const seen = new Set<string>();
  for (const e of manifest?.exercises ?? []) {
    for (const v of e.videos) if (v.ready && !seen.has(v.url)) { seen.add(v.url); videos.push(v); }
  }
  const pathOf = (v: MediaItem) => new URL(mediaUrl(v.url), document.baseURI).pathname;
  const missing = videos.filter((v) => !cached.has(pathOf(v)));
  const missingBytes = missing.reduce((sum, v) => sum + (v.byteSize ?? 0), 0);

  const refresh = async () => {
    setCached(await cachedVideoUrls());
    setUsage(await storageEstimate());
  };
  useEffect(() => { void refresh(); }, [manifest]);

  const downloadAll = async () => {
    setError(null);
    let failed = 0;
    setProgress({ done: 0, total: missing.length });
    for (const [i, v] of missing.entries()) {
      try { await cacheVideo(v); } catch { failed += 1; }
      setProgress({ done: i + 1, total: missing.length });
    }
    setProgress(null);
    if (failed) setError(`Не скачалось видео: ${failed}. Уже скачанные сохранены — нажмите ещё раз, чтобы докачать остальные.`);
    await refresh();
  };

  const removeAll = async () => {
    if (!window.confirm("Удалить скачанные видео? Упражнения и фото останутся, видео можно будет смотреть онлайн или скачать снова.")) return;
    await removeCachedVideos();
    await refresh();
    store.showToast("Скачанные видео удалены");
  };

  return (
    <>
      <div className="small muted">
        Видео без интернета: скачано {videos.length - missing.length} из {videos.length}.
        {usage ? ` Занято на устройстве: ${megabytes(usage.usage)}.` : ""}
      </div>
      {progress ? (
        <div>
          <div className="small">Скачиваю видео: {progress.done} из {progress.total}</div>
          <div className="progress blue"><div style={{ width: `${(progress.done / progress.total) * 100}%` }} /></div>
        </div>
      ) : missing.length ? (
        <button className="btn btn-secondary" disabled={!online} onClick={downloadAll}>
          Скачать все видео для офлайна{missingBytes ? ` (≈ ${megabytes(missingBytes)})` : ""}
        </button>
      ) : null}
      {videos.length - missing.length > 0 && !progress ? <button className="btn-text" onClick={removeAll}>Удалить скачанные видео</button> : null}
      {error ? <div className="small warn" role="alert">{error}</div> : null}
    </>
  );
}

/** Резервная копия: перенос истории на другое устройство или новый адрес приложения. */
function Backup() {
  const input = useRef<HTMLInputElement>(null);
  const historyCount = useStore((s) => s.history.length);
  const [message, setMessage] = useState<string | null>(null);

  const exportFile = () => {
    const blob = new Blob([JSON.stringify(store.exportBackup(), null, 1)], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `trenazher-backup-${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  };

  const importFile = async (file: File) => {
    try {
      const result = store.importBackup(JSON.parse(await file.text()));
      setMessage(`Восстановлено: тренировок ${result.history}, избранного ${result.favorites}. Ничего не удалено.`);
    } catch (e) {
      setMessage(`Не получилось: ${(e as Error).message}`);
    }
  };

  return (
    <Section title="Где хранятся данные" icon="device">
      <div className="small muted">
        История, избранное и настройки хранятся на этом устройстве (тренировок в истории: {historyCount}). На другое устройство они сами не переносятся — для этого есть резервная копия.
      </div>
      <button className="btn btn-secondary" onClick={exportFile}><Icon name="download" /> Сохранить резервную копию</button>
      <button className="btn-text blue" onClick={() => input.current?.click()}>Восстановить из файла</button>
      <input ref={input} type="file" accept="application/json,.json" className="visually-hidden"
        onChange={(e) => { const f = e.target.files?.[0]; if (f) void importFile(f); e.target.value = ""; }} />
      {message ? <div className="small" role="status">{message}</div> : null}
    </Section>
  );
}

export function Issues() {
  const issues = useStore((s) => s.content.manifest?.issues ?? []);
  const groups: Array<[ContentIssue["severity"], string]> = [["error", "Ошибки"], ["warning", "Нужно поправить в таблице"], ["info", "Для сведения"]];
  return (
    <div className="screen">
      <Header title="Проверка контента" back="/settings" />
      <div className="content">
        <div className="small muted">
          Упражнения собираются из таблицы «Дрон тренировка» и папок на Google Drive. Здесь — что не удалось сопоставить.
          Упражнения при этом работают, просто без части фото или видео.
        </div>
        {issues.length === 0 ? <EmptyState icon="check" title="Замечаний нет" message="Все файлы из таблицы найдены." /> : null}
        {groups.map(([severity, title]) => {
          const items = issues.filter((i) => i.severity === severity);
          if (!items.length) return null;
          return (
            <section key={severity} style={{ display: "flex", flexDirection: "column", gap: 8 }}>
              <div className="section-title"><h2>{title}</h2><span className="muted small">{items.length}</span></div>
              {items.map((item, i) => <div key={i} className="card pad small muted">{item.message}</div>)}
            </section>
          );
        })}
      </div>
    </div>
  );
}
