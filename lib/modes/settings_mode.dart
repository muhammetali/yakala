import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yakala/pages/settings_page.dart';
import 'package:yakala/providers/settings_provider.dart';

/// Settings mode — kullanıcının ayarları düzenlemesi için.
///
/// CLI: `yakala --mode=settings`
///
/// Pencere standart bir dialog: 560×640, ortalanmış, normal title bar
/// (X kapatma butonu var). Kullanıcı X'e bastığında pencere kapanır,
/// process exit eder. Off-screen pattern yok.
Future<void> runSettingsMode({
  required SettingsProvider settings,
}) async {
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(560, 640),
    center: true,
    minimumSize: Size(480, 560),
    title: 'Yakala — Ayarlar',
    titleBarStyle: TitleBarStyle.normal,
    skipTaskbar: false,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ],
      child: const _SettingsApp(),
    ),
  );
}

class _SettingsApp extends StatelessWidget {
  const _SettingsApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Yakala — Ayarlar',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const SettingsPage(),
    );
  }
}
