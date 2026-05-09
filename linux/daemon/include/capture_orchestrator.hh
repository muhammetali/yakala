#pragma once

#include <filesystem>

#include "settings_loader.hh"

namespace yakala::daemon {

// Capture orchestrator — kullanıcının bir capture mode tetiklediğinde
// (tray click, hotkey IPC, vb.) çalışan akış:
//
//   1. Path = /tmp/yakala_<ts>.png üret
//   2. Native capture (Capture sınıfı)
//   3. Settings.show_editor_after_capture true → UI editor spawn (faz 3)
//      veya false → direkt finalize
//   4. Finalize: clipboard copy, optional disk save, notification, sound
//
// Faz 2 scope: editor flow yok (UI refactor sonra). show_editor_after_capture
// flag'i şimdilik göz ardı edilir; her zaman direkt finalize.
class CaptureOrchestrator {
public:
  enum class Mode {
    kFullScreen,
    kRegion,    // faz 2'de full-screen-fallback
    kWindow,
  };

  explicit CaptureOrchestrator(SettingsLoader& settings);

  // Senkron — capture flow tamamlanana kadar dönmez. ~1-2s normal duration.
  // True: capture + clipboard ya da disk save'den en az biri başarılı.
  bool run(Mode mode);

private:
  static std::filesystem::path generate_temp_path();
  static std::filesystem::path expand_home(const std::string& path);

  bool finalize(const std::filesystem::path& image_path);

  SettingsLoader& settings_;
};

}  // namespace yakala::daemon
