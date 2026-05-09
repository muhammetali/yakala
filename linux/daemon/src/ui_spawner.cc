#include "ui_spawner.hh"

#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>

#include "logger.hh"

namespace yakala::daemon {

namespace fs = std::filesystem;

UiSpawner::UiSpawner() = default;

void UiSpawner::set_binary_path(fs::path path) {
  binary_path_ = std::move(path);
}

fs::path UiSpawner::resolve_binary_path() const {
  if (!binary_path_.empty()) return binary_path_;

  // 1) YAKALA_UI env override (debug/test için).
  if (const char* env = std::getenv("YAKALA_UI")) {
    if (*env) return fs::path(env);
  }

  // 2) Daemon binary ile aynı dizinde `yakala-ui` ara. Standard install
  //    layout: ~/.local/share/yakala/{yakala-daemon,yakala-ui}.
  std::error_code ec;
  fs::path self = fs::read_symlink("/proc/self/exe", ec);
  if (!ec && !self.empty()) {
    fs::path candidate = self.parent_path() / "yakala-ui";
    if (fs::exists(candidate, ec) && !ec) {
      return candidate;
    }
    // Fallback: `yakala` adı (refactor öncesi binary).
    candidate = self.parent_path() / "yakala";
    if (fs::exists(candidate, ec) && !ec) {
      return candidate;
    }
  }

  // 3) PATH lookup — execvp halletsin diye sadece ismi dön.
  return fs::path("yakala-ui");
}

int UiSpawner::spawn(const std::vector<std::string>& args) const {
  const fs::path bin = resolve_binary_path();

  // argv inşası — execvp char* dizisi ister, terminator nullptr.
  std::vector<char*> argv;
  std::string bin_str = bin.string();
  argv.push_back(const_cast<char*>(bin_str.c_str()));
  for (const auto& arg : args) {
    argv.push_back(const_cast<char*>(arg.c_str()));
  }
  argv.push_back(nullptr);

  YAKALA_LOG_INFO("spawn") << "exec " << bin_str
                           << " (" << args.size() << " args)";

  const pid_t pid = fork();
  if (pid < 0) {
    YAKALA_LOG_ERROR("spawn") << "fork başarısız: " << std::strerror(errno);
    return -1;
  }

  if (pid == 0) {
    // Child — exec ile UI binary'ye geç. Başarısız olursa _exit ile çık.
    // Industrial pattern: setsid çağrılırsa child farklı session'da olur,
    // parent SIGHUP almıyorsa onu da götürmez. Daemon respawn senaryolarında
    // önemli ama şimdi gerek yok — UI parent'a bağlı kalsın ki SIGCHLD reap
    // edilebilsin.
    execvp(argv[0], argv.data());
    // execvp dönerse hata.
    std::fprintf(stderr, "execvp(%s) failed: %s\n", argv[0],
                 std::strerror(errno));
    _exit(127);
  }

  // Parent — child PID'i dön. Reaping için ayrı SIGCHLD handler'da
  // waitpid(WNOHANG) çağrılmalı (main.cc set ediyor).
  YAKALA_LOG_DEBUG("spawn") << "child pid=" << pid;
  return pid;
}

}  // namespace yakala::daemon
