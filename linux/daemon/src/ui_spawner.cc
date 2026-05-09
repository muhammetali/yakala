#include "ui_spawner.hh"

#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <unistd.h>

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
    if (fs::exists(candidate, ec) && !ec) return candidate;
    // Fallback (eski install dosya adı).
    candidate = self.parent_path() / "yakala";
    if (fs::exists(candidate, ec) && !ec) return candidate;
  }

  // 3) PATH lookup.
  return fs::path("yakala-ui");
}

GSubprocess* UiSpawner::spawn(const std::vector<std::string>& args) const {
  const fs::path bin = resolve_binary_path();
  std::string bin_str = bin.string();

  std::vector<gchar*> pointers;
  pointers.reserve(args.size() + 2);
  pointers.push_back(const_cast<gchar*>(bin_str.c_str()));
  for (const auto& a : args) {
    pointers.push_back(const_cast<gchar*>(a.c_str()));
  }
  pointers.push_back(nullptr);

  // STDIN_INHERIT yeterli — stdout/stderr default'ta inherit eder (parent
  // fd'leri kalır). Bu sayede UI'nin debugPrint çıktıları daemon log'una
  // akar (debug için faydalı).
  GError* err = nullptr;
  GSubprocess* proc = g_subprocess_newv(
      pointers.data(),
      G_SUBPROCESS_FLAGS_STDIN_INHERIT,
      &err);
  if (!proc) {
    YAKALA_LOG_ERROR("spawn") << "yakala-ui spawn fail: "
                              << (err ? err->message : "?");
    if (err) g_error_free(err);
    return nullptr;
  }
  YAKALA_LOG_INFO("spawn") << "exec " << bin_str
                           << " (" << args.size() << " args, pid="
                           << g_subprocess_get_identifier(proc) << ")";
  return proc;
}

}  // namespace yakala::daemon
