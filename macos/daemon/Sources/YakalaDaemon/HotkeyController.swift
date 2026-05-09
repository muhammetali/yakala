import AppKit
import Carbon.HIToolbox
import Foundation

/// Global hotkey manager — Carbon RegisterEventHotKey API.
///
/// **Neden Carbon, neden NSEvent değil**: NSEvent.addGlobalMonitorForEvents
/// çalışıyor ama sandbox/Universal Access altında izin gerektirir ve daemon
/// app'lerde pratikte güvenilmez. Carbon RegisterEventHotKey eski ama "her
/// zaman çalışıyor" — Apple deprecate etmedi.
///
/// macOS user'ın hotkey customization'ı: install scripti varsayılan
/// Cmd+Shift+C'yi register eder. Kullanıcı değiştirmek isterse bu Settings
/// UI'sinde değil, **bizim daemon'umuzun config dosyasında** veya yeni
/// build'de yapılır (System Settings > Klavye > Kısayollar Apple'ın
/// kendi shortcut sistemi olduğu için Carbon'la entegre edilemez).
///
/// Şimdilik hardcoded ⌘⇧C — Faz 6'da settings.json'a hotkey alanı ekleyip
/// daemon başlangıcında bind edilebilir.
final class HotkeyController {
  typealias Handler = () -> Void

  private var hotKeyRef: EventHotKeyRef?
  private var handlerRef: EventHandlerRef?
  private var handler: Handler?

  // unique signature — 4-char code, başkalarıyla çakışmaması için.
  private let signature: OSType = {
    let chars: [UInt8] = [Character("Y").asciiValue!,
                          Character("k").asciiValue!,
                          Character("l").asciiValue!,
                          Character("a").asciiValue!]
    return (OSType(chars[0]) << 24) | (OSType(chars[1]) << 16) |
           (OSType(chars[2]) << 8)  |  OSType(chars[3])
  }()

  func register(handler: @escaping Handler) -> Bool {
    self.handler = handler
    var hotkeyId = EventHotKeyID(signature: signature, id: 1)

    // Cmd+Shift+C
    let keyCode: UInt32 = UInt32(kVK_ANSI_C)
    let modifiers: UInt32 = UInt32(cmdKey | shiftKey)

    var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                  eventKind: UInt32(kEventHotKeyPressed))

    // Static C callback — context olarak self pointer geçeriz.
    let selfPtr = Unmanaged.passUnretained(self).toOpaque()
    let cb: EventHandlerUPP = { (nextHandler, theEvent, userData) -> OSStatus in
      guard let userData = userData else { return noErr }
      let me = Unmanaged<HotkeyController>.fromOpaque(userData).takeUnretainedValue()
      me.handler?()
      return noErr
    }
    let installRC = InstallEventHandler(GetApplicationEventTarget(),
                                        cb, 1, &eventType,
                                        selfPtr, &handlerRef)
    if installRC != noErr {
      logError("hotkey", "InstallEventHandler fail: \(installRC)")
      return false
    }

    let registerRC = RegisterEventHotKey(keyCode, modifiers, hotkeyId,
                                         GetApplicationEventTarget(),
                                         0, &hotKeyRef)
    if registerRC != noErr {
      logError("hotkey", "RegisterEventHotKey fail: \(registerRC) — başka uygulama ⌘⇧C kullanıyor olabilir")
      return false
    }
    logInfo("hotkey", "registered ⌘⇧C")
    return true
  }

  func unregister() {
    if let ref = hotKeyRef {
      UnregisterEventHotKey(ref)
      hotKeyRef = nil
    }
    if let ref = handlerRef {
      RemoveEventHandler(ref)
      handlerRef = nil
    }
    handler = nil
  }

  deinit { unregister() }
}
