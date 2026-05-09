import Foundation

/// Capture flow orkestratörü — Linux daemon'undaki CaptureOrchestrator'ın
/// macOS karşılığı. Aynı semantik:
///   1. Re-entry guard (busy_)
///   2. Native capture (sync, ~200-500ms)
///   3. Editor/region UI gerekirse async spawn + termination wait
///   4. Finalize: clipboard + disk + notification
final class CaptureOrchestrator {
  enum Mode {
    case fullScreen
    case region
    case window
  }

  private let settings: SettingsLoader
  private let spawner: UISpawner

  private var busy = false
  private var pendingInput: URL?
  private var pendingOutput: URL?

  init(settings: SettingsLoader, spawner: UISpawner) {
    self.settings = settings
    self.spawner = spawner
  }

  /// Tetikleyici (tray click veya IPC) buradan çağırır.
  func run(mode: Mode) {
    if busy {
      logInfo("orch", "busy — yeni capture reddedildi")
      return
    }
    busy = true
    settings.loadIfChanged()
    let s = settings.current
    logInfo("orch", "capture başlıyor (mode=\(mode), default=\(s.defaultCaptureMode))")

    Task { @MainActor in
      let capturedPath = generateTempPath(prefix: "yakala")
      let captureMode: Capture.Mode = (mode == .window) ? .window : .fullScreen

      let ok = await Capture.capture(captureMode, outPath: capturedPath)
      if !ok {
        if s.notificationsEnabled {
          Notif.show(title: "Yakala",
                     body: "Ekran yakalanamadı. Sistem Ayarları > Gizlilik > Ekran Kaydı'ndan izin verin.")
        }
        busy = false
        return
      }

      let needsRegionUI = (mode == .region)
      let needsEditorUI = (mode != .region) && s.showEditorAfterCapture

      if needsRegionUI {
        let outURL = generateTempPath(prefix: "yakala_region")
        spawnUI(uiMode: "region", input: capturedPath, output: outURL)
        return
      }
      if needsEditorUI {
        let outURL = generateTempPath(prefix: "yakala_edit")
        spawnUI(uiMode: "editor", input: capturedPath, output: outURL)
        return
      }
      finalize(image: capturedPath)
      busy = false
    }
  }

  private func spawnUI(uiMode: String, input: URL, output: URL) {
    pendingInput = input
    pendingOutput = output
    let args = [
      "--mode=\(uiMode)",
      "--input=\(input.path)",
      "--output=\(output.path)",
    ]
    let proc = spawner.spawn(args: args) { [weak self] _ in
      self?.onUIExit()
    }
    if proc == nil {
      logWarn("orch", "UI spawn fail, fallback finalize")
      finalize(image: input)
      busy = false
      pendingInput = nil
      pendingOutput = nil
    } else {
      logInfo("orch", "UI spawned (\(uiMode)), waiting...")
    }
  }

  private func onUIExit() {
    logInfo("orch", "UI exit")
    guard let output = pendingOutput else {
      busy = false
      return
    }
    if FileManager.default.fileExists(atPath: output.path) {
      finalize(image: output)
      // Orijinal capture temp'i temizle.
      if let inp = pendingInput, inp != output {
        try? FileManager.default.removeItem(at: inp)
      }
    } else {
      logInfo("orch", "UI cancel — capture vazgeçildi")
      // Output yok = user cancelled. Input'u da temizle.
      if let inp = pendingInput {
        try? FileManager.default.removeItem(at: inp)
      }
    }
    pendingInput = nil
    pendingOutput = nil
    busy = false
  }

  @discardableResult
  private func finalize(image: URL) -> Bool {
    let s = settings.current
    let clipboardOK = Clipboard.copyPNGImage(from: image)

    var savedTo: URL?
    if !s.savePath.isEmpty {
      let dir = expandHome(s.savePath)
      try? FileManager.default.createDirectory(
        atPath: dir.path, withIntermediateDirectories: true)
      let dest = dir.appendingPathComponent(image.lastPathComponent)
      do {
        if FileManager.default.fileExists(atPath: dest.path) {
          try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: image, to: dest)
        savedTo = dest
        logInfo("orch", "disk'e kaydedildi: \(dest.path)")
      } catch {
        logWarn("orch", "disk kaydı başarısız: \(error)")
      }
    }

    if s.notificationsEnabled {
      let body: String
      switch (clipboardOK, savedTo) {
      case (false, nil): body = "Yakalandı ama kaydedilemedi."
      case (true, .some): body = "Panoya kopyalandı ve diske kaydedildi."
      case (true, nil): body = "Görüntü panoya kopyalandı."
      case (false, .some(let p)): body = "Diske kaydedildi: \(p.lastPathComponent)"
      }
      Notif.show(title: "Yakala", body: body, imagePath: image.path)
    }

    return clipboardOK || savedTo != nil
  }

  // ────────────────── Helpers ──────────────────

  private func generateTempPath(prefix: String) -> URL {
    let ms = Int64(Date().timeIntervalSince1970 * 1000)
    let tmpDir = FileManager.default.temporaryDirectory
    return tmpDir.appendingPathComponent("\(prefix)_\(ms).png")
  }

  private func expandHome(_ path: String) -> URL {
    if path.hasPrefix("~") {
      let home = FileManager.default.homeDirectoryForCurrentUser
      let suffix = path == "~" ? "" : String(path.dropFirst(path.hasPrefix("~/") ? 2 : 1))
      return home.appendingPathComponent(suffix)
    }
    return URL(fileURLWithPath: path)
  }
}
