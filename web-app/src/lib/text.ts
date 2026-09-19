// Русские подписи и форматирование.

export function plural(count: number, one: string, few: string, many: string): string {
  const n = Math.abs(count) % 100;
  const n1 = n % 10;
  if (n > 10 && n < 20) return many;
  if (n1 > 1 && n1 < 5) return few;
  if (n1 === 1) return one;
  return many;
}

export const exercisesText = (n: number) => `${n} ${plural(n, "упражнение", "упражнения", "упражнений")}`;
export const workoutsText = (n: number) => `${n} ${plural(n, "тренировка", "тренировки", "тренировок")}`;

export function durationText(ms: number): string {
  const minutes = Math.max(1, Math.round(ms / 60000));
  if (minutes < 60) return `${minutes} мин`;
  return `${Math.floor(minutes / 60)} ч ${minutes % 60} мин`;
}

export function timerText(seconds: number): string {
  const s = Math.max(0, seconds);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

export function megabytes(bytes: number): string {
  if (!bytes) return "0 МБ";
  if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} КБ`;
  const mb = bytes / (1024 * 1024);
  return mb >= 1024 ? `${(mb / 1024).toFixed(1).replace(".", ",")} ГБ` : `${Math.round(mb)} МБ`;
}

const dayTime = new Intl.DateTimeFormat("ru-RU", { weekday: "short", day: "numeric", month: "long", hour: "2-digit", minute: "2-digit" });
const monthYear = new Intl.DateTimeFormat("ru-RU", { month: "long", year: "numeric" });
const time = new Intl.DateTimeFormat("ru-RU", { hour: "2-digit", minute: "2-digit" });
const dayMonth = new Intl.DateTimeFormat("ru-RU", { day: "numeric", month: "long" });

export const formatDayTime = (t: number) => dayTime.format(new Date(t));
export const formatMonth = (t: number) => {
  const text = monthYear.format(new Date(t)).replace(" г.", "");
  return text.charAt(0).toUpperCase() + text.slice(1);
};

/** «сегодня в 10:42», «вчера в 19:00», «17 сентября в 08:15». */
export function formatRelative(t: number, now = Date.now()): string {
  const date = new Date(t);
  const today = new Date(now);
  today.setHours(0, 0, 0, 0);
  const day = new Date(t);
  day.setHours(0, 0, 0, 0);
  const diffDays = Math.round((today.getTime() - day.getTime()) / 86400000);
  const at = time.format(date);
  if (diffDays === 0) return `сегодня в ${at}`;
  if (diffDays === 1) return `вчера в ${at}`;
  return `${dayMonth.format(date)} в ${at}`;
}
