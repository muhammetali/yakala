#include "notification.hh"

#include "logger.hh"
#include "process_runner.hh"

namespace yakala::daemon {

namespace {

bool ensure_notify_send() {
  if (ProcessRunner::command_exists("notify-send")) return true;
  YAKALA_LOG_DEBUG("notif") << "notify-send yok — bildirim atlandı";
  return false;
}

}  // namespace

void Notification::show(const std::string& title, const std::string& body) {
  if (!ensure_notify_send()) return;
  // -a (app name): bildirim yöneticisinde "Yakala" kategorisi.
  // -t (timeout, ms): 5sn — masaüstü standardı.
  ProcessRunner::run_detached({
      "notify-send",
      "-a", "Yakala",
      "-t", "5000",
      title,
      body,
  });
}

void Notification::show_with_image(const std::string& title,
                                   const std::string& body,
                                   const std::string& image_path) {
  if (!ensure_notify_send()) return;
  // -i (icon): notify-send tam yol kabul eder ya icon-name ya da path.
  // freedesktop hint -h string:image-path:... ise daha güvenilir.
  ProcessRunner::run_detached({
      "notify-send",
      "-a", "Yakala",
      "-t", "5000",
      "-i", image_path,
      title,
      body,
  });
}

}  // namespace yakala::daemon
