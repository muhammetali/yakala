import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Sistem başlangıcında otomatik çalıştırma yönetimi.
///
/// Dev mode'da disabled — `Platform.resolvedExecutable` debug build'de Dart
/// VM binary'sini gösteriyor, autostart yanlış path'e işaret ederdi.
class AutostartService {
  bool _initialized = false;

  /// Dev modda autostart kullanılamaz; UI bunu disabled olarak göstermeli.
  bool get isSupported => kReleaseMode;

  Future<void> initialize() async {
    if (_initialized || !isSupported) return;
    try {
      final info = await PackageInfo.fromPlatform();
      launchAtStartup.setup(
        appName: info.appName.isEmpty ? 'Yakala' : info.appName,
        appPath: Platform.resolvedExecutable,
        packageName: info.packageName.isEmpty ? 'yakala' : info.packageName,
      );
      _initialized = true;
    } catch (e) {
      debugPrint('Autostart kurulum hatası: $e');
    }
  }

  Future<void> setEnabled(bool enabled) async {
    if (!isSupported) {
      debugPrint('Autostart dev modda devre dışı.');
      return;
    }
    if (!_initialized) await initialize();
    try {
      if (enabled) {
        await launchAtStartup.enable();
      } else {
        await launchAtStartup.disable();
      }
    } catch (e) {
      debugPrint('Autostart toggle hatası: $e');
    }
  }

  Future<bool> isEnabled() async {
    if (!isSupported) return false;
    if (!_initialized) await initialize();
    try {
      return await launchAtStartup.isEnabled();
    } catch (e) {
      debugPrint('Autostart durum okuma hatası: $e');
      return false;
    }
  }
}
