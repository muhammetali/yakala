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

  /// Linux off-screen "hide" pattern için sabitler.
  ///
  /// **Neden gerçek `windowManager.hide()` kullanmıyoruz (Linux'ta):**
  /// GTK pencere `Withdrawn` state'e geçtiğinde Flutter engine **paused**
  /// state'e iniyor — Dart isolate'in event loop'u throttle ediliyor. Sonuç:
  /// tray menü click'leri, global hotkey'ler, IPC komutları Dart tarafına
  /// ulaşmıyor. Empirik kanıt: ilk capture'dan sonra (ki son adımı
  /// `hide()`'tır) tray item'ları, hotkey, settings — hepsi tepkisiz; sadece
  /// uygulama tamamen restart edilince çalışıyor.
  ///
  /// **Çözüm**: pencereyi `show()` durumunda tut ama görünmez yap —
  /// 1×1 boyut, ekran dışı pozisyon, opacity 0, taskbar dışı. GTK pencereyi
  /// `Mapped/Visible` sayar → engine paused state'e girmez → tüm event
  /// loop'lar canlı kalır. Bu Discord, Slack, Telegram'ın Linux tray
  /// uygulamalarında kullandığı standart pattern.
  ///
  /// macOS/Windows'ta engine pause sorunu yok → orada gerçek `hide()` kalır.
  static const Offset _offScreenPosition = Offset(-32000, -32000);
  static const Size _offScreenSize = Size(1, 1);

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
    debugPrint(
      '[Yakala/Window] init build=v4-fullscreen-first-then-hide '
      'settingsSize=${_settingsSize.width.toStringAsFixed(0)}x'
      '${_settingsSize.height.toStringAsFixed(0)}',
    );

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
      // Defansif: ilk açılışta pencere fullscreen/maximized state'inde
      // gelmesin (önceki bir crash window state'i bozmuş olabilir, GTK
      // window manager bunu hatırlıyor olabilir).
      if (!Platform.isMacOS) {
        await _safe(() => windowManager.setFullScreen(false));
        await _safe(() => windowManager.unmaximize());
        await _safe(() => windowManager.setSize(_settingsSize));
      }
      await _hideToBackground();
    });

    windowManager.addListener(this);
    _initialized = true;
  }

  Future<void> showSettings() async {
    debugPrint('[Yakala/Window] showSettings v5 (defensive geometry reset + opacity)');
    if (_inOverlayMode) {
      await exitOverlay();
    } else if (!Platform.isMacOS) {
      // Agresif geometry reset: pencere fullscreen/maximized/oversized
      // state'inde takılı kalmış olabilir (önceki capture'ın crash'i, WM
      // artifact, _inOverlayMode flag'inin gerçek pencere state'iyle
      // uyuşmaması). Tüm modlardan çık + boyutu/pozisyonu yeniden zorla.
      // Linux'ta hide() pencereyi off-screen + opacity 0'a koyuyor — burada
      // tersine çevirmemiz şart.
      await _safe(() => windowManager.setFullScreen(false));
      await _safe(() => windowManager.unmaximize());
      await _safe(() => windowManager.setAlwaysOnTop(false));
      await _safe(() => windowManager.setResizable(true));
      await _safe(() => windowManager.setSize(_settingsSize));
      await _safe(() => windowManager.setOpacity(1.0));
      await _safe(() => windowManager.center());
    }
    _settingsVisible = true;
    notifyListeners();
    await _safe(() => windowManager.show());
    await _safe(() => windowManager.focus());
  }

  Future<void> hide() async {
    _settingsVisible = false;
    notifyListeners();
    await _hideToBackground();
  }

  /// Linux'ta pencereyi `Mapped/Visible` durumda tutarken görünmez yapar
  /// (engine pause'u engellemek için). macOS/Windows'ta gerçek `hide()`.
  /// Bkz. sınıf-üstü dokümantasyon.
  Future<void> _hideToBackground() async {
    if (!Platform.isLinux) {
      await _safe(() => windowManager.hide());
      return;
    }
    // Linux: off-screen + 1×1 + opacity 0. show() çağrısı pencereyi
    // mapped state'te tutar — Flutter engine paused olmaz.
    await _safe(() => windowManager.setAlwaysOnTop(false));
    await _safe(() => windowManager.setFullScreen(false));
    await _safe(() => windowManager.unmaximize());
    await _safe(() => windowManager.setResizable(true));
    await _safe(() => windowManager.setSkipTaskbar(true));
    await _safe(() => windowManager.setSize(_offScreenSize));
    await _safe(() => windowManager.setPosition(_offScreenPosition));
    await _safe(() => windowManager.setOpacity(0));
    // KRİTİK: show() çağrısı GTK pencereyi mapped state'e geçirir →
    // engine paused state'e girmez. Off-screen + opacity 0 olduğu için
    // kullanıcı için görünmez.
    await _safe(() => windowManager.show());
    debugPrint('[Yakala/Window] hidden via off-screen pattern (engine kept alive)');
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
    // Linux'ta off-screen hide pencereyi opacity 0 + 1×1'de bırakıyor —
    // overlay'e geçmeden önce reset şart, yoksa fullscreen overlay görünmez.
    if (Platform.isLinux) {
      await _safe(() => windowManager.setOpacity(1.0));
    }
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
    debugPrint('[Yakala/Window] enterOverlay v4 — focus() çağrıldı, Linux retry başlıyor');
    // Linux X11/Wayland'de frameless+alwaysOnTop+fullscreen pencerelerde WM
    // ilk `focus()` çağrısını sıkça gözardı eder (focus stealing prevention,
    // veya pencere henüz fully mapped olmamış). Sonuç: Flutter engine key
    // event almaz, RegionOverlay'in `Focus(autofocus: true)` widget'ı tetiklenmez,
    // Esc/Enter çalışmaz. Multi-stage retry — başarı garantisi yok ama X11'de
    // pratikte iş görüyor; her aşamada hala overlay mode'daysa tekrar dene.
    if (Platform.isLinux) {
      for (final ms in const [100, 300, 600]) {
        Future.delayed(Duration(milliseconds: ms), () async {
          if (_inOverlayMode) {
            debugPrint('[Yakala/Window] focus retry @ ${ms}ms');
            await _safe(() => windowManager.focus());
          }
        });
      }
    }
  }

  Future<void> exitOverlay() async {
    if (!_inOverlayMode) return;
    debugPrint('[Yakala/Window] exitOverlay v6 — paint-flush + verified unfullscreen');
    // Önce flag'i çevir + notify et — `WindowService notification ordering`
    // testi notify zamanında inOverlayMode=false bekliyor + widget tree
    // overlay widget'ını mount'tan düşürebilmeli.
    _inOverlayMode = false;
    notifyListeners();

    // KRİTİK 1 — paint flush:
    // notifyListeners() sadece next-frame'e build schedule eder; widget
    // tree (Consumer3) ColoredBox(transparent)'a geçiş için frame'in
    // gerçekten paint olmasını beklemeliyiz. Aksi halde GTK son rendered
    // frame'i (AnnotationEditor — siyah arka plan + foto) buffered tutuyor;
    // pencere boyutu/pozisyonu değişse bile içerik kalıyor (semptom:
    // "editor Bitti'den sonra ekrandan gitmiyor").
    //
    // Frame schedule etmek için scheduleFrame çağırıyoruz; sonra endOfFrame
    // ile bekliyoruz. Test ortamında (flutter_test) pump çağrılmadıkça
    // frame oluşmuyor → 200ms timeout ile bypass.
    try {
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame
          .timeout(const Duration(milliseconds: 200));
    } catch (_) {}

    // KRİTİK 2 — Linux GTK invariant'ı: `gtk_widget_hide()` ve geometry
    // operasyonları fullscreen state'inde güvenilir çalışmıyor. Önce
    // setFullScreen(false), SONRA gerçekten unfullscreen olduğunu polling
    // ile doğrula — Mutter (GNOME 46) unfullscreen request'lerini bazen
    // yutuyor (özellikle art arda capture cycle'larında).
    //
    // Eski v4 fix'i sabit 80ms delay kullanıyordu; user setup'ında yetmedi.
    // Polling deadline 1500ms — modern WM'lerde unfullscreen 50-300ms,
    // bu sınır safety margin.
    if (!Platform.isMacOS) {
      await _safe(() => windowManager.setFullScreen(false));
      final deadline = DateTime.now().add(const Duration(milliseconds: 1500));
      var pollCount = 0;
      while (DateTime.now().isBefore(deadline)) {
        bool stillFs = true;
        try {
          stillFs = await windowManager.isFullScreen();
        } catch (_) {
          // isFullScreen başarısız — emin değiliz, polling'e devam ama
          // 100ms daha sonra deadline'ı zorla.
          stillFs = true;
        }
        if (!stillFs) break;
        pollCount++;
        await Future.delayed(const Duration(milliseconds: 50));
      }
      debugPrint('[Yakala/Window] unfullscreen polled (iters=$pollCount)');
      await _safe(() => windowManager.unmaximize());
    }
    if (Platform.isMacOS) {
      await _safe(() => windowManager.setMovable(true));
    }
    // Linux'ta hide() yerine off-screen background'a in (engine paused
    // olmasın → tray/hotkey/IPC event loop'ları canlı kalsın). macOS/Windows
    // _hideToBackground gerçek hide yapar.
    await _hideToBackground();
    debugPrint('[Yakala/Window] exitOverlay v6 — done');
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
