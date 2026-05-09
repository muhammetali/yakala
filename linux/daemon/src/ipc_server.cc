#include "ipc_server.hh"

#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#include <system_error>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <unistd.h>

#include <gio/gio.h>
#include <gio/gunixsocketaddress.h>
#include <glib.h>
#include <nlohmann/json.hpp>

#include "logger.hh"

namespace yakala::daemon {

namespace fs = std::filesystem;
using nlohmann::json;

IpcServer::IpcServer() = default;

IpcServer::~IpcServer() {
  stop();
}

bool IpcServer::another_instance_running() {
  const fs::path sock_path = resolve_socket_path();
  std::error_code ec;
  if (!fs::exists(sock_path, ec) || ec) {
    return false;
  }
  // Connect denemesi — başarılı ise başka daemon çalışıyor.
  // Industrial pattern: SOCK_STREAM connect ECONNREFUSED dönerse stale.
  const int fd = ::socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    return false;  // emin değiliz, fail-open
  }
  struct sockaddr_un addr{};
  addr.sun_family = AF_UNIX;
  std::strncpy(addr.sun_path,
               sock_path.c_str(),
               sizeof(addr.sun_path) - 1);
  const int rc = ::connect(fd, reinterpret_cast<struct sockaddr*>(&addr),
                           sizeof(addr));
  ::close(fd);
  return rc == 0;
}

fs::path IpcServer::resolve_socket_path() {
  // XDG_RUNTIME_DIR — systemd-logind tarafından oturum açılışında set edilir,
  // genelde /run/user/<uid>. Yoksa /tmp fallback.
  const char* xdg_runtime = std::getenv("XDG_RUNTIME_DIR");
  if (xdg_runtime && *xdg_runtime) {
    return fs::path(xdg_runtime) / "yakala-daemon.sock";
  }
  // /tmp fallback — uid suffix ile çakışma önle.
  return fs::path("/tmp/yakala-daemon-" + std::to_string(getuid()) + ".sock");
}

void IpcServer::start(CommandHandler handler) {
  if (started_) {
    YAKALA_LOG_WARN("ipc") << "zaten başlatılmış, yeniden start atılıyor";
    return;
  }
  handler_ = std::move(handler);
  socket_path_ = resolve_socket_path();

  // Stale socket dosyasını temizle — bind aksi halde EADDRINUSE atar.
  std::error_code ec;
  if (fs::exists(socket_path_, ec)) {
    fs::remove(socket_path_, ec);
    if (ec) {
      YAKALA_LOG_WARN("ipc") << "stale socket silinemedi: " << ec.message();
    }
  }

  // Parent dizini garanti et.
  fs::create_directories(socket_path_.parent_path(), ec);

  service_ = g_socket_service_new();
  if (!service_) {
    throw std::runtime_error("g_socket_service_new başarısız");
  }

  GSocketAddress* address = g_unix_socket_address_new(socket_path_.c_str());
  GError* error = nullptr;
  GSocketAddress* effective_address = nullptr;
  const gboolean ok = g_socket_listener_add_address(
      G_SOCKET_LISTENER(service_),
      address,
      G_SOCKET_TYPE_STREAM,
      G_SOCKET_PROTOCOL_DEFAULT,
      nullptr,
      &effective_address,
      &error);
  g_object_unref(address);
  if (effective_address) g_object_unref(effective_address);

  if (!ok) {
    std::string msg = error ? error->message : "bilinmeyen hata";
    if (error) g_error_free(error);
    g_object_unref(service_);
    service_ = nullptr;
    throw std::runtime_error("IPC socket bind hatası: " + msg);
  }

  // 0600 permission — aynı user dışındaki kullanıcılar bağlanamasın.
  if (chmod(socket_path_.c_str(), 0600) != 0) {
    YAKALA_LOG_WARN("ipc") << "chmod 0600 başarısız: " << std::strerror(errno);
  }

  g_signal_connect(service_, "incoming",
                   G_CALLBACK(&IpcServer::on_incoming_static), this);

  g_socket_service_start(service_);
  started_ = true;
  YAKALA_LOG_INFO("ipc") << "dinleniyor: " << socket_path_.string();
}

void IpcServer::stop() {
  if (!started_) return;
  g_socket_service_stop(service_);
  g_socket_listener_close(G_SOCKET_LISTENER(service_));
  g_object_unref(service_);
  service_ = nullptr;
  std::error_code ec;
  fs::remove(socket_path_, ec);
  started_ = false;
  YAKALA_LOG_INFO("ipc") << "durduruldu";
}

gboolean IpcServer::on_incoming_static(GSocketService* /*service*/,
                                       GSocketConnection* connection,
                                       GObject* /*source_object*/,
                                       gpointer user_data) {
  auto* self = static_cast<IpcServer*>(user_data);
  // GSocketService bağlantıyı bizimle paylaşırken tek bir referans verir;
  // async okuma için ref'i artırmamız gerek (g_object_ref).
  g_object_ref(connection);
  self->on_incoming(connection);
  return TRUE;  // bağlantı işlendi, gelecek ones'lar için service açık kalsın.
}

void IpcServer::on_incoming(GSocketConnection* connection) {
  GInputStream* base_stream = g_io_stream_get_input_stream(G_IO_STREAM(connection));
  GDataInputStream* stream = g_data_input_stream_new(base_stream);
  // Line-delimited okuma. Async — main loop'u bloke etmiyor.
  // Read sonucu callback'e gelir; orada parse + handler çağrılır.
  g_data_input_stream_read_line_async(
      stream, G_PRIORITY_DEFAULT, nullptr,
      [](GObject* source, GAsyncResult* res, gpointer user_data) {
        auto* self = static_cast<IpcServer*>(user_data);
        gsize length = 0;
        GError* error = nullptr;
        GDataInputStream* s = G_DATA_INPUT_STREAM(source);
        gchar* line = g_data_input_stream_read_line_finish(
            s, res, &length, &error);
        if (error) {
          YAKALA_LOG_WARN("ipc") << "okuma hatası: " << error->message;
          g_error_free(error);
        } else if (line && length > 0) {
          self->process_line(std::string(line, length));
        }
        g_free(line);
        g_object_unref(s);
        // connection ref'ini bırak — istemci kapatınca close olur.
      },
      this);
  g_object_unref(connection);
}

void IpcServer::process_line(const std::string& line) {
  if (line.empty()) return;
  YAKALA_LOG_DEBUG("ipc") << "raw: " << line;

  std::string cmd;
  try {
    auto j = json::parse(line);
    if (j.contains("cmd") && j["cmd"].is_string()) {
      cmd = j["cmd"].get<std::string>();
    }
  } catch (const json::exception& e) {
    YAKALA_LOG_WARN("ipc") << "JSON parse hatası: " << e.what();
    return;
  }

  if (cmd.empty()) {
    YAKALA_LOG_WARN("ipc") << "cmd alanı yok veya boş";
    return;
  }

  if (handler_) {
    handler_(cmd, line);
  }
}

}  // namespace yakala::daemon
