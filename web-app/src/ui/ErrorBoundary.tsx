import { Component, type ReactNode } from "react";

/** Если экран сломался — не белая страница, а объяснение и выход. Данные в localStorage при этом целы. */
export class ErrorBoundary extends Component<{ children: ReactNode }, { error: Error | null }> {
  state = { error: null as Error | null };

  static getDerivedStateFromError(error: Error) {
    return { error };
  }

  render() {
    if (!this.state.error) return this.props.children;
    return (
      <div className="center-screen" style={{ minHeight: "100vh" }}>
        <h1 className="title-l">Что-то пошло не так</h1>
        <p className="muted">
          Экран не открылся. История, избранное и текущая тренировка на месте — ничего не потерялось.
        </p>
        <button className="btn btn-primary" onClick={() => { window.location.hash = "#/"; window.location.reload(); }}>
          Перезапустить приложение
        </button>
        <p className="tiny faint">Техническая причина: {this.state.error.message}</p>
      </div>
    );
  }
}
