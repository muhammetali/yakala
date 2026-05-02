import 'dart:io';
import 'package:flutter/foundation.dart';

import '../utils/powershell.dart';

/// Yakalama sonrası deklanşör sesi. Native sound theme dosyalarını kullanır,
/// ek paket eklemez. Process'leri DETACHED modda başlatır — sound async
/// olarak çalar, app process'i bekletmez ve zombi process bırakmaz.
/// settings.soundEffect kapalıysa hiç çağrılmaz.
class SoundService {
  static const _linuxCandidates = [
    '/usr/share/sounds/freedesktop/stereo/screen-capture.oga',
    '/usr/share/sounds/freedesktop/stereo/camera-shutter.oga',
    '/usr/share/sounds/Yaru/stereo/screen-capture.oga',
  ];

  // Çift tetiklenme koruması: 800ms içinde ikinci çağrı no-op.
  static DateTime? _lastPlayed;
  static const _cooldown = Duration(milliseconds: 800);

  /// Test seam: cooldown state'ini sıfırlar.
  @visibleForTesting
  static void debugReset() {
    _lastPlayed = null;
  }

  /// Test seam: en son ne zaman çaldığını döner.
  @visibleForTesting
  static DateTime? get debugLastPlayed => _lastPlayed;

  /// Cooldown'ı geçer mi diye sadece check eder, side-effect yapmaz.
  @visibleForTesting
  static bool wouldPlay(DateTime now) {
    return _lastPlayed == null || now.difference(_lastPlayed!) >= _cooldown;
  }

  static Future<void> playCaptureSound() async {
    final now = DateTime.now();
    if (_lastPlayed != null && now.difference(_lastPlayed!) < _cooldown) {
      return;
    }
    _lastPlayed = now;

    try {
      if (Platform.isMacOS) {
        await _detached('afplay', ['/System/Library/Sounds/Grab.aiff']);
      } else if (Platform.isLinux) {
        await _playLinux();
      } else if (Platform.isWindows) {
        await _playWindows();
      }
    } catch (e) {
      debugPrint('SoundService: ses çalınamadı: $e');
    }
  }

  static Future<void> _playLinux() async {
    for (final path in _linuxCandidates) {
      if (File(path).existsSync()) {
        await _detached('paplay', [path]);
        return;
      }
    }
    await _detached('canberra-gtk-play', ['--id=screen-capture']);
  }

  static Future<void> _playWindows() async {
    const script = r'(New-Object System.Media.SoundPlayer '
        r'"$env:windir\Media\Windows Notify.wav").Play()';
    try {
      await PowerShell.startDetached(script: script);
    } catch (e) {
      debugPrint('SoundService: powershell başlatılamadı: $e');
    }
  }

  /// Detached spawn — paplay/afplay arka planda kendi başına çalar.
  /// stdout/stderr stream'leri parent process'e bağlı kalmaz.
  static Future<void> _detached(String cmd, List<String> args) async {
    try {
      await Process.start(
        cmd,
        args,
        mode: ProcessStartMode.detached,
      );
    } catch (e) {
      debugPrint('SoundService: $cmd başlatılamadı: $e');
    }
  }
}
