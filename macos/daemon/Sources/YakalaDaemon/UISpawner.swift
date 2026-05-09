import Foundation

/// Flutter UI binary'sini spawn eder. Bundle layout:
///   Yakala.app/Contents/MacOS/Yakala (Flutter UI ana binary)
///   Yakala.app/Contents/Helpers/yakala-daemon (bu daemon)
///
/// Daemon /Contents/Helpers/'ten çalıştığı için UI binary'si
/// `../MacOS/Yakala` yolunda. Standart pattern: `Process` ile spawn,
/// terminationHandler ile callback.
final class UISpawner {
  let uiBinaryURL: URL

  init() {
    self.uiBinaryURL = UISpawner.resolveBinary()
  }

  static func resolveBinary() -> URL {
    if let env = ProcessInfo.processInfo.environment["YAKALA_UI"], !env.isEmpty {
      return URL(fileURLWithPath: env)
    }
    // Daemon binary'sinin yanı: ../MacOS/Yakala
    if let exec = Bundle.main.executableURL {
      let helpersDir = exec.deletingLastPathComponent()  // .../Helpers
      let macosDir = helpersDir.deletingLastPathComponent()
        .appendingPathComponent("MacOS")
      let candidate = macosDir.appendingPathComponent("Yakala")
      if FileManager.default.fileExists(atPath: candidate.path) {
        return candidate
      }
    }
    // SPM dev modu (swift run): build/release/yakala-ui veya CWD/yakala-ui
    let cwd = FileManager.default.currentDirectoryPath
    return URL(fileURLWithPath: cwd).appendingPathComponent("yakala-ui")
  }

  /// UI'yi async spawn eder. terminationHandler exit edince çağrılır —
  /// daemon orchestrator burada finalize çalıştırır.
  /// `nil` döner spawn fail; aksi halde Process — caller terminationHandler
  /// ekleyebilir.
  func spawn(args: [String], onExit: @escaping (Int32) -> Void) -> Process? {
    let process = Process()
    process.executableURL = uiBinaryURL
    process.arguments = args

    process.terminationHandler = { proc in
      DispatchQueue.main.async {
        onExit(proc.terminationStatus)
      }
    }

    do {
      try process.run()
      logInfo("spawn", "exec \(uiBinaryURL.path) (\(args.count) args, pid=\(process.processIdentifier))")
      return process
    } catch {
      logError("spawn", "spawn fail: \(error)")
      return nil
    }
  }
}
