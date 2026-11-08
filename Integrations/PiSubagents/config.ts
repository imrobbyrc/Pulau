import { readFileSync, statSync } from "node:fs";

export function reportingIssue(active: boolean, isTTY: boolean, env: NodeJS.ProcessEnv): string | undefined {
  if (!active || !isTTY) return "no interactive TTY";
  if (!env.REX_BLOCK) return "not inside Rex";
  const term = env.TERM ?? "";
  if (env.TMUX || term.startsWith("screen") || term.startsWith("tmux")) return "tmux/screen is not supported";
  if (env.PI_PROGRAM_STATUS === "0") return "PI_PROGRAM_STATUS=0";
  return undefined;
}

export function readGlobalEnabled(path: string): boolean {
  try {
    if (statSync(path).size > 32_768) return false;
    const value: unknown = JSON.parse(readFileSync(path, "utf8"));
    if (!value || typeof value !== "object" || Array.isArray(value)) return false;
    const enabled = (value as { enabled?: unknown }).enabled;
    return enabled === undefined ? true : enabled === true;
  } catch (error) {
    return (error as NodeJS.ErrnoException).code === "ENOENT";
  }
}
