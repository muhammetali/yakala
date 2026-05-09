# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`yakala` is a desktop screen-capture tool for Linux (production-ready) and macOS (in progress). UI strings are in Turkish.

**Architecture: native daemon + on-demand Flutter UI** (since branch `feat/native-daemon`, faz 1-3.5).

The previous Flutter-only architecture (single Flutter binary acting as tray app) was abandoned because of structural bugs in the Linux/GNOME ecosystem:
- `system_tray` and `tray_manager` Linux backends ignored 2nd menu click on GNOME 46 (ubuntu-appindicators extension dispatch issue).
- `hotkey_manager_linux` 0.2.0 silently ignored `keybinder_bind` failures.
- Off-screen window pattern + Mutter compositor interactions left "frozen editor" artifacts.

These are documented in `memory/linux_capture_stability.md`, `memory/linux_hotkey_tray_bypass.md`, and superseded by `memory/native_daemon_architecture.md`.

## Architecture

### Two-process design

| Binary | Language | Lifetime | Responsibilities |
|---|---|---|---|
| `yakala-daemon` | C++17 (Linux) / Swift (macOS, planned) | long-running, autostarted | tray icon, IPC server, native screen capture, clipboard, notification, UI orchestration |
| `yakala-ui` | Flutter (Dart) | on-demand, exit when done | `AnnotationEditor`, `RegionOverlay`, `SettingsPage` |

The daemon is the **always-on** component. The Flutter UI binary is launched only when needed (capture editor, region selection, settings page) and exits with `exit(0)` when the user finishes that mode.

### Communication

- **Daemon → UI**: `fork+execvp` via GSubprocess. Args: `yakala-ui --mode={editor,region,settings} [--input=<png>] [--output=<edit-png>]`. STDIN/STDOUT/STDERR inherit (UI's debugPrint flows into daemon log).
- **UI → Daemon**: Unix socket (`$XDG_RUNTIME_DIR/yakala-daemon.sock` on Linux, `~/Library/Application Support/Yakala/daemon.sock` on macOS). JSON line-delimited messages.

UI sends `{"cmd": "ui_result", "ok": true, "output": "/tmp/yakala_edit_xxx.png"}` after Bitti, or `{"cmd": "ui_result", "ok": false, "reason": "user_cancelled"}` on cancel. Daemon waits via `g_subprocess_wait_async`, then finalizes (clipboard, disk, notification).

External clients (GNOME custom shortcut, scripts) can also connect to the socket: `yakala-daemon --capture-fullscreen` is the **same binary** running in CLI client mode — it opens the socket, sends `{"cmd": "capture_full"}`, and exits. Industrial pattern shared with git, docker daemon, etc.

### Settings persistence

Single source of truth: `~/.config/yakala/settings.json` (Linux) / `~/Library/Application Support/Yakala/settings.json` (macOS).

UI writes atomically (`tmp + rename`); daemon reads on startup and re-reads via mtime check at every capture. Both processes can write/read the same file safely; race window is acceptable since daemon never writes (only UI does).

Hotkey is **not** in settings.json — it's owned by the OS:
- Linux: GNOME `gsettings` custom keybinding (Super+Shift+C → `yakala-daemon --capture-fullscreen`). `linux/install-launcher.sh` registers it.
- macOS: Carbon `RegisterEventHotKey` (planned in Faz 4); fallback NSEvent global monitor.

Autostart is **not** in settings.json — owned by the OS:
- Linux: `~/.config/autostart/yakala-daemon.desktop` (installed by `install-launcher.sh`).
- macOS: LaunchAgent plist (planned).

## Common commands

```bash
# Flutter UI
flutter pub get
flutter analyze                            # required gate
flutter test                               # all tests
flutter build linux --release              # build UI bundle

# Linux native daemon
cmake -S linux/daemon -B build/daemon-linux -DCMAKE_BUILD_TYPE=Release
cmake --build build/daemon-linux           # produces build/daemon-linux/yakala-daemon

# Install both binaries
bash linux/install-launcher.sh -y          # builds, installs, registers shortcut, starts daemon
```

`flutter analyze` is the required gate after Dart edits. After C++ daemon edits, ensure cmake build succeeds without warnings.

## Linux daemon source layout

```
linux/daemon/
├── CMakeLists.txt
├── include/
│   ├── logger.hh           — thread-safe stderr logger, YAKALA_LOG env
│   ├── settings_loader.hh  — XDG JSON loader, mtime-based reload
│   ├── ipc_server.hh       — Unix socket, JSON line protocol, single-instance check
│   ├── ui_spawner.hh       — GSubprocess wrapper for yakala-ui
│   ├── tray.hh             — libayatana-appindicator native tray
│   ├── process_runner.hh   — sync/async GSubprocess shell-out helper
│   ├── capture.hh          — screen capture (grim/import/scrot/maim chain)
│   ├── clipboard.hh        — xclip/wl-copy with file-stdin async pattern
│   ├── notification.hh     — notify-send fire-and-forget
│   └── capture_orchestrator.hh — capture+UI+finalize flow with re-entry guard
└── src/                    — same names, .cc
    └── main.cc             — entry: GTK init, signal handlers, glib main loop
```

## Flutter UI source layout

```
lib/
├── main.dart               — minimal CLI dispatcher (~80 lines)
├── modes/
│   ├── editor_mode.dart    — runEditorMode: input PNG → AnnotationEditor → output PNG → exit
│   ├── region_mode.dart    — runRegionMode: full-screen PNG → RegionOverlay → cropped PNG → exit
│   └── settings_mode.dart  — runSettingsMode: SettingsPage in a normal window
├── pages/settings_page.dart — settings UI (no hotkey recorder, no autostart toggle — OS owns those)
├── providers/settings_provider.dart — JSON file backed (NOT SharedPreferences)
├── utils/ipc_client.dart   — daemon socket sender (best-effort)
├── widgets/                — AnnotationEditor, RegionOverlay, TextInputDialog
└── models/capture_mode.dart — enum (no enum-to-screen_capturer mapping; daemon doesn't use Dart for capture)
```

## Capture flow

1. **Trigger**: tray menu click (handled inline in C++) OR `yakala-daemon --capture-fullscreen` CLI (sends IPC) OR external IPC client.
2. **Native capture**: `Capture::capture_full_screen()` shells out to grim/import/scrot/maim. ~190ms typical. Result: `/tmp/yakala_<ts>.png`.
3. **UI flow** (only if needed):
   - `mode == region`: spawn `yakala-ui --mode=region --input=<png> --output=<crop>`.
   - `mode == fullScreen|window` AND `settings.show_editor_after_capture`: spawn `yakala-ui --mode=editor --input=<png> --output=<edit>`.
   - else: skip UI, go straight to finalize.
4. **UI session**: user edits/selects in Flutter window. On Bitti, UI writes output file + sends IPC `ui_result`, then `exit(0)`. Daemon's `g_subprocess_wait_async` callback fires.
5. **Finalize**: copy PNG to clipboard (async via `xclip`/`wl-copy` with file-stdin), optional copy to user save_path, notification via `notify-send`.

Re-entry guard: `CaptureOrchestrator::busy_` flag — while a capture (incl. UI session) is in flight, new triggers are silently dropped.

## Conventions

### C++ (linux/daemon)
- C++17, `-Wall -Wextra -Wpedantic`. RAII for all GLib/GTK resources (ref/unref pattern with smart guards or explicit pairs).
- Logging: `YAKALA_LOG_INFO("tag") << "..."` macros (stream-style). Levels: debug/info/warn/error, controlled by `YAKALA_LOG=info` env.
- All shell-outs through `ProcessRunner` (sync) or `g_subprocess_newv` (async). Timeouts mandatory.
- No custom SIGCHLD handler — GLib handles child reap. Adding one races with `g_subprocess_wait_async`.

### Dart (lib/)
- State management: `Provider` + `ChangeNotifier`. `SettingsProvider` is the only persistent store.
- `gap` package (`Gap(...)`) for spacing, not `SizedBox`.
- Material 3 with `ColorScheme.fromSeed(Colors.deepPurple, brightness: dark)`.
- Mode files in `lib/modes/` are entry-points: each calls `runApp` and never returns to caller.
- Naming: `snake_case.dart` files, `PascalCase` classes, `camelCase` members.
- All exit paths from UI mode call `exit(0)` after IPC.

### Shell-out safety (Linux)
- Every Process spawn must (1) have a timeout, (2) reject `\n` `\r` in user-controlled paths, (3) use file-stdin instead of pipe-stdin for tools that fork-and-detach (xclip, wl-copy).

## Testing

`flutter test` covers: SettingsProvider JSON round-trip, AnnotationEditor + RegionOverlay widget tests, TextInputDialog. Mock channels in `test/helpers/mock_channels.dart` cover `window_manager` and `screen_retriever` only (other plugins are gone).

C++ daemon currently has no unit tests — coverage is integration-level via end-to-end runs. Future: GoogleTest for `IpcServer`, `SettingsLoader`, `Capture` (mock ProcessRunner).

## Branch / commit history

- `main` — last Flutter-only commit is `5d80ae0`. Don't push native-daemon work here until Faz 4 (macOS) is done.
- `feat/native-daemon` — current development branch, faz 1-3.5 complete (Linux production-ready).

Major commits on `feat/native-daemon`:
- `48ad93c` checkpoint: tray_manager + v6 exitOverlay (last Flutter-only state)
- `6dfce23` faz 1: native daemon scaffold
- `392cb1d` faz 2: native capture + clipboard + notification + single-instance
- `d3b15ae` faz 3: Flutter UI refactor + install integration (-5000 lines net)
- `d2a8503` faz 3.5: editor + region UI flow async integration

## Project notes

- `.gemini/` directory contains older convention docs from a Gemini-CLI-driven phase; lower priority than this file.
- macOS daemon (Faz 4) not yet started — `macos/Runner/` still has the old Flutter wrapper.
