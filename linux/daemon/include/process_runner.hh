#pragma once

#include <chrono>
#include <optional>
#include <string>
#include <vector>

namespace yakala::daemon {

// Sonuç tipi: exit code + stdout/stderr (gerekirse). Çoğu shell-out için
// sadece exit code yeterli — stdout/stderr opsiyonel.
struct ProcessResult {
  int exit_code{-1};
  bool timed_out{false};
  std::string stdout_text{};
  std::string stderr_text{};

  bool succeeded() const { return exit_code == 0 && !timed_out; }
};

// Sync shell-out wrapper. GSubprocess tabanlı — GLib main loop'la uyumlu.
// Industrial pattern: tüm Process.run çağrılarının single point of entry'si.
class ProcessRunner {
public:
  // Komut çalıştır, exit'e kadar bekle. Timeout aşılırsa SIGKILL gönderilip
  // `timed_out=true` döner.
  // `stdin_bytes` opsiyonel — varsa child process'in stdin'ine yazılır
  // (örn. xclip/wl-copy PNG bytes).
  static ProcessResult run(const std::vector<std::string>& argv,
                           std::chrono::milliseconds timeout =
                               std::chrono::seconds(8),
                           const std::vector<unsigned char>* stdin_bytes = nullptr);

  // Async fire-and-forget — exit code beklenmez, callback yok. Notification
  // gibi best-effort işler için.
  static void run_detached(const std::vector<std::string>& argv);

  // PATH'da komut var mı (which/command -v karşılığı). Process spawn etmez,
  // hızlı.
  static bool command_exists(const std::string& name);
};

}  // namespace yakala::daemon
