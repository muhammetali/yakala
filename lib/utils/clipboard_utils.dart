import 'dart:io';
import 'package:flutter/foundation.dart';

import 'display_server.dart';
import 'powershell.dart';

class ClipboardUtils {
  static const _shellTimeout = Duration(seconds: 8);

  /// Verilen dosya yolundaki PNG görseli OS panosuna kopyalar.
  /// Başarılıysa true döner.
  static Future<bool> copyImageToClipboard(String imagePath) async {
    if (!isPathSafe(imagePath)) {
      debugPrint('Clipboard: tehlikeli karakter içeren path reddedildi: $imagePath');
      return false;
    }
    if (!File(imagePath).existsSync()) {
      debugPrint('Clipboard: dosya bulunamadı: $imagePath');
      return false;
    }
    if (Platform.isMacOS) return _copyImageMacOS(imagePath);
    if (Platform.isLinux) return _copyImageLinux(imagePath);
    if (Platform.isWindows) return _copyImageWindows(imagePath);
    debugPrint('Clipboard: bu platform desteklenmiyor.');
    return false;
  }

  /// Path'te AppleScript / shell injection için tehlikeli karakter olmamalı.
  /// Sadece newline ve carriage return reddedilir (AppleScript'i bölebilir).
  /// Boşluk Windows username'lerinde (C:\Users\My Name\...) yaygın olduğu için kabul.
  static bool isPathSafe(String path) {
    return !path.contains('\n') && !path.contains('\r');
  }

  static Future<bool> _copyImageMacOS(String path) async {
    final escaped = path.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    final script =
        'set the clipboard to (read (POSIX file "$escaped") as «class PNGf»)';
    try {
      final result = await Process.run('osascript', ['-e', script])
          .timeout(_shellTimeout);
      if (result.exitCode != 0) {
        debugPrint('osascript hatası: ${result.stderr}');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('macOS clipboard hatası: $e');
      return false;
    }
  }

  static Future<bool> _copyImageLinux(String path) async {
    if (DisplayServerInfo.isWayland) {
      return _spawnDetachedAndPipe(
        tool: 'wl-copy',
        args: const ['--type', 'image/png'],
        imagePath: path,
        installHint: 'wl-clipboard paketi kurulu mu? '
            '(Ubuntu/Debian: sudo apt install wl-clipboard)',
      );
    }
    return _spawnDetachedAndPipe(
      tool: 'xclip',
      args: const ['-selection', 'clipboard', '-t', 'image/png'],
      imagePath: path,
      installHint: 'xclip kurulu mu? '
          '(Ubuntu/Debian: sudo apt install xclip)',
    );
  }

  /// X11 (`xclip`) ve Wayland (`wl-copy`) clipboard araçları, seçim sahipliğini
  /// korumak için arka plana çatallanır (fork). Çocuk süreç parent'ın
  /// stdout/stderr file descriptor'larını miras alır ve klipboard içeriği
  /// değişene kadar kapatmaz. Bu yüzden `Process.run` + exitCode bekleyen
  /// her yaklaşım sonsuza kadar asılı kalır (kullanıcının raporladığı 8sn
  /// TimeoutException'ın kök sebebi). Çözüm: detachedWithStdio modunda
  /// başlatıp parent süreç ile çocuğun stdio'su arasındaki yaşam döngüsü
  /// bağını kesmek; stdin'e veriyi yazıp kapatınca araç içeriği okumuş ve
  /// klipboard sahipliğini almış olur — parent burada bekleme yapmaz.
  static Future<bool> _spawnDetachedAndPipe({
    required String tool,
    required List<String> args,
    required String imagePath,
    required String installHint,
  }) async {
    Process process;
    try {
      process = await Process.start(
        tool,
        args,
        mode: ProcessStartMode.detachedWithStdio,
      );
    } on ProcessException catch (e) {
      debugPrint('Linux clipboard: "$tool" çalıştırılamadı ($e). $installHint');
      return false;
    } catch (e) {
      debugPrint('Linux clipboard: "$tool" beklenmedik hata: $e');
      return false;
    }

    try {
      // openRead().pipe(stdin) source bittiğinde stdin'i de kapatır.
      // Stdin kapanması = aracın tüm görüntü baytlarını okuyup seçim sahipliğini
      // alması. Parent burada işini bitirmiştir; çocuk daemon olarak yaşar.
      await File(imagePath)
          .openRead()
          .pipe(process.stdin)
          .timeout(_shellTimeout);
      return true;
    } catch (e) {
      debugPrint('Linux clipboard: "$tool" stdin yazma hatası: $e');
      try {
        process.kill();
      } catch (_) {}
      return false;
    }
  }

  /// Windows: path'i environment variable üzerinden geçiriyoruz, böylece
  /// PowerShell argüman parser'ı veya quoting sorunu olmaz.
  static Future<bool> _copyImageWindows(String path) async {
    const psScript = r'''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$p = $env:YAKALA_IMG
$img = [System.Drawing.Image]::FromFile($p)
[System.Windows.Forms.Clipboard]::SetImage($img)
$img.Dispose()
''';
    try {
      final result = await PowerShell.run(
        script: psScript,
        timeout: _shellTimeout,
        environment: {'YAKALA_IMG': path},
      );
      if (result.exitCode != 0) {
        debugPrint('powershell hatası: ${result.stderr}');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('Windows clipboard hatası: $e');
      return false;
    }
  }
}
