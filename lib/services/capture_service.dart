import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:screen_capturer/screen_capturer.dart' as sc;
import 'package:screen_retriever/screen_retriever.dart';
import 'package:yakala/models/capture_mode.dart';
import 'package:yakala/models/capture_result.dart';
import 'package:yakala/providers/settings_provider.dart';
import 'package:yakala/services/annotation_service.dart';
import 'package:yakala/services/notification_service.dart';
import 'package:yakala/services/region_selector_service.dart';
import 'package:yakala/services/sound_service.dart';
import 'package:yakala/services/window_service.dart';
import 'package:yakala/utils/clipboard_utils.dart';
import 'package:yakala/utils/silent_capture.dart';

/// Tüm yakalama akışını yöneten orkestratör.
/// Akış: capture → (opsiyonel) annotation editor → finalize (clipboard + disk + ses + bildirim).
class CaptureService {
  final SettingsProvider settings;
  final RegionSelectorService regionSelector;
  final AnnotationService annotationService;
  final WindowService windowService;

  CaptureService({
    required this.settings,
    required this.regionSelector,
    required this.annotationService,
    required this.windowService,
  });

  /// Bir capture devam ederken (selection / editor açıkken) ikinci bir
  /// `capture()` çağrısının re-entry yapıp shared state'i (window overlay,
  /// OverlayController completer'ları) bozmasını engelleyen mutex.
  ///
  /// Concrete senaryo: kullanıcı editor açıkken hotkey'e tekrar basarsa,
  /// ikinci `_runEditor` `enterOverlay` çağırır + `annotationService.start`
  /// önceki completer'ı cancel eder. Cancel olan birinci capture'ın `finally`
  /// bloğu `windowService.exitOverlay()` çalıştırır → ikinci capture'ın yeni
  /// overlay'i invisible kalır ("editor açılmıyor" semptomu). Mutex bu yarışı
  /// yapısal olarak imkansız kılar — concurrency contract'ı macOS Screenshot
  /// / Snipping Tool ile aynı: aynı anda tek capture.
  bool _inFlight = false;

  /// Test gözlem noktası — `inFlight` durumunda yeni `capture()` çağrılarının
  /// silently drop edildiğini doğrulamak için.
  @visibleForTesting
  bool get inFlight => _inFlight;

  Future<CaptureResult> capture(CaptureMode mode) async {
    if (_inFlight) {
      debugPrint('[Yakala/Capture] reject (already in flight) mode=$mode');
      return CaptureResult.cancelled();
    }
    _inFlight = true;
    debugPrint('[Yakala/Capture] start mode=$mode');

    try {
      if (!await _ensurePermission()) {
        debugPrint('[Yakala/Capture] permission DENIED');
        return CaptureResult.failed('izin yok');
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      String? capturedPath;

      if (mode == CaptureMode.region) {
        // Region: in-place editor (selection + annotation tek pencerede).
        // showEditorAfterCapture region için her zaman uygulanır (toolbar ekranda).
        capturedPath = await _selectRegion(timestamp);
        if (capturedPath == null) {
          debugPrint('[Yakala/Capture] region cancelled');
          return CaptureResult.cancelled();
        }
      } else {
        capturedPath = await _captureNative(mode, timestamp);
        if (capturedPath == null) {
          debugPrint('[Yakala/Capture] native capture cancelled/failed');
          return CaptureResult.cancelled();
        }

        // Non-region modes: opsiyonel full-screen editor
        if (settings.showEditorAfterCapture) {
          capturedPath = await _runEditor(capturedPath, timestamp);
          if (capturedPath == null) {
            debugPrint('[Yakala/Capture] editor cancelled');
            return CaptureResult.cancelled();
          }
        }
      }

      debugPrint('[Yakala/Capture] finalize path=$capturedPath');
      return await _finalize(capturedPath, timestamp);
    } finally {
      // Source of truth: pencere overlay mode'da mı? Lokal "inOverlay" bool
      // tutmaya çalışmak hatalıydı — region cancel akışında atama satırına
      // ulaşılmadan return edildiği için exitOverlay çağrılmıyor, pencere
      // fullscreen overlay'de takılı kalıyordu (kullanıcı Alt+F4 ile çıkmak
      // zorunda kalıyordu). Şimdi WindowService'in kendi state'ini sorguluyoruz;
      // _selectRegion / _runEditor enterOverlay çağırdıysa flag true olur.
      // _inFlight mutex'i zaten concurrent capture'ı engelliyor → race yok.
      if (windowService.inOverlayMode) {
        await windowService.exitOverlay();
      }
      _inFlight = false;
      debugPrint('[Yakala/Capture] done');
    }
  }

  Future<bool> _ensurePermission() async {
    if (!Platform.isMacOS) return true;
    try {
      final allowed = await sc.screenCapturer.isAccessAllowed();
      if (!allowed) {
        await sc.screenCapturer.requestAccess();
        await NotificationService.show(
          'Yakala',
          'Ekran kaydı izni gerekiyor. Sistem Ayarları > Gizlilik > Ekran Kaydı.',
        );
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('İzin kontrolü hatası: $e');
      return true;
    }
  }

  /// Native yakalama (fullScreen / window). Başarılıysa path, iptal/hata ise null döner.
  ///
  /// **fullScreen** modu için önce `SilentCapture` denenir (grim / scrot /
  /// import on Linux, `screencapture -x` on macOS, PowerShell on Windows).
  /// `screen_capturer` paketinin Linux backend'i `gnome-screenshot`'a DBus
  /// üzerinden sinyal gönderiyor; pencere `windowManager.hide()` ile gizli
  /// iken bu yol fragile (flash + bazı GTK/Wayland sürümlerinde kuyruk
  /// asılı kalıyor). SilentCapture saf shell-out — DBus, dart:ui veya WM
  /// state'i hiç dokunmuyor → arka planda da güvenilir. Sadece SilentCapture
  /// başarısız olursa (paket yok, izin yok) screen_capturer fallback.
  ///
  /// **window** modu interaktif — kullanıcının pencere seçmesi gerekiyor.
  /// SilentCapture buna uygun değil; her platformda screen_capturer'ı
  /// (macOS `screencapture -w`, Linux `gnome-screenshot --window`,
  /// Windows native picker) doğrudan kullanırız.
  Future<String?> _captureNative(CaptureMode mode, int timestamp) async {
    final tempDir = await getTemporaryDirectory();
    final tempPath = p.join(tempDir.path, 'yakala_$timestamp.png');

    if (mode == CaptureMode.fullScreen) {
      final ok = await SilentCapture.captureFullScreen(tempPath);
      if (ok) {
        debugPrint('[Yakala/Capture] fullScreen via SilentCapture');
        return tempPath;
      }
      debugPrint(
        '[Yakala/Capture] SilentCapture başarısız, screen_capturer fallback',
      );
    }

    sc.CapturedData? captured;
    try {
      captured = await sc.screenCapturer.capture(
        mode: mode.toScreenCapturerMode(),
        imagePath: tempPath,
        // Native shutter her zaman silent — sound'u biz finalize'da çalıyoruz
        // (tek kaynak, çift sound olmasın, Linux'ta gnome-screenshot fallback'i
        // de boğulmuş olur).
        silent: true,
      );
    } catch (e) {
      debugPrint('Capture hatası: $e');
      await NotificationService.show('Yakala', 'Yakalama başarısız oldu.');
      return null;
    }
    if (captured == null || !File(tempPath).existsSync()) return null;
    return tempPath;
  }

  /// Region akışı: sessiz tam ekran → overlay (selection + in-place annotation) → final PNG.
  Future<String?> _selectRegion(int timestamp) async {
    await windowService.hide();
    await Future.delayed(const Duration(milliseconds: 80));

    final tempDir = await getTemporaryDirectory();
    final fullPath = p.join(tempDir.path, 'yakala_full_$timestamp.png');

    bool ok = await SilentCapture.captureFullScreen(fullPath);
    if (!ok) {
      try {
        final result = await sc.screenCapturer.capture(
          mode: sc.CaptureMode.screen,
          imagePath: fullPath,
          silent: true,
        );
        ok = result != null && File(fullPath).existsSync();
      } catch (e) {
        debugPrint('Region: tam ekran capture hatası: $e');
      }
    }
    if (!ok) {
      await NotificationService.show('Yakala', captureFailMessage());
      return null;
    }

    final bytes = await File(fullPath).readAsBytes();
    final display = await screenRetriever.getPrimaryDisplay();
    final logicalSize = display.size;

    await windowService.enterOverlay(logicalSize);
    final annotatedBytes = await regionSelector.startWith(
      image: bytes,
      logicalSize: logicalSize,
    );
    _cleanupTempFile(fullPath);

    if (annotatedBytes == null) return null;

    final outPath = p.join(tempDir.path, 'yakala_$timestamp.png');
    await File(outPath).writeAsBytes(annotatedBytes);
    return outPath;
  }

  /// Full-screen / window mode için editor (selection yok, full-screen toolbar).
  /// Confirmed ise yeni path, cancel ise null.
  Future<String?> _runEditor(String inputPath, int timestamp) async {
    final display = await screenRetriever.getPrimaryDisplay();
    await windowService.enterOverlay(display.size);
    final bytes = await File(inputPath).readAsBytes();
    final annotatedBytes = await annotationService.start(bytes);
    if (annotatedBytes == null) {
      _cleanupTempFile(inputPath);
      return null;
    }
    final tempDir = await getTemporaryDirectory();
    final outPath = p.join(tempDir.path, 'yakala_edit_$timestamp.png');
    await File(outPath).writeAsBytes(annotatedBytes);
    if (outPath != inputPath) _cleanupTempFile(inputPath);
    return outPath;
  }

  void _cleanupTempFile(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  Future<CaptureResult> _finalize(String tempPath, int timestamp) async {
    final clipboardOk = await ClipboardUtils.copyImageToClipboard(tempPath);

    String? savedToDisk;
    if (settings.savePath.trim().isNotEmpty) {
      savedToDisk = await _persistToUserPath(tempPath, settings.savePath, timestamp);
    }

    // Sound fire-and-forget — async kuyruğunu beklemeyiz.
    if (settings.soundEffect) {
      unawaited(SoundService.playCaptureSound());
    }

    if (settings.notificationsEnabled) {
      final body = buildNotificationBody(
        clipboardOk: clipboardOk,
        savedToDisk: savedToDisk,
      );
      await NotificationService.show('Yakala', body);
    }

    return CaptureResult.ok(imagePath: tempPath, savedToDisk: savedToDisk);
  }

  Future<String?> _persistToUserPath(
    String tempPath,
    String savePath,
    int timestamp,
  ) async {
    try {
      final expanded = expandHome(savePath);
      final dir = Directory(expanded);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final destPath = p.join(expanded, 'yakala_$timestamp.png');
      await File(tempPath).copy(destPath);
      return destPath;
    } catch (e) {
      debugPrint('Kayıt hatası: $e');
      return null;
    }
  }

  /// `~` ve `~/...` formatlarını $HOME / %USERPROFILE% ile genişletir. Hiçbir
  /// env yoksa girdiyi olduğu gibi döner. `_persistToUserPath` çağırıyor;
  /// public yapmamızın tek sebebi unit test edilebilirliği — instance state
  /// kullanmıyor, bu yüzden static.
  @visibleForTesting
  static String expandHome(String path,
      {Map<String, String>? overrideEnv}) {
    if (!path.startsWith('~')) return path;
    final env = overrideEnv ?? Platform.environment;
    final home = env['HOME'] ?? env['USERPROFILE'] ?? '';
    if (home.isEmpty) return path;
    return p.join(home, path.substring(path.startsWith('~/') ? 2 : 1));
  }

  /// Region capture için silent_capture + screen_capturer fallback zinciri
  /// tamamen başarısız olduğunda gösterilen mesaj. Linux'ta hangi paketin
  /// eksik olduğunu DisplayServer'a göre tahmin ederiz.
  @visibleForTesting
  static String captureFailMessage({Map<String, String>? overrideEnv}) {
    if (!Platform.isLinux) return 'Tam ekran yakalanamadı.';
    final env = overrideEnv ?? Platform.environment;
    final wayland = (env['WAYLAND_DISPLAY']?.isNotEmpty ?? false) ||
        (env['XDG_SESSION_TYPE']?.toLowerCase() == 'wayland');
    final pkg = wayland ? 'grim' : 'imagemagick';
    return 'Tam ekran yakalanamadı. Eksik araç: $pkg. '
        'Kurulum scriptini yeniden çalıştırın: bash linux/install-launcher.sh';
  }

  @visibleForTesting
  static String buildNotificationBody({
    required bool clipboardOk,
    required String? savedToDisk,
  }) {
    if (!clipboardOk && savedToDisk == null) {
      return 'Yakalandı ama kaydedilemedi.';
    }
    if (clipboardOk && savedToDisk != null) {
      return 'Panoya kopyalandı ve diske kaydedildi.';
    }
    if (clipboardOk) {
      return 'Görüntü panoya kopyalandı.';
    }
    return 'Diske kaydedildi: ${p.basename(savedToDisk!)}';
  }
}
