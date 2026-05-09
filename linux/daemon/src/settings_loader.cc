#include "settings_loader.hh"

#include <cstdlib>
#include <fstream>
#include <sstream>
#include <system_error>

#include <nlohmann/json.hpp>

#include "logger.hh"

namespace yakala::daemon {

namespace fs = std::filesystem;
using nlohmann::json;

SettingsLoader::SettingsLoader() : path_(resolve_path()) {}

fs::path SettingsLoader::resolve_path() {
  // XDG Base Directory Specification: $XDG_CONFIG_HOME varsa onu kullan,
  // yoksa $HOME/.config. macOS'tan farklı (orada Application Support
  // tercih edilir, ama bu Linux daemon'u).
  const char* xdg_config = std::getenv("XDG_CONFIG_HOME");
  fs::path base;
  if (xdg_config && *xdg_config) {
    base = xdg_config;
  } else {
    const char* home = std::getenv("HOME");
    if (!home || !*home) {
      // Edge case: HOME yok (servis modunda olabilir). Tmp'e fall back.
      return fs::path("/tmp/yakala/settings.json");
    }
    base = fs::path(home) / ".config";
  }
  return base / "yakala" / "settings.json";
}

Settings SettingsLoader::load() {
  Settings result{};
  std::error_code ec;
  if (!fs::exists(path_, ec) || ec) {
    YAKALA_LOG_INFO("settings") << "dosya yok, default kullanılıyor: " << path_.string();
    last_mtime_ = std::nullopt;
    cached_ = result;
    return result;
  }

  std::ifstream in(path_);
  if (!in) {
    YAKALA_LOG_WARN("settings") << "dosya açılamadı: " << path_.string();
    cached_ = result;
    return result;
  }

  std::stringstream buffer;
  buffer << in.rdbuf();
  const std::string content = buffer.str();
  if (content.empty()) {
    YAKALA_LOG_WARN("settings") << "dosya boş, default kullanılıyor";
    cached_ = result;
    return result;
  }

  try {
    auto j = json::parse(content);
    if (j.contains("default_capture_mode") && j["default_capture_mode"].is_string()) {
      result.default_capture_mode = j["default_capture_mode"].get<std::string>();
    }
    if (j.contains("show_editor_after_capture") && j["show_editor_after_capture"].is_boolean()) {
      result.show_editor_after_capture = j["show_editor_after_capture"].get<bool>();
    }
    if (j.contains("sound_effect") && j["sound_effect"].is_boolean()) {
      result.sound_effect = j["sound_effect"].get<bool>();
    }
    if (j.contains("notifications_enabled") && j["notifications_enabled"].is_boolean()) {
      result.notifications_enabled = j["notifications_enabled"].get<bool>();
    }
    if (j.contains("save_path") && j["save_path"].is_string()) {
      result.save_path = j["save_path"].get<std::string>();
    }
  } catch (const json::exception& e) {
    YAKALA_LOG_WARN("settings") << "JSON parse hatası: " << e.what();
    // result default state'inde kalır.
  }

  // mtime'ı kaydet (lazy reload için).
  last_mtime_ = fs::last_write_time(path_, ec);
  if (ec) {
    last_mtime_ = std::nullopt;
  }

  cached_ = result;
  return result;
}

const Settings& SettingsLoader::load_if_changed() {
  std::error_code ec;
  if (!fs::exists(path_, ec) || ec) {
    return cached_;
  }
  const auto current_mtime = fs::last_write_time(path_, ec);
  if (ec) {
    // mtime alınamadı — cache'i koru, log yazma (gürültülü olur).
    return cached_;
  }
  if (last_mtime_ && *last_mtime_ == current_mtime) {
    return cached_;
  }
  YAKALA_LOG_DEBUG("settings") << "mtime değişti, reload";
  load();
  return cached_;
}

}  // namespace yakala::daemon
