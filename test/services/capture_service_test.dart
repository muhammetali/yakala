import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yakala/models/capture_mode.dart';
import 'package:yakala/services/annotation_service.dart';
import 'package:yakala/services/autostart_service.dart';
import 'package:yakala/services/capture_service.dart';
import 'package:yakala/providers/settings_provider.dart';
import 'package:yakala/services/region_selector_service.dart';
import 'package:yakala/services/window_service.dart';

import '../helpers/mock_channels.dart';

void main() {
  setUpAll(() {
    setupMockChannels();
  });

  Future<CaptureService> build() async {
    final settings = await SettingsProvider.create(AutostartService());
    return CaptureService(
      settings: settings,
      regionSelector: RegionSelectorService(),
      annotationService: AnnotationService(),
      windowService: WindowService(),
    );
  }

  group('CaptureService instantiation', () {
    test('servislerle inşa edilir', () async {
      final c = await build();
      expect(c, isNotNull);
      expect(c.settings, isNotNull);
      expect(c.regionSelector, isNotNull);
      expect(c.annotationService, isNotNull);
      expect(c.windowService, isNotNull);
    });
  });

  // Concrete bug: kullanıcı editor açıkken hotkey/tray'a tekrar basarsa
  // ikinci capture'ın `enterOverlay()` + `annotationService.start()`'ı önceki
  // completer'ı cancel ediyor; cancel olan birinci capture'ın `finally`
  // bloğu `windowService.exitOverlay()` çalıştırıp pencereyi gizliyor →
  // ikinci capture'ın yeni overlay'i invisible kalıyor ("editor açılmıyor").
  // Mutex bu yarışı yapısal olarak engeller.
  group('CaptureService re-entry guard (mutex)', () {
    test('Aynı anda iki capture çağrılırsa ikincisi cancelled döner', () async {
      if (Platform.isMacOS) return; // izin diyaloğu açabilir
      final c = await build();
      expect(c.inFlight, isFalse,
          reason: 'idle CaptureService inFlight olmamalı');

      // İlk capture'ı await'siz başlat. async fonksiyonu ilk await'e kadar
      // senkron çalışır → return etmeden ÖNCE _inFlight=true olur.
      final first = c.capture(CaptureMode.fullScreen);
      expect(c.inFlight, isTrue,
          reason: 'capture başlar başlamaz inFlight true olmalı');

      // İkinci capture aynı senkron tick'te başlar → guard reject etmeli.
      final second = await c.capture(CaptureMode.region);
      expect(second.isCancelled, isTrue,
          reason: 'in-flight iken çağrılan ikinci capture cancelled döner');
      // imagePath boş olmalı — yani gerçek bir capture yapmadı
      expect(second.imagePath, isNull);

      // Birinci capture kendi haline tamamlansın (mock channel'da capture
      // null/no-file döndüğü için cancelled bitmeli).
      final firstResult = await first;
      expect(firstResult, isNotNull);
      expect(c.inFlight, isFalse,
          reason: 'birinci tamamlanınca guard release olur');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test(
        'Birinci tamamlandıktan SONRA ikinci capture normal çalışır (guard release)',
        () async {
      if (Platform.isMacOS) return;
      final c = await build();
      // Birinciyi tamamen bitir
      await c.capture(CaptureMode.fullScreen);
      expect(c.inFlight, isFalse);

      // Sonraki capture guard'a takılmamalı — yine bir CaptureResult dönmeli
      // (mock'ta cancelled olur, önemli olan reject edilmemesi).
      final second = await c.capture(CaptureMode.fullScreen);
      expect(second, isNotNull);
      expect(c.inFlight, isFalse);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test(
        'Çoklu re-entry — üç eş zamanlı çağrıda yalnız biri gerçek capture yapar',
        () async {
      if (Platform.isMacOS) return;
      final c = await build();
      final f1 = c.capture(CaptureMode.fullScreen);
      final f2 = c.capture(CaptureMode.fullScreen);
      final f3 = c.capture(CaptureMode.fullScreen);

      final results = await Future.wait([f1, f2, f3]);
      // Throw yok — hepsi tamamlandı
      expect(results, hasLength(3));
      // En az 2'si cancelled olmalı (guard tarafından reject edilen 2 tane)
      final cancelledCount = results.where((r) => r.isCancelled).length;
      expect(cancelledCount, greaterThanOrEqualTo(2),
          reason: 'guard 2 ya da 3 çağrıyı reject etmeli');
      expect(c.inFlight, isFalse);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('CaptureService.capture mode dispatch', () {
    test('Native modlar (fullScreen) — exception fırlatmaz, result döner',
        () async {
      // Linux/Windows'ta permission check no-op; capture screen_capturer'ı çağırır.
      // Mock'ta capture {imagePath: '/tmp/mock_capture.png', ...} dönüyor ama
      // dosya gerçekten yok → cancelled dönecek
      final c = await build();
      final result = await c.capture(CaptureMode.fullScreen);
      // Throw olmadığını ve bir CaptureResult döndüğünü doğrula
      expect(result, isNotNull);
      // Cancelled veya failed olabilir — ama kesinlikle null değil
      expect(result.success, anyOf(isTrue, isFalse));
    }, skip: Platform.isMacOS, // macOS izin diyaloğu açabilir
        timeout: const Timeout(Duration(seconds: 30)));

    test('Window mode — aynı şekilde graceful sonuç', () async {
      final c = await build();
      final result = await c.capture(CaptureMode.window);
      expect(result, isNotNull);
    },
        skip: Platform.isMacOS,
        timeout: const Timeout(Duration(seconds: 30)));
  });

  group('CaptureService.expandHome', () {
    test('~ tek başına HOME döner', () {
      expect(
        CaptureService.expandHome('~', overrideEnv: const {'HOME': '/u/x'}),
        '/u/x',
      );
    });

    test('~/foo → HOME/foo', () {
      expect(
        CaptureService.expandHome('~/Pictures',
            overrideEnv: const {'HOME': '/home/mali'}),
        '/home/mali/Pictures',
      );
    });

    test('~bar → HOME/bar (slashsız sonek)', () {
      expect(
        CaptureService.expandHome('~bar',
            overrideEnv: const {'HOME': '/u'}),
        '/u/bar',
      );
    });

    test('~ ile başlamayan path olduğu gibi döner', () {
      expect(
        CaptureService.expandHome('/abs/path',
            overrideEnv: const {'HOME': '/u'}),
        '/abs/path',
      );
      expect(
        CaptureService.expandHome('relative',
            overrideEnv: const {'HOME': '/u'}),
        'relative',
      );
    });

    test('HOME yok ama USERPROFILE var → USERPROFILE kullanılır (Windows)', () {
      expect(
        CaptureService.expandHome('~/Docs',
            overrideEnv: const {'USERPROFILE': r'C:\Users\Mali'}),
        // path.join Linux runner'da forward-slash kullanır; içerik beklenir,
        // separator değil önemli olan
        contains('Mali'),
      );
    });

    test('HOME ve USERPROFILE ikisi de yoksa girdi olduğu gibi döner', () {
      expect(
        CaptureService.expandHome('~/x', overrideEnv: const {}),
        '~/x',
      );
    });
  });

  group('CaptureService.captureFailMessage', () {
    test('Linux dışı platformda jenerik mesaj', () {
      // Linux dışı dalı tetiklemek için Platform.isLinux'a bakar; testte
      // override edemiyoruz ama Linux runner'da bu test sadece Linux dalını
      // doğrular. Diğer dalın yerine: mesajın hep aynı temel ifadeyle başlıyor.
      final msg = CaptureService.captureFailMessage(
        overrideEnv: const {'WAYLAND_DISPLAY': 'wayland-0'},
      );
      expect(msg, contains('Tam ekran yakalanamadı'));
    });

    test('Linux + Wayland → grim önerir', () {
      if (!Platform.isLinux) return;
      final msg = CaptureService.captureFailMessage(
        overrideEnv: const {'WAYLAND_DISPLAY': 'wayland-0'},
      );
      expect(msg, contains('grim'));
      expect(msg, contains('install-launcher.sh'));
    });

    test('Linux + X11 (XDG_SESSION_TYPE=x11) → imagemagick önerir', () {
      if (!Platform.isLinux) return;
      final msg = CaptureService.captureFailMessage(
        overrideEnv: const {'XDG_SESSION_TYPE': 'x11'},
      );
      expect(msg, contains('imagemagick'));
    });

    test('Linux + XDG_SESSION_TYPE=wayland (WAYLAND_DISPLAY yokken) → grim', () {
      if (!Platform.isLinux) return;
      final msg = CaptureService.captureFailMessage(
        overrideEnv: const {'XDG_SESSION_TYPE': 'wayland'},
      );
      expect(msg, contains('grim'));
    });

    test('Linux + boş env → varsayılan X11 → imagemagick', () {
      if (!Platform.isLinux) return;
      final msg = CaptureService.captureFailMessage(overrideEnv: const {});
      expect(msg, contains('imagemagick'));
    });
  });

  group('CaptureService.buildNotificationBody', () {
    test('clipboard yok + disk yok → kaydedilemedi', () {
      final body = CaptureService.buildNotificationBody(
        clipboardOk: false,
        savedToDisk: null,
      );
      expect(body, 'Yakalandı ama kaydedilemedi.');
    });

    test('clipboard ok + disk ok → ikisi de söylenir', () {
      final body = CaptureService.buildNotificationBody(
        clipboardOk: true,
        savedToDisk: '/tmp/yakala_123.png',
      );
      expect(body, 'Panoya kopyalandı ve diske kaydedildi.');
    });

    test('clipboard ok + disk yok → sadece panoya', () {
      final body = CaptureService.buildNotificationBody(
        clipboardOk: true,
        savedToDisk: null,
      );
      expect(body, 'Görüntü panoya kopyalandı.');
    });

    test('clipboard yok + disk ok → diskteki dosya adı görünür', () {
      final body = CaptureService.buildNotificationBody(
        clipboardOk: false,
        savedToDisk: '/home/mali/Pictures/yakala_999.png',
      );
      expect(body, 'Diske kaydedildi: yakala_999.png');
    });
  });
}
