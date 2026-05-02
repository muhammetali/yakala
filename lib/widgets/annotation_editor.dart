import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:image_painter/image_painter.dart';

/// image_painter paketini saran annotation editor.
///
/// Paketin built-in toolbar'ı (`showControls: true`) yerine kendi araç
/// çubuğumuzu kullanıyoruz. Kök sebep: paketin v0.7.1'deki text aracı
/// `showDialog` ile transparan/dekoratif olmayan bir TextField açıyor —
/// bu, frameless+transparent+alwaysOnTop overlay penceresinde fokus alamıyor
/// ve görsel olarak da bir alana benzemiyor (kullanıcı yazdığını göremiyor).
/// Ayrıca toolbar İngilizce. Kendi toolbar'ımız hem Türkçe etiketleri,
/// hem de düzgün bir Material AlertDialog ile metin girişini sağlıyor.
class AnnotationEditor extends StatefulWidget {
  final Uint8List imageBytes;
  final ValueChanged<Uint8List> onConfirm;
  final VoidCallback onCancel;

  const AnnotationEditor({
    super.key,
    required this.imageBytes,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<AnnotationEditor> createState() => _AnnotationEditorState();
}

class _AnnotationEditorState extends State<AnnotationEditor> {
  late final ImagePainterController _controller;
  final FocusNode _focus = FocusNode();
  bool _exporting = false;

  // Region overlay'in floating toolbar'ı ile aynı 8 renk — iki editor
  // arasında tutarlı paleti garanti eder.
  static const List<Color> _palette = [
    Colors.red,
    Colors.orange,
    Colors.yellow,
    Colors.green,
    Colors.blue,
    Colors.purple,
    Colors.white,
    Colors.black,
  ];

  // Region overlay'in stroke slider aralığı ile aynı (1-20).
  static const double _strokeMin = 1;
  static const double _strokeMax = 20;

  static const List<_ToolDef> _tools = [
    _ToolDef(PaintMode.freeStyle, Icons.edit, 'Serbest Çizim'),
    _ToolDef(PaintMode.line, Icons.horizontal_rule, 'Çizgi'),
    _ToolDef(PaintMode.arrow, Icons.arrow_right_alt, 'Ok'),
    _ToolDef(PaintMode.dashLine, Icons.power_input, 'Kesik Çizgi'),
    _ToolDef(PaintMode.rect, Icons.crop_square, 'Dikdörtgen'),
    _ToolDef(PaintMode.circle, Icons.circle_outlined, 'Daire'),
    _ToolDef(PaintMode.text, Icons.text_fields, 'Metin'),
    _ToolDef(PaintMode.none, Icons.pan_tool, 'Taşı / Yakınlaştır'),
  ];

  @override
  void initState() {
    super.initState();
    _controller = ImagePainterController(
      color: Colors.red,
      strokeWidth: 4,
      mode: PaintMode.freeStyle,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    // ImagePainter widget kendi dispose'unda controller'ı dispose ediyor
    // (image_painter v0.7.1 _paint_over_image.dart:439). Burada tekrar
    // çağırmak double-dispose hatası veriyordu.
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_exporting) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onCancel();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _confirm();
      return KeyEventResult.handled;
    }
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final ctrlOrMeta = pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight) ||
        pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight);
    if (ctrlOrMeta && event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (_controller.paintHistory.isNotEmpty) _controller.undo();
      return KeyEventResult.handled;
    }
    if (ctrlOrMeta && event.logicalKey == LogicalKeyboardKey.keyC) {
      _confirm();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _confirm() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final bytes = await _controller.exportImage();
      if (bytes == null) {
        widget.onCancel();
        return;
      }
      widget.onConfirm(bytes);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _onToolSelected(PaintMode mode) async {
    debugPrint('[Yakala/Editor] tool selected: $mode');
    _controller.setMode(mode);
    if (mode == PaintMode.text) {
      final text = await _promptForText();
      if (text == null || text.isEmpty) {
        // İptal: serbest çizime dön ki kullanıcı yanlışlıkla canvas'a
        // tıklarsa text mode'da takılmasın.
        debugPrint('[Yakala/Editor] text dialog cancelled');
        _controller.setMode(PaintMode.freeStyle);
        return;
      }
      // Text PaintInfo: offsets boş bırakılırsa _image_painter render'ı
      // canvas merkezine yerleştirir (lib/src/_image_painter.dart:93).
      // Mode hâlâ PaintMode.text olduğu için kullanıcı sürükleyerek metnin
      // pozisyonunu değiştirebilir (paket içi onTextUpdateMode mekanizması).
      _controller.addPaintInfo(
        PaintInfo(
          mode: PaintMode.text,
          offsets: const [],
          text: text,
          color: _controller.color,
          strokeWidth: _controller.scaledStrokeWidth,
        ),
      );
      debugPrint(
        '[Yakala/Editor] text added: "$text" '
        '(history=${_controller.paintHistory.length})',
      );
    }
  }

  Future<String?> _promptForText() async {
    final textController = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Metin Ekle'),
          content: TextField(
            controller: textController,
            autofocus: true,
            maxLines: 3,
            minLines: 1,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: 'Görsele eklenecek metin',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) =>
                Navigator.of(dialogContext).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(textController.text.trim()),
              child: const Text('Ekle'),
            ),
          ],
        );
      },
    );
    textController.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black.withValues(alpha: 0.92),
        body: SafeArea(
          child: Column(
            children: [
              _buildActionBar(scheme),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ImagePainter.memory(
                      widget.imageBytes,
                      controller: _controller,
                      scalable: true,
                      showControls: false,
                    ),
                  ),
                ),
              ),
              _buildToolbar(scheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionBar(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.black.withValues(alpha: 0.7),
      child: Row(
        children: [
          IconButton(
            tooltip: 'İptal (Esc)',
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: _exporting ? null : widget.onCancel,
          ),
          const Gap(8),
          const Text(
            'Düzenle',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Tooltip(
            message: 'Bitti (Enter / ⌘/Ctrl+C)',
            child: ElevatedButton.icon(
              onPressed: _exporting ? null : _confirm,
              icon: _exporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('Bitti'),
              style: ElevatedButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(ColorScheme scheme) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Colors.black.withValues(alpha: 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final tool in _tools)
                      _toolButton(tool, scheme),
                    const Gap(12),
                    Container(
                      width: 1,
                      height: 28,
                      color: Colors.white24,
                    ),
                    const Gap(12),
                    for (final color in _palette) _colorButton(color, scheme),
                    const Gap(12),
                    Container(
                      width: 1,
                      height: 28,
                      color: Colors.white24,
                    ),
                    const Gap(12),
                    IconButton(
                      tooltip: 'Geri Al (⌘/Ctrl+Z)',
                      icon: const Icon(Icons.undo, color: Colors.white),
                      onPressed: _controller.paintHistory.isEmpty
                          ? null
                          : _controller.undo,
                    ),
                    IconButton(
                      tooltip: 'Tümünü Temizle',
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.white),
                      onPressed: _controller.paintHistory.isEmpty
                          ? null
                          : _controller.clear,
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  const Gap(4),
                  const Icon(Icons.line_weight, color: Colors.white70, size: 18),
                  const Gap(8),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 7),
                      ),
                      child: Slider(
                        min: _strokeMin,
                        max: _strokeMax,
                        value: _controller.strokeWidth
                            .clamp(_strokeMin, _strokeMax),
                        activeColor: scheme.primary,
                        inactiveColor: Colors.white24,
                        onChanged: _controller.setStrokeWidth,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text(
                      _controller.strokeWidth.toStringAsFixed(0),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _toolButton(_ToolDef tool, ColorScheme scheme) {
    final isSelected = _controller.mode == tool.mode;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tool.label,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _onToolSelected(tool.mode),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color:
                  isSelected ? scheme.primary.withValues(alpha: 0.25) : null,
              borderRadius: BorderRadius.circular(8),
              border: isSelected
                  ? Border.all(color: scheme.primary, width: 1.5)
                  : Border.all(color: Colors.transparent, width: 1.5),
            ),
            child: Icon(
              tool.icon,
              color: isSelected ? scheme.primary : Colors.white70,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _colorButton(Color color, ColorScheme scheme) {
    final isSelected = _controller.color.toARGB32() == color.toARGB32();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _controller.setColor(color),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? Colors.white : Colors.white24,
              width: isSelected ? 2.5 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolDef {
  final PaintMode mode;
  final IconData icon;
  final String label;
  const _ToolDef(this.mode, this.icon, this.label);
}
