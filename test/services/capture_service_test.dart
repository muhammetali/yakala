import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yakala/models/capture_mode.dart';
import 'package:yakala/services/annotation_service.dart';
import 'package:yakala/services/autostart_service.dart';
import 'package:yakala/services/capture_service.dart';
import 'package:yakala/providers/settings_provider.dart';
import 'package:yakala/services/region_selector_service.dart';
import 'package:yakala/services/window_service.dart';

import '../helpers/mock_channels.dart';

void main() {
  setUpAll(() {
    setupMockChannels();
  });

  Future<CaptureService> build() async {
    final settings = await SettingsProvider.create(AutostartService());
    return CaptureService(
      settings: settings,
      regionSelector: RegionSelectorService(),
      annotationService: AnnotationService(),
      windowService: WindowService(),
    );
  }

  group('CaptureService instantiation', () {
    test('servislerle inşa edilir', () async {
      final c = await build();
      expect(c, isNotNull);
      expect(c.settings, isNotNull);
      expect(c.regionSelector, isNotNull);
      expect(c.annotationService, isNotNull);
      expect(c.windowService, isNotNull);
    });
  });

  group('CaptureService.capture mode dispatch', () {
    test('Native modlar (fullScreen) — exception fırlatmaz, result döner',
        () async {
      // Linux/Windows'ta permission check no-op; capture screen_capturer'ı çağırır.
      // Mock'ta capture {imagePath: '/tmp/mock_capture.png', ...} dönüyor ama
      // dosya gerçekten yok → cancelled dönecek
      final c = await build();
      final result = await c.capture(CaptureMode.fullScreen);
      // Throw olmadığını ve bir CaptureResult döndüğünü doğrula
      expect(result, isNotNull);
      // Cancelled veya failed olabilir — ama kesinlikle null değil
      expect(result.success, anyOf(isTrue, isFalse));
    }, skip: Platform.isMacOS, // macOS izin diyaloğu açabilir
        timeout: const Timeout(Duration(seconds: 30)));

    test('Window mode — aynı şekilde graceful sonuç', () async {
      final c = await build();
      final result = await c.capture(CaptureMode.window);
      expect(result, isNotNull);
    },
        skip: Platform.isMacOS,
        timeout: const Timeout(Duration(seconds: 30)));
  });
}
