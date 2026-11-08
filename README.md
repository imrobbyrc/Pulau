# Pulau

Small macOS menu-bar app that brings incoming notifications to a notch-style banner.

## Build and run

```sh
./build-app.sh
open dist/Pulau.app
```

Choose **Minimal** under **Expand Size** to show compact Codex and GLM usage on hover; click it for full details. **Default** opens full details on hover. Notifications always use the full banner.

Choose **Start notifications** from the menu-bar menu to enable notification banners. The setting and Island Look are remembered after relaunch; choose **Stop notifications** to disable capture. Use **Test banner (visual only)** to check banner rendering without granting notification access. Pulau only observes notifications delivered after it starts; it does not keep history or dismiss Notification Center entries.

The **System (Experimental)** island look uses undocumented Liquid Glass variant 11 and private shape/highlight APIs on macOS 27.0.1, falling back to the public HUD material on other versions. Private APIs can change or crash after system updates and are not suitable for Mac App Store distribution. The standalone tuning prototype is saved in `Experiments/notch-height-slider.swift`.

## GLM usage

Set a GLM API key from the Agent Usage menu to see your five-hour and weekly remaining limits. The key is stored in macOS Keychain and sent to Z.ai. GLM provider adapted from OpenUsage (MIT) by Robin Ebers.

## Codex usage

Sign in to Codex from the menu to see your five-hour remaining limit in the island. Use the menu to refresh or sign out. Codex provider adapted from [OpenUsage](https://github.com/robinebers/OpenUsage) (MIT) by Robin Ebers. Codex and Z.ai provider icons are sourced from OpenUsage; its MIT license is included with the icons. Provider marks remain trademarks of their respective owners.

## Permission and privacy

The optional Pi Subagents plugin sends the first line of each working subagent's task instruction to Rex (up to 80 characters) for Pulau's hover details. This may contain sensitive information. Disable the plugin in Pulau or with `/pulau-subagents off` to stop sharing. See `Integrations/PiSubagents/README.md`.

macOS has no public API for observing notifications from other apps. Pulau reads the private `usernoted` SQLite database in read-only mode, so macOS updates may break capture. It requires **Full Disk Access**:

1. Open **Full Disk Access Settings…** from Pulau's menu.
2. Add `dist/Pulau.app` and enable it.
3. Quit and relaunch Pulau. If notifications were enabled, capture resumes automatically.

There is no permission prompt. The build script signs with the first available Apple Development identity, like drSim; no provisioning profile is needed because app is not sandboxed. Full Disk Access is broad and notification text may contain sensitive content, including authentication codes. Live database capture has not yet been tested on this machine.
