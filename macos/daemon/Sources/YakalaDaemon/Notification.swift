import Foundation
import UserNotifications

/// Native macOS bildirim — UNUserNotificationCenter (modern API).
/// İlk çağrıda kullanıcı izin promptu görür. Reddedilirse fallback yok
/// (eski NSUserNotification deprecate edildi, çalışmıyor).
enum Notif {
  static func requestAuthorization() async {
    let center = UNUserNotificationCenter.current()
    do {
      let granted = try await center.requestAuthorization(options: [.alert, .sound])
      logInfo("notif", "izin: \(granted ? "verildi" : "reddedildi")")
    } catch {
      logWarn("notif", "izin hatası: \(error)")
    }
  }

  static func show(title: String, body: String, imagePath: String? = nil) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default

    // Image attachment — DE/macOS bildirim panelinde küçük thumbnail olarak
    // gösterir.
    if let imagePath = imagePath, FileManager.default.fileExists(atPath: imagePath) {
      let url = URL(fileURLWithPath: imagePath)
      if let attachment = try? UNNotificationAttachment(identifier: "yakala-thumb",
                                                       url: url,
                                                       options: nil) {
        content.attachments = [attachment]
      }
    }

    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil)  // immediate

    UNUserNotificationCenter.current().add(request) { error in
      if let error = error {
        logWarn("notif", "add fail: \(error)")
      }
    }
  }
}
