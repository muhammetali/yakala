// Yakala Linux Daemon — entry point.
//
// Mimari (Faz 1 MVP — bu dosya scope):
//   GLib main loop → Tray (libayatana-appindicator) → IPC server (Unix socket)
//                  → UI spawner (fork+exec yakala-ui)
//                  → Settings loader (XDG ~/.config/yakala/settings.json)
//
// Henüz native değil:
//   - Hotkey: GNOME custom shortcut yakala-daemon'u CLI flag ile çağıracak
//     (mevcut "GNOME shortcut + IPC" stratejisi korunuyor — bu commit'te
//     daemon o IPC'yi sağlıyor, Flutter UI değil).
//   - Capture: faz 2'de native (xdg-portal Wayland + grim/scrot/import X11).
//
// Sinyaller:
//   - SIGINT/SIGTERM → graceful shutdown.
//   - SIGCHLD → UI subprocess reap (zombie önleme).

#include <cerrno>
#include <csignal>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <memory>
#include <string>
#include <sys/types.h>
#include <sys/wait.h>

#include <gtk/gtk.h>

#include "capture_orchestrator.hh"
#include "ipc_server.hh"
#include "logger.hh"
#include "settings_loader.hh"
#include "tray.hh"
#include "ui_spawner.hh"

namespace {

namespace fs = std::filesystem;
using namespace yakala::daemon;

GMainLoop* g_main_loop = nullptr;

void on_signal_quit(int sig) {
  YAKALA_LOG_INFO("main") << "sinyal alındı (" << sig << "), çıkılıyor";
  if (g_main_loop) {
    g_main_loop_quit(g_main_loop);
  }
}

// SIGCHLD handler — UI subprocess'leri reap eder. Aksi halde zombie
// process'ler birikiyor, ilk kullanıcı görmüyor ama uzun-yaşayan daemon'da
// bug.
void on_sigchld(int /*sig*/) {
  // signal handler içinde async-signal-safe API'ler dışında bir şey
  // çağrılmamalı. waitpid AS-safe.
  while (waitpid(-1, nullptr, WNOHANG) > 0) {
    // reaped — pid'i log'lamayı async-safe olmadığı için atlıyoruz.
  }
}

// Tray icon dosyasının yolu. install-launcher.sh tarafından
// ~/.local/share/yakala/icons/tray.png yoluna kopyalanır.
fs::path resolve_icon_path() {
  // 1) YAKALA_ICON env override.
  if (const char* env = std::getenv("YAKALA_ICON")) {
    if (*env) return fs::path(env);
  }
  // 2) Daemon binary ile aynı dizinde icons/tray.png.
  std::error_code ec;
  fs::path self = fs::read_symlink("/proc/self/exe", ec);
  if (!ec && !self.empty()) {
    fs::path candidate = self.parent_path() / "icons" / "tray.png";
    if (fs::exists(candidate, ec) && !ec) {
      return candidate;
    }
  }
  // 3) Hicolor theme — kullanıcı tarafına yüklenmiş olabilir.
  if (const char* home = std::getenv("HOME")) {
    fs::path candidate = fs::path(home) /
        ".local/share/icons/hicolor/256x256/apps/yakala.png";
    if (fs::exists(candidate, ec) && !ec) {
      return candidate;
    }
  }
  // 4) Generic fallback ismi — libayatana adı ile çözer.
  return fs::path("yakala");
}

}  // namespace

int main(int argc, char** argv) {
  // GTK init — argc/argv'yi düzeltebiliyor.
  gtk_init(&argc, &argv);

  Logger::init();
  YAKALA_LOG_INFO("main") << "yakala-daemon başlıyor (faz 1 MVP)";

  // Single-instance kontrolü: socket'e ping at, cevap geliyorsa başka
  // daemon çalışıyor → sessizce çık (autostart + manuel başlatma çift-tray
  // semptomu engellenir).
  if (IpcServer::another_instance_running()) {
    YAKALA_LOG_INFO("main") << "başka bir daemon zaten çalışıyor, çıkılıyor";
    return 0;
  }

  // Sinyal handler'ları.
  std::signal(SIGINT, on_signal_quit);
  std::signal(SIGTERM, on_signal_quit);
  // SIGCHLD — sigaction ile, SA_RESTART + SA_NOCLDSTOP.
  struct sigaction sa_chld{};
  sa_chld.sa_handler = on_sigchld;
  sigemptyset(&sa_chld.sa_mask);
  sa_chld.sa_flags = SA_RESTART | SA_NOCLDSTOP;
  sigaction(SIGCHLD, &sa_chld, nullptr);

  // SIGPIPE — IPC client client side close ettikten sonra write yaparsak
  // SIGPIPE alıyoruz; daemon'u öldürmemeli.
  std::signal(SIGPIPE, SIG_IGN);

  // Settings: bir kez yükle, capture trigger anında reload edilir.
  SettingsLoader settings_loader;
  settings_loader.load();
  YAKALA_LOG_INFO("main")
      << "settings yüklendi (mode="
      << settings_loader.current().default_capture_mode << ")";

  // UI spawner — yakala-ui binary path lazy resolve. Settings için kullanılır;
  // capture editor flow Faz 3'te eklenecek.
  UiSpawner ui_spawner;

  // Capture orchestrator — native capture + clipboard + notification akışını
  // sahiplenir. Tray click ve IPC capture command her ikisi de buna delege
  // eder.
  CaptureOrchestrator orchestrator(settings_loader);

  // Tray.
  Tray tray;
  const fs::path icon = resolve_icon_path();
  tray.init(icon.string(), "Yakala",
            [&ui_spawner, &orchestrator](TrayAction action) {
              switch (action) {
                case TrayAction::kCaptureFullScreen:
                  orchestrator.run(CaptureOrchestrator::Mode::kFullScreen);
                  break;
                case TrayAction::kCaptureRegion:
                  orchestrator.run(CaptureOrchestrator::Mode::kRegion);
                  break;
                case TrayAction::kCaptureWindow:
                  orchestrator.run(CaptureOrchestrator::Mode::kWindow);
                  break;
                case TrayAction::kOpenSettings:
                  ui_spawner.spawn({"--settings"});
                  break;
                case TrayAction::kQuit:
                  if (g_main_loop) g_main_loop_quit(g_main_loop);
                  break;
              }
            });

  // IPC server — GNOME custom shortcut ve UI binary'sinin daemon'a
  // mesaj göndermek için kullandığı kanal.
  IpcServer ipc;
  ipc.start([&ui_spawner, &orchestrator](std::string_view cmd,
                                         std::string_view body) {
    YAKALA_LOG_INFO("ipc") << "cmd=" << std::string(cmd);
    if (cmd == "ping") {
      return;
    }
    if (cmd == "show_settings") {
      ui_spawner.spawn({"--settings"});
      return;
    }
    if (cmd == "capture_full" || cmd == "capture-fullscreen") {
      orchestrator.run(CaptureOrchestrator::Mode::kFullScreen);
      return;
    }
    if (cmd == "capture_region" || cmd == "capture-region") {
      orchestrator.run(CaptureOrchestrator::Mode::kRegion);
      return;
    }
    if (cmd == "capture_window" || cmd == "capture-window") {
      orchestrator.run(CaptureOrchestrator::Mode::kWindow);
      return;
    }
    if (cmd == "ui_result") {
      // Faz 3'te: UI editor sonucu — daemon clipboard'a UI'nin döndüğü path'i
      // yansıtacak.
      YAKALA_LOG_DEBUG("ipc") << "ui_result body=" << std::string(body);
      return;
    }
    YAKALA_LOG_WARN("ipc") << "bilinmeyen cmd=" << std::string(cmd);
  });

  // Main loop.
  g_main_loop = g_main_loop_new(nullptr, FALSE);
  YAKALA_LOG_INFO("main") << "main loop başladı";
  g_main_loop_run(g_main_loop);

  // Graceful shutdown.
  YAKALA_LOG_INFO("main") << "main loop bitti, temizlik yapılıyor";
  ipc.stop();
  tray.shutdown();
  g_main_loop_unref(g_main_loop);
  g_main_loop = nullptr;
  return 0;
}
