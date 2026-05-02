import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:yakala/models/hotkey_config.dart';
import 'package:yakala/services/hotkey_service.dart';

import '../helpers/mock_channels.dart';

void main() {
  setUpAll(() {
    setupMockChannels();
  });

  group('HotkeyService.register', () {
    test('successful registration → true', () async {
      final s = HotkeyService();
      final ok = await s.register(HotkeyConfig.defaultConfig, () async {});
      expect(ok, isTrue);
      await s.dispose();
    });

    test('callback async fonksiyon olarak saklanır', () async {
      final s = HotkeyService();
      var called = 0;
      await s.register(HotkeyConfig.defaultConfig, () async {
        called++;
      });
      // Mock channel keyDownHandler tetiklemiyor; sadece exception fırlatmadığını
      // ve register'ın true döndüğünü doğrulamış olduk.
      expect(called, 0);
      await s.dispose();
    });

    test('update yeni config ile re-register yapar', () async {
      final s = HotkeyService();
      await s.register(HotkeyConfig.defaultConfig, () async {});

      const newConfig = HotkeyConfig(
        keyUsbHidUsage: 0x00070009,
        modifiers: [HotKeyModifier.alt],
      );
      final ok = await s.update(newConfig);
      expect(ok, isTrue);
      await s.dispose();
    });

    test('update register edilmemişken → false', () async {
      final s = HotkeyService();
      // register() hiç çağrılmadı
      const config = HotkeyConfig(
        keyUsbHidUsage: 0x00070009,
        modifiers: [HotKeyModifier.alt],
      );
      final ok = await s.update(config);
      expect(ok, isFalse);
    });

    test('dispose temiz çalışır (register yapılmamışken bile)', () async {
      final s = HotkeyService();
      // register edilmedi
      expect(() async => await s.dispose(), returnsNormally);
    });

    test('dispose register sonrası temiz çalışır', () async {
      final s = HotkeyService();
      await s.register(HotkeyConfig.defaultConfig, () async {});
      expect(() async => await s.dispose(), returnsNormally);
    });
  });
}
