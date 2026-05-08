#!/usr/bin/env bash
# Yakala — Linux launcher kurulumu (kullanıcı bazında).
#
# - Sistem bağımlılıklarını tespit edip eksikleri kurar (apt/dnf/pacman/zypper).
# - Build edilmiş bundle'ı (binary + .so + data/) ~/.local/share/yakala
#   altına kopyalar (stabil kurulum dizini — `flutter clean` artık launcher'ı
#   kırmaz).
# - .desktop dosyasını ~/.local/share/applications altına yazar; Exec stabil
#   yola işaret eder.
# - İkonu hicolor temasına yükler (32x32 + 256x256).
# - Desktop & icon cache'i yeniler (varsa).
#
# Kullanım:
#   flutter build linux --release
#   bash linux/install-launcher.sh            # interaktif
#   bash linux/install-launcher.sh -y         # otomatik (CI/script için)
#   bash linux/install-launcher.sh --skip-deps # bağımlılık kurulumunu atla
set -euo pipefail

ASSUME_YES=0
SKIP_DEPS=0
for arg in "$@"; do
  case "$arg" in
    -y|--yes) ASSUME_YES=1 ;;
    --skip-deps) SKIP_DEPS=1 ;;
    -h|--help)
      sed -n '2,18p' "$0"
      exit 0
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Bağımlılık kurulumu --------------------------------------------------
# Yakala şu sistem araçlarına bağımlı:
#   - region capture: grim (Wayland) veya imagemagick/import (X11)
#   - clipboard:      wl-clipboard (Wayland) veya xclip (X11)
#   - bildirim:       libnotify (notify-send) — KDE'de varsayılan değil
#   - ses:            pulseaudio-utils (paplay) veya libcanberra
# Distro'yu /etc/os-release ile tespit eder, paket adlarını eşleyip eksikleri
# kurarız. Bilinmeyen distro: kullanıcıya elle kurması için liste veririz.

detect_session_type() {
  if [[ -n "${WAYLAND_DISPLAY:-}" ]] || [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
    echo "wayland"
  else
    echo "x11"
  fi
}

detect_distro() {
  if [[ ! -r /etc/os-release ]]; then
    echo "unknown"
    return
  fi
  # ID ve ID_LIKE ikisi de denenir; ör. Linux Mint ID=linuxmint, ID_LIKE=ubuntu.
  local id id_like
  id=$(. /etc/os-release && echo "${ID:-}")
  id_like=$(. /etc/os-release && echo "${ID_LIKE:-}")
  for candidate in "$id" $id_like; do
    case "$candidate" in
      debian|ubuntu|linuxmint|pop|elementary|raspbian) echo "debian"; return ;;
      fedora|rhel|centos|rocky|almalinux)              echo "fedora"; return ;;
      arch|manjaro|endeavouros|garuda)                 echo "arch";   return ;;
      opensuse*|suse|sled|sles)                        echo "suse";   return ;;
      alpine)                                          echo "alpine"; return ;;
    esac
  done
  echo "unknown"
}

# Eksik komutları (whitespace ayrılmış) listele.
missing_commands() {
  local session=$1
  local missing=()
  if [[ "$session" == "wayland" ]]; then
    command -v grim    >/dev/null 2>&1 || missing+=("grim")
    command -v wl-copy >/dev/null 2>&1 || missing+=("wl-copy")
  else
    # X11: silent_capture'da import → scrot → maim sırası var; en az birinin
    # olması yeter ama varsayılan olarak imagemagick (import) öneriyoruz.
    if ! command -v import >/dev/null 2>&1 \
       && ! command -v scrot >/dev/null 2>&1 \
       && ! command -v maim  >/dev/null 2>&1; then
      missing+=("import")
    fi
    command -v xclip >/dev/null 2>&1 || missing+=("xclip")
  fi
  command -v notify-send >/dev/null 2>&1 || missing+=("notify-send")
  command -v paplay      >/dev/null 2>&1 \
    || command -v canberra-gtk-play >/dev/null 2>&1 \
    || missing+=("paplay")
  echo "${missing[@]}"
}

# Distro + komut adı → paket adı eşlemesi.
package_for() {
  local distro=$1 cmd=$2
  case "$distro:$cmd" in
    debian:grim)         echo "grim" ;;
    debian:wl-copy)      echo "wl-clipboard" ;;
    debian:import)       echo "imagemagick" ;;
    debian:xclip)        echo "xclip" ;;
    debian:notify-send)  echo "libnotify-bin" ;;
    debian:paplay)       echo "pulseaudio-utils" ;;

    fedora:grim)         echo "grim" ;;
    fedora:wl-copy)      echo "wl-clipboard" ;;
    fedora:import)       echo "ImageMagick" ;;
    fedora:xclip)        echo "xclip" ;;
    fedora:notify-send)  echo "libnotify" ;;
    fedora:paplay)       echo "pulseaudio-utils" ;;

    arch:grim)           echo "grim" ;;
    arch:wl-copy)        echo "wl-clipboard" ;;
    arch:import)         echo "imagemagick" ;;
    arch:xclip)          echo "xclip" ;;
    arch:notify-send)    echo "libnotify" ;;
    arch:paplay)         echo "libpulse" ;;

    suse:grim)           echo "grim" ;;
    suse:wl-copy)        echo "wl-clipboard" ;;
    suse:import)         echo "ImageMagick" ;;
    suse:xclip)          echo "xclip" ;;
    suse:notify-send)    echo "libnotify-tools" ;;
    suse:paplay)         echo "pulseaudio-utils" ;;

    alpine:grim)         echo "grim" ;;
    alpine:wl-copy)      echo "wl-clipboard" ;;
    alpine:import)       echo "imagemagick" ;;
    alpine:xclip)        echo "xclip" ;;
    alpine:notify-send)  echo "libnotify" ;;
    alpine:paplay)       echo "pulseaudio-utils" ;;

    *) echo "" ;;
  esac
}

install_packages() {
  local distro=$1
  shift
  local pkgs=("$@")
  local sudo_cmd=""
  if [[ $EUID -ne 0 ]]; then
    if ! command -v sudo >/dev/null 2>&1; then
      echo "Hata: paket kurulumu root yetkisi ister, sudo bulunamadı." >&2
      return 1
    fi
    sudo_cmd="sudo"
  fi
  case "$distro" in
    debian) $sudo_cmd apt-get update -qq && $sudo_cmd apt-get install -y "${pkgs[@]}" ;;
    fedora) $sudo_cmd dnf install -y "${pkgs[@]}" ;;
    arch)   $sudo_cmd pacman -S --needed --noconfirm "${pkgs[@]}" ;;
    suse)   $sudo_cmd zypper --non-interactive install "${pkgs[@]}" ;;
    alpine) $sudo_cmd apk add --no-cache "${pkgs[@]}" ;;
    *)      return 1 ;;
  esac
}

ensure_dependencies() {
  if [[ $SKIP_DEPS -eq 1 ]]; then
    echo "Bağımlılık kurulumu atlandı (--skip-deps)."
    return 0
  fi
  local session distro missing pkgs=() unmapped=()
  session=$(detect_session_type)
  distro=$(detect_distro)
  read -r -a missing <<<"$(missing_commands "$session")"

  if [[ ${#missing[@]} -eq 0 ]]; then
    echo "Sistem bağımlılıkları tamam ($session)."
    return 0
  fi

  echo
  echo "Yakala şu araçları gerektiriyor ama sistemde yok: ${missing[*]}"

  if [[ "$distro" == "unknown" ]]; then
    echo "Distro otomatik tespit edilemedi (/etc/os-release okunamıyor)."
    echo "Lütfen aşağıdaki araçları kendi paket yöneticinizle kurun: ${missing[*]}"
    return 0
  fi

  for cmd in "${missing[@]}"; do
    local pkg
    pkg=$(package_for "$distro" "$cmd")
    if [[ -z "$pkg" ]]; then
      unmapped+=("$cmd")
    else
      pkgs+=("$pkg")
    fi
  done

  if [[ ${#pkgs[@]} -eq 0 ]]; then
    echo "Eşleme tablosunda paket bulunamadı: ${unmapped[*]}"
    echo "Lütfen elle kurun ve scripti tekrar çalıştırın."
    return 0
  fi

  echo "Distro: $distro — kurulacak paketler: ${pkgs[*]}"
  if [[ $ASSUME_YES -ne 1 ]]; then
    read -r -p "Devam edilsin mi? [E/h] " reply
    case "${reply,,}" in
      ""|e|evet|y|yes) ;;
      *) echo "İptal edildi. Yakala bağımlılık olmadan kurulmaya devam edecek."; return 0 ;;
    esac
  fi

  if ! install_packages "$distro" "${pkgs[@]}"; then
    echo "Paket kurulumu başarısız. Yakala devam ediyor; ilgili özellikler"
    echo "(panoya kopyalama / bildirim / region capture) çalışmayabilir."
    return 0
  fi

  if [[ ${#unmapped[@]} -gt 0 ]]; then
    echo "Şunlar için paket eşlemesi yok, elle kurmanız gerekebilir: ${unmapped[*]}"
  fi
  echo "Bağımlılıklar kuruldu."
}

ensure_dependencies

# --- Bundle kurulumu ------------------------------------------------------

# Hangi build varyantı varsa onun bundle'ını al — release tercih edilir.
BUNDLE_SRC=""
for candidate in \
  "$REPO_ROOT/build/linux/x64/release/bundle" \
  "$REPO_ROOT/build/linux/x64/profile/bundle" \
  "$REPO_ROOT/build/linux/x64/debug/bundle"; do
  if [[ -x "$candidate/yakala" ]]; then
    BUNDLE_SRC="$candidate"
    break
  fi
done

if [[ -z "$BUNDLE_SRC" ]]; then
  echo "Hata: yakala bundle'ı bulunamadı." >&2
  echo "Önce derleyin: flutter build linux --release" >&2
  exit 1
fi

ICON_SRC_LARGE="$SCRIPT_DIR/yakala.png"
ICON_SRC_TRAY="$REPO_ROOT/assets/app_icon.png"

if [[ ! -f "$ICON_SRC_TRAY" ]]; then
  echo "Hata: tray ikonu bulunamadı: $ICON_SRC_TRAY" >&2
  exit 1
fi

INSTALL_DIR="$HOME/.local/share/yakala"
APPS_DIR="$HOME/.local/share/applications"
HICOLOR="$HOME/.local/share/icons/hicolor"
mkdir -p "$APPS_DIR" "$HICOLOR/32x32/apps" "$HICOLOR/256x256/apps"

# Bundle'ı stabil dizine kopyala. Eski kurulumu temizle ki yetim dosya
# (silinmiş .so vb.) kalmasın. Atomic değil — ama bu kullanıcı bazlı
# best-effort kurulum.
if [[ -d "$INSTALL_DIR" ]]; then
  rm -rf "$INSTALL_DIR"
fi
mkdir -p "$INSTALL_DIR"
# `cp -a` mod/zaman bilgilerini korur; `bundle/.` içindekileri kopyalar
# (parent dizini değil).
cp -a "$BUNDLE_SRC/." "$INSTALL_DIR/"

INSTALLED_BINARY="$INSTALL_DIR/yakala"
chmod 0755 "$INSTALLED_BINARY"

# İkonlar.
install -m 0644 "$ICON_SRC_TRAY" "$HICOLOR/32x32/apps/yakala.png"
if [[ -f "$ICON_SRC_LARGE" ]]; then
  install -m 0644 "$ICON_SRC_LARGE" "$HICOLOR/256x256/apps/yakala.png"
fi

# .desktop — Exec stabil install yoluna işaret eder, build dizinine değil.
DESKTOP_FILE="$APPS_DIR/yakala.desktop"
sed "s|__EXEC__|$INSTALLED_BINARY|g" \
  "$SCRIPT_DIR/yakala.desktop.template" > "$DESKTOP_FILE"
chmod 0644 "$DESKTOP_FILE"

# Cache yenileme — best-effort.
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -t "$HICOLOR" >/dev/null 2>&1 || true
fi

# --- GNOME native custom shortcut --------------------------------------------
# Linux'ta hotkey_manager paketi keybinder-3.0 üzerinden çalışır; GNOME 46 X11
# oturumunda `keybinder_bind` sessizce başarısız olabiliyor (paketin native
# kodu dönüş değerini kontrol etmiyor → kullanıcıya UYARI gitmiyor, hotkey
# hiç tetiklenmiyor). Aynı zamanda ubuntu-appindicators extension'ı tray
# callback dispatch'ini menu activation sonrası ölü tutuyor.
#
# Çözüm: GNOME'un kendi custom-keybindings altyapısı bu zincirin dışında.
# `gsettings` ile Super+Shift+C → `yakala --capture-fullscreen` tanımlıyoruz;
# tuşa bastığında gnome-shell yakala'yı çağırıyor, IPC ile çalışan instance
# capture başlatıyor.
register_gnome_shortcut() {
  if ! command -v gsettings >/dev/null 2>&1; then
    echo "gsettings bulunamadı — sistem kısayolu kaydı atlandı (GNOME değil)."
    return 0
  fi
  # GNOME / Cinnamon / Budgie hepsi gsettings ile aynı şemayı paylaşır.
  # XDG_CURRENT_DESKTOP = "ubuntu:GNOME", "GNOME", "X-Cinnamon", "Budgie:GNOME"...
  local desk="${XDG_CURRENT_DESKTOP:-}"
  if [[ "${desk^^}" != *"GNOME"* ]] \
     && [[ "${desk^^}" != *"CINNAMON"* ]] \
     && [[ "${desk^^}" != *"BUDGIE"* ]] \
     && [[ "${desk^^}" != *"UNITY"* ]]; then
    echo "Masaüstü ortamı GNOME tabanlı değil ($desk) — sistem kısayolu kaydı atlandı."
    echo "Klavye kısayolunu masaüstü ortamınızdan elle tanımlayın:"
    echo "  Komut : $INSTALLED_BINARY --capture-fullscreen"
    echo "  Önerilen tuş: Super+Shift+C"
    return 0
  fi

  local kb_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/yakala-capture/"
  local kb_schema="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$kb_path"
  local list_schema="org.gnome.settings-daemon.plugins.media-keys"

  # Mevcut listeyi al — boş ise '[]' veya '@as []' döner.
  local existing
  existing=$(gsettings get "$list_schema" custom-keybindings 2>/dev/null || echo "[]")

  # Kendi path'imiz listede yoksa ekle.
  if [[ "$existing" != *"$kb_path"* ]]; then
    if [[ "$existing" == "[]" ]] || [[ "$existing" == "@as []" ]]; then
      gsettings set "$list_schema" custom-keybindings "['$kb_path']" || true
    else
      # 'sondaki ]' yerine ', '$kb_path']' — basit string sürçme yeterli.
      local new="${existing%]}, '$kb_path']"
      gsettings set "$list_schema" custom-keybindings "$new" || true
    fi
  fi

  # Shortcut özellikleri.
  gsettings set "$kb_schema" name 'Yakala — Tam Ekran' || true
  gsettings set "$kb_schema" command "$INSTALLED_BINARY --capture-fullscreen" || true
  gsettings set "$kb_schema" binding '<Super><Shift>c' || true

  echo "GNOME kısayolu kaydedildi: Super+Shift+C → yakala --capture-fullscreen"
}

register_gnome_shortcut

cat <<EOF
Yakala kuruldu.

  Bundle   : $INSTALL_DIR
  Launcher : $DESKTOP_FILE
  İkon 32  : $HICOLOR/32x32/apps/yakala.png
  İkon 256 : $HICOLOR/256x256/apps/yakala.png
  Exec     : $INSTALLED_BINARY --settings
  Kısayol  : Super+Shift+C (GNOME custom shortcut → tam ekran yakalama)

Programlar menüsünde "Yakala" adıyla görünmesi 1-2 saniye sürebilir.
Artık 'flutter clean' launcher'ı kırmaz; tekrar kurmak için bu betiği
yeniden çalıştırın.

Kaldırmak için:
  rm -rf "$INSTALL_DIR"
  rm "$DESKTOP_FILE"
  rm -f "$HICOLOR/32x32/apps/yakala.png" "$HICOLOR/256x256/apps/yakala.png"
  # GNOME kısayolu da silmek isterseniz:
  # gsettings reset org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/yakala-capture/ name
EOF
