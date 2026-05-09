import AppKit

/// macOS menu bar tray. NSStatusItem + NSMenu — Linux'taki AppIndicator'ın
/// yerini alır. `LSUIElement = true` daemon'u dock'tan gizler; sadece menu
/// bar'da görünür (1Password, Slack, Telegram pattern).
final class TrayController {
  enum Action {
    case captureFullScreen
    case captureRegion
    case captureWindow
    case openSettings
    case quit
  }

  typealias Handler = (Action) -> Void

  private var statusItem: NSStatusItem?
  private var handler: Handler?

  func install(handler: @escaping Handler) {
    self.handler = handler

    // Square bar height — macOS standardı.
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    // Icon — template image olarak set edilirse macOS dark/light auto adapt eder.
    if let image = loadTrayImage() {
      image.isTemplate = true
      item.button?.image = image
    } else {
      item.button?.title = "Y"
    }
    item.button?.toolTip = "Yakala"

    let menu = NSMenu()
    menu.addItem(makeItem("Tam Ekran Yakala", action: .captureFullScreen))
    menu.addItem(makeItem("Bölge Yakala",     action: .captureRegion))
    menu.addItem(makeItem("Pencere Yakala",   action: .captureWindow))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(makeItem("Ayarlar",          action: .openSettings))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(makeItem("Çıkış",            action: .quit))

    item.menu = menu
    self.statusItem = item
    logInfo("tray", "init tamam")
  }

  func uninstall() {
    if let item = statusItem {
      NSStatusBar.system.removeStatusItem(item)
    }
    statusItem = nil
    handler = nil
  }

  private func makeItem(_ title: String, action: Action) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: #selector(menuClicked(_:)),
                          keyEquivalent: "")
    item.target = self
    item.representedObject = action
    return item
  }

  @objc private func menuClicked(_ sender: NSMenuItem) {
    guard let action = sender.representedObject as? Action else { return }
    logInfo("tray", "menu click \(action)")
    handler?(action)
  }

  /// Tray ikonunu yükler. Bundle içinde Resources/tray-icon.png varsa onu
  /// kullanır; yoksa NSImage(named:) ile system icon fallback.
  private func loadTrayImage() -> NSImage? {
    // Çalışan binary'nin parent dizininde icons/tray.png ara — install
    // layout'una uygun (Yakala.app/Contents/Helpers/icons/tray.png).
    if let exec = Bundle.main.executableURL {
      let candidate = exec
        .deletingLastPathComponent()
        .appendingPathComponent("icons")
        .appendingPathComponent("tray.png")
      if FileManager.default.fileExists(atPath: candidate.path) {
        return NSImage(contentsOf: candidate)
      }
    }
    // Daemon Bundle dışında raw binary olarak çalıştırıldığında (swift run),
    // CWD'ye veya .build dizinine yakın icon ara.
    let cwd = FileManager.default.currentDirectoryPath
    let cwdCandidate = URL(fileURLWithPath: cwd)
      .appendingPathComponent("icons/tray.png")
    if FileManager.default.fileExists(atPath: cwdCandidate.path) {
      return NSImage(contentsOf: cwdCandidate)
    }
    // Son fallback: SF Symbol (macOS 11+).
    return NSImage(systemSymbolName: "camera.viewfinder",
                   accessibilityDescription: "Yakala")
  }
}
