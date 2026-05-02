# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`yakala` is a desktop-focused Flutter app (macOS, Linux, Windows) for screen capture. It runs from the system tray with **no main window** in normal use — only the Settings window is ever shown, and only when explicitly opened. The user-configurable global hotkey (default `Cmd+Shift+C`) and the tray "Ekranı Yakala" submenu both invoke capture **directly** without showing any UI; the captured PNG is copied to the OS clipboard, optionally saved to a user-chosen folder, and a native notification is shown. UI strings are in Turkish.

## Common commands

```bash
flutter pub get                                  # install deps
flutter run -d macos | -d linux | -d windows     # run desktop target
flutter analyze                                  # lint / static analysis (run after every change)
flutter test                                     # all tests
flutter test test/widget_test.dart               # single test file
flutter test --plain-name "SettingsProvider"     # single test group/name
```

`flutter analyze` is the required gate after edits — do not leave warnings or errors.

## Architecture

The app is layered: `main.dart` is a thin bootstrap, native side-effects live in `services/`, persistent state lives in `providers/`, and UI in `pages/widgets/`.

**1. `main()` only wires services** (`lib/main.dart`). It acquires a single-instance lock (PID file in temp), initializes `WindowService` (hidden window with `setPreventClose(true)`), `AutostartService`, loads `SettingsProvider` from `SharedPreferences`, registers the global hotkey via `HotkeyService` with the `CaptureService.capture(defaultMode)` callback, builds the tray menu via `TrayService`, and finally hands `SettingsProvider` to the widget tree. The widget tree only ever renders `SettingsPage` — there is no state-driven navigation.

**2. Capture is windowless for fullScreen / window modes.** Hotkey trigger and tray submenu call `CaptureService.capture(mode)` directly. The service: checks macOS Screen Recording permission via `screen_capturer.isAccessAllowed`, captures to a temp PNG via `screen_capturer`, copies to the clipboard via `ClipboardUtils`, optionally copies to `settings.savePath`, and fires a native notification via `NotificationService`. The Settings window only appears when the user clicks the tray "Ayarlar" item.

**Region mode is different — it uses a custom overlay.** `CaptureService._selectRegion()`: hides any visible window, captures the full screen silently via `SilentCapture` (uses `import`/`grim`/`screencapture -x` — no flash/sound, NOT `screen_capturer` which on Linux flashes a notification), then asks `WindowService.enterOverlay(screenSize)` to repurpose the existing window as a fullscreen, frameless, transparent, always-on-top overlay. The widget tree switches to `RegionOverlay`. The user draws a selection, drags/resizes via 8 handles, confirms with `Ctrl/Cmd+C` or `Enter`, cancels with `Esc`. On confirm, the logical-pixel rect is mapped to physical pixels (image/window size ratio) and `image.copyCrop` produces the cropped PNG.

**Annotation editor (post-capture).** If `settings.showEditorAfterCapture` is true (default), `CaptureService._runEditor()` opens the captured PNG in `AnnotationEditor` (wraps `image_painter`). Toolbar: free-style pen, line, arrow, dotted line, rectangle, circle, text, color picker, stroke width, undo, clear. User clicks "Bitti" to flatten + finalize, or "İptal" to discard. The window stays in overlay mode (full-screen with editor centered) for both region selector and editor — no extra window switching. After editor (or directly if disabled), `CaptureService._finalize()` runs: clipboard copy → optional disk save → `SoundService.playCaptureSound()` (shutter via `afplay`/`paplay`/PowerShell SoundPlayer) if `settings.soundEffect` → notification.

**3. Services layer (`lib/services/`) isolates all native side-effects.** Each service has explicit `initialize()` / `dispose()` lifecycle and is constructed once in `main()`:
- `WindowService` — `WindowListener` with `onWindowClose() → hide()` because the X button must not kill a tray app. Settings window dimensions live here. `enterOverlay/exitOverlay` toggle the same physical window between settings dialog and fullscreen region overlay (no second window — just resize + alwaysOnTop + frameless).
- `OverlayController<TResult, TPayload>` — generic Completer-based async coordinator. `RegionSelectorService` and `AnnotationService` extend it. Single source of truth for "open an overlay, wait for user, get result" flows. CaptureService awaits the completer; widget tree renders the corresponding overlay while `isActive`.
- `SoundService` — capture shutter sound. macOS: `afplay /System/Library/Sounds/Grab.aiff`. Linux: tries freedesktop sound theme paths via `paplay`, falls back to `canberra-gtk-play --id=screen-capture`. Windows: PowerShell `SoundPlayer`. No package dependency.
- `SilentCapture` (in `lib/utils/silent_capture.dart`) — internal-use full-screen capture that produces NO visual/audio feedback. Used for region's frozen background. Tries `grim` (Wayland), `import` (ImageMagick X11), `scrot`, `maim` in order on Linux. Distinct from `screen_capturer` which on Linux flashes via `gnome-screenshot`. All shell-outs have 8s timeout. Windows uses PowerShell with path passed via env var (PS injection-safe).
- `TempCleanup` (in `lib/utils/temp_cleanup.dart`) — sweeps `yakala_*.png` files older than 24h from temp dir on app startup. Called fire-and-forget from `main()` so it doesn't delay launch.
- `HotkeyService` — single active `HotKey`; `update(config)` re-registers (used by the Settings hotkey recorder for live re-bind).
- `TrayService` — tray icon + submenu (full/region/window) + Ayarlar + Çıkış. Quit calls `dispose()` on every service in order, then `lock.release()`, then `exit(0)`.
- `CaptureService` — orchestrates the full capture flow (see point 2). Reads `SettingsProvider` for mode, sound, savePath, notifications.
- `NotificationService` — `osascript display notification` (macOS) / `notify-send` (Linux) / PowerShell toast (Windows). Best-effort; never throws.
- `AutostartService` — wraps `launch_at_startup`. Initialized lazily; `setEnabled(bool)` is what `SettingsProvider.setStartAtLogin` calls.
- `SingleInstanceService` — PID-lock file in temp dir, atomic via temp-file + rename pattern (no race window between check and write). `kill -0` (POSIX) / `tasklist` (Windows) liveness check. Second instance exits silently. Stale locks (dead PID) are claimed.

**4. State / persistence (`lib/providers/settings_provider.dart`).** `SettingsProvider extends ChangeNotifier` is backed by `SharedPreferences`. Every setter writes to prefs **and** triggers any required side-effect (e.g. `setStartAtLogin` → `AutostartService.setEnabled`). Construct via `await SettingsProvider.create(autostart)` — never directly. Defaults: notifications=true, sound=true, savePath='' (clipboard-only), defaultCaptureMode=fullScreen, hotkey=⌘⇧C.

**5. Hotkey customization.** `HotkeyConfig` (`lib/models/hotkey_config.dart`) is JSON-serializable (`keyUsbHidUsage` int + `List<HotKeyModifier>`), with `toHotKey()` for runtime registration and `displayLabel` for UI rendering (⌘⇧⌥⌃ symbols). The `HotkeyRecorder` widget (`lib/widgets/hotkey_recorder.dart`) captures live key events via `Focus.onKeyEvent`, requires at least one modifier, and on success calls `SettingsProvider.setHotkey` + `HotkeyService.update`.

**6. Native bridges in `lib/utils/`.**
- `ClipboardUtils.copyImageToClipboard(path) → bool` — Wayland-aware (detects `WAYLAND_DISPLAY` and uses `wl-copy` via stdin pipe), falls back to `xclip` for X11. macOS uses `osascript` with `«class PNGf»` (PNG, not JPEG) and shell-escapes the path. Windows uses PowerShell `System.Windows.Forms.Clipboard.SetImage`. Always returns `false` on failure (never throws); callers branch on the bool.
- `TrayUtils.getIconPath()` — `system_tray` cannot read Flutter assets directly, so this copies `assets/app_icon.png` to a temp file and returns the path. Any new tray icon must follow the same pattern.

## Conventions

From `.gemini/CONVENTIONS.md` (the project's own conventions, translated highlights):

- **State management:** `Provider` + `ChangeNotifier`. Persistent state goes through `SettingsProvider`. Don't introduce ad-hoc statics for app state.
- **Folder layout:** `pages/` (screens), `providers/` (state), `services/` (native/external orchestrators with init/dispose), `utils/` (pure helpers + native bridges), `widgets/` (reusable UI), `models/` (DTOs / enums).
- **Strict typing:** avoid `dynamic`. Prefer `async/await` over `.then()` chains.
- **Spacing:** use the `gap` package (`Gap(...)`) rather than `SizedBox` for layout spacing.
- **Material 3** with custom `ColorScheme.fromSeed` (deep purple, dark brightness).
- **Naming:** `snake_case.dart` files, `PascalCase` classes, `camelCase` members.
- **Desktop plugin hygiene:** guard plugin calls with `Platform.is*`, never throw from native bridges (return `bool`/null and let the caller decide), always provide `dispose()` for anything that registers OS-level listeners (tray, hotkeys, window).
- **Shell-out safety:** every `Process.run` / `Process.start` to a system command must (1) have a timeout (typically 4-8s), (2) reject paths/inputs containing `\n` `\r` (newline injection), (3) on Windows, pass user-controlled strings via `environment:` map rather than interpolating into the script string. See `clipboard_utils.dart`, `silent_capture.dart`, `notification_service.dart` for the pattern.

## Testing

Tests **must** mock the native plugin method channels — real ones aren't available in the test runner. `test/helpers/mock_channels.dart` (`setupMockChannels()`) stubs `window_manager`, `screen_capturer`, `hotkey_manager`, `system_tray`, `path_provider`, `launch_at_startup`, `package_info_plus`, `screen_retriever`, and seeds `SharedPreferences` via `setMockInitialValues({})`. Always call it from `setUpAll` in any test that touches these plugins (directly or transitively). When adding a new native plugin, extend `mock_channels.dart` rather than mocking ad-hoc per test.

`test/platform_compatibility_test.dart` is a structural smoke test — it asserts desktop directories (`macos/`, `linux/`), required pubspec deps, and the tray icon asset exist, and that no Dart source uses backslash asset paths. Keep it green when reorganizing.

`test/widget_test.dart` covers `SettingsProvider` defaults / persistence, `HotkeyConfig` JSON round-trip, and a `SettingsPage` render smoke test. There is no test for `CaptureService` because it requires real screen capture.

## Project notes

`.gemini/SCRATCHPAD.md` is a Gemini-CLI-specific working file; ignore it for Claude Code work. Conventions in `.gemini/CONVENTIONS.md` and goals in `.gemini/GEMINI.md` apply equally here.
