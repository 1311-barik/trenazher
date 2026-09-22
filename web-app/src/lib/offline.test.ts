import { describe, expect, it } from "vitest";
import { downloadVideos, isOutOfSpace } from "./offline";

// ТЗ 6.5: «не хватает места — сообщить и предложить освободить», а не продолжать
// молотить по списку с одинаковой ошибкой.

const quotaError = () => Object.assign(new Error("quota"), { name: "QuotaExceededError" });

describe("скачивание видео для офлайна", () => {
  it("докачивает остальные после обычной ошибки сети", async () => {
    const seen: string[] = [];
    const result = await downloadVideos(["a", "b", "c"], async (id) => {
      seen.push(id);
      if (id === "b") throw new Error("network");
    });
    expect(seen).toEqual(["a", "b", "c"]);
    expect(result).toEqual({ done: 2, failed: 1, outOfSpace: false });
  });

  it("останавливается, когда кончилось место, и говорит об этом отдельно", async () => {
    const seen: string[] = [];
    const result = await downloadVideos(["a", "b", "c"], async (id) => {
      seen.push(id);
      if (id === "b") throw quotaError();
    });
    expect(seen).toEqual(["a", "b"]);
    expect(result).toEqual({ done: 1, failed: 1, outOfSpace: true });
  });

  it("сообщает прогресс после каждого файла", async () => {
    const steps: number[] = [];
    await downloadVideos(["a", "b"], async () => {}, (done) => steps.push(done));
    expect(steps).toEqual([1, 2]);
  });

  it("узнаёт нехватку места по имени ошибки и по коду Safari", () => {
    expect(isOutOfSpace(quotaError())).toBe(true);
    expect(isOutOfSpace(Object.assign(new Error("x"), { code: 22 }))).toBe(true);
    expect(isOutOfSpace(new Error("network"))).toBe(false);
  });
});
