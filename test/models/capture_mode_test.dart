import 'package:flutter_test/flutter_test.dart';
import 'package:screen_capturer/screen_capturer.dart' as sc;
import 'package:yakala/models/capture_mode.dart';

void main() {
  group('CaptureMode.label', () {
    test('Türkçe label\'lar', () {
      expect(CaptureMode.fullScreen.label, 'Tüm Ekran');
      expect(CaptureMode.region.label, 'Bölge Seç');
      expect(CaptureMode.window.label, 'Pencere');
    });
  });

  group('CaptureMode.toScreenCapturerMode', () {
    test('fullScreen → sc.CaptureMode.screen', () {
      expect(
        CaptureMode.fullScreen.toScreenCapturerMode(),
        sc.CaptureMode.screen,
      );
    });

    test('region → sc.CaptureMode.region', () {
      expect(
        CaptureMode.region.toScreenCapturerMode(),
        sc.CaptureMode.region,
      );
    });

    test('window → sc.CaptureMode.window', () {
      expect(
        CaptureMode.window.toScreenCapturerMode(),
        sc.CaptureMode.window,
      );
    });
  });

  group('CaptureMode enum invariants', () {
    test('values length 3', () {
      expect(CaptureMode.values.length, 3);
    });

    test('index ile round-trip', () {
      for (final m in CaptureMode.values) {
        expect(CaptureMode.values[m.index], m);
      }
    });
  });
}
