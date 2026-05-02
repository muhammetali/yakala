import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:yakala/models/capture_mode.dart';
import 'package:yakala/models/hotkey_config.dart';
import 'package:yakala/providers/settings_provider.dart';
import 'package:yakala/services/autostart_service.dart';

import '../helpers/mock_channels.dart';

void main() {
  setUpAll(() {
    setupMockChannels();
  });

  group('SettingsProvider defaults', () {
    test('endüstri standardı default değerler', () async {
      final p = await SettingsProvider.create(AutostartService());
      expect(p.startAtLogin, isFalse);
      expect(p.soundEffect, isTrue);
      expect(p.notificationsEnabled, isTrue);
      expect(p.showEditorAfterCapture, isTrue);
      expect(p.savePath, isEmpty);
      expect(p.defaultCaptureMode, CaptureMode.fullScreen);
      expect(p.hotkey.modifiers, contains(HotKeyModifier.meta));
    });
  });

  group('SettingsProvider short-circuit (no-op when value unchanged)', () {
    test('setSoundEffect aynı değerle no-op', () async {
      final p = await SettingsProvider.create(AutostartService());
      // default true; tekrar true → notify olmamalı
      var n = 0;
      p.addListener(() => n++);
      await p.setSoundEffect(true);
      expect(n, 0);
    });

    test('setSoundEffect farklı değerle notify eder', () async {
      final p = await SettingsProvider.create(AutostartService());
      var n = 0;
      p.addListener(() => n++);
      await p.setSoundEffect(false);
      expect(n, 1);
      // Tekrar false → no-op
      await p.setSoundEffect(false);
      expect(n, 1);
    });

    test('setNotificationsEnabled short-circuit', () async {
      final p = await SettingsProvider.create(AutostartService());
      var n = 0;
      p.addListener(() => n++);
      await p.setNotificationsEnabled(true); // already true
      expect(n, 0);
      await p.setNotificationsEnabled(false);
      expect(n, 1);
    });

    test('setShowEditorAfterCapture short-circuit', () async {
      final p = await SettingsProvider.create(AutostartService());
      var n = 0;
      p.addListener(() => n++);
      await p.setShowEditorAfterCapture(true); // already true
      expect(n, 0);
    });

    test('setSavePath short-circuit', () async {
      final p = await SettingsProvider.create(AutostartService());
      var n = 0;
      p.addListener(() => n++);
      await p.setSavePath(''); // already empty
      expect(n, 0);
      await p.setSavePath('/tmp/yakala');
      expect(n, 1);
      await p.setSavePath('/tmp/yakala'); // same
      expect(n, 1);
    });

    test('setHotkey short-circuit (JSON bazlı eşitlik)', () async {
      final p = await SettingsProvider.create(AutostartService());
      var n = 0;
      p.addListener(() => n++);
      // Default ile aynı config → no-op
      await p.setHotkey(HotkeyConfig.defaultConfig);
      expect(n, 0);
      // Farklı config → notify
      const newConfig = HotkeyConfig(
        keyUsbHidUsage: 0x00070009,
        modifiers: [HotKeyModifier.alt],
      );
      await p.setHotkey(newConfig);
      expect(n, 1);
    });

    test('setDefaultCaptureMode short-circuit', () async {
      final p = await SettingsProvider.create(AutostartService());
      var n = 0;
      p.addListener(() => n++);
      await p.setDefaultCaptureMode(CaptureMode.fullScreen); // default
      expect(n, 0);
      await p.setDefaultCaptureMode(CaptureMode.region);
      expect(n, 1);
    });
  });

  group('SettingsProvider persistence across instances', () {
    test('Yazılan değer ikinci instance\'tan okunur', () async {
      final p1 = await SettingsProvider.create(AutostartService());
      await p1.setSavePath('/tmp/yakala_persist_test');

      final p2 = await SettingsProvider.create(AutostartService());
      expect(p2.savePath, '/tmp/yakala_persist_test');
    });
  });
}
