import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_painter/image_painter.dart';

import 'text_input_dialog.dart';

/// `compute()` argümanı — Rect/Size yerine düz primitives, isolate
/// transfer'inde tip uyuşmazlığı riskini sıfırlar.
class _CropArgs {
  final Uint8List bytes;
  final double left;
  final double top;
  final double width;
  final double height;
  final double logicalWidth;
  final double logicalHeight;

  const _CropArgs({
    required this.bytes,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.logicalWidth,
    required this.logicalHeight,
  });
}

/// Top-level (compute() bunu zorunlu kılar): PNG decode → copyCrop →
/// encode. Hata olursa null. Çağrılan worker isolate'ta paralel çalışır.
Uint8List? _cropPngInIsolate(_CropArgs a) {
  try {
    final decoded = img.decodePng(a.bytes);
    if (decoded == null) return null;
    final sx = decoded.width / a.logicalWidth;
    final sy = decoded.height / a.logicalHeight;
    final x = (a.left * sx).round().clamp(0, decoded.width - 1);
    final y = (a.top * sy).round().clamp(0, decoded.height - 1);
    final w = (a.width * sx).round().clamp(1, decoded.width - x);
    final h = (a.height * sy).round().clamp(1, decoded.height - y);
    final cropped = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
    return Uint8List.fromList(img.encodePng(cropped));
  } catch (_) {
    return null;
  }
}

/// İki fazlı bölge yakalama overlay'i.
///
/// **Phase 1 (selecting):** Sürükle ile bölge seç, 8 handle ile resize, içeride
/// drag ile move. Ctrl/Cmd+C veya Enter ile annotating'e geçer; Esc iptal.
///
/// **Phase 2 (annotating):** Seçim sabitlenir, içine cropped image yerleştirilir,
/// yanında floating toolbar (kalem/çizgi/ok/dikdörtgen/daire/yazı/renk/kalınlık/
/// undo/bitti/iptal) belirir. Ctrl/Cmd+C veya Bitti tıklayınca annotated PNG
/// bytes onConfirm'e gider; Esc seçim fazına döner; X iptal.
class RegionOverlay extends StatefulWidget {
  final Uint8List backgroundImage;
  final Size imagePixelSize;
  final ValueChanged<Uint8List> onConfirm;
  final VoidCallback onCancel;

  const RegionOverlay({
    super.key,
    required this.backgroundImage,
    required this.imagePixelSize,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<RegionOverlay> createState() => _RegionOverlayState();
}

enum _Handle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
}

enum _DragMode { idle, drawing, moving, resizing }

enum _Phase { selecting, annotating }

class _RegionOverlayState extends State<RegionOverlay> {
  static const double _handleSize = 10;
  static const double _handleHitPadding = 8;

  final FocusNode _focus = FocusNode();
  _Phase _phase = _Phase.selecting;

  // Phase 1 state
  Rect? _selection;
  Offset? _drawAnchor;
  Offset? _moveOffset;
  _Handle? _activeHandle;
  _DragMode _mode = _DragMode.idle;
  MouseCursor _currentCursor = SystemMouseCursors.precise;

  // Phase 2 state
  Uint8List? _croppedBytes;
  ImagePainterController? _annotCtrl;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    // _annotCtrl: ImagePainter widget'ı kendi dispose'unda controller'ı dispose
    // ediyor (image_painter v0.7.1). Burada elle dispose edersek double-dispose.
    super.dispose();
  }

  // ───────────────────────── Selection (Phase 1) ─────────────────────────

  void _onPanStart(DragStartDetails d) {
    if (_phase != _Phase.selecting) return;
    final pos = d.localPosition;
    final sel = _selection;
    if (sel != null) {
      final handle = _hitTestHandle(sel, pos);
      if (handle != null) {
        _mode = _DragMode.resizing;
        _activeHandle = handle;
        return;
      }
      if (sel.contains(pos)) {
        _mode = _DragMode.moving;
        _moveOffset = pos - sel.topLeft;
        return;
      }
    }
    _mode = _DragMode.drawing;
    _drawAnchor = pos;
    setState(() => _selection = Rect.fromPoints(pos, pos));
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_phase != _Phase.selecting) return;
    final size = MediaQuery.of(context).size;
    final clamped = Offset(
      d.localPosition.dx.clamp(0.0, size.width),
      d.localPosition.dy.clamp(0.0, size.height),
    );
    setState(() {
      switch (_mode) {
        case _DragMode.drawing:
          _selection = _normalize(Rect.fromPoints(_drawAnchor!, clamped));
          break;
        case _DragMode.moving:
          final sel = _selection!;
          final newTL = clamped - _moveOffset!;
          final dx = newTL.dx.clamp(0.0, size.width - sel.width);
          final dy = newTL.dy.clamp(0.0, size.height - sel.height);
          _selection = Rect.fromLTWH(dx, dy, sel.width, sel.height);
          break;
        case _DragMode.resizing:
          _selection = _normalize(_resize(_selection!, _activeHandle!, clamped));
          break;
        case _DragMode.idle:
          break;
      }
    });
  }

  void _onPanEnd(DragEndDetails _) {
    if (_phase != _Phase.selecting) return;
    final wasDrawing = _mode == _DragMode.drawing;
    final sel = _selection;

    _mode = _DragMode.idle;
    _activeHandle = null;
    _drawAnchor = null;
    _moveOffset = null;

    if (wasDrawing && sel != null && (sel.width < 5 || sel.height < 5)) {
      setState(() => _selection = null);
      return;
    }

    // Endüstri standardı: yeni bir bölge çizimi tamamlandığında (mouse release)
    // toolbar otomatik açılır. Resize/move sonrası transition tetiklenmez —
    // kullanıcı handle'ları ile defalarca ayarlayabilir.
    if (wasDrawing && sel != null) {
      _confirmSelection();
    }
  }

  Rect _normalize(Rect r) => Rect.fromLTRB(
        math.min(r.left, r.right),
        math.min(r.top, r.bottom),
        math.max(r.left, r.right),
        math.max(r.top, r.bottom),
      );

  Rect _resize(Rect r, _Handle h, Offset p) {
    switch (h) {
      case _Handle.topLeft:
        return Rect.fromLTRB(p.dx, p.dy, r.right, r.bottom);
      case _Handle.topRight:
        return Rect.fromLTRB(r.left, p.dy, p.dx, r.bottom);
      case _Handle.bottomLeft:
        return Rect.fromLTRB(p.dx, r.top, r.right, p.dy);
      case _Handle.bottomRight:
        return Rect.fromLTRB(r.left, r.top, p.dx, p.dy);
      case _Handle.top:
        return Rect.fromLTRB(r.left, p.dy, r.right, r.bottom);
      case _Handle.bottom:
        return Rect.fromLTRB(r.left, r.top, r.right, p.dy);
      case _Handle.left:
        return Rect.fromLTRB(p.dx, r.top, r.right, r.bottom);
      case _Handle.right:
        return Rect.fromLTRB(r.left, r.top, p.dx, r.bottom);
    }
  }

  _Handle? _hitTestHandle(Rect r, Offset p) {
    final pad = _handleHitPadding;
    bool near(Offset c) => (p - c).distance <= _handleSize / 2 + pad;
    if (near(r.topLeft)) return _Handle.topLeft;
    if (near(r.topRight)) return _Handle.topRight;
    if (near(r.bottomLeft)) return _Handle.bottomLeft;
    if (near(r.bottomRight)) return _Handle.bottomRight;
    if (near(Offset(r.center.dx, r.top))) return _Handle.top;
    if (near(Offset(r.center.dx, r.bottom))) return _Handle.bottom;
    if (near(Offset(r.left, r.center.dy))) return _Handle.left;
    if (near(Offset(r.right, r.center.dy))) return _Handle.right;
    return null;
  }

  MouseCursor _cursorFor(Offset pos) {
    if (_phase != _Phase.selecting) return SystemMouseCursors.basic;
    final sel = _selection;
    if (sel == null) return SystemMouseCursors.precise;
    final handle = _hitTestHandle(sel, pos);
    if (handle != null) {
      switch (handle) {
        case _Handle.topLeft:
        case _Handle.bottomRight:
          return SystemMouseCursors.resizeUpLeftDownRight;
        case _Handle.topRight:
        case _Handle.bottomLeft:
          return SystemMouseCursors.resizeUpRightDownLeft;
        case _Handle.top:
        case _Handle.bottom:
          return SystemMouseCursors.resizeUpDown;
        case _Handle.left:
        case _Handle.right:
          return SystemMouseCursors.resizeLeftRight;
      }
    }
    if (sel.contains(pos)) return SystemMouseCursors.move;
    return SystemMouseCursors.precise;
  }

  void _updateCursor(Offset pos) {
    final next = _cursorFor(pos);
    if (next != _currentCursor) {
      setState(() => _currentCursor = next);
    }
  }

  // ───────────────────────── Phase transitions ─────────────────────────

  Future<void> _confirmSelection() async {
    final sel = _selection;
    if (sel == null || sel.width < 5 || sel.height < 5) return;

    final logical = MediaQuery.of(context).size;
    debugPrint('[Yakala/RegionOverlay] confirmSelection rect=$sel logical=$logical');
    final cropped = await _cropBackground(sel, logical);
    if (cropped == null) {
      debugPrint('[Yakala/RegionOverlay] crop FAILED — onCancel');
      widget.onCancel();
      return;
    }

    final ctrl = ImagePainterController(
      color: Colors.red,
      strokeWidth: 4,
      mode: PaintMode.freeStyle,
    );
    setState(() {
      _phase = _Phase.annotating;
      _croppedBytes = cropped;
      _annotCtrl = ctrl;
    });
    debugPrint('[Yakala/RegionOverlay] annotating phase ready (cropped=${cropped.length}B)');
  }

  Future<Uint8List?> _cropBackground(Rect logicalRect, Size logicalSize) {
    // 4K ekranda decode/copyCrop/encode toplamı 80-250ms — UI thread'de
    // yapılırsa kullanıcı phase 1→phase 2 geçişinde donma hisseder.
    // compute() ile worker isolate'a alıyoruz; widget rebuild sırasında
    // selection rect + handles render edilmeye devam eder.
    return compute(_cropPngInIsolate, _CropArgs(
      bytes: widget.backgroundImage,
      left: logicalRect.left,
      top: logicalRect.top,
      width: logicalRect.width,
      height: logicalRect.height,
      logicalWidth: logicalSize.width,
      logicalHeight: logicalSize.height,
    ));
  }

  Future<void> _confirmAnnotation() async {
    final ctrl = _annotCtrl;
    if (ctrl == null || _exporting) return;
    setState(() => _exporting = true);
    debugPrint(
      '[Yakala/RegionOverlay] confirmAnnotation start '
      '(history=${ctrl.paintHistory.length})',
    );
    Uint8List? bytes;
    try {
      bytes = await ctrl.exportImage();
    } catch (e, st) {
      debugPrint('[Yakala/RegionOverlay] exportImage HATA: $e\n$st');
    }
    if (!mounted) return;
    // Fallback: cropped image as-is (annotation yapılmadıysa)
    bytes ??= _croppedBytes;
    if (bytes == null) {
      debugPrint('[Yakala/RegionOverlay] export null + croppedBytes null → onCancel');
      widget.onCancel();
      return;
    }
    debugPrint('[Yakala/RegionOverlay] confirm → onConfirm (${bytes.length}B)');
    widget.onConfirm(bytes);
  }

  void _backToSelecting() {
    setState(() {
      _phase = _Phase.selecting;
      _croppedBytes = null;
      _annotCtrl = null; // ImagePainter widget unmount → kendi dispose'unu yapar
    });
  }

  // ───────────────────────── Keyboard ─────────────────────────

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_phase == _Phase.annotating) {
        _backToSelecting();
      } else {
        widget.onCancel();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _phase == _Phase.selecting ? _confirmSelection() : _confirmAnnotation();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyC) {
      final pressed = HardwareKeyboard.instance.logicalKeysPressed;
      final ctrlOrMeta = pressed.contains(LogicalKeyboardKey.controlLeft) ||
          pressed.contains(LogicalKeyboardKey.controlRight) ||
          pressed.contains(LogicalKeyboardKey.metaLeft) ||
          pressed.contains(LogicalKeyboardKey.metaRight);
      if (ctrlOrMeta) {
        _phase == _Phase.selecting
            ? _confirmSelection()
            : _confirmAnnotation();
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.keyZ) {
      final pressed = HardwareKeyboard.instance.logicalKeysPressed;
      final ctrlOrMeta = pressed.contains(LogicalKeyboardKey.controlLeft) ||
          pressed.contains(LogicalKeyboardKey.controlRight) ||
          pressed.contains(LogicalKeyboardKey.metaLeft) ||
          pressed.contains(LogicalKeyboardKey.metaRight);
      if (ctrlOrMeta && _phase == _Phase.annotating) {
        _annotCtrl?.undo();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  // ───────────────────────── Build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: MouseRegion(
        cursor: _currentCursor,
        onHover: (e) {
          if (_phase == _Phase.selecting) _updateCursor(e.localPosition);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background screenshot — her zaman zemin
            Positioned.fill(
              child: Image.memory(
                widget.backgroundImage,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.medium,
              ),
            ),
            // Dim overlay (her iki fazda da, selection'da delik)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _DimPainter(_selection)),
              ),
            ),

            // Phase 1: gesture detector + handles
            if (_phase == _Phase.selecting) ...[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                ),
              ),
              if (_selection != null) ..._buildSelectionUI(_selection!),
              const Positioned(
                bottom: 30,
                left: 0,
                right: 0,
                child: Center(child: _HintBar(phase: _Phase.selecting)),
              ),
            ],

            // Phase 2: ImagePainter inside selection + floating toolbar
            if (_phase == _Phase.annotating &&
                _selection != null &&
                _croppedBytes != null &&
                _annotCtrl != null) ...[
              Positioned.fromRect(
                rect: _selection!,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  child: ClipRect(
                    child: ImagePainter.memory(
                      _croppedBytes!,
                      controller: _annotCtrl!,
                      showControls: false,
                      scalable: false,
                    ),
                  ),
                ),
              ),
              _AnnotationToolbar(
                selection: _selection!,
                controller: _annotCtrl!,
                exporting: _exporting,
                onDone: _confirmAnnotation,
                onCancel: widget.onCancel,
                onBack: _backToSelecting,
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSelectionUI(Rect sel) {
    return [
      Positioned.fromRect(
        rect: sel,
        child: IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 1),
            ),
          ),
        ),
      ),
      ..._handleWidgets(sel),
      Positioned(
        left: sel.left,
        top: sel.top - 26 < 4 ? sel.top + 6 : sel.top - 24,
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${sel.width.round()} × ${sel.height.round()}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontFamily: 'Menlo',
              ),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _handleWidgets(Rect sel) {
    final positions = <_Handle, Offset>{
      _Handle.topLeft: sel.topLeft,
      _Handle.top: Offset(sel.center.dx, sel.top),
      _Handle.topRight: sel.topRight,
      _Handle.right: Offset(sel.right, sel.center.dy),
      _Handle.bottomRight: sel.bottomRight,
      _Handle.bottom: Offset(sel.center.dx, sel.bottom),
      _Handle.bottomLeft: sel.bottomLeft,
      _Handle.left: Offset(sel.left, sel.center.dy),
    };
    return positions.entries.map((e) {
      final p = e.value;
      return Positioned(
        left: p.dx - _handleSize / 2,
        top: p.dy - _handleSize / 2,
        width: _handleSize,
        height: _handleSize,
        child: IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.deepPurpleAccent, width: 1),
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 2,
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }
}

class _DimPainter extends CustomPainter {
  final Rect? selection;
  _DimPainter(this.selection);

  @override
  void paint(Canvas canvas, ui.Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.45);
    final full = Offset.zero & size;
    if (selection == null) {
      canvas.drawRect(full, paint);
      return;
    }
    final path = Path()
      ..addRect(full)
      ..addRect(selection!)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_DimPainter old) => old.selection != selection;
}

class _HintBar extends StatelessWidget {
  final _Phase phase;
  const _HintBar({required this.phase});

  @override
  Widget build(BuildContext context) {
    final text = phase == _Phase.selecting
        ? 'Sürükle: bölge seç (bırakınca düzenleme açılır)   •   '
            'Köşe/kenar: yeniden boyutlandır   •   Esc: iptal'
        : '⌘/Ctrl+C veya Enter: kopyala   •   ⌘/Ctrl+Z: geri al   •   '
            'Esc: seçime dön';
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }
}

// ─────────────────── Floating annotation toolbar ───────────────────

class _AnnotationToolbar extends StatefulWidget {
  final Rect selection;
  final ImagePainterController controller;
  final bool exporting;
  final VoidCallback onDone;
  final VoidCallback onCancel;
  final VoidCallback onBack;

  const _AnnotationToolbar({
    required this.selection,
    required this.controller,
    required this.exporting,
    required this.onDone,
    required this.onCancel,
    required this.onBack,
  });

  @override
  State<_AnnotationToolbar> createState() => _AnnotationToolbarState();
}

class _AnnotationToolbarState extends State<_AnnotationToolbar> {
  static const _toolbarHeight = 52.0;
  static const _margin = 12.0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChange);
    super.dispose();
  }

  void _onControllerChange() {
    if (mounted) setState(() {});
  }

  /// Yazı butonunun sahip olduğu davranış: dialog ile metni al, paint
  /// history'e ekle. `image_painter` v0.7.1'de canvas'ta "tıkla→metin gir"
  /// mekanizması yok; metin paket içinde ancak `addPaintInfo(PaintInfo(
  /// mode: text, ...))` ile görünür hale gelir. `offsets: const []`
  /// bırakıldığında metin canvas merkezine yerleşir
  /// (_image_painter.dart:93). Mode `text` kalırsa sürükleyerek
  /// pozisyonlanabilir (paket içi onTextUpdateMode).
  Future<void> _promptText() async {
    final ctrl = widget.controller;
    debugPrint('[Yakala/Toolbar] text button tapped — opening dialog');
    ctrl.setMode(PaintMode.text);
    final text = await _showTextDialog(context);
    if (!mounted) return;
    if (text == null || text.isEmpty) {
      debugPrint('[Yakala/Toolbar] text dialog cancelled — reverting to freeStyle');
      ctrl.setMode(PaintMode.freeStyle);
      return;
    }
    ctrl.addPaintInfo(
      PaintInfo(
        mode: PaintMode.text,
        offsets: const [],
        text: text,
        color: ctrl.color,
        strokeWidth: ctrl.scaledStrokeWidth,
      ),
    );
    debugPrint(
      '[Yakala/Toolbar] text added: "$text" '
      '(history=${ctrl.paintHistory.length}, color=${ctrl.color}, '
      'fontPx=${(6 * ctrl.scaledStrokeWidth).toStringAsFixed(0)})',
    );
  }

  Future<String?> _showTextDialog(BuildContext ctx) {
    return TextInputDialog.show(
      ctx,
      title: 'Metin Ekle',
      hintText: 'Görsele eklenecek metin',
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final sel = widget.selection;

    // Konumlandırma: önce altta dene, olmazsa üstte, yoksa sağa
    double top;
    if (sel.bottom + _margin + _toolbarHeight < screenSize.height - 20) {
      top = sel.bottom + _margin;
    } else if (sel.top - _margin - _toolbarHeight > 20) {
      top = sel.top - _margin - _toolbarHeight;
    } else {
      top = screenSize.height - _toolbarHeight - 20;
    }

    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: Center(child: _ToolbarBar(controller: widget.controller, parent: this)),
    );
  }
}

class _ToolbarBar extends StatelessWidget {
  final ImagePainterController controller;
  final _AnnotationToolbarState parent;

  const _ToolbarBar({required this.controller, required this.parent});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: Container(
        height: _AnnotationToolbarState._toolbarHeight,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToolBtn(
              icon: Icons.edit,
              tooltip: 'Serbest çizim',
              active: controller.mode == PaintMode.freeStyle,
              onTap: () => controller.setMode(PaintMode.freeStyle),
            ),
            _ToolBtn(
              icon: Icons.show_chart,
              tooltip: 'Çizgi',
              active: controller.mode == PaintMode.line,
              onTap: () => controller.setMode(PaintMode.line),
            ),
            _ToolBtn(
              icon: Icons.arrow_forward,
              tooltip: 'Ok',
              active: controller.mode == PaintMode.arrow,
              onTap: () => controller.setMode(PaintMode.arrow),
            ),
            _ToolBtn(
              icon: Icons.crop_square,
              tooltip: 'Dikdörtgen',
              active: controller.mode == PaintMode.rect,
              onTap: () => controller.setMode(PaintMode.rect),
            ),
            _ToolBtn(
              icon: Icons.circle_outlined,
              tooltip: 'Daire',
              active: controller.mode == PaintMode.circle,
              onTap: () => controller.setMode(PaintMode.circle),
            ),
            _ToolBtn(
              icon: Icons.text_fields,
              tooltip: 'Yazı',
              active: controller.mode == PaintMode.text,
              onTap: parent._promptText,
            ),
            const _Divider(),
            _ColorPicker(
              current: controller.color,
              onPick: controller.setColor,
            ),
            const _Divider(),
            _StrokeSlider(
              value: controller.strokeWidth,
              onChanged: controller.setStrokeWidth,
            ),
            const _Divider(),
            _ToolBtn(
              icon: Icons.undo,
              tooltip: 'Geri al (⌘/Ctrl+Z)',
              onTap: controller.undo,
            ),
            _ToolBtn(
              icon: Icons.delete_outline,
              tooltip: 'Tümünü sil',
              onTap: controller.clear,
            ),
            const _Divider(),
            IconButton(
              tooltip: 'Seçime dön (Esc)',
              icon: const Icon(Icons.crop, color: Colors.white70, size: 20),
              onPressed: parent.widget.onBack,
            ),
            IconButton(
              tooltip: 'İptal',
              icon: const Icon(Icons.close, color: Colors.white70, size: 20),
              onPressed: parent.widget.onCancel,
            ),
            const SizedBox(width: 6),
            ElevatedButton.icon(
              onPressed: parent.widget.exporting ? null : parent.widget.onDone,
              icon: parent.widget.exporting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check, size: 18),
              label: const Text('Bitti'),
              style: ElevatedButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.white24,
    );
  }
}

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;

  const _ToolBtn({
    required this.icon,
    required this.tooltip,
    this.active = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 34,
          height: 34,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: active ? scheme.primary.withValues(alpha: 0.3) : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 18,
            color: active ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }
}

class _ColorPicker extends StatelessWidget {
  final Color current;
  final ValueChanged<Color> onPick;

  const _ColorPicker({required this.current, required this.onPick});

  static const _palette = [
    Colors.red,
    Colors.orange,
    Colors.yellow,
    Colors.green,
    Colors.blue,
    Colors.purple,
    Colors.white,
    Colors.black,
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: _palette.map((c) {
        final selected = c.toARGB32() == current.toARGB32();
        return GestureDetector(
          onTap: () => onPick(c),
          child: Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? Colors.white : Colors.white24,
                width: selected ? 2 : 1,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _StrokeSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _StrokeSlider({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 2,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: SliderComponentShape.noOverlay,
          activeTrackColor: Colors.white,
          inactiveTrackColor: Colors.white24,
          thumbColor: Colors.white,
        ),
        child: Slider(
          min: 1,
          max: 20,
          value: value.clamp(1, 20),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
