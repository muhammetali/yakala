import 'dart:io';

import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

/// Ana pencere yöneticisi + reactive visibility state.
///
/// `settingsVisible` flag'i kullanıcının **kasıtlı olarak** Settings sayfasını
/// açtığını işaretler. Widget tree fallback olarak SettingsPage göstermez —
/// yalnız `settingsVisible == true` ise. Bu sayede capture confirm sonrası
/// region overlay → kapanma transition'ında fullscreen settings flash olmaz.
class WindowService extends ChangeNotifier with WindowListener {
  /// Settings dialog'unun "tasarım" boyutu (1.0x scale için). HiDPI
  /// ekranlarda ekran scaleFactor'ına göre büyütülür — `_settingsSize`
  /// runtime'da hesaplanır.
  static const Size _baseSettingsSize = Size(560, 640);

  /// scaleFactor üst sınırı: 4K ekranda bile 1120×1280'i geçmesin diye
  /// (kullanıcı küçük pencere isterse zaten resize edebilir).
  static const double _maxScale = 2.0;

  bool _initialized = false;
  bool _inOverlayMode = false;
  bool _settingsVisible = false;
  Size _settingsSize = _baseSettingsSize;

  bool get settingsVisible => _settingsVisible;
  bool get inOverlayMode => _inOverlayMode;

  Future<void> initialize() async {
    if (_initialized) return;
    await windowManager.ensureInitialized();

    _settingsSize = await _resolveSettingsSize();

    final windowOptions = WindowOptions(
      size: _settingsSize,
      center: true,
      skipTaskbar: true,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      backgroundColor: Colors.transparent,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setPreventClose(true);
      await windowManager.hide();
    });

    windowManager.addListener(this);
    _initialized = true;
  }

  Future<void> showSettings() async {
    if (_inOverlayMode) await exitOverlay();
    _settingsVisible = true;
    notifyListeners();
    await _safe(() => windowManager.show());
    await _safe(() => windowManager.focus());
  }

  Future<void> hide() async {
    _settingsVisible = false;
    notifyListeners();
    await _safe(() => windowManager.hide());
  }

  /// Fullscreen, frameless, transparent, always-on-top overlay moduna geç.
  ///
  /// Linux/Windows'da panelleri (üst menü, görev çubuğu) kapsayabilmek için
  /// gerçek `setFullScreen(true)` kullanılır — aksi halde WM strut'lara saygı
  /// gösterip overlay'i çalışma alanına sıkıştırır. macOS'ta fullscreen yeni
  /// bir Space açacağından, orada borderless+alwaysOnTop yeterli.
  Future<void> enterOverlay(Size logicalSize) async {
    _inOverlayMode = true;
    _settingsVisible = false;
    notifyListeners();
    await _safe(() => windowManager.setAlwaysOnTop(true));
    await _safe(() => windowManager.setResizable(false));
    if (Platform.isMacOS) {
      await _safe(() => windowManager.setMovable(false));
      await _safe(() => windowManager.setSize(logicalSize));
      await _safe(() => windowManager.setPosition(Offset.zero));
    } else {
      await _safe(() => windowManager.setSize(logicalSize));
      await _safe(() => windowManager.setPosition(Offset.zero));
      await _safe(() => windowManager.setFullScreen(true));
    }
    await _safe(() => windowManager.show());
    await _safe(() => windowManager.focus());
  }

  Future<void> exitOverlay() async {
    if (!_inOverlayMode) return;
    if (!Platform.isMacOS) {
      await _safe(() => windowManager.setFullScreen(false));
    }
    // Pencereyi ÖNCE gizle ki overlay → settings transition'ında flash olmasın.
    await _safe(() => windowManager.hide());
    _inOverlayMode = false;
    notifyListeners();
    await _safe(() => windowManager.setAlwaysOnTop(false));
    await _safe(() => windowManager.setResizable(true));
    if (Platform.isMacOS) {
      await _safe(() => windowManager.setMovable(true));
    }
    await _safe(() => windowManager.setSize(_settingsSize));
    await _safe(() => windowManager.center());
  }

  /// Primary display'in scaleFactor'ına göre Settings penceresi boyutunu
  /// hesaplar. Hata olursa base boyut. macOS'ta scaleFactor genelde 2.0
  /// (Retina); Linux Wayland'da 1.0/1.25/1.5 yaygın; Windows'ta 1.0/1.25/
  /// 1.5/2.0 yaygın.
  Future<Size> _resolveSettingsSize() async {
    try {
      final display = await screenRetriever.getPrimaryDisplay();
      var scale = display.scaleFactor?.toDouble() ?? 1.0;
      if (scale.isNaN || scale <= 0) scale = 1.0;
      if (scale > _maxScale) scale = _maxScale;
      return Size(
        _baseSettingsSize.width * scale,
        _baseSettingsSize.height * scale,
      );
    } catch (e) {
      debugPrint('WindowService: scaleFactor okunamadı, base boyut: $e');
      return _baseSettingsSize;
    }
  }

  Future<void> _safe(Future<void> Function() op) async {
    try {
      await op();
    } catch (e) {
      debugPrint('WindowService op hatası (yutuldu): $e');
    }
  }

  @override
  void onWindowClose() async {
    if (_inOverlayMode) {
      await exitOverlay();
      return;
    }
    await hide();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _initialized = false;
    super.dispose();
  }
}
