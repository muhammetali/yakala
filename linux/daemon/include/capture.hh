#pragma once

#include <filesystem>

namespace yakala::daemon {

// Native screen capture. Hiçbir UI / flash / sound üretmez (silent).
//
// Linux strategy:
//   1. Wayland tespit edilirse `grim` (Wayland-native, FreeDesktop standardı)
//   2. X11'de `import` (ImageMagick), `scrot`, `maim` sırasıyla
//   3. Hiçbiri yoksa false (kullanıcıya install rehberliği daemon log'unda)
//
// Tüm shell-out'lar ProcessRunner üzerinden — 8s timeout + AS-safe.
class Capture {
public:
  // Tam ekran yakalama. `out_path` mutlaka yazılabilir bir konuma işaret
  // etmeli (`/tmp/yakala_<ts>.png` standart). Başarılı ise `true`, dosya
  // mevcut + boyut > 0.
  static bool capture_full_screen(const std::filesystem::path& out_path);

  // Aktif/seçilen pencereyi yakalama. X11'de `import -window`, Wayland'da
  // `grim` ile compositor sıkıntısı (window-only Wayland'da portal gerekir,
  // şimdi destek yok — false döner).
  static bool capture_active_window(const std::filesystem::path& out_path);

  // Çalışan oturum tipi (display server detection helper).
  enum class DisplayServer { kWayland, kX11, kUnknown };
  static DisplayServer detect_display_server();

  // Eksik tool'lar için kullanıcı dostu hata mesajı (notification body için).
  static std::string capture_fail_hint();
};

}  // namespace yakala::daemon
