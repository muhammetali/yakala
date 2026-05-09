import AppKit
import CoreGraphics
import Foundation

#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

/// macOS native screen capture.
///
/// Strateji:
///   1. ScreenCaptureKit (macOS 12.3+) — modern, sandboxed, izin gerekiyor
///      ama kullanıcı ilk kullanımda Sistem Ayarları > Gizlilik > Ekran
///      Kaydı'ndan onaylar. Native API, en yüksek kalite.
///   2. CGWindowListCreateImage fallback — eski API, izin sorunsuz ama
///      sınırlı (örn. zoom-in screen detayı yakalayamaz). Yedek olarak
///      tutarız.
///
/// macOS sandbox policy'si ekran kaydı izni ister; izin yoksa first-launch'ta
/// kullanıcıya prompt gösterilir. Eğer kullanıcı izin reddi, capture
/// fonksiyonu nil/false döner — orchestrator notification ile bilgilendirir.
enum Capture {
  enum Mode {
    case fullScreen
    case window  // aktif pencere
  }

  /// PNG'yi `outPath`'e yazar. Başarılı ise true.
  static func capture(_ mode: Mode, outPath: URL) async -> Bool {
    switch mode {
    case .fullScreen:
      return await captureFullScreen(outPath: outPath)
    case .window:
      return await captureActiveWindow(outPath: outPath)
    }
  }

  /// Tam ekran. Önce ScreenCaptureKit, sonra CGWindowListCreateImage fallback.
  private static func captureFullScreen(outPath: URL) async -> Bool {
    #if canImport(ScreenCaptureKit)
    if #available(macOS 12.3, *) {
      do {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
          logWarn("capture", "ScreenCaptureKit: display yok")
          return await captureCGFallback(outPath: outPath)
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.scalesToFit = false
        config.showsCursor = false

        let cgImage = try await SCScreenshotManager.captureImage(
          contentFilter: filter,
          configuration: config)
        return writePNG(cgImage: cgImage, to: outPath)
      } catch {
        logWarn("capture", "ScreenCaptureKit başarısız: \(error)")
      }
    }
    #endif
    return await captureCGFallback(outPath: outPath)
  }

  private static func captureActiveWindow(outPath: URL) async -> Bool {
    #if canImport(ScreenCaptureKit)
    if #available(macOS 12.3, *) {
      do {
        let content = try await SCShareableContent.current
        // Aktif pencereyi bul: NSWorkspace.shared.frontmostApplication +
        // bu uygulamanın window'larından ön planda olanı.
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
          return await captureFullScreen(outPath: outPath)
        }
        let pid = frontApp.processIdentifier
        let appWindows = content.windows.filter {
          $0.owningApplication?.processID == pid
        }
        guard let topWindow = appWindows.first else {
          return await captureFullScreen(outPath: outPath)
        }
        guard let display = content.displays.first else {
          return false
        }
        let filter = SCContentFilter(display: display,
                                     including: [topWindow])
        let config = SCStreamConfiguration()
        config.width = Int(topWindow.frame.width)
        config.height = Int(topWindow.frame.height)
        config.showsCursor = false

        let cgImage = try await SCScreenshotManager.captureImage(
          contentFilter: filter,
          configuration: config)
        return writePNG(cgImage: cgImage, to: outPath)
      } catch {
        logWarn("capture", "Window capture başarısız: \(error)")
      }
    }
    #endif
    return await captureFullScreen(outPath: outPath)
  }

  private static func captureCGFallback(outPath: URL) async -> Bool {
    // CGWindowListCreateImage main display ID ile.
    let displayID = CGMainDisplayID()
    guard let cgImage = CGDisplayCreateImage(displayID) else {
      logError("capture", "CGDisplayCreateImage nil")
      return false
    }
    return writePNG(cgImage: cgImage, to: outPath)
  }

  private static func writePNG(cgImage: CGImage, to outPath: URL) -> Bool {
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
      logError("capture", "PNG encode başarısız")
      return false
    }
    do {
      try pngData.write(to: outPath, options: .atomic)
      logInfo("capture", "yakalama başarılı: \(outPath.path)")
      return true
    } catch {
      logError("capture", "PNG yazma hatası: \(error)")
      return false
    }
  }
}
