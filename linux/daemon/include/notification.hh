#pragma once

#include <string>

namespace yakala::daemon {

// Native bildirim göstericisi (best-effort). `notify-send` üzerinden — DBus
// org.freedesktop.Notifications protokolüne çevirir. Async fire-and-forget
// (kullanıcı bildirimi 5 saniye gösterilir, daemon'un beklemesi gerekmez).
class Notification {
public:
  static void show(const std::string& title, const std::string& body);

  // PNG dosyası işaretiyle birlikte bildirim — ImageBox icon olarak gösterilir
  // (DE destekliyorsa). Yakalama sonrası "şu küçük thumbnail'a tıkla" UX'i
  // için kullanışlı.
  static void show_with_image(const std::string& title,
                              const std::string& body,
                              const std::string& image_path);
};

}  // namespace yakala::daemon
