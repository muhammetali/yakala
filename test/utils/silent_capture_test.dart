import 'package:flutter_test/flutter_test.dart';
import 'package:yakala/utils/silent_capture.dart';

void main() {
  group('SilentCapture.isPathSafe', () {
    test('normal path güvenli', () {
      expect(SilentCapture.isPathSafe('/tmp/yakala_full_123.png'), isTrue);
    });

    test('boşluk içeren path güvenli (cross-platform)', () {
      expect(SilentCapture.isPathSafe('/tmp/has space.png'), isTrue);
      expect(
        SilentCapture.isPathSafe(r'C:\Users\My Name\AppData\file.png'),
        isTrue,
      );
    });

    test('newline reddedilir', () {
      expect(SilentCapture.isPathSafe('/tmp/x\ny.png'), isFalse);
    });

    test('carriage return reddedilir', () {
      expect(SilentCapture.isPathSafe('/tmp/x\r.png'), isFalse);
    });
  });

  group('SilentCapture.captureFullScreen rejection', () {
    test('newline path → false (shell çağrılmaz)', () async {
      final result =
          await SilentCapture.captureFullScreen('/tmp/evil\ninject.png');
      expect(result, isFalse);
    });

    test('var olmayan dizine yazma denemesi → throw etmez', () async {
      // Read-only veya nonexistent path — shell tool fail eder
      final result = await SilentCapture.captureFullScreen(
        '/proc/yakala_test_should_not_exist.png',
      );
      // Throw olmamalı, false dönmeli
      expect(result, isFalse);
    });
  });
}
