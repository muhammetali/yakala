#pragma once

#include <functional>
#include <memory>
#include <string>
#include <vector>

// gtk.h header'a — forward-decl yetersiz (gpointer, GtkWidget* nested type
// dependencies). Pollute olan ama yaygın bir header.
#include <gtk/gtk.h>

// libayatana-appindicator forward decl yeterli — sadece pointer kullanıyoruz.
extern "C" {
typedef struct _AppIndicator AppIndicator;
}

namespace yakala::daemon {

// Tray menü item kimlikleri. Daemon'un click handler'ı bu enum üzerinden
// branch eder; menü item'ın display label'ı dahili.
enum class TrayAction {
  kCaptureFullScreen,
  kCaptureRegion,
  kCaptureWindow,
  kOpenSettings,
  kQuit,
};

// libayatana-appindicator tabanlı tray. system_tray/tray_manager paketleriyle
// karşılaştırıldığında:
//   - Native C++ — Flutter engine paused state'inden bağımsız.
//   - Click event'leri GTK main loop üzerinden direkt geliyor — DBus stale
//     menu invariant'ı yok (bu invariant Flutter+plugin köprüsünden
//     kaynaklanıyordu, native libappindicator'da değil).
//
// Lifecycle: `init()` bir kez çağrılır (main.cc); GTK main loop çalışırken
// click event'leri handler'a iletilir.
class Tray {
public:
  using ClickHandler = std::function<void(TrayAction)>;

  Tray();
  ~Tray();

  Tray(const Tray&) = delete;
  Tray& operator=(const Tray&) = delete;

  // Init: AppIndicator + menü oluştur, set_status(ACTIVE). Glib main loop
  // başladığında tray görünür olur.
  // `icon_path`: PNG dosya yolu — install zamanı bilinir.
  // `tooltip`: tray hover'da görünen metin (libayatana destekliyorsa).
  void init(const std::string& icon_path,
            const std::string& tooltip,
            ClickHandler handler);

  // Tooltip'i güncelle (settings'te hotkey değiştiğinde çağrılır).
  void set_tooltip(const std::string& tooltip);

  // Graceful shutdown — AppIndicator referanslarını bırakır.
  void shutdown();

private:
  // GTK menu item callback wrapper — userdata olarak `this` ve action enum
  // taşıyan struct geçer.
  struct MenuItemContext {
    Tray* self;
    TrayAction action;
  };

  static void on_menu_clicked(GtkWidget* /*widget*/, gpointer user_data);
  GtkWidget* build_menu_item(const std::string& label,
                             TrayAction action);

  AppIndicator* indicator_{nullptr};
  GtkMenu* menu_{nullptr};
  std::vector<std::unique_ptr<MenuItemContext>> contexts_{};
  ClickHandler handler_{};
};

}  // namespace yakala::daemon
