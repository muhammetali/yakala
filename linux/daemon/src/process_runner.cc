#include "process_runner.hh"

#include <cstdlib>
#include <cstring>

#include <gio/gio.h>
#include <glib.h>

#include "logger.hh"

namespace yakala::daemon {

namespace {

// argv vector'ünü GSubprocess'in beklediği `gchar* []` (null-terminated)
// formatına çevirir. Geri dönen array g_strfreev ile değil, tek tek free
// edilmemeli — c_str() pointer'ları çağıranın string'lerine bağlı.
std::vector<gchar*> to_argv_pointers(const std::vector<std::string>& argv) {
  std::vector<gchar*> out;
  out.reserve(argv.size() + 1);
  for (const auto& s : argv) {
    out.push_back(const_cast<gchar*>(s.c_str()));
  }
  out.push_back(nullptr);
  return out;
}

}  // namespace

ProcessResult ProcessRunner::run(const std::vector<std::string>& argv,
                                 std::chrono::milliseconds timeout,
                                 const std::vector<unsigned char>* stdin_bytes) {
  ProcessResult result;
  if (argv.empty()) return result;

  auto pointers = to_argv_pointers(argv);

  // GSubprocessFlags glib'de düz `int` enum — C++ strong typing için kast lazım.
  int flag_bits = G_SUBPROCESS_FLAGS_STDOUT_PIPE | G_SUBPROCESS_FLAGS_STDERR_PIPE;
  if (stdin_bytes) {
    flag_bits |= G_SUBPROCESS_FLAGS_STDIN_PIPE;
  } else {
    flag_bits |= G_SUBPROCESS_FLAGS_STDIN_INHERIT;
  }
  const auto flags = static_cast<GSubprocessFlags>(flag_bits);

  GError* err = nullptr;
  GSubprocess* proc = g_subprocess_newv(pointers.data(), flags, &err);
  if (!proc) {
    YAKALA_LOG_DEBUG("proc") << "spawn fail (" << argv[0] << "): "
                             << (err ? err->message : "?");
    if (err) g_error_free(err);
    return result;
  }

  // stdin pipe'a yaz (varsa) — communicate ile stdin yazıp stdout/stderr okuruz.
  GBytes* stdin_buf = nullptr;
  if (stdin_bytes && !stdin_bytes->empty()) {
    stdin_buf = g_bytes_new(stdin_bytes->data(), stdin_bytes->size());
  }

  // Timeout için GCancellable + timeout source ayarla. communicate sync
  // blocking — main loop'tan ayrı thread'de değil. Daemon tray callback'i
  // sırasında main loop bloke olur ama bu kabul edilebilir (capture <2s).
  GCancellable* cancel = g_cancellable_new();
  guint timeout_id = g_timeout_add(
      static_cast<guint>(timeout.count()),
      [](gpointer data) -> gboolean {
        g_cancellable_cancel(static_cast<GCancellable*>(data));
        return G_SOURCE_REMOVE;
      },
      cancel);

  GBytes* stdout_buf = nullptr;
  GBytes* stderr_buf = nullptr;
  GError* comm_err = nullptr;
  const gboolean ok = g_subprocess_communicate(proc, stdin_buf, cancel,
                                               &stdout_buf, &stderr_buf,
                                               &comm_err);
  g_source_remove(timeout_id);

  if (!ok) {
    if (comm_err) {
      const bool cancelled = g_error_matches(comm_err, G_IO_ERROR,
                                             G_IO_ERROR_CANCELLED);
      result.timed_out = cancelled;
      YAKALA_LOG_WARN("proc") << argv[0]
                              << (cancelled ? " timeout" : " comm error: ")
                              << (cancelled ? "" : comm_err->message);
      g_error_free(comm_err);
    }
    if (result.timed_out) {
      g_subprocess_force_exit(proc);
    }
  }

  if (stdout_buf) {
    gsize n = 0;
    const gchar* data = static_cast<const gchar*>(g_bytes_get_data(stdout_buf, &n));
    if (data && n > 0) result.stdout_text.assign(data, n);
    g_bytes_unref(stdout_buf);
  }
  if (stderr_buf) {
    gsize n = 0;
    const gchar* data = static_cast<const gchar*>(g_bytes_get_data(stderr_buf, &n));
    if (data && n > 0) result.stderr_text.assign(data, n);
    g_bytes_unref(stderr_buf);
  }
  if (stdin_buf) g_bytes_unref(stdin_buf);

  // Wait for process to actually exit (communicate may have closed pipes
  // while child is still running on cancel path).
  g_subprocess_wait(proc, nullptr, nullptr);
  result.exit_code = g_subprocess_get_exit_status(proc);

  g_object_unref(cancel);
  g_object_unref(proc);
  return result;
}

void ProcessRunner::run_detached(const std::vector<std::string>& argv) {
  if (argv.empty()) return;
  auto pointers = to_argv_pointers(argv);
  GError* err = nullptr;
  GSubprocess* proc = g_subprocess_newv(
      pointers.data(),
      static_cast<GSubprocessFlags>(G_SUBPROCESS_FLAGS_STDIN_INHERIT
                                  | G_SUBPROCESS_FLAGS_STDOUT_SILENCE
                                  | G_SUBPROCESS_FLAGS_STDERR_SILENCE),
      &err);
  if (!proc) {
    YAKALA_LOG_DEBUG("proc") << "detached spawn fail (" << argv[0]
                             << "): " << (err ? err->message : "?");
    if (err) g_error_free(err);
    return;
  }
  // Object will be cleaned up after exit (no waiting). g_subprocess'in dtor'u
  // SIGCHLD reap eder; biz ref'i hemen bırakabiliriz.
  g_object_unref(proc);
}

bool ProcessRunner::command_exists(const std::string& name) {
  // PATH lookup — g_find_program_in_path standart yardımcı.
  gchar* path = g_find_program_in_path(name.c_str());
  if (!path) return false;
  g_free(path);
  return true;
}

}  // namespace yakala::daemon
