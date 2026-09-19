// Набор иконок (контуры 24×24). Своими силами — без внешних библиотек.

const paths: Record<string, string> = {
  back: "M15 18l-6-6 6-6",
  forward: "M9 18l6-6-6-6",
  down: "M6 9l6 6 6-6",
  heart: "M12 20s-7-4.4-9.3-8.6C1 8.2 2.8 5 6.1 5c2 0 3.2 1.1 3.9 2.2C10.7 6.1 11.9 5 13.9 5 17.2 5 19 8.2 17.3 11.4 15 15.6 12 20 12 20z",
  check: "M5 12.5l4.5 4.5L19 7.5",
  timer: "M12 8v5l3 2M9 2h6M12 22a8 8 0 100-16 8 8 0 000 16z",
  play: "M8 5.5v13l11-6.5z",
  close: "M6 6l12 12M18 6L6 18",
  info: "M12 22a10 10 0 100-20 10 10 0 000 20zM12 11v6M12 7.5v.5",
  undo: "M9 14L4 9l5-5M4 9h10.5a5.5 5.5 0 010 11H11",
  gear: "M12 15a3 3 0 100-6 3 3 0 000 6zM19.4 15a1.7 1.7 0 00.3 1.8l.1.1a2 2 0 11-2.8 2.8l-.1-.1a1.7 1.7 0 00-1.8-.3 1.7 1.7 0 00-1 1.5V21a2 2 0 11-4 0v-.1a1.7 1.7 0 00-1.1-1.5 1.7 1.7 0 00-1.8.3l-.1.1a2 2 0 11-2.8-2.8l.1-.1a1.7 1.7 0 00.3-1.8 1.7 1.7 0 00-1.5-1H3a2 2 0 110-4h.1a1.7 1.7 0 001.5-1.1 1.7 1.7 0 00-.3-1.8l-.1-.1a2 2 0 112.8-2.8l.1.1a1.7 1.7 0 001.8.3H9a1.7 1.7 0 001-1.5V3a2 2 0 114 0v.1a1.7 1.7 0 001 1.5 1.7 1.7 0 001.8-.3l.1-.1a2 2 0 112.8 2.8l-.1.1a1.7 1.7 0 00-.3 1.8V9a1.7 1.7 0 001.5 1H21a2 2 0 110 4h-.1a1.7 1.7 0 00-1.5 1z",
  history: "M3 12a9 9 0 109-9 9.7 9.7 0 00-6.7 2.8L3 8M3 3v5h5M12 7v5l4 2",
  list: "M8 6h13M8 12h13M8 18h13M3.5 6h.01M3.5 12h.01M3.5 18h.01",
  grid: "M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h6v6h-6z",
  flame: "M12 22c4 0 7-2.7 7-6.8 0-3.4-2.3-5.7-4-7.7-.4 2-1.3 3.2-2.6 3.8C12.8 8.3 11.6 5 8.7 2.5 8.9 6.4 5 8.8 5 14.6 5 18.9 8 22 12 22z",
  wifiOff: "M2 2l20 20M8.5 16.5a5 5 0 017 0M5 12.9a10 10 0 015.2-2.7M19 12.9a10 10 0 00-2.1-1.6M1.4 9a15 15 0 014.3-2.7M22.6 9A15 15 0 0010.7 5.1M12 20h.01",
  photo: "M4 5h16v14H4zM4 16l5-5 4 4 2-2 5 5M15.5 9.5h.01",
  film: "M4 4h16v16H4zM8 4v16M16 4v16M4 8h4M4 12h4M4 16h4M16 8h4M16 12h4M16 16h4",
  more: "M5 12h.01M12 12h.01M19 12h.01",
  download: "M12 4v11M7 10l5 5 5-5M5 20h14",
  bell: "M18 16v-5a6 6 0 10-12 0v5l-2 2h16zM10 21h4",
  trash: "M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13",
  calendar: "M4 6h16v14H4zM4 10h16M8 3v4M16 3v4",
  cloud: "M7 18a4.5 4.5 0 01-.5-9A6 6 0 0118 8.5a4.5 4.5 0 01-.5 9.5z M9 13l2 2 4-4",
  alert: "M12 3l10 18H2zM12 10v5M12 18h.01",
  share: "M12 3v12M8 7l4-4 4 4M5 12v8h14v-8",
  plus: "M12 5v14M5 12h14",
  repeat: "M17 2l4 4-4 4M3 11V9a3 3 0 013-3h15M7 22l-4-4 4-4M21 13v2a3 3 0 01-3 3H3",
  device: "M7 2h10v20H7zM11 18h2",
};

export function Icon({ name, size = 22, filled = false, className }: { name: keyof typeof paths | string; size?: number; filled?: boolean; className?: string }) {
  return (
    <svg className={className} width={size} height={size} viewBox="0 0 24 24" aria-hidden="true"
      fill={filled ? "currentColor" : "none"} stroke="currentColor" strokeWidth={filled ? 0 : 2} strokeLinecap="round" strokeLinejoin="round">
      <path d={paths[name] ?? ""} />
    </svg>
  );
}

export function SelectionMark({ on }: { on: boolean }) {
  return (
    <span className={`mark ${on ? "mark-on" : ""}`} aria-hidden="true">
      {on ? <Icon name="check" size={18} /> : null}
    </span>
  );
}
