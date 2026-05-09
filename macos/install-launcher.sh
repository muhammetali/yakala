#!/usr/bin/env bash
# Yakala — macOS launcher kurulumu (kullanıcı bazında).
#
# - Flutter UI bundle'ını /Applications/Yakala.app olarak kopyalar.
# - Swift daemon binary'sini Yakala.app/Contents/Helpers/yakala-daemon olarak kurar.
# - Tray icon'u Yakala.app/Contents/Helpers/icons/tray.png'ye yerleştirir.
# - LaunchAgent plist'i ~/Library/LaunchAgents/com.yakala.daemon.plist'e
#   yazıp launchctl ile yükler (login'de daemon otomatik başlar).
#
# Önkoşullar:
#   1. Flutter UI build edilmiş:    flutter build macos --release
#   2. Swift daemon build edilmiş:  cd macos/daemon && swift build -c release
#
# Kullanım:
#   bash macos/install-launcher.sh         # interaktif
#   bash macos/install-launcher.sh -y      # otomatik
set -euo pipefail

ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help)
      sed -n '2,18p' "$0"
      exit 0
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Flutter UI bundle (Yakala.app — Flutter macOS build output).
UI_APP_SRC=""
for candidate in \
  "$REPO_ROOT/build/macos/Build/Products/Release/Yakala.app" \
  "$REPO_ROOT/build/macos/Build/Products/Profile/Yakala.app" \
  "$REPO_ROOT/build/macos/Build/Products/Debug/Yakala.app"; do
  if [[ -d "$candidate" ]]; then
    UI_APP_SRC="$candidate"
    break
  fi
done

if [[ -z "$UI_APP_SRC" ]]; then
  echo "Hata: Flutter Yakala.app bundle'ı bulunamadı." >&2
  echo "Önce: flutter build macos --release" >&2
  exit 1
fi

# Swift daemon binary.
DAEMON_BIN_SRC="$SCRIPT_DIR/daemon/.build/release/yakala-daemon"
if [[ ! -x "$DAEMON_BIN_SRC" ]]; then
  echo "Hata: yakala-daemon binary'si bulunamadı." >&2
  echo "Önce: cd macos/daemon && swift build -c release" >&2
  exit 1
fi

# Tray icon — Linux'taki ile aynı assets/app_icon.png.
ICON_SRC="$REPO_ROOT/assets/app_icon.png"
if [[ ! -f "$ICON_SRC" ]]; then
  echo "Hata: tray icon bulunamadı: $ICON_SRC" >&2
  exit 1
fi

INSTALL_DIR="/Applications/Yakala.app"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
LA_PLIST="$LAUNCH_AGENTS_DIR/com.yakala.daemon.plist"

mkdir -p "$LAUNCH_AGENTS_DIR"

# Önce çalışan daemon'u durdur (eski plist varsa).
if [[ -f "$LA_PLIST" ]]; then
  launchctl unload "$LA_PLIST" 2>/dev/null || true
fi
pkill -9 -f "/Applications/Yakala.app/Contents/Helpers/yakala-daemon" 2>/dev/null || true
sleep 1

# Eski Yakala.app'i temizle (atomic değil, best-effort).
if [[ -d "$INSTALL_DIR" ]]; then
  rm -rf "$INSTALL_DIR"
fi

# UI bundle'ı kopyala — `Yakala.app` zaten standalone, parent /Applications.
cp -a "$UI_APP_SRC" "$INSTALL_DIR"

# Helpers dizinine daemon kur.
HELPERS_DIR="$INSTALL_DIR/Contents/Helpers"
mkdir -p "$HELPERS_DIR/icons"
install -m 0755 "$DAEMON_BIN_SRC" "$HELPERS_DIR/yakala-daemon"
install -m 0644 "$ICON_SRC" "$HELPERS_DIR/icons/tray.png"

DAEMON_BINARY="$HELPERS_DIR/yakala-daemon"
UI_BINARY="$INSTALL_DIR/Contents/MacOS/Yakala"

# LaunchAgent plist — login'de daemon başlar. KeepAlive ile crash'lerde
# auto-restart.
cat > "$LA_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.yakala.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>$DAEMON_BINARY</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/Yakala/daemon.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/Yakala/daemon.log</string>
</dict>
</plist>
PLIST
chmod 0644 "$LA_PLIST"

# Log dizinini hazırla.
mkdir -p "$HOME/Library/Logs/Yakala"

# LaunchAgent yükle (daemon hemen başlar).
launchctl load "$LA_PLIST"

cat <<EOF
Yakala kuruldu (macOS native daemon mimarisi).

  App bundle  : $INSTALL_DIR
  Daemon      : $DAEMON_BINARY
  UI binary   : $UI_BINARY
  LaunchAgent : $LA_PLIST
  Log dosyası : $HOME/Library/Logs/Yakala/daemon.log

Daemon arka planda başlatıldı; menu bar'da Yakala ikonu birkaç saniyede
görünür. İlk capture sırasında macOS Sistem Ayarları > Gizlilik > Ekran
Kaydı'nda Yakala'ya izin vermeniz gerekecek.

Hotkey: ⌘⇧C (daemon Carbon RegisterEventHotKey ile kaydeder; eğer başka
uygulama kullanıyorsa kayıt başarısız olur, log'da uyarı görünür).

Mimari:
  - Tray + hotkey + capture + clipboard + notification → Swift daemon
  - Editor + Region overlay + Settings → Flutter UI (Process spawn)
  - IPC: Unix socket ~/Library/Application Support/Yakala/daemon.sock

Kaldırmak için:
  launchctl unload "$LA_PLIST"
  rm -rf "$INSTALL_DIR" "$LA_PLIST" "$HOME/Library/Application Support/Yakala"
EOF
