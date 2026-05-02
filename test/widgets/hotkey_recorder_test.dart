import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:yakala/models/hotkey_config.dart';
import 'package:yakala/widgets/hotkey_recorder.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('HotkeyRecorder display', () {
    testWidgets('initial state\'te current config\'in label\'ını gösterir',
        (tester) async {
      const config = HotkeyConfig(
        keyUsbHidUsage: 0x00070006, // C
        modifiers: [HotKeyModifier.meta, HotKeyModifier.shift],
      );
      await tester.pumpWidget(wrap(
        HotkeyRecorder(current: config, onChanged: (_) {}),
      ));
      // Label'da ⌘ ve ⇧ olmalı
      expect(find.textContaining('⌘'), findsOneWidget);
    });

    testWidgets('tıklayınca recording moduna girer + hint metni gösterir',
        (tester) async {
      const config = HotkeyConfig(
        keyUsbHidUsage: 0x00070006,
        modifiers: [HotKeyModifier.meta],
      );
      await tester.pumpWidget(wrap(
        HotkeyRecorder(current: config, onChanged: (_) {}),
      ));
      await tester.tap(find.byType(HotkeyRecorder));
      await tester.pump();

      expect(find.textContaining('Kombinasyona bas'), findsOneWidget);
    });
  });

  group('HotkeyRecorder keyboard handling', () {
    testWidgets('Esc recording\'i iptal eder', (tester) async {
      var changed = 0;
      const config = HotkeyConfig(
        keyUsbHidUsage: 0x00070006,
        modifiers: [HotKeyModifier.meta],
      );
      await tester.pumpWidget(wrap(
        HotkeyRecorder(current: config, onChanged: (_) => changed++),
      ));
      await tester.tap(find.byType(HotkeyRecorder));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      // onChanged çağrılmamalı
      expect(changed, 0);
      // Hint metni kayboldu/değişti
      expect(find.textContaining('Kombinasyona bas'), findsNothing);
    });

    testWidgets('modifiersız tuş → uyarı + onChanged çağrılmaz', (tester) async {
      var changed = 0;
      const config = HotkeyConfig(
        keyUsbHidUsage: 0x00070006,
        modifiers: [HotKeyModifier.meta],
      );
      await tester.pumpWidget(wrap(
        HotkeyRecorder(current: config, onChanged: (_) => changed++),
      ));
      await tester.tap(find.byType(HotkeyRecorder));
      await tester.pump();

      // Sadece A tuşu (modifier yok)
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();

      expect(changed, 0);
      expect(find.textContaining('modifier'), findsOneWidget);
    });

    testWidgets('modifier + key → onChanged tetiklenir', (tester) async {
      HotkeyConfig? captured;
      const config = HotkeyConfig(
        keyUsbHidUsage: 0x00070006,
        modifiers: [HotKeyModifier.meta],
      );
      await tester.pumpWidget(wrap(
        HotkeyRecorder(current: config, onChanged: (c) => captured = c),
      ));
      await tester.tap(find.byType(HotkeyRecorder));
      await tester.pump();

      // Shift basılı tut + A tuşuna bas
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(captured, isNotNull);
      expect(captured!.modifiers, contains(HotKeyModifier.shift));
    });

    testWidgets('sadece modifier (Shift) basılınca handle edilir, beklenir',
        (tester) async {
      var changed = 0;
      const config = HotkeyConfig(
        keyUsbHidUsage: 0x00070006,
        modifiers: [HotKeyModifier.meta],
      );
      await tester.pumpWidget(wrap(
        HotkeyRecorder(current: config, onChanged: (_) => changed++),
      ));
      await tester.tap(find.byType(HotkeyRecorder));
      await tester.pump();

      // Sadece Shift down — kombinasyon henüz tamamlanmadı
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(changed, 0);
      // Hala recording'de
      expect(find.textContaining('Kombinasyona bas'), findsOneWidget);
    });
  });
}
