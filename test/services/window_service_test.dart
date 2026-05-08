import 'dart:io';
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

  // **Engine pause regression**: Linux GTK'da `windowManager.hide()` pencereyi
  // Withdrawn state'e geçiriyor → Flutter engine paused → tray click,
  // global hotkey, IPC event'leri Dart'a iletilmiyor. Çözüm: hide() yerine
  // pencereyi off-screen + opacity 0 + 1×1 + show() durumunda tut → mapped
  // kalır → engine pause olmaz. Bu testler regresyon koruması.
  group('WindowService engine-pause guard (Linux off-screen pattern)', () {
    test('hide() Linux\'ta gerçek hide() çağırmaz, off-screen pattern uygular',
        () async {
      if (!Platform.isLinux) return;
      final ws = WindowService();
      await ws.initialize();

      windowManagerCalls.clear();
      await ws.hide();

      expect(
        windowManagerCalls,
        isNot(contains('hide')),
        reason: 'Linux\'ta windowManager.hide() çağrılmamalı '
            '(engine paused olmasın diye). Mevcut çağrılar: $windowManagerCalls',
      );
      expect(windowManagerCalls, contains('setOpacity'),
          reason: 'opacity 0 → görünmez');
      // window_manager paketi setSize+setPosition'ı internally tek setBounds
      // call'ına birleştiriyor → her iki değişiklik için tek native call.
      expect(windowManagerCalls, contains('setBounds'),
          reason: '1×1 size + off-screen pozisyon için setBounds');
      expect(windowManagerCalls, contains('show'),
          reason: 'show() pencereyi mapped state\'te tutar (engine canlı)');
      expect(windowManagerCalls, contains('setSkipTaskbar'),
          reason: 'taskbar\'da görünmesin');
    });

    test('exitOverlay() Linux\'ta gerçek hide() çağırmaz', () async {
      if (!Platform.isLinux) return;
      final ws = WindowService();
      await ws.initialize();
      await ws.enterOverlay(const Size(1920, 1080));

      windowManagerCalls.clear();
      await ws.exitOverlay();

      expect(
        windowManagerCalls,
        isNot(contains('hide')),
        reason: 'exitOverlay\'in son adımı off-screen pattern olmalı, '
            'hide() değil. Mevcut çağrılar: $windowManagerCalls',
      );
      // Off-screen pattern'a inmiş olmalı:
      expect(windowManagerCalls, contains('setOpacity'));
      expect(windowManagerCalls, contains('show'));
    });

    test('showSettings() Linux\'ta opacity 1.0\'a reset eder', () async {
      if (!Platform.isLinux) return;
      final ws = WindowService();
      await ws.initialize();
      await ws.hide();

      windowManagerCalls.clear();
      await ws.showSettings();

      expect(windowManagerCalls, contains('setOpacity'),
          reason: 'showSettings opacity\'yi 1.0\'a geri çekmeli, '
              'aksi halde hide() sonrası settings görünmez');
      expect(windowManagerCalls, contains('show'));
    });

    test('non-Linux platformlarda gerçek hide() kullanılır', () async {
      if (Platform.isLinux) return;
      final ws = WindowService();
      await ws.initialize();

      windowManagerCalls.clear();
      await ws.hide();

      expect(windowManagerCalls, contains('hide'),
          reason: 'macOS/Windows engine pause sorunu yaşamıyor → '
              'gerçek hide() kalmalı');
    });
  });
}
