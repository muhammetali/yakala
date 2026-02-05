import 'dart:io';
import 'package:flutter/foundation.dart';

class ClipboardUtils {
  /// Verilen dosya yolundaki görseli panoya (Clipboard) kopyalar.
  static Future<void> copyImageToClipboard(String imagePath) async {
    if (Platform.isMacOS) {
      await _copyImageMacOS(imagePath);
    } else if (Platform.isLinux) {
      await _copyImageLinux(imagePath);
    } else {
      debugPrint("Bu platformda panoya resim kopyalama henüz desteklenmiyor.");
    }
  }

  static Future<void> _copyImageMacOS(String path) async {
    try {
      // AppleScript kullanarak resmi panoya at
      final script = '''
        set the clipboard to (read (POSIX file "$path") as JPEG picture)
      ''';
      
      await Process.run('osascript', ['-e', script]);
      debugPrint("MacOS: Resim panoya kopyalandı.");
    } catch (e) {
      debugPrint("MacOS Clipboard Hatası: $e");
    }
  }

  static Future<void> _copyImageLinux(String path) async {
    try {
      // xclip veya wl-copy kontrolü yapılmalı
      // Şimdilik xclip varsayıyoruz (X11)
      await Process.run('xclip', ['-selection', 'clipboard', '-t', 'image/png', '-i', path]);
       debugPrint("Linux: Resim panoya kopyalandı.");
    } catch (e) {
      debugPrint("Linux Clipboard Hatası: $e");
    }
  }
}
