#pragma once

#include <filesystem>

namespace yakala::daemon {

// PNG image'ı sistem clipboard'una kopyalar. Wayland'da `wl-copy`, X11'de
// `xclip` kullanır. Her ikisi de stdin'den ham PNG bytes ister.
class Clipboard {
public:
  // PNG dosyasını oku → clipboard'a image/png MIME ile yaz.
  // Throw etmez, başarısızsa false döner. (Kullanıcı için en kötü durum:
  // diske yazıldı ama clipboard'a değil — notification bunu söyler.)
  static bool copy_png_image(const std::filesystem::path& png_path);
};

}  // namespace yakala::daemon
