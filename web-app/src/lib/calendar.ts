import type { Settings } from "./types";

// Напоминания без сервера рассылок: повторяющееся событие в Календаре iPhone.
// Файл .ics собирается прямо в приложении и отдаётся через «Поделиться» —
// переход по ссылке уводил бы из приложения, запущенного с экрана «Домой».

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



/** Текст файла напоминания. Делаем его на телефоне, чтобы приложение никуда не уходило:
 *  переход на .ics в режиме «с экрана Домой» оставлял белый экран без выхода. */
export function icsText(settings: Settings, now = new Date()): string {
  const start = firstOccurrence(settings, now);
  const end = new Date(start.getTime() + 60 * 60 * 1000);
  const days = [...settings.reminderWeekdays].sort((a, b) => a - b).map((d) => DAY_CODES[d - 1]).join(",");
  return [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Trenazher//RU",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    "BEGIN:VEVENT",
    `UID:trenazher-${floating(start)}@trenazher`,
    `DTSTAMP:${floating(now)}Z`,
    `DTSTART:${floating(start)}`,
    `DTEND:${floating(end)}`,
    `RRULE:FREQ=WEEKLY;BYDAY=${days}`,
    "SUMMARY:Тренировка",
    "DESCRIPTION:Открой Тренажёр и выбери тренировку.",
    "BEGIN:VALARM",
    "ACTION:DISPLAY",
    "DESCRIPTION:Время тренировки",
    "TRIGGER:-PT0M",
    "END:VALARM",
    "END:VEVENT",
    "END:VCALENDAR",
    "",
  ].join("\r\n");
}

const WEEKDAY_NAMES = ["понедельник", "вторник", "среда", "четверг", "пятница", "суббота", "воскресенье"];

/** Человеческое описание расписания — для подсказки «поставить вручную». */
export function scheduleText(settings: Settings): string {
  const days = [...settings.reminderWeekdays].sort((a, b) => a - b).map((d) => WEEKDAY_NAMES[d - 1]).join(", ");
  const time = `${String(settings.reminderHour).padStart(2, "0")}:${String(settings.reminderMinute).padStart(2, "0")}`;
  return `${days || "дни не выбраны"} в ${time}`;
}
