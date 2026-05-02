import 'package:flutter_test/flutter_test.dart';
import 'package:yakala/models/capture_result.dart';

void main() {
  group('CaptureResult.ok', () {
    test('success true, imagePath set, error null', () {
      final r = CaptureResult.ok(imagePath: '/tmp/x.png');
      expect(r.success, isTrue);
      expect(r.imagePath, '/tmp/x.png');
      expect(r.error, isNull);
      expect(r.savedToDisk, isNull);
      expect(r.isCancelled, isFalse);
    });

    test('savedToDisk opsiyonel', () {
      final r = CaptureResult.ok(
        imagePath: '/tmp/x.png',
        savedToDisk: '/home/user/x.png',
      );
      expect(r.savedToDisk, '/home/user/x.png');
    });
  });

  group('CaptureResult.cancelled', () {
    test('success false, isCancelled true, error \'cancelled\'', () {
      final r = CaptureResult.cancelled();
      expect(r.success, isFalse);
      expect(r.isCancelled, isTrue);
      expect(r.error, 'cancelled');
      expect(r.imagePath, isNull);
    });
  });

  group('CaptureResult.failed', () {
    test('success false, error message set, isCancelled false', () {
      final r = CaptureResult.failed('Disk full');
      expect(r.success, isFalse);
      expect(r.error, 'Disk full');
      expect(r.isCancelled, isFalse);
      expect(r.imagePath, isNull);
    });

    test('failed != cancelled', () {
      final f = CaptureResult.failed('xyz');
      final c = CaptureResult.cancelled();
      expect(f.isCancelled, isFalse);
      expect(c.isCancelled, isTrue);
    });
  });
}
