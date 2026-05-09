#pragma once

#include <filesystem>
#include <functional>
#include <memory>
#include <string>
#include <string_view>

// glib.h pulled in for GSocketService*, gpointer, gboolean. Header'a koymak
// pratik — alternatif extern "C" forward-decl'leri eksik kalıyor (gboolean
// = int gibi bağımlılıkları taşımak gerek). glib.h zaten sistem-genelinde
// pollute olan bir header.
#include <gio/gio.h>

namespace yakala::daemon {

// Daemon'un IPC sunucusu — Unix domain socket üzerinde JSON line-delimited
// protokol.
//
// Socket path: $XDG_RUNTIME_DIR/yakala-daemon.sock (genelde
// /run/user/<uid>/yakala-daemon.sock). Atomic temizlik — daemon kalkarken
// stale socket dosyasını siler, restart'ta yeniden bind eder.
//
// Mesaj formatı (her satır bir mesaj, '\n' terminator):
//   { "cmd": "capture", "mode": "fullScreen|region|window" }
//   { "cmd": "show_settings" }
//   { "cmd": "ping" }                       — health check, daemon "pong" döner
//   { "cmd": "ui_result", "ok": true,
//     "output": "/tmp/yakala_xxx.png" }     — UI confirmed kaydetti
//   { "cmd": "ui_result", "ok": false,
//     "reason": "user_cancelled" }
//
// Tek-yönlü protokol (request → no response) — sadece "ping" cevap döner.
// Bu pattern Slack/Telegram'ın daemon control socket'ine benziyor.
class IpcServer {
public:
  // Mesaj geldiğinde çağrılan handler. JSON parse edilmiş command ve raw
  // body alır. Returnsuz — handler async fire-and-forget.
  using CommandHandler = std::function<void(std::string_view cmd,
                                            std::string_view body)>;

  IpcServer();
  ~IpcServer();

  IpcServer(const IpcServer&) = delete;
  IpcServer& operator=(const IpcServer&) = delete;

  // Init: socket dosyasını yarat, dinlemeye başla, glib main loop'a bağla.
  // Throw'larsa daemon başlamaz.
  void start(CommandHandler handler);

  // Graceful shutdown: socket'i kapat, dosyayı sil. Yıkıcıdan da çağrılır.
  void stop();

  // Socket path — install ve troubleshooting için public.
  static std::filesystem::path resolve_socket_path();

  // Çalışan başka bir daemon var mı? Socket'e connect deneme yapar:
  //   - Connect başarılı → başka instance var → true.
  //   - Connect ECONNREFUSED → stale socket dosyası → false.
  //   - Socket dosyası yok → false.
  // Daemon main()'in başında çağrılır — varsa çık (çift-tray engelleme).
  static bool another_instance_running();

private:
  // glib callback'leri — static çünkü C API.
  static gboolean on_incoming_static(GSocketService* service,
                                     GSocketConnection* connection,
                                     GObject* source_object,
                                     gpointer user_data);

  void on_incoming(GSocketConnection* connection);
  void process_line(const std::string& line);

  GSocketService* service_{nullptr};
  std::filesystem::path socket_path_;
  CommandHandler handler_{};
  bool started_{false};
};

}  // namespace yakala::daemon
