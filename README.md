# Pulau

Small macOS menu-bar app that brings incoming notifications to a notch-style banner.

## Build and run

```sh
./build-app.sh
open dist/Pulau.app
```

Start **Start notifications** from the menu-bar menu. Use **Test banner (visual only)** to check banner rendering without granting notification access. Pulau only observes notifications delivered after it starts; it does not keep history or dismiss Notification Center entries.

## GLM usage

Set a GLM API key from the Agent Usage menu to see your five-hour and weekly remaining limits. The key is stored in macOS Keychain and sent to Z.ai. GLM provider adapted from OpenUsage (MIT) by Robin Ebers.

## Codex usage

Sign in to Codex from the menu to see your five-hour remaining limit in the island. Use the menu to refresh or sign out. Codex provider adapted from [OpenUsage](https://github.com/robinebers/OpenUsage) (MIT) by Robin Ebers. The provider marks are original, brand-inspired graphics, not official logos.

## Permission and privacy

macOS has no public API for observing notifications from other apps. Pulau reads the private `usernoted` SQLite database in read-only mode, so macOS updates may break capture. It requires **Full Disk Access**:

1. Open **Full Disk Access Settings…** from Pulau's menu.
2. Add `dist/Pulau.app` and enable it.
3. Quit and relaunch Pulau, then start notifications.

There is no permission prompt. The build script signs with the first available Apple Development identity, like drSim; no provisioning profile is needed because app is not sandboxed. Full Disk Access is broad and notification text may contain sensitive content, including authentication codes. Live database capture has not yet been tested on this machine.
