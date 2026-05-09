// Yakala macOS Native Daemon — entry point.
//
// Mimari Linux daemon ile simetrik:
//   tray (NSStatusItem) → IPC server (Unix socket) → capture (ScreenCaptureKit)
//                       → UI spawner (Process / yakala-ui)
//                       → settings loader (JSON file)
//
// CLI client mode: aynı binary `--capture-fullscreen` vb. flag'lerle
// çalışırsa çalışan daemon'a IPC ile komut yollar, exit eder. Cmd+Shift+C
// shortcut bu pattern'i kullanmaz (Carbon RegisterEventHotKey direkt
// daemon process'inde alır) — ama bash scriptleri / üçüncü-parti tools
// bu CLI'ı kullanabilir.

import AppKit
import Foundation

// CLI arg parsing — daemon mode mu yoksa client mode mu?
let args = CommandLine.arguments

func sendIPC(_ cmd: String) -> Int32 {
  let home = FileManager.default.homeDirectoryForCurrentUser
  let socketURL = home
    .appendingPathComponent("Library")
    .appendingPathComponent("Application Support")
    .appendingPathComponent("Yakala")
    .appendingPathComponent("daemon.sock")
  guard FileManager.default.fileExists(atPath: socketURL.path) else {
    FileHandle.standardError.write("yakala-daemon: çalışan daemon yok\n".data(using: .utf8) ?? Data())
    return 1
  }

  let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
  guard fd >= 0 else { return 1 }
  defer { Darwin.close(fd) }

  var addr = sockaddr_un()
  addr.sun_family = sa_family_t(AF_UNIX)
  _ = socketURL.path.withCString { src in
    withUnsafeMutablePointer(to: &addr.sun_path) {
      $0.withMemoryRebound(to: CChar.self,
                           capacity: MemoryLayout.size(ofValue: addr.sun_path)) {
        strncpy($0, src, MemoryLayout.size(ofValue: addr.sun_path) - 1)
      }
    }
  }
  let len = socklen_t(MemoryLayout<sockaddr_un>.size)
  let rc = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      Darwin.connect(fd, $0, len)
    }
  }
  if rc != 0 {
    FileHandle.standardError.write("yakala-daemon: connect fail\n".data(using: .utf8) ?? Data())
    return 1
  }
  let msg = "{\"cmd\":\"\(cmd)\"}\n"
  guard let data = msg.data(using: .utf8) else { return 1 }
  let n = data.withUnsafeBytes { ptr -> ssize_t in
    return Darwin.send(fd, ptr.baseAddress, data.count, 0)
  }
  return n == data.count ? 0 : 1
}

for arg in args.dropFirst() {
  switch arg {
  case "--capture-fullscreen": exit(sendIPC("capture_full"))
  case "--capture-region":     exit(sendIPC("capture_region"))
  case "--capture-window":     exit(sendIPC("capture_window"))
  case "--show-settings":      exit(sendIPC("show_settings"))
  case "--ping":               exit(sendIPC("ping"))
  case "--help", "-h":
    print("""
yakala-daemon — Yakala native daemon (macOS)

Kullanım:
  yakala-daemon                        # daemon mode (autostart)
  yakala-daemon --capture-fullscreen   # IPC: tam ekran yakala
  yakala-daemon --capture-region       # IPC: bölge yakala
  yakala-daemon --capture-window       # IPC: pencere yakala
  yakala-daemon --show-settings        # IPC: ayarları aç
  yakala-daemon --ping                 # daemon canlı mı

Env:
  YAKALA_LOG=debug|info|warn|error
  YAKALA_UI=<path>                     # UI binary override
""")
    exit(0)
  default: break
  }
}

// Daemon mode başlatma.
logInfo("main", "yakala-daemon başlıyor")

if IPCServer.anotherInstanceRunning() {
  logInfo("main", "başka bir daemon zaten çalışıyor, çıkılıyor")
  exit(0)
}

// AppKit lifecycle — NSApplication açılmadan tray çalışmaz.
let app = NSApplication.shared
// LSUIElement Info.plist'ten geliyor olmalı; runtime'da activation policy:
app.setActivationPolicy(.accessory)

// Bildirim izni iste (async — kullanıcı kabul ederse sonraki bildirimler
// görünür).
Task {
  await Notif.requestAuthorization()
}

let settings = SettingsLoader()
settings.load()

let spawner = UISpawner()
let orchestrator = CaptureOrchestrator(settings: settings, spawner: spawner)

// Tray.
let tray = TrayController()
tray.install { action in
  switch action {
  case .captureFullScreen: orchestrator.run(mode: .fullScreen)
  case .captureRegion:     orchestrator.run(mode: .region)
  case .captureWindow:     orchestrator.run(mode: .window)
  case .openSettings:
    _ = spawner.spawn(args: ["--mode=settings"]) { _ in }
  case .quit:
    NSApp.terminate(nil)
  }
}

// Hotkey.
let hotkey = HotkeyController()
let registered = hotkey.register {
  orchestrator.run(mode: .fullScreen)
}
if !registered {
  logWarn("hotkey", "Cmd+Shift+C kayıt başarısız — başka uygulama kullanıyor olabilir")
}

// IPC.
let ipc = IPCServer()
do {
  try ipc.start { cmd, _ in
    DispatchQueue.main.async {
      switch cmd {
      case "capture_full":   orchestrator.run(mode: .fullScreen)
      case "capture_region": orchestrator.run(mode: .region)
      case "capture_window": orchestrator.run(mode: .window)
      case "show_settings":
        _ = spawner.spawn(args: ["--mode=settings"]) { _ in }
      case "ping": break
      case "ui_result":
        // Editor/region UI sonucu — orchestrator'un kendi terminationHandler'ı
        // halleder. Bu mesaj UI'den geliyor ama orchestrator çoktan dosya
        // kontrol etmiş olacak.
        break
      default:
        logWarn("ipc", "bilinmeyen cmd: \(cmd)")
      }
    }
  }
} catch {
  logError("ipc", "start fail: \(error) — daemon yine de tray ile çalışır")
}

logInfo("main", "main loop başladı")
app.run()  // Bloke — Cmd+Q veya tray Çıkış'tan çıkış.

logInfo("main", "main loop bitti, temizlik")
ipc.stop()
hotkey.unregister()
tray.uninstall()
