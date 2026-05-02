import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

class HotkeyConfig {
  final int keyUsbHidUsage;
  final List<HotKeyModifier> modifiers;

  const HotkeyConfig({
    required this.keyUsbHidUsage,
    required this.modifiers,
  });

  static const HotkeyConfig defaultConfig = HotkeyConfig(
    keyUsbHidUsage: 0x00070006,
    modifiers: [HotKeyModifier.shift, HotKeyModifier.meta],
  );

  PhysicalKeyboardKey get physicalKey => PhysicalKeyboardKey(keyUsbHidUsage);

  HotKey toHotKey() => HotKey(
        key: physicalKey,
        modifiers: modifiers,
        scope: HotKeyScope.system,
      );

  /// Modifier'ları index yerine `name` ile serialize ederiz: paket gelecekte
  /// enum sırasını değiştirirse persisted config bozulmaz.
  String toJsonString() => jsonEncode({
        'key': keyUsbHidUsage,
        'modifiers': modifiers.map(_modifierName).toList(),
      });

  static HotkeyConfig fromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return defaultConfig;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final key = map['key'] as int;
      final mods = <HotKeyModifier>[];
      for (final entry in (map['modifiers'] as List)) {
        if (entry is String) {
          final m = _modifierFromName(entry);
          if (m != null) mods.add(m);
        } else if (entry is int && entry >= 0 && entry < HotKeyModifier.values.length) {
          // Eski format (index-based) ile geriye uyumluluk
          mods.add(HotKeyModifier.values[entry]);
        }
      }
      return HotkeyConfig(keyUsbHidUsage: key, modifiers: mods);
    } catch (_) {
      return defaultConfig;
    }
  }

  static String _modifierName(HotKeyModifier m) {
    switch (m) {
      case HotKeyModifier.meta:
        return 'meta';
      case HotKeyModifier.shift:
        return 'shift';
      case HotKeyModifier.alt:
        return 'alt';
      case HotKeyModifier.control:
        return 'control';
      case HotKeyModifier.capsLock:
        return 'capsLock';
      case HotKeyModifier.fn:
        return 'fn';
    }
  }

  static HotKeyModifier? _modifierFromName(String name) {
    switch (name) {
      case 'meta':
        return HotKeyModifier.meta;
      case 'shift':
        return HotKeyModifier.shift;
      case 'alt':
        return HotKeyModifier.alt;
      case 'control':
        return HotKeyModifier.control;
      case 'capsLock':
        return HotKeyModifier.capsLock;
      case 'fn':
        return HotKeyModifier.fn;
      default:
        return null;
    }
  }

  String get displayLabel {
    final parts = <String>[];
    for (final mod in modifiers) {
      parts.add(_modifierSymbol(mod));
    }
    parts.add(_keyLabel(physicalKey));
    return parts.join(' ');
  }

  static String _modifierSymbol(HotKeyModifier mod) {
    switch (mod) {
      case HotKeyModifier.meta:
        return '⌘';
      case HotKeyModifier.shift:
        return '⇧';
      case HotKeyModifier.alt:
        return '⌥';
      case HotKeyModifier.control:
        return '⌃';
      case HotKeyModifier.capsLock:
        return '⇪';
      case HotKeyModifier.fn:
        return 'fn';
    }
  }

  static String _keyLabel(PhysicalKeyboardKey key) {
    final debug = key.debugName ?? '';
    final cleaned = debug.replaceAll('Key ', '').replaceAll('Digit ', '');
    return cleaned.isEmpty ? '?' : cleaned.toUpperCase();
  }
}
