# 📸 Yakala

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform: Linux](https://img.shields.io/badge/platform-Linux-blue.svg)](#)

A fast, tray-only screen capture tool for Linux, built with a native C++ daemon and an on-demand
Flutter UI. No window is ever visible during normal use — press a hotkey, capture, done.

> Linux is production-ready. macOS support is in progress (native daemon scaffolded, capture/tray
> not yet implemented). UI text is in Turkish.

## 🌟 Features

- 🖥️ **Full screen, region, or window capture** — from the tray menu or a global hotkey (`Super+Shift+C` by default)
- ✂️ **Region selection overlay** — drag to select, then optionally annotate
- ✏️ **Built-in annotation editor** — draw, add text, and mark up a capture before it's saved
- 📋 **Instant clipboard copy** on every capture, with an optional save-to-file
- 🔔 **Native notifications** and an optional shutter sound
- 🚀 **Autostart on login**, single-instance guarded
- ⚡ **~190ms typical capture latency** — the daemon shells out directly to `grim`/`import`/`scrot`/`maim`, no Flutter overhead on the capture path

## 🏗️ Architecture

Yakala splits into two processes so the always-on parts (tray, hotkey, capture, clipboard) never
have to pay Flutter's startup cost, and the UI only exists while it's actually needed:

| Binary | Language | Lifetime | Responsibilities |
|---|---|---|---|
| `yakala-daemon` | C++17 | long-running, autostarted | tray icon, global hotkey, IPC server, native screen capture, clipboard, notifications |
| `yakala-ui` | Flutter (Dart) | on-demand, exits when done | annotation editor, region-selection overlay, settings window |

The daemon spawns `yakala-ui` as a subprocess only when a window is actually needed (editing,
region selection, settings) and communicates over a Unix domain socket. See
[`CLAUDE.md`](CLAUDE.md) for the full architecture writeup and [`BUSINESS_FLOW.md`](BUSINESS_FLOW.md)
for a complete behavioral spec of every user flow and edge case.

## 📦 Installation (Linux)

### From a release (recommended)

Download the latest `yakala-linux-x64.tar.gz` from [Releases](../../releases), then:

```bash
tar xzf yakala-linux-x64.tar.gz
cd yakala
bash linux/install-launcher.sh -y
```

This detects your distro (Debian/Ubuntu, Fedora, Arch, openSUSE, Alpine), installs the small set
of runtime tools it shells out to (a screenshot backend, a clipboard tool, `notify-send`), installs
Yakala to `~/.local/share/yakala`, registers a GNOME custom shortcut (`Super+Shift+C`), and starts
the daemon.

### From source

```bash
git clone https://github.com/muhammetali/yakala.git
cd yakala
flutter pub get
flutter build linux --release

cmake -S linux/daemon -B build/daemon-linux -DCMAKE_BUILD_TYPE=Release
cmake --build build/daemon-linux

bash linux/install-launcher.sh -y
```

Build-time dependencies for the daemon: `cmake`, `pkg-config`, a C++17 compiler, `libgtk-3-dev`,
`libayatana-appindicator3-dev`, `libdbus-1-dev`, `nlohmann-json3-dev`.

## 🗑️ Uninstall

```bash
pkill -f ~/.local/share/yakala/yakala-daemon
rm -rf ~/.local/share/yakala \
       ~/.local/share/applications/yakala.desktop \
       ~/.config/autostart/yakala-daemon.desktop
```

## Development

```bash
flutter analyze     # required gate after Dart changes
flutter test        # SettingsProvider, AnnotationEditor, RegionOverlay, TextInputDialog
```

See [`CLAUDE.md`](CLAUDE.md) for source layout, IPC protocol details, and coding conventions.

## 📄 License
MIT — see [LICENSE](LICENSE).
