#include "capture_orchestrator.hh"

#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <system_error>

#include "capture.hh"
#include "clipboard.hh"
#include "logger.hh"
#include "notification.hh"

namespace yakala::daemon {

namespace fs = std::filesystem;

CaptureOrchestrator::CaptureOrchestrator(SettingsLoader& settings)
    : settings_(settings) {}

fs::path CaptureOrchestrator::generate_temp_path() {
  const auto now = std::chrono::system_clock::now().time_since_epoch();
  const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(now).count();
  // Temp dir resolution: TMPDIR env üstün, sonra /tmp.
  const char* tmp = std::getenv("TMPDIR");
  fs::path base = (tmp && *tmp) ? fs::path(tmp) : fs::path("/tmp");
  return base / ("yakala_" + std::to_string(ms) + ".png");
}

fs::path CaptureOrchestrator::expand_home(const std::string& path) {
  if (path.empty() || path[0] != '~') return fs::path(path);
  const char* home = std::getenv("HOME");
  if (!home || !*home) return fs::path(path);
  if (path == "~") return fs::path(home);
  if (path.size() > 1 && path[1] == '/') {
    return fs::path(home) / path.substr(2);
  }
  return fs::path(home) / path.substr(1);
}

bool CaptureOrchestrator::run(Mode mode) {
  // Settings'i her capture'da reload — kullanıcı UI'dan değişiklik yaptıysa
  // hemen yansır.
  settings_.load_if_changed();
  const auto& s = settings_.current();

  YAKALA_LOG_INFO("orch") << "capture başlıyor (mode=" << static_cast<int>(mode)
                         << ", default=" << s.default_capture_mode << ")";

  const fs::path out = generate_temp_path();
  bool ok = false;
  switch (mode) {
    case Mode::kFullScreen:
      ok = Capture::capture_full_screen(out);
      break;
    case Mode::kWindow:
      ok = Capture::capture_active_window(out);
      break;
    case Mode::kRegion:
      // Faz 2: region henüz UI overlay'e bağlı, daemon-only modda full-screen
      // fallback yapıyoruz. Faz 3'te UI overlay → daemon kırpma akışı kurulur.
      YAKALA_LOG_WARN("orch") << "Region modu Faz 3'e kadar full-screen fallback";
      ok = Capture::capture_full_screen(out);
      break;
  }

  if (!ok) {
    if (s.notifications_enabled) {
      Notification::show("Yakala", Capture::capture_fail_hint());
    }
    return false;
  }

  return finalize(out);
}

bool CaptureOrchestrator::finalize(const fs::path& image_path) {
  const auto& s = settings_.current();

  // 1) Clipboard
  const bool clipboard_ok = Clipboard::copy_png_image(image_path);

  // 2) Optional disk save
  std::optional<fs::path> saved_to;
  if (!s.save_path.empty()) {
    const fs::path dir = expand_home(s.save_path);
    std::error_code ec;
    fs::create_directories(dir, ec);
    if (ec) {
      YAKALA_LOG_WARN("orch") << "save dir oluşturulamadı: "
                              << dir.string() << " (" << ec.message() << ")";
    } else {
      const fs::path dest = dir / image_path.filename();
      fs::copy_file(image_path, dest,
                    fs::copy_options::overwrite_existing, ec);
      if (!ec) {
        saved_to = dest;
        YAKALA_LOG_INFO("orch") << "disk'e kaydedildi: " << dest.string();
      } else {
        YAKALA_LOG_WARN("orch") << "disk kaydı başarısız: " << ec.message();
      }
    }
  }

  // 3) Notification
  if (s.notifications_enabled) {
    std::string body;
    if (!clipboard_ok && !saved_to) {
      body = "Yakalandı ama kaydedilemedi.";
    } else if (clipboard_ok && saved_to) {
      body = "Panoya kopyalandı ve diske kaydedildi.";
    } else if (clipboard_ok) {
      body = "Görüntü panoya kopyalandı.";
    } else {
      body = "Diske kaydedildi: " + saved_to->filename().string();
    }
    Notification::show_with_image("Yakala", body, image_path.string());
  }

  // 4) Sound — şimdilik atlandı (Faz 2.5: paplay / canberra-gtk-play).
  //    Düşük öncelik; kullanıcı için bildirim yeterli.

  return clipboard_ok || saved_to.has_value();
}

}  // namespace yakala::daemon
