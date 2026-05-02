import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:yakala/models/hotkey_config.dart';

void main() {
  group('HotkeyConfig', () {
    test('default config: ⌘⇧C', () {
      const c = HotkeyConfig.defaultConfig;
      expect(c.modifiers, contains(HotKeyModifier.meta));
      expect(c.modifiers, contains(HotKeyModifier.shift));
      expect(c.keyUsbHidUsage, 0x00070006); // C key
    });

    test('JSON round-trip name-based serialize', () {
      const original = HotkeyConfig(
        keyUsbHidUsage: 0x00070009,
        modifiers: [HotKeyModifier.alt, HotKeyModifier.shift],
      );
      final json = original.toJsonString();
      // Modifier'lar isim olarak yazılmalı
      expect(json, contains('"alt"'));
      expect(json, contains('"shift"'));

      final back = HotkeyConfig.fromJsonString(json);
      expect(back.keyUsbHidUsage, original.keyUsbHidUsage);
      expect(back.modifiers, original.modifiers);
    });

    test('legacy index format backward compatible', () {
      // Eski format: modifier'lar int index
      // HotKeyModifier.values[0] = first enum value
      // Plugin enum sırası: shift, control, alt, meta, capsLock, fn (paket version'una göre)
      // Index'e göre okunup HotKeyModifier dönmeli
      const legacy = '{"key": 458758, "modifiers": [0, 1]}';
      final config = HotkeyConfig.fromJsonString(legacy);
      expect(config.modifiers.length, 2);
      // İlk iki modifier enum değerleri
      expect(config.modifiers[0], HotKeyModifier.values[0]);
      expect(config.modifiers[1], HotKeyModifier.values[1]);
    });

    test('mixed format (name + int) tolerantly parsed', () {
      const mixed = '{"key": 458758, "modifiers": ["meta", 0]}';
      final config = HotkeyConfig.fromJsonString(mixed);
      expect(config.modifiers.length, 2);
      expect(config.modifiers, contains(HotKeyModifier.meta));
    });

    test('bilinmeyen modifier ismi atlanır', () {
      const json = '{"key": 458758, "modifiers": ["meta", "unknownMod"]}';
      final config = HotkeyConfig.fromJsonString(json);
      expect(config.modifiers.length, 1);
      expect(config.modifiers.first, HotKeyModifier.meta);
    });

    test('out-of-range int index atlanır', () {
      const json = '{"key": 458758, "modifiers": [99]}';
      final config = HotkeyConfig.fromJsonString(json);
      expect(config.modifiers.length, 0);
    });

    test('bozuk json default config döner', () {
      final config = HotkeyConfig.fromJsonString('{not valid');
      expect(config.keyUsbHidUsage, HotkeyConfig.defaultConfig.keyUsbHidUsage);
      expect(config.modifiers, HotkeyConfig.defaultConfig.modifiers);
    });

    test('null veya boş string → default config', () {
      expect(
        HotkeyConfig.fromJsonString(null).keyUsbHidUsage,
        HotkeyConfig.defaultConfig.keyUsbHidUsage,
      );
      expect(
        HotkeyConfig.fromJsonString('').keyUsbHidUsage,
        HotkeyConfig.defaultConfig.keyUsbHidUsage,
      );
    });

    test('displayLabel modifier sembolleri + tuş', () {
      const c = HotkeyConfig(
        keyUsbHidUsage: 0x00070006, // C
        modifiers: [HotKeyModifier.meta, HotKeyModifier.shift],
      );
      final label = c.displayLabel;
      expect(label, contains('⌘'));
      expect(label, contains('⇧'));
      // C tuşu "C" olarak görünmeli
      expect(label.toUpperCase(), contains('C'));
    });

    test('toHotKey döndürdüğü HotKey doğru config içerir', () {
      const c = HotkeyConfig(
        keyUsbHidUsage: 0x00070009,
        modifiers: [HotKeyModifier.alt],
      );
      final hk = c.toHotKey();
      expect(hk.modifiers, [HotKeyModifier.alt]);
      expect(hk.scope, HotKeyScope.system);
    });
  });
}
