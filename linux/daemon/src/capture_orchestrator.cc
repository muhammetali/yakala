#include "capture_orchestrator.hh"

#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <system_error>

#include <glib.h>

#include "capture.hh"
#include "clipboard.hh"
#include "logger.hh"
#include "notification.hh"

namespace yakala::daemon {

namespace fs = std::filesystem;

CaptureOrchestrator::CaptureOrchestrator(SettingsLoader& settings,
                                         UiSpawner& ui_spawner)
    : settings_(settings), ui_spawner_(ui_spawner) {}

fs::path CaptureOrchestrator::generate_temp_path(const std::string& prefix) {
  const auto now = std::chrono::system_clock::now().time_since_epoch();
  const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(now).count();
  const char* tmp = std::getenv("TMPDIR");
  fs::path base = (tmp && *tmp) ? fs::path(tmp) : fs::path("/tmp");
  return base / (prefix + "_" + std::to_string(ms) + ".png");
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
  // Re-entry guard — bir capture (özellikle editor session) açıkken yeni
  // tetikleme drop edilir. Tray callback'i veya IPC handler buraya birden
  // çok kez gelirse sadece ilki kabul edilir.
  if (busy_) {
    YAKALA_LOG_INFO("orch") << "busy — yeni capture reddedildi";
    return false;
  }

  settings_.load_if_changed();
  const auto& s = settings_.current();
  YAKALA_LOG_INFO("orch") << "capture başlıyor (mode=" << static_cast<int>(mode)
                          << ", default=" << s.default_capture_mode << ")";

  busy_ = true;
  const fs::path captured = generate_temp_path("yakala");
  bool ok = false;

  // 1) Senkron native capture.
  switch (mode) {
    case Mode::kFullScreen:
      ok = Capture::capture_full_screen(captured);
      break;
    case Mode::kWindow:
      ok = Capture::capture_active_window(captured);
      break;
    case Mode::kRegion:
      // Region mode: önce full-screen yakala (frozen background için).
      // Sonra UI overlay spawn et — kullanıcı bölge seçer + crop yapar.
      ok = Capture::capture_full_screen(captured);
      break;
  }

  if (!ok) {
    if (s.notifications_enabled) {
      Notification::show("Yakala", Capture::capture_fail_hint());
    }
    busy_ = false;
    return false;
  }

  // 2) UI flow gerekli mi?
  const bool needs_region_ui = (mode == Mode::kRegion);
  // fullScreen/window için editor opsiyonel (ayar).
  const bool needs_editor_ui =
      (mode != Mode::kRegion) && s.show_editor_after_capture;

  if (needs_region_ui) {
    const fs::path output = generate_temp_path("yakala_region");
    spawn_region(captured, output);
    return true;  // async — busy_ child callback'te temizlenir.
  }
  if (needs_editor_ui) {
    const fs::path output = generate_temp_path("yakala_edit");
    spawn_editor(captured, output);
    return true;  // async
  }

  // 3) Direkt finalize (UI yok).
  finalize(captured);
  busy_ = false;
  return true;
}

void CaptureOrchestrator::spawn_editor(const fs::path& input,
                                       const fs::path& output) {
  pending_input_ = input;
  pending_output_ = output;

  GSubprocess* proc = ui_spawner_.spawn({
      "--mode=editor",
      "--input=" + input.string(),
      "--output=" + output.string(),
  });
  if (!proc) {
    YAKALA_LOG_WARN("orch") << "editor spawn başarısız, finalize input";
    finalize(input);
    busy_ = false;
    return;
  }
  // g_subprocess_wait_async — UI exit'i async izle, callback ana loop'tan
  // çağrılır. Child reap'i de glib yapar; SIGCHLD kendisi yönetir.
  g_subprocess_wait_async(proc, nullptr,
                          &CaptureOrchestrator::on_ui_exit_static, this);
  YAKALA_LOG_INFO("orch") << "editor spawned, waiting...";
}

void CaptureOrchestrator::spawn_region(const fs::path& input,
                                       const fs::path& output) {
  pending_input_ = input;
  pending_output_ = output;

  GSubprocess* proc = ui_spawner_.spawn({
      "--mode=region",
      "--input=" + input.string(),
      "--output=" + output.string(),
  });
  if (!proc) {
    YAKALA_LOG_WARN("orch") << "region spawn başarısız, finalize input";
    finalize(input);
    busy_ = false;
    return;
  }
  g_subprocess_wait_async(proc, nullptr,
                          &CaptureOrchestrator::on_ui_exit_static, this);
  YAKALA_LOG_INFO("orch") << "region spawned, waiting...";
}

void CaptureOrchestrator::on_ui_exit_static(GObject* source,
                                            GAsyncResult* res,
                                            gpointer user_data) {
  auto* self = static_cast<CaptureOrchestrator*>(user_data);
  GSubprocess* proc = G_SUBPROCESS(source);
  GError* err = nullptr;
  const gboolean ok = g_subprocess_wait_finish(proc, res, &err);
  const int exit_status = g_subprocess_get_exit_status(proc);
  if (!ok || err) {
    if (err) {
      YAKALA_LOG_WARN("orch") << "wait_finish err: " << err->message;
      g_error_free(err);
    }
  }
  YAKALA_LOG_INFO("orch") << "UI exit (status=" << exit_status << ")";
  if (self) self->on_ui_exit();
  g_object_unref(proc);
}

void CaptureOrchestrator::on_ui_exit() {
  finalize_after_ui();
}

void CaptureOrchestrator::finalize_after_ui() {
  std::error_code ec;
  fs::path final_image;
  if (!pending_output_.empty() && fs::exists(pending_output_, ec) && !ec) {
    // UI başarıyla output yazdı (Bitti veya region confirm).
    final_image = pending_output_;
    YAKALA_LOG_INFO("orch") << "UI output kullanılıyor: "
                            << final_image.string();
  } else {
    // UI cancel — output yok. Orijinal capture'ı kullanmıyoruz; iptal
    // ettikse kullanıcı "save edilmesin" istemiş demektir. Ama region
    // mode'da iptal etmek "no capture" anlamına gelmesi yanlış olur —
    // user en azından "Bitti" bekler. Şimdiki UX: cancel = vazgeçildi,
    // hiçbir şey kaydetme.
    YAKALA_LOG_INFO("orch") << "UI cancel — capture vazgeçildi";
    // Temp dosyayı temizle.
    if (!pending_input_.empty()) fs::remove(pending_input_, ec);
    pending_input_.clear();
    pending_output_.clear();
    busy_ = false;
    return;
  }

  finalize(final_image);

  // Orijinal capture temp'i temizle (UI output'u kullanıyoruz).
  if (!pending_input_.empty() && pending_input_ != final_image) {
    fs::remove(pending_input_, ec);
  }
  pending_input_.clear();
  pending_output_.clear();
  busy_ = false;
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

  return clipboard_ok || saved_to.has_value();
}

}  // namespace yakala::daemon
