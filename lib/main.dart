import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:system_tray/system_tray.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yakala/providers/app_state.dart';
import 'package:yakala/utils/clipboard_utils.dart';
import 'package:yakala/utils/tray_utils.dart';
import 'package:yakala/pages/settings_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Pencere Yöneticisini Başlat
  await windowManager.ensureInitialized();
  
  WindowOptions windowOptions = const WindowOptions(
    size: Size(800, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.hide();
  });

  // Global AppState instance for usage outside of widget tree (like in tray/hotkeys)
  final appState = AppState();

  // 2. Kısayol (Cmd+Shift+C)
  await hotKeyManager.unregisterAll();
  HotKey captureHotKey = HotKey(
    key: PhysicalKeyboardKey.keyC,
    modifiers: [HotKeyModifier.shift, HotKeyModifier.meta], 
    scope: HotKeyScope.system,
  );

  await hotKeyManager.register(
    captureHotKey,
    keyDownHandler: (hotKey) async {
      debugPrint('📸 Kısayol tetiklendi');
      appState.navigateTo(AppPage.capture);
      await windowManager.show();
      await windowManager.focus();
    },
  );

  // 3. System Tray (Menü)
  final SystemTray systemTray = SystemTray();
  String iconPath = await TrayUtils.getIconPath(); // Asset -> File

  await systemTray.initSystemTray(
    title: "Yakala",
    iconPath: iconPath,
    toolTip: "Yakala",
  );

  final Menu menu = Menu();
  await menu.buildFrom([
    MenuItemLabel(label: 'Ekranı Yakala', onClicked: (menuItem) async {
      appState.navigateTo(AppPage.capture);
      await windowManager.show();
      await windowManager.focus();
    }),
    MenuItemLabel(label: 'Ayarlar', onClicked: (menuItem) async {
      appState.navigateTo(AppPage.settings);
      await windowManager.show();
      await windowManager.focus();
    }),
    MenuItemLabel(label: 'Çıkış', onClicked: (menuItem) {
      exit(0);
    }),
  ]);

  await systemTray.setContextMenu(menu);

  runApp(
    ChangeNotifierProvider.value(
      value: appState,
      child: const YakalaApp(),
    ),
  );
}

class YakalaApp extends StatelessWidget {
  const YakalaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Yakala',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: Consumer<AppState>(
        builder: (context, appState, child) {
          switch (appState.currentPage) {
            case AppPage.settings:
              return const SettingsPage();
            case AppPage.capture:
              return const CaptureScreen();
            case AppPage.home:
              return const CaptureScreen();
          }
        },
      ),
    );
  }
}

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  String _status = "Kısayol bekleniyor: Cmd+Shift+C";

  Future<void> _captureScreen() async {
    setState(() => _status = "Ekran Görüntüsü Alınıyor...");

    try {
      await windowManager.hide();
      await Future.delayed(const Duration(milliseconds: 300));

      Directory tempDir = await getTemporaryDirectory();
      String savePath = '${tempDir.path}/yakala_temp_${DateTime.now().millisecondsSinceEpoch}.png';

      CapturedData? capturedData = await screenCapturer.capture(
        mode: CaptureMode.screen,
        imagePath: savePath,
        silent: true,
      );

      if (capturedData != null && File(savePath).existsSync()) {
         await ClipboardUtils.copyImageToClipboard(savePath);
         
         await windowManager.show();
         if (mounted) {
           setState(() {
             _status = "Görüntü Panoya Kopyalandı! (Cmd+V yap)";
           });
         }
         
         // 2 saniye sonra otomatik gizle (Opsiyonel, kullanıcı dostu)
         Future.delayed(const Duration(seconds: 3), () async {
           if (mounted) await windowManager.hide();
         });
         
      } else {
        await windowManager.show();
         if (mounted) setState(() => _status = "Görüntü alınamadı.");
      }
    } catch (e) {
      await windowManager.show();
      if (mounted) setState(() => _status = "Hata: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ignore: deprecated_member_use
      backgroundColor: Colors.black.withOpacity(0.85),
      body: Stack(
        children: [
          // Kapat Butonu (Sağ Üst)
          Positioned(
            top: 10, right: 10,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white54),
              onPressed: () => windowManager.hide(),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.camera, size: 80, color: Colors.deepPurpleAccent),
                const SizedBox(height: 20),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w300),
                ),
                const SizedBox(height: 40),
                ElevatedButton.icon(
                  onPressed: _captureScreen,
                  icon: const Icon(Icons.touch_app),
                  label: const Text("Şimdi Yakala"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  ),
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () {
                    // Ayarlar'a geçiş butonu
                    context.read<AppState>().navigateTo(AppPage.settings);
                  }, 
                  child: const Text("Ayarlar", style: TextStyle(color: Colors.white54)),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}