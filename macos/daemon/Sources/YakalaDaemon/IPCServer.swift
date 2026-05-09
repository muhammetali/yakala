import Foundation
import Network

/// Daemon'un Unix domain socket sunucusu — JSON line-delimited protokol
/// (Linux daemon'uyla aynı format). Network framework'ün NWListener'ı
/// üzerine kurulu — main loop entegrasyonu macOS'ta GCD üzerinden olur.
///
/// Mesaj formatı:
///   { "cmd": "capture_full" | "capture_region" | "capture_window" |
///            "show_settings" | "ping" | "ui_result" }
///
/// Tek-yönlü protokol — server response yok (sadece "ping" cevap dönecek
/// ileride). UI'den gelen `ui_result` editor flow callback'inde işlenir.
final class IPCServer {
  typealias CommandHandler = (_ cmd: String, _ rawJson: String) -> Void

  private(set) var socketURL: URL
  private var listener: NWListener?
  private var handler: CommandHandler?
  private let queue = DispatchQueue(label: "com.yakala.ipc", qos: .userInitiated)

  init() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    self.socketURL = home
      .appendingPathComponent("Library")
      .appendingPathComponent("Application Support")
      .appendingPathComponent("Yakala")
      .appendingPathComponent("daemon.sock")
  }

  /// Aynı socket'e connect denemesi başarılı ise başka bir daemon zaten
  /// çalışıyor demektir. Daemon main()'in ilk satırlarında çağrılır —
  /// duplicate instance engellenir.
  static func anotherInstanceRunning() -> Bool {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let url = home
      .appendingPathComponent("Library")
      .appendingPathComponent("Application Support")
      .appendingPathComponent("Yakala")
      .appendingPathComponent("daemon.sock")
    guard FileManager.default.fileExists(atPath: url.path) else {
      return false
    }
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { Darwin.close(fd) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let path = url.path
    _ = path.withCString { src in
      withUnsafeMutablePointer(to: &addr.sun_path) {
        $0.withMemoryRebound(to: CChar.self,
                             capacity: MemoryLayout.size(ofValue: addr.sun_path)) {
          strncpy($0, src, MemoryLayout.size(ofValue: addr.sun_path) - 1)
        }
      }
    }
    let len = socklen_t(MemoryLayout<sockaddr_un>.size)
    let result = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(fd, $0, len)
      }
    }
    return result == 0
  }

  /// Sunucuyu başlat. Başarısız ise throw — main bunu fatal sayar.
  func start(handler: @escaping CommandHandler) throws {
    self.handler = handler

    // Stale socket dosyasını sil (varsa).
    try? FileManager.default.removeItem(at: socketURL)

    // Parent dizini oluştur.
    try FileManager.default.createDirectory(
      at: socketURL.deletingLastPathComponent(),
      withIntermediateDirectories: true)

    // NWEndpoint.Host(.unix(...)) Network framework'te direkt yok — alt
    // seviye Darwin.socket + bind + listen kullanıyoruz, sonra NWConnection
    // ile accept loop. Daha modern alternatif `NWListener.using(parameters)`
    // ama Unix domain socket için dökümentasyon zayıf.
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
      throw NSError(domain: "yakala.ipc", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "socket() fail"])
    }

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
    let bindRC = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(fd, $0, len)
      }
    }
    if bindRC != 0 {
      Darwin.close(fd)
      throw NSError(domain: "yakala.ipc", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "bind fail: \(String(cString: strerror(errno)))"])
    }
    // 0600 permission — aynı user dışındaki kullanıcılara kapalı.
    chmod(socketURL.path, 0o600)

    if Darwin.listen(fd, 16) != 0 {
      Darwin.close(fd)
      throw NSError(domain: "yakala.ipc", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "listen fail"])
    }

    // Accept loop GCD üzerinde — her client tek-yönlü mesaj gönderip kapanır.
    queue.async { [weak self] in
      while true {
        let clientFd = Darwin.accept(fd, nil, nil)
        if clientFd < 0 {
          if errno == EINTR { continue }
          break
        }
        self?.handleClient(clientFd)
      }
      Darwin.close(fd)
    }

    logInfo("ipc", "dinleniyor: \(socketURL.path)")
  }

  private func handleClient(_ fd: Int32) {
    defer { Darwin.close(fd) }
    var buffer = [UInt8](repeating: 0, count: 4096)
    var accumulated = Data()
    while true {
      let n = Darwin.read(fd, &buffer, buffer.count)
      if n <= 0 { break }
      accumulated.append(buffer, count: n)
      if let nl = accumulated.firstIndex(of: 0x0A) {  // newline = mesaj sonu
        let line = accumulated.prefix(nl)
        if let str = String(data: line, encoding: .utf8) {
          processLine(str)
        }
        break
      }
      if accumulated.count > 64 * 1024 {
        logWarn("ipc", "mesaj çok büyük, drop")
        break
      }
    }
  }

  private func processLine(_ line: String) {
    logDebug("ipc", "raw: \(line)")
    guard let data = line.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let cmd = obj["cmd"] as? String, !cmd.isEmpty else {
      logWarn("ipc", "JSON parse hatası veya cmd alanı yok")
      return
    }
    handler?(cmd, line)
  }

  func stop() {
    listener?.cancel()
    listener = nil
    try? FileManager.default.removeItem(at: socketURL)
    logInfo("ipc", "durduruldu")
  }
}
