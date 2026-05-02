import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Ana pencere yöneticisi + reactive visibility state.
///
/// `settingsVisible` flag'i kullanıcının **kasıtlı olarak** Settings sayfasını
/// açtığını işaretler. Widget tree fallback olarak SettingsPage göstermez —
/// yalnız `settingsVisible == true` ise. Bu sayede capture confirm sonrası
/// region overlay → kapanma transition'ında fullscreen settings flash olmaz.
class WindowService extends ChangeNotifier with WindowListener {
  static const Size _settingsSize = Size(560, 640);

  bool _initialized = false;
  bool _inOverlayMode = false;
  bool _settingsVisible = false;

  bool get settingsVisible => _settingsVisible;
  bool get inOverlayMode => _inOverlayMode;

  Future<void> initialize() async {
    if (_initialized) return;
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
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
