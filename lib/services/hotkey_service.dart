import 'package:flutter/foundation.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:yakala/models/hotkey_config.dart';

/// Global kısayol kaydını yönetir. Sadece kendi tuttuğu hotkey'i unregister eder
/// (`unregisterAll` kullanmaz — başka plugin hotkey'lerini kırmamak için).
class HotkeyService {
  HotKey? _registered;
  Future<void> Function()? _onTrigger;

  /// Başarılı registrationda true; OS başka uygulamaya tahsis ettiyse / paket
  /// hata fırlattıysa false.
  Future<bool> register(
    HotkeyConfig config,
    Future<void> Function() onTrigger,
  ) async {
    // Önce eski hotkey'i kaldır (varsa)
    await _unregisterCurrent();

    final hotKey = config.toHotKey();
    _onTrigger = onTrigger;
    try {
      await hotKeyManager.register(
        hotKey,
        keyDownHandler: (_) async {
          final cb = _onTrigger;
          if (cb != null) await cb();
        },
      );
      _registered = hotKey;
      return true;
    } catch (e) {
      debugPrint('HotkeyService: registration başarısız: $e');
      _registered = null;
      return false;
    }
  }

  /// Mevcut callback'i koruyarak yeni config ile re-register.
  /// true = yeni hotkey aktif; false = başarısız (eski hotkey de kayıtsız).
  Future<bool> update(HotkeyConfig config) async {
    final cb = _onTrigger;
    if (cb == null) return false;
    return register(config, cb);
  }

  Future<void> _unregisterCurrent() async {
    final prev = _registered;
    if (prev == null) return;
    try {
      await hotKeyManager.unregister(prev);
    } catch (e) {
      debugPrint('HotkeyService: unregister hatası (yutuldu): $e');
    }
    _registered = null;
  }

  Future<void> dispose() async {
    await _unregisterCurrent();
    _onTrigger = null;
  }
}
