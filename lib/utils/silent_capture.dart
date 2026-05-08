import 'dart:io';
import 'package:flutter/foundation.dart';

import 'display_server.dart';
import 'powershell.dart';

/// Region overlay'in "frozen background" capture'ı için sessiz tam ekran yakalama.
/// Hiçbir flash/sound/notification göstermez.
class SilentCapture {
  static const _shellTimeout = Duration(seconds: 8);

  /// Test seam: production'da `null`. Testler shell-out'u bypass etmek için
  /// `(_) async => false` (fallback path'i tetikler) veya
  /// `(path) async { File(path).writeAsBytesSync(...); return true; }` set
  /// edebilir. CaptureService bunu doğrudan kullanmıyor; bu seam SilentCapture
  /// üreten kodun production binary'lerini test runner'da çalıştırmasını
  /// engellemek için.
  @visibleForTesting
  static Future<bool> Function(String outputPath)? testOverride;

  /// Belirtilen path'e tam ekran PNG yazar. Başarılı olursa true.
  static Future<bool> captureFullScreen(String outputPath) async {
    final override = testOverride;
    if (override != null) return override(outputPath);
    if (!isPathSafe(outputPath)) {
      debugPrint('SilentCapture: tehlikeli karakter içeren path reddedildi.');
      return false;
    }
    if (Platform.isLinux) return _captureLinux(outputPath);
    if (Platform.isMacOS) return _captureMacOS(outputPath);
    if (Platform.isWindows) return _captureWindows(outputPath);
    return false;
  }

  /// Sadece newline/CR reddet — boşluk Windows username'lerinde geçerli.
  static bool isPathSafe(String p) {
    return !p.contains('\n') && !p.contains('\r');
  }

  static Future<bool> _captureLinux(String path) async {
    final isWayland = DisplayServerInfo.isWayland;
    if (isWayland) {
      if (await _run('grim', [path])) return true;
    }
    if (await _run('import', ['-silent', '-window', 'root', path])) return true;
    if (await _run('scrot', ['-z', '-o', path])) return true;
    if (await _run('maim', [path])) return true;
    debugPrint(
      'SilentCapture: Linux için sessiz tool bulunamadı. '
      'Kurulum: ${isWayland ? "sudo apt install grim" : "sudo apt install imagemagick"}',
    );
    return false;
  }

  static Future<bool> _captureMacOS(String path) async {
    return _run('screencapture', ['-x', '-t', 'png', path]);
  }

  /// Windows: PowerShell'e path'i env üzerinden geçir (injection güvenli).
  static Future<bool> _captureWindows(String path) async {
    const script = r'''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
$bmp.Save($env:YAKALA_OUT, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose()
$bmp.Dispose()
''';
    try {
      final result = await PowerShell.run(
        script: script,
        timeout: _shellTimeout,
        environment: {'YAKALA_OUT': path},
      );
      return result.exitCode == 0 && File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Output dosyasının gerçekten yazıldığını + boyutunun >0 olduğunu kontrol eder.
  static Future<bool> _run(String cmd, List<String> args) async {
    try {
      final result = await Process.run(cmd, args).timeout(_shellTimeout);
      if (result.exitCode != 0) return false;
      // args.last yerine güvenilir kontrol: tüm string'lere bak, .png ile bitenini bul
      final outputPath = args.firstWhere(
        (a) => a.endsWith('.png'),
        orElse: () => args.last,
      );
      final file = File(outputPath);
      if (!file.existsSync()) return false;
      final size = await file.length();
      return size > 0;
    } catch (_) {
      return false;
    }
  }
}
