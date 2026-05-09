#include "clipboard.hh"

#include <cstdlib>
#include <fstream>
#include <iterator>
#include <vector>

#include <gio/gio.h>

#include "logger.hh"
#include "process_runner.hh"

namespace yakala::daemon {

namespace fs = std::filesystem;

namespace {

bool is_wayland() {
  const char* wl = std::getenv("WAYLAND_DISPLAY");
  if (wl && *wl) return true;
  const char* type = std::getenv("XDG_SESSION_TYPE");
  if (type) {
    std::string lower(type);
    for (char& c : lower) c = static_cast<char>(std::tolower(c));
    if (lower == "wayland") return true;
  }
  return false;
}

// xclip ve wl-copy "clipboard ownership" pattern'i kullanır:
//   1. parent process stdin'den input okur
//   2. fork() yapar
//   3. parent hemen çıkar (exit 0)
//   4. child arka planda yaşar, X11/Wayland selection request'lerini cevaplar
//      (kullanıcı paste yapana kadar)
//
// `g_subprocess_communicate` parent exit'inde dönmüyor çünkü stdout/stderr
// pipe'larını child'in inheritance ile tuttuğu sürece "EOF" gelmiyor —
// daemon'un main loop'u 8s timeout'a kadar bloke oluyor (capture sırasındaki
// next click'leri kuyruklayıp sonra burst halinde çalıştırıyor).
//
// Çözüm: `GSubprocessLauncher` ile stdin'i dosyadan oku (pipe'a yazmadan),
// stdout/stderr'i SILENCE (bizim tarafa pipe yok), spawn et, **bekleme**.
// xclip backgrounded child'ı bizimle bağlantısız çalışır.
bool spawn_clipboard_tool_async(const std::vector<std::string>& argv,
                                const fs::path& stdin_file) {
  GSubprocessLauncher* launcher = g_subprocess_launcher_new(
      static_cast<GSubprocessFlags>(G_SUBPROCESS_FLAGS_STDOUT_SILENCE |
                                    G_SUBPROCESS_FLAGS_STDERR_SILENCE));
  g_subprocess_launcher_set_stdin_file_path(launcher, stdin_file.c_str());

  std::vector<gchar*> pointers;
  pointers.reserve(argv.size() + 1);
  for (const auto& s : argv) {
    pointers.push_back(const_cast<gchar*>(s.c_str()));
  }
  pointers.push_back(nullptr);

  GError* err = nullptr;
  GSubprocess* proc = g_subprocess_launcher_spawnv(
      launcher, pointers.data(), &err);
  g_object_unref(launcher);

  if (!proc) {
    YAKALA_LOG_WARN("clipboard") << argv[0]
                                 << " spawn fail: "
                                 << (err ? err->message : "?");
    if (err) g_error_free(err);
    return false;
  }
  // Backgrounded daemon child'a artık ihtiyacımız yok; ref'i bırak. GLib
  // SIGCHLD reap'i ana process'imizin sigaction handler'ında (main.cc).
  g_object_unref(proc);
  return true;
}

}  // namespace

bool Clipboard::copy_png_image(const fs::path& png_path) {
  std::error_code ec;
  if (!fs::exists(png_path, ec) || ec) {
    YAKALA_LOG_WARN("clipboard") << "PNG yok: " << png_path.string();
    return false;
  }

  if (is_wayland()) {
    if (!ProcessRunner::command_exists("wl-copy")) {
      YAKALA_LOG_WARN("clipboard") << "wl-copy yok — apt install wl-clipboard";
      return false;
    }
    if (spawn_clipboard_tool_async({"wl-copy", "--type", "image/png"},
                                   png_path)) {
      YAKALA_LOG_INFO("clipboard") << "PNG → clipboard (wl-copy, async)";
      return true;
    }
    return false;
  }

  // X11: xclip stdin'i dosyadan okur, fork+detach yapar.
  if (!ProcessRunner::command_exists("xclip")) {
    YAKALA_LOG_WARN("clipboard") << "xclip yok — apt install xclip";
    return false;
  }
  if (spawn_clipboard_tool_async(
          {"xclip", "-selection", "clipboard", "-t", "image/png"},
          png_path)) {
    YAKALA_LOG_INFO("clipboard") << "PNG → clipboard (xclip, async)";
    return true;
  }
  return false;
}

}  // namespace yakala::daemon
