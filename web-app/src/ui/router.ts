import { useEffect, useState } from "react";

// Навигация через адрес после «#». В приложении с экрана «Домой» у iPhone нет кнопки «Назад»
// браузера, поэтому у каждого экрана своя кнопка «‹» с понятным родителем.

export function parseRoute(hash: string): string[] {
  return hash.replace(/^#\/?/, "").split("/").filter(Boolean).map((p) => decodeURIComponent(p));
}

export function useRoute(): string[] {
  const [route, setRoute] = useState(() => parseRoute(window.location.hash));
  useEffect(() => {
    const onChange = () => {
      setRoute(parseRoute(window.location.hash));
      window.scrollTo(0, 0);
    };
    window.addEventListener("hashchange", onChange);
    return () => window.removeEventListener("hashchange", onChange);
  }, []);
  return route;
}

export function go(path: string, replace = false): void {
  const hash = "#" + path;
  if (replace) window.location.replace(hash);
  else window.location.hash = hash;
}

export const link = (...parts: string[]) => "/" + parts.map((p) => encodeURIComponent(p)).join("/");
