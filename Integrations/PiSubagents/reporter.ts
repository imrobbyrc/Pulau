import { createHash } from "node:crypto";

type Status = "working" | "blocked" | "done" | "error";
const prefix = "pulau-subagents";

function childId(runId: string, taskId: string): string {
  return `${prefix}/${createHash("sha256").update(runId).update("\0").update(taskId).digest("hex").slice(0, 16)}`;
}

function stateFor(status: string): Status | undefined {
  switch (status) {
    case "starting":
    case "running": return "working";
    case "awaiting_parent": return "blocked";
    case "completed": return "done";
    case "failed": return "error";
    default: return undefined;
  }
}

export class Reporter {
  private enabled = true;
  private readonly states = new Map<string, Status>();
  private readonly titles = new Map<string, string>();
  private model?: string;
  constructor(private readonly write: (sequence: string) => void) {}

  get isEnabled(): boolean { return this.enabled; }

  private send(state: Status | "clear", id: string): void {
    const title = state === "working" ? this.titles.get(id) : undefined;
    const message = title ? `:msg=${Buffer.from(title, "utf8").toString("base64")}` : "";
    this.write(`\x1b]7501;state=${state}:id=${id}${state === "clear" ? "" : ":app=pi"}${message}\x1b\\`);
  }

  setModel(provider: unknown, id: unknown): void {
    const valid = (value: unknown): value is string => typeof value === "string" && /^[A-Za-z0-9._+:/-]{1,80}$/.test(value);
    const name = valid(provider) && valid(id) ? `${provider}/${id}` : undefined;
    const model = name && name.length <= 80 ? name : undefined;
    if (model === this.model) return;
    this.model = model;
    if (this.enabled) this.sendModel();
  }

  private sendModel(): void {
    const message = this.model ? `:app=pi:msg=${Buffer.from(this.model, "utf8").toString("base64")}` : "";
    this.write(`\x1b]7501;state=${this.model ? "idle" : "clear"}:id=${prefix}/model${message}\x1b\\`);
  }

  update(runId: unknown, taskId: unknown, status: unknown, task?: unknown): void {
    if (typeof runId !== "string" || typeof taskId !== "string" || typeof status !== "string") return;
    const id = childId(runId, taskId);
    const previousTitle = this.titles.get(id);
    if (typeof task === "string") {
      const title = Array.from(task.split(/[\r\n]/, 1)[0].replace(/[\u0000-\u001f\u007f-\u009f]/g, " ").trim()).slice(0, 80).join("");
      if (title) this.titles.set(id, title);
      else this.titles.delete(id);
    }
    if (["completed", "failed", "aborted"].includes(status)) this.titles.delete(id);
    const state = stateFor(status);
    if (!state) {
      if (this.states.delete(id) && this.enabled) this.send("clear", id);
      return;
    }
    if (this.states.get(id) === state && previousTitle === this.titles.get(id)) return;
    this.states.set(id, state);
    if (this.enabled) this.send(state, id);
  }

  setEnabled(value: boolean): void {
    if (this.enabled === value) return;
    this.enabled = value;
    if (!value) this.send("clear", prefix);
    else {
      if (this.model) this.sendModel();
      for (const [id, state] of this.states) this.send(state, id);
    }
  }

  clear(): void {
    this.send("clear", prefix);
    this.states.clear();
    this.titles.clear();
    this.model = undefined;
  }
}
