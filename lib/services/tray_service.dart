import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart' as tm;
import 'package:yakala/models/capture_mode.dart';
import 'package:yakala/utils/tray_utils.dart';

/// Tray menüsü servisi (`tray_manager` paketi → libayatana-appindicator /
/// StatusNotifierItem).
///
/// **Eski sürümün (system_tray 2.0.3) düşürülme sebebi**: paket 3 yıldır
/// güncellenmemiş; Linux backend'inde menü click 1'den sonra DBus seviyesinde
/// dead-end oluşuyordu — AppIndicator daemon menüyü "kullanıldı" olarak
/// işaretleyip 2. click'i Dart'a hiç iletmiyordu. Yeni `Menu` objesi rebuild
/// + 250ms debounce workaround'u logla teyitli olarak yetmedi (`menu (re)built
/// (region)` log'undan sonra kullanıcı tıkladı, hiçbir log akmadı).
///
/// **`tray_manager` neden tercih edildi**:
///   1. leanflutter.dev verified publisher — projedeki `window_manager`,
///      `hotkey_manager`, `screen_retriever`, `screen_capturer`'ın aynı ekibi.
///   2. Aktif bakım (6 ay önce yayın) ve 104k weekly download.
///   3. Linux'ta StatusNotifierItem-tabanlı modern protocol → menu staleness
///      semptomu raporlanmamış.
///
/// **Click coalescing korundu**: bir capture in-flight iken yeni tray click'leri
/// `_clickBusy` ile sessizce drop edilir → CaptureService re-entry guard'ı
/// zaten engeller ama tray seviyesinde de drop etmek log gürültüsünü azaltır
/// ve action kuyruğu büyümez.
///
/// **Eski rebuild zamanlayıcısı kaldırıldı** — `system_tray`'e özgü bir
/// workaround'du; `tray_manager`'da setContextMenu sonrası menü taze kalıyor.
/// Test surface'i (`debugHasPendingRebind`) korundu, hep `false` döner.
class TrayService with tm.TrayListener {
  // Menu key → action eşlemesi. `onTrayMenuItemClick` global callback'inde
  // item'ı `key` ile ayırt ediyoruz. system_tray dönemindeki per-item closure
  // pattern yerine: `tray_manager` tüm item click'lerini tek listener'a
  // yönlendiriyor.
  static const _keyFullScreen = 'capture_full_screen';
  static const _keyRegion = 'capture_region';
  static const _keyWindow = 'capture_window';
  static const _keySettings = 'open_settings';
  static const _keyQuit = 'quit_app';

  bool _initialized = false;
  bool _clickBusy = false;
  String? _iconPath;

  Future<void> Function(CaptureMode)? _onCapture;
  Future<void> Function()? _onSettings;
  Future<void> Function()? _onQuit;

  Future<void> initialize({
    required String hotkeyLabel,
    required Future<void> Function(CaptureMode) onCapture,
    required Future<void> Function() onSettings,
    required Future<void> Function() onQuit,
  }) async {
    if (_initialized) return;

    _onCapture = onCapture;
    _onSettings = onSettings;
    _onQuit = onQuit;

    _iconPath = await TrayUtils.getIconPath();
    await tm.trayManager.setIcon(_iconPath!);
    await _safe(() => tm.trayManager.setToolTip('Yakala — $hotkeyLabel'));
    await _setMenu();

    tm.trayManager.addListener(this);
    _initialized = true;
    debugPrint('[Yakala/Tray] initialized (tray_manager)');
  }

  /// Yeni `Menu` inşa eder ve `setContextMenu`'ya verir. Tek atımlık —
  /// `tray_manager`'da rebuild gerekmez (system_tray dönemindeki gibi).
  Future<void> _setMenu() async {
    final menu = tm.Menu(items: [
      tm.MenuItem(
        key: _keyFullScreen,
        label: CaptureMode.fullScreen.label,
      ),
      tm.MenuItem(
        key: _keyRegion,
        label: CaptureMode.region.label,
      ),
      tm.MenuItem(
        key: _keyWindow,
        label: CaptureMode.window.label,
      ),
      tm.MenuItem.separator(),
      tm.MenuItem(
        key: _keySettings,
        label: 'Ayarlar',
      ),
      tm.MenuItem.separator(),
      tm.MenuItem(
        key: _keyQuit,
        label: 'Çıkış',
      ),
    ]);
    try {
      await tm.trayManager.setContextMenu(menu);
      debugPrint('[Yakala/Tray] menu set');
    } catch (e) {
      debugPrint('[Yakala/Tray] setContextMenu failed: $e');
    }
  }

  /// Hotkey değişince tooltip'i günceller.
  Future<void> updateTooltip(String hotkeyLabel) async {
    if (!_initialized) return;
    await _safe(() => tm.trayManager.setToolTip('Yakala — $hotkeyLabel'));
  }

  Future<void> dispose() async {
    if (!_initialized) return;
    tm.trayManager.removeListener(this);
    try {
      await tm.trayManager.destroy();
    } catch (e) {
      debugPrint('[Yakala/Tray] destroy hatası (yutuldu): $e');
    }
    _initialized = false;
  }

  // ────────────────── TrayListener implementations ──────────────────

  @override
  void onTrayIconMouseDown() {
    // Linux'ta libappindicator sol-click'te menüyü otomatik açar.
    // Windows/macOS'ta menüyü manuel pop-up etmek gerekir.
    if (Platform.isWindows || Platform.isMacOS) {
      tm.trayManager.popUpContextMenu();
    }
  }

  @override
  void onTrayIconMouseUp() {}

  @override
  void onTrayIconRightMouseDown() {
    // Windows context menu sağ tıkta açılır.
    if (Platform.isWindows) {
      tm.trayManager.popUpContextMenu();
    }
  }

  @override
  void onTrayIconRightMouseUp() {}

  @override
  void onTrayMenuItemClick(tm.MenuItem menuItem) {
    final key = menuItem.key;
    debugPrint('[Yakala/Tray] menu click key=$key');
    final cap = _onCapture;
    final set = _onSettings;
    final quit = _onQuit;

    switch (key) {
      case _keyFullScreen:
        if (cap != null) {
          handleClick('fullScreen', () => cap(CaptureMode.fullScreen));
        }
        break;
      case _keyRegion:
        if (cap != null) {
          handleClick('region', () => cap(CaptureMode.region));
        }
        break;
      case _keyWindow:
        if (cap != null) {
          handleClick('window', () => cap(CaptureMode.window));
        }
        break;
      case _keySettings:
        if (set != null) handleClick('settings', set);
        break;
      case _keyQuit:
        // Çıkış busy guard'ını bypass eder — exit(0) her zaman geçmeli,
        // capture in-flight olsa bile kullanıcı uygulamayı kapatabilmeli.
        if (quit != null) {
          debugPrint('[Yakala/Tray] click quit');
          quit();
        }
        break;
      default:
        debugPrint('[Yakala/Tray] bilinmeyen menu key: $key');
    }
  }

  // ────────────────── Click coalescing ──────────────────

  /// Test'lerin doğrudan çağırması için public.
  ///
  /// Sözleşme:
  ///   - `_clickBusy == true` → erken dön (drop, sayaç artmaz, action çalışmaz)
  ///   - aksi halde flag set, action await, finally release
  @visibleForTesting
  Future<void> handleClick(
    String name,
    Future<void> Function() action,
  ) async {
    if (_clickBusy) {
      debugPrint('[Yakala/Tray] click $name dropped (already busy)');
      return;
    }
    _clickBusy = true;
    _acceptedClickCount++;
    debugPrint('[Yakala/Tray] click $name');
    try {
      await action();
    } catch (e, st) {
      debugPrint('[Yakala/Tray] $name handler exception: $e\n$st');
    } finally {
      _clickBusy = false;
      // Ubuntu GNOME 46 + ubuntu-appindicators extension bug'ı: menu item
      // activation sonrası extension callback registration'ı stale kalıyor —
      // 2. tıklamada menü açılıyor (ikon kaydı yaşıyor) ama item click event'i
      // Dart'a hiç gelmiyor (forensic log ile teyitli). Workaround: tray
      // ikonunu komple destroy + recreate → extension yeni bir kayıt olarak
      // görür, callback'leri tekrar dispatch eder.
      //
      // Cost: 2-3 DBus round-trip (~10-30ms), fire-and-forget olduğu için
      // kullanıcı için görünmez. macOS/Windows'ta gerek yok — orada native
      // tray API'si callback registration'ı korur.
      if (Platform.isLinux && _initialized) {
        unawaited(_recreateTray());
      }
    }
  }

  /// Linux GNOME extension callback-staleness workaround. Bkz. [handleClick]
  /// finally bloğundaki kapsamlı yorum.
  Future<void> _recreateTray() async {
    if (!_initialized) return;
    final path = _iconPath;
    if (path == null) return;
    try {
      await tm.trayManager.destroy();
    } catch (e) {
      debugPrint('[Yakala/Tray] recreate destroy hatası (yutuldu): $e');
    }
    try {
      await tm.trayManager.setIcon(path);
      await _setMenu();
      debugPrint('[Yakala/Tray] tray recreated (callback registration reset)');
    } catch (e) {
      debugPrint('[Yakala/Tray] recreate setIcon/setMenu hatası: $e');
    }
  }

  Future<void> _safe(Future<void> Function() op) async {
    try {
      await op();
    } catch (e) {
      debugPrint('[Yakala/Tray] op hatası (yutuldu): $e');
    }
  }

  // ────────────────── @visibleForTesting gözlem noktaları ──────────────────

  /// Drop edilmeden gerçekten action'a giren click sayısı.
  int _acceptedClickCount = 0;

  @visibleForTesting
  int get debugAcceptedClickCount => _acceptedClickCount;

  @visibleForTesting
  bool get debugClickBusy => _clickBusy;

  /// Geriye dönük test compat. Eski sürümde menü-rebuild zamanlayıcısı vardı;
  /// `tray_manager`'da gerek yok, hep `false` döner.
  @visibleForTesting
  bool get debugHasPendingRebind => false;
}
