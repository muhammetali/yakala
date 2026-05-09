#pragma once

#include <filesystem>
#include <string>
#include <vector>

#include <gio/gio.h>

namespace yakala::daemon {

// Flutter UI binary'sini spawn eder. GSubprocess kullanır — SIGCHLD'i
// GLib main loop yönetir, bizim sigaction handler'ı koymamız gerek yok
// (custom handler g_child_watch_add ile çakışıyordu).
//
// `spawn` GSubprocess* döner — caller `g_object_ref` alıp
// `g_subprocess_wait_async` ile child exit'i izleyebilir. Caller bitirince
// `g_object_unref` ile bırakır.
class UiSpawner {
public:
  UiSpawner();

  // UI binary path'ini çözer (cached). Override env > /proc/self/exe parent
  // > PATH lookup.
  std::filesystem::path resolve_binary_path() const;

  // UI'yi spawn eder. argv[0] otomatik atanır; çağıran sadece flag'leri verir.
  // **Returns**: GSubprocess* (caller bir ref sahibi olur — `g_object_unref`
  // ile bırakmak gerek). Spawn fail → nullptr.
  GSubprocess* spawn(const std::vector<std::string>& args) const;

  // Test/debug için path override.
  void set_binary_path(std::filesystem::path path);

private:
  std::filesystem::path binary_path_;
};

}  // namespace yakala::daemon
