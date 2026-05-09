#pragma once

#include <chrono>
#include <filesystem>
#include <optional>
#include <string>

namespace yakala::daemon {

// Daemon'un capture'a karar verirken ihtiyacı olan settings.
//
// Settings dosyası daemon ile UI arasında paylaşılır:
//   ~/.config/yakala/settings.json (XDG)
//
// UI yazar (Settings sayfasından), daemon her capture'dan önce yeniden
// okur (poll değil — `mtime` kontrol ile lazy reload). Atomic write
// pattern (write to .tmp + rename) UI tarafında zorunlu.
struct Settings {
  // Yakalama varsayılan modu (hotkey tetiklendiğinde).
  // Değerler: "fullScreen", "region", "window".
  std::string default_capture_mode{"fullScreen"};

  // Yakalama sonrası editor açılsın mı.
  bool show_editor_after_capture{true};

  // Yakalama sonrası ses çalınsın mı.
  bool sound_effect{true};

  // Native bildirim gösterilsin mi.
  bool notifications_enabled{true};

  // Diske kayıt yolu — boş ise sadece clipboard.
  std::string save_path{};

  // Hotkey gsettings tarafında yönetildiği için daemon burada saklamıyor.
  // (Linux native shortcut altyapısı bu config'i sahipleniyor.)
};

class SettingsLoader {
public:
  SettingsLoader();

  // ~/.config/yakala/settings.json (XDG_CONFIG_HOME üstün gelir).
  static std::filesystem::path resolve_path();

  // Diskten oku. Dosya yoksa default Settings dönülür (hata değil).
  // JSON parse hatası → log + default Settings.
  Settings load();

  // mtime değişmişse reload eder, değişmemişse cached değer döner.
  // Hot-path'te (capture trigger anında) kullanılır.
  const Settings& load_if_changed();

  const Settings& current() const { return cached_; }

private:
  std::filesystem::path path_;
  Settings cached_{};
  std::optional<std::filesystem::file_time_type> last_mtime_;
};

}  // namespace yakala::daemon
