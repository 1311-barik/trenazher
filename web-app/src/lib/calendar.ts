import type { Settings } from "./types";

// Напоминания без сервера рассылок: повторяющееся событие в Календаре iPhone.
// Сервер (nginx, см. deploy/trenazher.nginx) отдаёт .ics по параметрам ссылки —
// Safari показывает системное окно «Добавить в Календарь».

const DAY_CODES = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]; // 1 … 7

const pad = (n: number) => String(n).padStart(2, "0");

/** Локальное время без часового пояса: iPhone поймёт его в своём поясе. */
function floating(date: Date): string {
  return `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}T${pad(date.getHours())}${pad(date.getMinutes())}00`;
}

/** Ближайший подходящий день недели в выбранное время (первое событие должно совпасть с правилом повтора). */
export function firstOccurrence(settings: Settings, now = new Date()): Date {
  const days = new Set(settings.reminderWeekdays);
  for (let offset = 0; offset < 8; offset += 1) {
    const candidate = new Date(now);
    candidate.setDate(now.getDate() + offset);
    candidate.setHours(settings.reminderHour, settings.reminderMinute, 0, 0);
    const weekday = ((candidate.getDay() + 6) % 7) + 1; // понедельник = 1
    if (days.has(weekday) && candidate.getTime() > now.getTime()) return candidate;
  }
  throw new Error("Не выбрано ни одного дня");
}

export function reminderQuery(settings: Settings, now = new Date()): string {
  const start = firstOccurrence(settings, now);
  const end = new Date(start.getTime() + 60 * 60 * 1000);
  const days = [...settings.reminderWeekdays].sort((a, b) => a - b).map((d) => DAY_CODES[d - 1]).join(",");
  return `days=${days}&start=${floating(start)}&end=${floating(end)}`;
}

export const reminderUrl = (settings: Settings, now = new Date()) => `reminder.ics?${reminderQuery(settings, now)}`;
