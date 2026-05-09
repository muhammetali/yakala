import AppKit
import Foundation

/// macOS clipboard yardımcısı — NSPasteboard üstünde PNG image. Linux'taki
/// xclip/wl-copy fork-pattern hack'i macOS'ta gerekmez; AppKit clean API.
enum Clipboard {
  @discardableResult
  static func copyPNGImage(from path: URL) -> Bool {
    guard let data = try? Data(contentsOf: path) else {
      logWarn("clipboard", "PNG okunamadı: \(path.path)")
      return false
    }
    guard let image = NSImage(data: data) else {
      logWarn("clipboard", "NSImage init başarısız")
      return false
    }
    let pb = NSPasteboard.general
    pb.clearContents()
    let ok = pb.writeObjects([image])
    if ok {
      logInfo("clipboard", "PNG → clipboard")
    } else {
      logWarn("clipboard", "clipboard write fail")
    }
    return ok
  }
}
