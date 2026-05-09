#pragma once

#include <filesystem>
#include <string>
#include <vector>

namespace yakala::daemon {

// Flutter UI binary'sini spawn eder. Daemon UI'nin exit code'unu beklemez —
// fire-and-forget. UI işini bitirince IPC üzerinden sonuç gönderir.
class UiSpawner {
public:
  UiSpawner();

  // UI binary'sinin yolunu çözer. Önce env (`YAKALA_UI`), sonra daemon binary
  // ile aynı dizindeki `yakala-ui`, sonra PATH lookup.
  std::filesystem::path resolve_binary_path() const;

  // UI'yi spawn eder. argv[0] otomatik atanır; çağıran sadece flag'leri verir.
  // Ör: `spawn({"--mode=editor", "--input=/tmp/foo.png"})`.
  // Returns: child PID, ya da spawn başarısızsa -1.
  // Industrial pattern: fork+execvp + parent SIGCHLD ile reap eder.
  int spawn(const std::vector<std::string>& args) const;

  // Test/debug için path override.
  void set_binary_path(std::filesystem::path path);

private:
  std::filesystem::path binary_path_;
};

}  // namespace yakala::daemon
