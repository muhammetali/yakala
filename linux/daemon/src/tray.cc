#include "tray.hh"

#include <stdexcept>

#include <gtk/gtk.h>
#include <libayatana-appindicator/app-indicator.h>

#include "logger.hh"

namespace yakala::daemon {

Tray::Tray() = default;

Tray::~Tray() {
  shutdown();
}

void Tray::init(const std::string& icon_path,
                const std::string& tooltip,
                ClickHandler handler) {
  if (indicator_) {
    YAKALA_LOG_WARN("tray") << "zaten init edilmiş";
    return;
  }
  handler_ = std::move(handler);

  // GTK_INIT main.cc'de yapıldı varsayılır.
  indicator_ = app_indicator_new(
      "yakala-tray",                              // ID
      icon_path.c_str(),                          // icon path (absolute)
      APP_INDICATOR_CATEGORY_APPLICATION_STATUS); // kategori — system tray
  if (!indicator_) {
    throw std::runtime_error("app_indicator_new başarısız");
  }
  app_indicator_set_status(indicator_, APP_INDICATOR_STATUS_ACTIVE);
  app_indicator_set_title(indicator_, "Yakala");
  // Title (libayatana-appindicator 0.5.x'ten itibaren tooltip benzeri davranır
  // bazı oturum yöneticilerinde — ör. KDE statusnotifier).

  // Menü oluştur. GtkMenu* — append ile item ekle, show_all ile expose et.
  menu_ = GTK_MENU(gtk_menu_new());

  GtkWidget* item;
  item = build_menu_item("Tam Ekran Yakala", TrayAction::kCaptureFullScreen);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu_), item);
  item = build_menu_item("Bölge Yakala", TrayAction::kCaptureRegion);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu_), item);
  item = build_menu_item("Pencere Yakala", TrayAction::kCaptureWindow);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu_), item);

  GtkWidget* sep1 = gtk_separator_menu_item_new();
  gtk_menu_shell_append(GTK_MENU_SHELL(menu_), sep1);

  item = build_menu_item("Ayarlar", TrayAction::kOpenSettings);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu_), item);

  GtkWidget* sep2 = gtk_separator_menu_item_new();
  gtk_menu_shell_append(GTK_MENU_SHELL(menu_), sep2);

  item = build_menu_item("Çıkış", TrayAction::kQuit);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu_), item);

  gtk_widget_show_all(GTK_WIDGET(menu_));
  app_indicator_set_menu(indicator_, menu_);

  YAKALA_LOG_INFO("tray") << "init tamam (icon=" << icon_path << ")";
  // Note: tooltip libayatana-appindicator API'sinde direkt yok; title
  // setiyle indirekt şekilde gösterilebiliyor (DE'ye göre değişir).
  (void)tooltip;
}

void Tray::set_tooltip(const std::string& tooltip) {
  // libayatana-appindicator0.5.x'te public API setter yok — title üzerinden
  // best-effort. Sessiz no-op yapmak da kabul.
  (void)tooltip;
}

void Tray::shutdown() {
  if (indicator_) {
    app_indicator_set_status(indicator_, APP_INDICATOR_STATUS_PASSIVE);
    g_object_unref(indicator_);
    indicator_ = nullptr;
  }
  contexts_.clear();
  handler_ = {};
}

GtkWidget* Tray::build_menu_item(const std::string& label,
                                 TrayAction action) {
  GtkWidget* item = gtk_menu_item_new_with_label(label.c_str());
  // userdata için heap-alloc context — Tray ömrü item ömrünü kapsar.
  auto ctx = std::make_unique<MenuItemContext>();
  ctx->self = this;
  ctx->action = action;
  g_signal_connect(item, "activate",
                   G_CALLBACK(&Tray::on_menu_clicked), ctx.get());
  contexts_.push_back(std::move(ctx));
  return item;
}

void Tray::on_menu_clicked(GtkWidget* /*widget*/, gpointer user_data) {
  auto* ctx = static_cast<MenuItemContext*>(user_data);
  if (!ctx || !ctx->self) return;
  YAKALA_LOG_INFO("tray") << "menu click action="
                          << static_cast<int>(ctx->action);
  if (ctx->self->handler_) {
    ctx->self->handler_(ctx->action);
  }
}

}  // namespace yakala::daemon
