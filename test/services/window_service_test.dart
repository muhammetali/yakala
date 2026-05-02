import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:yakala/services/window_service.dart';

import '../helpers/mock_channels.dart';

void main() {
  setUpAll(() {
    setupMockChannels();
  });

  group('WindowService initial state', () {
    test('settingsVisible ve inOverlayMode false', () {
      final ws = WindowService();
      expect(ws.settingsVisible, isFalse);
      expect(ws.inOverlayMode, isFalse);
    });

    test('ChangeNotifier listener arayüzü çalışıyor', () {
      final ws = WindowService();
      expect(() => ws.addListener(() {}), returnsNormally);
    });
  });

  group('WindowService showSettings/hide state machine', () {
    test('showSettings → settingsVisible true + notify', () async {
      final ws = WindowService();
      await ws.initialize();
      var notified = 0;
      ws.addListener(() => notified++);

      await ws.showSettings();
      expect(ws.settingsVisible, isTrue);
      expect(notified, greaterThan(0));
    });

    test('hide → settingsVisible false + notify', () async {
      final ws = WindowService();
      await ws.initialize();
      await ws.showSettings();
      expect(ws.settingsVisible, isTrue);

      var notified = 0;
      ws.addListener(() => notified++);
      await ws.hide();
      expect(ws.settingsVisible, isFalse);
      expect(notified, greaterThan(0));
    });

    test('showSettings sonrası hide → false', () async {
      final ws = WindowService();
      await ws.initialize();
      await ws.showSettings();
      await ws.hide();
      expect(ws.settingsVisible, isFalse);
    });
  });

  group('WindowService overlay mode', () {
    test('enterOverlay → inOverlayMode true + settingsVisible false', () async {
      final ws = WindowService();
      await ws.initialize();
      await ws.showSettings(); // settingsVisible = true
      expect(ws.settingsVisible, isTrue);

      await ws.enterOverlay(const Size(1920, 1080));
      expect(ws.inOverlayMode, isTrue);
      expect(ws.settingsVisible, isFalse); // overlay'e geçince settings false
    });

    test('exitOverlay → inOverlayMode false', () async {
      final ws = WindowService();
      await ws.initialize();
      await ws.enterOverlay(const Size(1920, 1080));
      expect(ws.inOverlayMode, isTrue);

      await ws.exitOverlay();
      expect(ws.inOverlayMode, isFalse);
    });

    test('exitOverlay overlay yokken no-op', () async {
      final ws = WindowService();
      await ws.initialize();
      // Overlay'e hiç girmedik
      await ws.exitOverlay();
      expect(ws.inOverlayMode, isFalse);
    });

    test('showSettings overlay\'dan çıkar', () async {
      final ws = WindowService();
      await ws.initialize();
      await ws.enterOverlay(const Size(800, 600));
      expect(ws.inOverlayMode, isTrue);

      await ws.showSettings();
      expect(ws.inOverlayMode, isFalse);
      expect(ws.settingsVisible, isTrue);
    });
  });

  group('WindowService notification ordering', () {
    test('exitOverlay önce hide, sonra notify (flash önleme)', () async {
      final ws = WindowService();
      await ws.initialize();
      await ws.enterOverlay(const Size(1920, 1080));

      // exitOverlay sırasında: hide → _inOverlayMode=false + notify
      // Notify zamanında inOverlayMode false olmuş olmalı
      bool? observedInOverlay;
      ws.addListener(() {
        observedInOverlay ??= ws.inOverlayMode;
      });
      await ws.exitOverlay();

      expect(observedInOverlay, isFalse);
    });
  });
}
