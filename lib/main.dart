import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yakala/models/capture_mode.dart';
import 'package:yakala/pages/settings_page.dart';
import 'package:yakala/providers/settings_provider.dart';
import 'package:yakala/services/annotation_service.dart';
import 'package:yakala/services/autostart_service.dart';
import 'package:yakala/services/capture_service.dart';
import 'package:yakala/services/hotkey_service.dart';
import 'package:yakala/services/instance_command_service.dart';
import 'package:yakala/services/notification_service.dart';
import 'package:yakala/services/region_selector_service.dart';
import 'package:yakala/services/single_instance_service.dart';
import 'package:yakala/services/tray_service.dart';
import 'package:yakala/services/window_service.dart';
import 'package:yakala/utils/temp_cleanup.dart';
import 'package:yakala/widgets/annotation_editor.dart';
import 'package:yakala/widgets/region_overlay.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // CLI flag'leri. Launcher (.desktop) tıklamasında --settings geçilir;
  // login-time autostart bare çalıştırır → silent tray.
  final showSettingsRequested = args.contains('--settings');

  // GNOME native custom shortcut entegrasyonu için CLI capture flag'leri.
  // Sebep: Linux'ta iki bilinen bug var:
  //   1) `hotkey_manager_linux` 0.2.0 native plugin'i `keybinder_bind`
  //      dönüş değerini kontrol etmiyor — başarısız register Dart'a `true`
  //      olarak rapor ediliyor (hotkey hiç tetiklenmiyor, kullanıcıya hata
  //      mesajı yok).
  //   2) GNOME 46 ubuntu-appindicators extension menü item activation
  //      sonrası callback dispatch'ini ölü tutuyor — 2. tray click hiç
  //      Dart'a ulaşmıyor (system_tray ve tray_manager paketlerinin
  //      ikisi de aynı semptomu yaşıyor; bu paket bug'ı değil, extension
  //      bug'ı).
  // Çözüm: GNOME'un kendi shortcut altyapısı (gsettings custom-keybindings)
  // bu zincirin tamamen dışında çalışıyor → install-launcher.sh registar
  // ediyor, kullanıcı tuşa bastığında GNOME shell `yakala --capture-*`
  // komutunu çalıştırıyor, bu süreç IPC ile çalışan instance'a komut
  // gönderip çıkıyor. Slack/Telegram/Flameshot aynı pattern'i kullanıyor.
  String? captureRequested;
  if (args.contains('--capture-fullscreen')) {
    captureRequested = 'capture_full';
  } else if (args.contains('--capture-region')) {
    captureRequested = 'capture_region';
  } else if (args.contains('--capture-window')) {
    captureRequested = 'capture_window';
  }

  final lock = SingleInstanceService();
  if (!await lock.acquire()) {
    // Çalışan birinci örneğe ne istediğimizi söyle, sonra çık.
    final String cmd;
    if (captureRequested != null) {
      cmd = captureRequested;
    } else if (showSettingsRequested) {
      cmd = 'show_settings';
    } else {
      cmd = 'focus';
    }
    await InstanceCommandService.sendCommand(cmd);
    exit(0);
  }

  // 24 saatten eski temp PNG'leri startup'ta sil (fire-and-forget).
  // Future await edilmiyor — main'i bekletmemek için.
  TempCleanup.sweepOld();

  final windowService = WindowService();
  await windowService.initialize();

  final autostart = AutostartService();
  await autostart.initialize();

  final settings = await SettingsProvider.create(autostart);
  final regionSelector = RegionSelectorService();
  final annotationService = AnnotationService();
  final captureService = CaptureService(
    settings: settings,
    regionSelector: regionSelector,
    annotationService: annotationService,
    windowService: windowService,
  );

  final hotkeyService = HotkeyService();
  final hotkeyOk = await hotkeyService.register(settings.hotkey, () async {
    await captureService.capture(settings.defaultCaptureMode);
  });
  if (!hotkeyOk) {
    debugPrint(
      'UYARI: Global kısayol kaydı başarısız (muhtemelen başka uygulama '
      'kullanıyor): ${settings.hotkey.displayLabel}',
    );
    // Settings açık değilse SnackBar görünmez; native bildirim ile
    // (özellikle Wayland kullanıcıları için) durumu kullanıcıya iletiyoruz.
    // Tray menüsü hala kullanılabilir → fatal değil.
    unawaited(NotificationService.show(
      'Yakala',
      'Kısayol "${settings.hotkey.displayLabel}" kaydedilemedi. '
          'Tray menüsünden yakalayabilir veya Ayarlar\'dan farklı bir '
          'kombinasyon seçebilirsiniz.',
    ));
  }

  // İkinci örneklerden gelecek IPC komutlarını dinle. Launcher tıklaması
  // (--settings) → çalışan tray uygulaması ayarları açar; ekstra süreç açılmaz.
  final ipcService = InstanceCommandService();
  await ipcService.startServer(onCommand: (cmd) async {
    switch (cmd) {
      case 'show_settings':
        await windowService.showSettings();
        break;
      case 'focus':
        await windowService.showSettings();
        break;
      case 'capture_full':
        await captureService.capture(CaptureMode.fullScreen);
        break;
      case 'capture_region':
        await captureService.capture(CaptureMode.region);
        break;
      case 'capture_window':
        await captureService.capture(CaptureMode.window);
        break;
      default:
        debugPrint('Bilinmeyen IPC komutu: $cmd');
    }
  });

  final trayService = TrayService();
  await trayService.initialize(
    hotkeyLabel: settings.hotkey.displayLabel,
    onCapture: (CaptureMode mode) async {
      await captureService.capture(mode);
    },
    onSettings: windowService.showSettings,
    onQuit: () async {
      await hotkeyService.dispose();
      await trayService.dispose();
      await ipcService.dispose();
      windowService.dispose();
      await lock.release();
      exit(0);
    },
  );

  // Hotkey değişince tray tooltip'i de güncelle.
  settings.addListener(() {
    trayService.updateTooltip(settings.hotkey.displayLabel);
  });

  // İlk örnek launcher'dan açıldıysa ayarları göster (runApp sonrası,
  // widget tree hazır olunca).
  if (showSettingsRequested) {
    Future.microtask(windowService.showSettings);
  }

  // İlk örnek capture flag'i ile açıldıysa (instance yokken GNOME shortcut
  // tetiklendiyse) — startup tamamlanıp services hazır olunca capture'ı
  // çalıştır. Yaygın senaryo değil (autostart ilk instance'ı çoktan açmış
  // olmalı) ama kullanıcı manuel olarak `yakala --capture-*` çağırırsa
  // burası tetikleniyor.
  if (captureRequested != null) {
    final mode = switch (captureRequested) {
      'capture_full' => CaptureMode.fullScreen,
      'capture_region' => CaptureMode.region,
      'capture_window' => CaptureMode.window,
      _ => CaptureMode.fullScreen,
    };
    Future.microtask(() => captureService.capture(mode));
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<RegionSelectorService>.value(value: regionSelector),
        ChangeNotifierProvider<AnnotationService>.value(value: annotationService),
        ChangeNotifierProvider<WindowService>.value(value: windowService),
      ],
      child: YakalaApp(hotkeyService: hotkeyService),
    ),
  );
}

class YakalaApp extends StatelessWidget {
  final HotkeyService hotkeyService;

  const YakalaApp({super.key, required this.hotkeyService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Yakala',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: Consumer3<RegionSelectorService, AnnotationService, WindowService>(
        builder: (context, region, annotation, windowService, _) {
          if (annotation.isActive && annotation.imageBytes != null) {
            return AnnotationEditor(
              imageBytes: annotation.imageBytes!,
              onConfirm: annotation.confirm,
              onCancel: annotation.cancel,
            );
          }
          if (region.isActive && region.backgroundImage != null) {
            return Scaffold(
              backgroundColor: Colors.black,
              body: RegionOverlay(
                backgroundImage: region.backgroundImage!,
                imagePixelSize: region.logicalSize ?? const Size(1920, 1080),
                onConfirm: region.confirm,
                onCancel: region.cancel,
              ),
            );
          }
          if (windowService.settingsVisible) {
            return SettingsPage(
              hotkeyService: hotkeyService,
              windowService: windowService,
            );
          }
          // Hiçbir şey aktif değil → görünmez placeholder.
          // (Pencere zaten gizli olmalı; emin olmak için transparent.)
          return const ColoredBox(color: Colors.transparent);
        },
      ),
    );
  }
}
