import Foundation

/// Tek-satır, thread-safe stderr logger. YAKALA_LOG env değişkeni ile
/// seviye kontrolü (debug/info/warn/error). Linux daemon'undaki Logger
/// sınıfının Swift karşılığı — aynı output formatı (ortak log analizi için).
enum LogLevel: Int, Comparable {
  case debug = 0
  case info = 1
  case warn = 2
  case error = 3

  var label: String {
    switch self {
    case .debug: return "DEBUG"
    case .info:  return "INFO "
    case .warn:  return "WARN "
    case .error: return "ERROR"
    }
  }

  static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
    return lhs.rawValue < rhs.rawValue
  }
}

enum Logger {
  // Atomic level — env init'te bir kez okunur.
  private static let level: LogLevel = {
    let env = ProcessInfo.processInfo.environment["YAKALA_LOG"] ?? "info"
    switch env.lowercased() {
    case "debug": return .debug
    case "warn", "warning": return .warn
    case "error": return .error
    default: return .info
    }
  }()

  // Stderr write için lock — birden çok thread aynı anda yazarsa satır atomicity.
  private static let lock = NSLock()

  static func log(_ msgLevel: LogLevel, tag: String, _ message: String) {
    guard msgLevel >= level else { return }
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    let timestamp = formatter.string(from: Date())
    let line = "[\(timestamp)] \(msgLevel.label) [Yakala/\(tag)] \(message)\n"
    lock.lock()
    FileHandle.standardError.write(line.data(using: .utf8) ?? Data())
    lock.unlock()
  }
}

// Convenience macros — Swift'te func ile.
@inlinable
func logDebug(_ tag: String, _ message: @autoclosure () -> String) {
  Logger.log(.debug, tag: tag, message())
}
@inlinable
func logInfo(_ tag: String, _ message: @autoclosure () -> String) {
  Logger.log(.info, tag: tag, message())
}
@inlinable
func logWarn(_ tag: String, _ message: @autoclosure () -> String) {
  Logger.log(.warn, tag: tag, message())
}
@inlinable
func logError(_ tag: String, _ message: @autoclosure () -> String) {
  Logger.log(.error, tag: tag, message())
}
