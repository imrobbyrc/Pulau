# Pulau Pi Subagents

Optional Pi extension for `@imrobbyrc/pi-core-subagent` 1.3.62 and Rex. It reports each subagent's coarse lifecycle through a separate OSC 7501 child record. Pulau reads the records from Rex and displays them separately from the parent Pi agent.

The active Pi session's provider and model ID are sent to Rex and shown in Pulau on hover. For working subagents, the first line of the task instruction (up to 80 characters) is sent as the status message to Rex and shown in Pulau on hover. This may contain sensitive information; disable the plugin when you do not want it shared with Rex. No results, paths outside that line, or raw run/task IDs are sent. Queued and aborted tasks are not reported. Completed and failed records remain until the session ends or reporting is disabled. Tasks already active before the extension loads may not show a title.

## Install

Use **Pi Subagents Plugin → Install Pi plugin** in Pulau's menu, or install from the Pulau repository:

```sh
pi install "$(pwd)/Integrations/PiSubagents"
```

In each existing Pi session, run `/reload`; new Pi sessions load it automatically. It reports only in an interactive Rex terminal, not over tmux or screen, and respects `PI_PROGRAM_STATUS=0`.

## Disable and remove

- In Pulau's menu, **Enable Pi Subagents** controls reporting globally. Updated plugin sessions observe the change automatically; existing sessions running an older plugin need `/reload` once.
- `/pulau-subagents off` disables reporting and clears its Rex records for the current session. `/pulau-subagents on` enables it again only when the global Pulau switch is on; `/pulau-subagents status` shows the effective setting. The per-session toggle resets when Pi reloads.
- **Uninstall Pi plugin** disables reporting and removes its global Pi package registration. The local package files are retained. Existing Pi sessions may need `/reload`; do this only after active in-process subagents finish.
- `pi config` can also manage the package. If it applies a custom extension filter, change that filter in `pi config` before using Pulau's switch.
- To uninstall from the CLI, use `pi remove /absolute/path/to/the/installed/PiSubagents`, then `/reload` existing sessions.

The global switch is stored in `~/.config/pulau/pi-subagents.json`. Invalid settings fail closed rather than enabling reporting. Stopping this extension does not change Pi's own root status or terminate agents.

## Test

```sh
bun test Integrations/PiSubagents/*.test.ts
```
