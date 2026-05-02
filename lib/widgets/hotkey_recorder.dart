import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:yakala/models/hotkey_config.dart';

/// Kullanıcı tıklayınca "kayıt" moduna girer ve sonraki tuş kombinasyonunu yakalar.
/// En az bir modifier (shift/cmd/alt/ctrl) zorunludur — global hotkey için iyi pratik.
class HotkeyRecorder extends StatefulWidget {
  final HotkeyConfig current;
  final ValueChanged<HotkeyConfig> onChanged;

  const HotkeyRecorder({
    super.key,
    required this.current,
    required this.onChanged,
  });

  @override
  State<HotkeyRecorder> createState() => _HotkeyRecorderState();
}

class _HotkeyRecorderState extends State<HotkeyRecorder> {
  bool _recording = false;
  final FocusNode _focus = FocusNode();
  String? _hint;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _startRecording() {
    setState(() {
      _recording = true;
      _hint = 'Kombinasyona bas... (Esc iptal)';
    });
    _focus.requestFocus();
  }

  void _stopRecording([String? hint]) {
    setState(() {
      _recording = false;
      _hint = hint;
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _stopRecording();
      return KeyEventResult.handled;
    }

    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final modifiers = <HotKeyModifier>[];
    if (pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight)) {
      modifiers.add(HotKeyModifier.meta);
    }
    if (pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight)) {
      modifiers.add(HotKeyModifier.shift);
    }
    if (pressed.contains(LogicalKeyboardKey.altLeft) ||
        pressed.contains(LogicalKeyboardKey.altRight)) {
      modifiers.add(HotKeyModifier.alt);
    }
    if (pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight)) {
      modifiers.add(HotKeyModifier.control);
    }

    if (_isModifierKey(event.logicalKey)) {
      // Sadece modifier basıldı, asıl tuşu bekle.
      return KeyEventResult.handled;
    }

    if (modifiers.isEmpty) {
      _stopRecording('En az bir modifier (⌘/⇧/⌥/⌃) gerekli');
      return KeyEventResult.handled;
    }

    final config = HotkeyConfig(
      keyUsbHidUsage: event.physicalKey.usbHidUsage,
      modifiers: modifiers,
    );
    widget.onChanged(config);
    _stopRecording();
    return KeyEventResult.handled;
  }

  bool _isModifierKey(LogicalKeyboardKey k) {
    return k == LogicalKeyboardKey.metaLeft ||
        k == LogicalKeyboardKey.metaRight ||
        k == LogicalKeyboardKey.shiftLeft ||
        k == LogicalKeyboardKey.shiftRight ||
        k == LogicalKeyboardKey.altLeft ||
        k == LogicalKeyboardKey.altRight ||
        k == LogicalKeyboardKey.controlLeft ||
        k == LogicalKeyboardKey.controlRight;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: GestureDetector(
        onTap: _recording ? null : _startRecording,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _recording
                ? scheme.primary.withValues(alpha: 0.15)
                : scheme.onSurface.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _recording
                  ? scheme.primary
                  : scheme.onSurface.withValues(alpha: 0.12),
            ),
          ),
          child: Text(
            // Recording'de hint; değilse stop'tan kalan hint varsa onu göster,
            // yoksa current config label'ı.
            _recording
                ? (_hint ?? 'Kombinasyona bas...')
                : (_hint ?? widget.current.displayLabel),
            style: TextStyle(
              color: scheme.onSurface,
              fontWeight: FontWeight.bold,
              fontFamily: 'Menlo',
            ),
          ),
        ),
      ),
    );
  }
}
