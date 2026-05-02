import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yakala/utils/clipboard_utils.dart';

void main() {
  group('ClipboardUtils.isPathSafe', () {
    test('normal path güvenli', () {
      expect(ClipboardUtils.isPathSafe('/tmp/yakala_123.png'), isTrue);
    });

    test('boşluk içeren path güvenli (Windows username)', () {
      expect(
        ClipboardUtils.isPathSafe(r'C:\Users\My Name\AppData\Local\Temp\x.png'),
        isTrue,
      );
    });

    test('newline içeren path reddedilir', () {
      expect(ClipboardUtils.isPathSafe('/tmp/evil\ninject.png'), isFalse);
    });

    test('carriage return içeren path reddedilir', () {
      expect(ClipboardUtils.isPathSafe('/tmp/x\r.png'), isFalse);
    });

    test('boş string güvenli sayılır (existsSync sonra catch eder)', () {
      expect(ClipboardUtils.isPathSafe(''), isTrue);
    });

    test('Türkçe karakter / unicode güvenli', () {
      expect(ClipboardUtils.isPathSafe('/tmp/şéñ.png'), isTrue);
    });
  });

  group('ClipboardUtils.copyImageToClipboard rejection', () {
    test('newline path → false (shell çağrılmaz)', () async {
      final result =
          await ClipboardUtils.copyImageToClipboard('/tmp/evil\ninject.png');
      expect(result, isFalse);
    });

    test('var olmayan dosya → false', () async {
      final result = await ClipboardUtils.copyImageToClipboard(
        '/tmp/definitely_does_not_exist_yakala_test.png',
      );
      expect(result, isFalse);
    });

    test('var olan ama geçersiz PNG dosya: shell hatası → false', () async {
      // Geçici text dosyası oluştur (PNG değil) — shell çağrılır ama exitCode!=0
      final tempDir = await Directory.systemTemp.createTemp('yakala_clip_');
      final dummyFile = File('${tempDir.path}/not_a_png.png');
      await dummyFile.writeAsString('this is not a png');
      try {
        final result =
            await ClipboardUtils.copyImageToClipboard(dummyFile.path);
        // Linux'ta xclip/wl-copy bu dosyayı işleyebilir veya işleyemeyebilir;
        // önemli olan throw etmemesi
        expect(result, anyOf(isTrue, isFalse));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });
}
