import Foundation

/// Daemon ile UI arasında paylaşılan ayar deposu.
/// Yol: ~/Library/Application Support/Yakala/settings.json
///
/// UI atomic write yapar (tmp + rename); daemon mtime check ile her capture
/// öncesinde reload eder. Linux daemon'undaki SettingsLoader'ın aynısı,
/// path farkı.
struct Settings: Codable {
  var defaultCaptureMode: String = "fullScreen"
  var showEditorAfterCapture: Bool = true
  var soundEffect: Bool = true
  var notificationsEnabled: Bool = true
  var savePath: String = ""

  enum CodingKeys: String, CodingKey {
    case defaultCaptureMode = "default_capture_mode"
    case showEditorAfterCapture = "show_editor_after_capture"
    case soundEffect = "sound_effect"
    case notificationsEnabled = "notifications_enabled"
    case savePath = "save_path"
  }
}

final class SettingsLoader {
  let path: URL
  private(set) var current = Settings()
  private var lastMtime: Date?

  init() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    self.path = home
      .appendingPathComponent("Library")
      .appendingPathComponent("Application Support")
      .appendingPathComponent("Yakala")
      .appendingPathComponent("settings.json")
  }

  /// Diskten oku. Hata olursa default değerler — log ile uyarı.
  @discardableResult
  func load() -> Settings {
    guard FileManager.default.fileExists(atPath: path.path) else {
      logInfo("settings", "dosya yok, default kullanılıyor: \(path.path)")
      return current
    }
    do {
      let data = try Data(contentsOf: path)
      let decoded = try JSONDecoder().decode(Settings.self, from: data)
      current = decoded

      // mtime'ı yakala
      let attrs = try FileManager.default.attributesOfItem(atPath: path.path)
      lastMtime = attrs[.modificationDate] as? Date
    } catch {
      logWarn("settings", "load hatası (default kullanılıyor): \(error)")
    }
    return current
  }

  /// mtime değişmişse reload. Her capture öncesinde çağrılır (cheap).
  @discardableResult
  func loadIfChanged() -> Settings {
    guard FileManager.default.fileExists(atPath: path.path) else {
      return current
    }
    do {
      let attrs = try FileManager.default.attributesOfItem(atPath: path.path)
      let currentMtime = attrs[.modificationDate] as? Date
      if let last = lastMtime, let now = currentMtime, last == now {
        return current
      }
      logDebug("settings", "mtime değişti, reload")
      load()
    } catch {
      // mtime alınamadı — cache'i koru.
    }
    return current
  }
}
