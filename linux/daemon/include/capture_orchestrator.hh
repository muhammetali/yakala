#pragma once

#include <filesystem>

#include <gio/gio.h>

#include "settings_loader.hh"
#include "ui_spawner.hh"

namespace yakala::daemon {

// Capture orchestrator — kullanıcının bir capture mode tetiklediğinde
// (tray click, hotkey IPC, vb.) çalışan akış:
//
// **Senkron faz** (capture, hızlı):
//   1. Path = /tmp/yakala_<ts>.png üret
//   2. Native capture (Capture sınıfı) — 200-500ms
//
// **Async faz** (editor/region UI), settings'e göre koşullu:
//   3a. Region mode ya da fullScreen+show_editor_after_capture →
//       yakala-ui spawn et (--mode=editor / --mode=region)
//   3b. g_child_watch_add ile child exit callback bekle (main loop block
//       OLMAZ; tray ve hotkey diğer click'lere açık kalır — re-entry guard
//       editor session'ı sırasında yeni capture'ları reddeder).
//
// **Finalize faz**:
//   4. Clipboard copy, optional disk save, notification.
//
// Re-entry koruması: bir capture flow'u in-flight iken (capture sırasında
// veya editor açıkken) gelen yeni run() çağrıları sessizce drop edilir.
class CaptureOrchestrator {
public:
  enum class Mode {
    kFullScreen,
    kRegion,
    kWindow,
  };

  CaptureOrchestrator(SettingsLoader& settings, UiSpawner& ui_spawner);

  // Async başlatıcı — capture senkron yapılır, editor/region UI gerekiyorsa
  // asenkron beklenir. False: re-entry, capture başarısız, vb.
  bool run(Mode mode);

  bool is_busy() const { return busy_; }

private:
  static std::filesystem::path generate_temp_path(const std::string& prefix = "yakala");
  static std::filesystem::path expand_home(const std::string& path);

  // Editor UI spawn et (capture sonrası). Output path callback'te kullanılır.
  void spawn_editor(const std::filesystem::path& input_path,
                    const std::filesystem::path& output_path);

  // Region UI spawn et (full-screen capture'dan sonra). Output path
  // kırpılmış + annotated PNG.
  void spawn_region(const std::filesystem::path& input_path,
                    const std::filesystem::path& output_path);

  // glib g_subprocess_wait_async callback static thunk → instance method'a
  // delege.
  static void on_ui_exit_static(GObject* source, GAsyncResult* res,
                                gpointer user_data);
  void on_ui_exit();

  // UI session sonrası finalize — output dosyası var ise final image; yoksa
  // user cancelled (orijinal capture kullanılır).
  void finalize_after_ui();

  // Saf finalize (UI flow'suz).
  bool finalize(const std::filesystem::path& image_path);

  SettingsLoader& settings_;
  UiSpawner& ui_spawner_;

  bool busy_{false};

  // Async UI session state'i — busy iken doldurulur, callback temizler.
  std::filesystem::path pending_input_{};
  std::filesystem::path pending_output_{};
};

}  // namespace yakala::daemon
