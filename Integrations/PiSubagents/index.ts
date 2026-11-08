import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { homedir } from "node:os";
import { join } from "node:path";
import { readGlobalEnabled, reportingIssue } from "./config.ts";
import { Reporter } from "./reporter.ts";

type TaskEvent = { runId?: unknown; taskId?: unknown; status?: unknown };
type RunEvent = { run?: { id?: unknown; tasks?: Array<{ id?: unknown; status?: unknown; task?: unknown }> } };

export default function (pi: ExtensionAPI) {
  let active = false;
  let sessionEnabled = true;
  let globalEnabled = true;
  let preferenceTimer: ReturnType<typeof setInterval> | undefined;
  let activityTimer: ReturnType<typeof setInterval> | undefined;
  let subagents: { status(): unknown } | undefined;
  const configPath = join(homedir(), ".config", "pulau", "pi-subagents.json");
  const reporter = new Reporter((sequence) => {
    if (!reportingIssue(active, Boolean(process.stdout.isTTY), process.env)) process.stdout.write(sequence);
  });

  // Best effort: poll the subagent manager for live tool activity when the package resolves.
  void (async () => {
    for (const specifier of ["@imrobbyrc/pi-core-subagent", "pi-core-subagent"]) {
      try {
        const mod = await import(specifier);
        subagents = mod.createSubagentController(pi);
        return;
      } catch {}
    }
  })();

  function pollActivity() {
    if (!subagents) return;
    try {
      const runs = subagents.status() as Array<{ id?: unknown; tasks?: Array<{ id?: unknown; status?: unknown; lastActivity?: unknown }> }>;
      for (const run of runs ?? []) {
        if (typeof run?.id !== "string" || !Array.isArray(run.tasks)) continue;
        for (const task of run.tasks) {
          if (task.status === "running" && typeof task.lastActivity === "string") {
            reporter.setActivity(run.id, task.id, task.lastActivity);
          }
        }
      }
    } catch {}
  }

  function syncGlobal() {
    globalEnabled = readGlobalEnabled(configPath);
    reporter.setEnabled(sessionEnabled && globalEnabled);
  }

  function updateRun(data: unknown) {
    if (!active || !data || typeof data !== "object") return;
    const run = (data as RunEvent).run;
    if (!run || !Array.isArray(run.tasks)) return;
    for (const task of run.tasks) reporter.update(run.id, task.id, task.status, task.task);
  }

  pi.events.on("subagent:run-created", updateRun);
  pi.events.on("subagent:run-completed", updateRun);
  pi.events.on("subagent:task-updated", (data: unknown) => {
    if (!active || !data || typeof data !== "object") return;
    const event = data as TaskEvent;
    reporter.update(event.runId, event.taskId, event.status);
  });
  for (const name of ["subagent:task-resumed", "subagent:task-corrected", "subagent:task-aborted"]) {
    pi.events.on(name, (data: unknown) => {
      if (!active || !data || typeof data !== "object") return;
      const event = data as TaskEvent;
      reporter.update(event.runId, event.taskId, "queued");
    });
  }

  pi.on("session_start", (_event, ctx) => {
    active = ctx.hasUI;
    if (active) {
      reporter.clear();
      syncGlobal();
      reporter.setModel(ctx.model?.provider, ctx.model?.id);
      preferenceTimer = setInterval(syncGlobal, 1000);
      preferenceTimer.unref();
      activityTimer = setInterval(pollActivity, 1500);
      activityTimer.unref();
    }
  });
  pi.on("model_select", (event) => {
    if (active) reporter.setModel(event.model?.provider, event.model?.id);
  });
  pi.on("session_shutdown", () => {
    if (preferenceTimer) clearInterval(preferenceTimer);
    preferenceTimer = undefined;
    if (activityTimer) clearInterval(activityTimer);
    activityTimer = undefined;
    if (active) reporter.clear();
    active = false;
  });

  pi.registerCommand("pulau-subagents", {
    description: "Toggle Rex subagent reporting for this Pi session: on, off, or status",
    handler: async (args, ctx) => {
      const action = args.trim().toLowerCase();
      if (action === "on") sessionEnabled = true;
      else if (action === "off") sessionEnabled = false;
      else if (action !== "" && action !== "status") {
        ctx.ui.notify("Use /pulau-subagents on, off, or status", "warning");
        return;
      }
      syncGlobal();
      const issue = reportingIssue(active, Boolean(process.stdout.isTTY), process.env);
      const reason = !globalEnabled ? "disabled in Pulau" : issue ?? "this session";
      ctx.ui.notify(`Pulau subagent reporting: ${reporter.isEnabled && !issue ? "on" : "off"} (${reason})`, "info");
    },
  });
}
