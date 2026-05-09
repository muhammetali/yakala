#include "capture.hh"

#include <cstdlib>
#include <system_error>

#include "logger.hh"
#include "process_runner.hh"

namespace yakala::daemon {

namespace fs = std::filesystem;

namespace {

bool file_nonempty(const fs::path& p) {
  std::error_code ec;
  if (!fs::exists(p, ec) || ec) return false;
  const auto size = fs::file_size(p, ec);
  return !ec && size > 0;
}

// Komutu çalıştır, başarı kriteri: dosya nonempty (exit code'a bakmıyoruz).
// Empirik gerekçe: ImageMagick `import -silent` warning durumlarında exit=1
// dönüyor ama dosyayı doğru yazıyor. Asıl kriter: dosya var ve > 0 byte.
// Timeout durumunda dosya da yazılmıyor → false.
bool try_capture(const std::vector<std::string>& argv, const fs::path& out) {
  if (argv.empty()) return false;
  if (!ProcessRunner::command_exists(argv[0])) {
    YAKALA_LOG_DEBUG("capture") << argv[0] << " yüklü değil, sıradaki tool";
    return false;
  }
  // Output path eski yakalamadan kalmış olabilir — önce sil ki
  // file_nonempty stale dosyayı yanlışlıkla "success" diye yorumlamasın.
  std::error_code ec;
  fs::remove(out, ec);

  const auto res = ProcessRunner::run(argv);
  if (res.timed_out) {
    YAKALA_LOG_WARN("capture") << argv[0] << " timeout";
    return false;
  }
  if (!file_nonempty(out)) {
    YAKALA_LOG_WARN("capture") << argv[0]
                               << " başarısız (exit=" << res.exit_code
                               << ", dosya yok/boş)";
    if (!res.stderr_text.empty()) {
      YAKALA_LOG_DEBUG("capture") << "stderr: " << res.stderr_text;
    }
    return false;
  }
  if (res.exit_code != 0) {
    // Dosya var ama exit nonzero — ImageMagick benzeri tool'ların warning
    // davranışı. Toleranslı kabul.
    YAKALA_LOG_INFO("capture") << argv[0] << " ile yakalama başarılı "
                               << "(warning exit=" << res.exit_code
                               << "): " << out.string();
  } else {
    YAKALA_LOG_INFO("capture") << argv[0] << " ile yakalama başarılı: "
                               << out.string();
  }
  return true;
}

}  // namespace

Capture::DisplayServer Capture::detect_display_server() {
  // Sıralama: WAYLAND_DISPLAY (en kesin), XDG_SESSION_TYPE, DISPLAY (X11
  // fallback).
  const char* wl = std::getenv("WAYLAND_DISPLAY");
  if (wl && *wl) return DisplayServer::kWayland;
  const char* type = std::getenv("XDG_SESSION_TYPE");
  if (type) {
    std::string lower(type);
    for (char& c : lower) c = static_cast<char>(std::tolower(c));
    if (lower == "wayland") return DisplayServer::kWayland;
    if (lower == "x11") return DisplayServer::kX11;
  }
  const char* display = std::getenv("DISPLAY");
  if (display && *display) return DisplayServer::kX11;
  return DisplayServer::kUnknown;
}

bool Capture::capture_full_screen(const fs::path& out) {
  const auto path_str = out.string();
  const auto server = detect_display_server();

  // Wayland: grim öncelikli — native protokol, izin gerek yok (compositor
  // pencere yakalamayı destekliyorsa).
  if (server == DisplayServer::kWayland) {
    if (try_capture({"grim", path_str}, out)) return true;
    YAKALA_LOG_INFO("capture") << "grim fallback'e düşüldü (X11 tools)";
  }

  // X11 (veya Wayland fallback için Xwayland):
  if (try_capture({"import", "-silent", "-window", "root", path_str}, out)) {
    return true;
  }
  if (try_capture({"scrot", "-z", "-o", path_str}, out)) return true;
  if (try_capture({"maim", path_str}, out)) return true;

  YAKALA_LOG_ERROR("capture") << "Hiçbir capture tool bulunamadı/çalışmadı.";
  return false;
}

bool Capture::capture_active_window(const fs::path& out) {
  const auto path_str = out.string();
  const auto server = detect_display_server();

  if (server == DisplayServer::kX11) {
    // ImageMagick `import` parametre olarak window ID alır; "-frame" ile
    // dekorasyonları dahil eder. Aktif pencereyi xdotool ile bul, sonra
    // import ile yakala.
    const auto getid = ProcessRunner::run(
        {"xdotool", "getactivewindow"});
    if (getid.succeeded() && !getid.stdout_text.empty()) {
      std::string wid = getid.stdout_text;
      while (!wid.empty() && (wid.back() == '\n' || wid.back() == ' ')) {
        wid.pop_back();
      }
      if (!wid.empty()
          && try_capture({"import", "-silent", "-frame",
                          "-window", wid, path_str}, out)) {
        return true;
      }
    }
    // Fallback: import -window root (full screen). Kullanıcı yine bir
    // yakalama görür — aktif window yerine full screen.
    YAKALA_LOG_WARN("capture") << "active window alınamadı, full screen'e düşüldü";
    return capture_full_screen(out);
  }

  // Wayland'da "active window" tek-call ile yapılamıyor (compositor
  // protokol gerek). Şimdilik full-screen fallback.
  YAKALA_LOG_WARN("capture") << "Wayland'da window mode desteklenmiyor — "
                             << "full-screen capture yapılıyor";
  return capture_full_screen(out);
}

std::string Capture::capture_fail_hint() {
  if (detect_display_server() == DisplayServer::kWayland) {
    return "Tam ekran yakalanamadı. Eksik araç: grim. "
           "Kurulum: sudo apt install grim";
  }
  return "Tam ekran yakalanamadı. Eksik araç: imagemagick. "
         "Kurulum: sudo apt install imagemagick";
}

}  // namespace yakala::daemon
