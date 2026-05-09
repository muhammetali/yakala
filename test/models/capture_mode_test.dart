import 'package:flutter_test/flutter_test.dart';
import 'package:yakala/models/capture_mode.dart';

void main() {
  group('CaptureMode', () {
    test('label values', () {
      expect(CaptureMode.fullScreen.label, 'Tüm Ekran');
      expect(CaptureMode.region.label, 'Bölge Seç');
      expect(CaptureMode.window.label, 'Pencere');
    });

    test('enum.name JSON-friendly format', () {
      // Daemon ile paylaşılan settings.json'da bu string'ler kullanılır.
      expect(CaptureMode.fullScreen.name, 'fullScreen');
      expect(CaptureMode.region.name, 'region');
      expect(CaptureMode.window.name, 'window');
    });

    test('values list count', () {
      expect(CaptureMode.values.length, 3);
    });
  });
}
