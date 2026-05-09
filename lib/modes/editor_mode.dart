import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yakala/providers/settings_provider.dart';
import 'package:yakala/utils/ipc_client.dart';
import 'package:yakala/widgets/annotation_editor.dart';

/// Editor mode — daemon yakaladığı PNG'yi UI'ye annotation için verir.
///
/// CLI: `yakala --mode=editor --input=<png-path> --output=<edit-path>`
///
/// Lifecycle:
///   1. windowManager init + fullscreen
///   2. PNG oku
///   3. AnnotationEditor mount
///   4. Bitti → output dosyasına yaz, daemon'a IPC ile bildir, exit(0)
///   5. İptal → daemon'a IPC ile bildir, exit(0) (output yazılmaz)
///
/// **Hayali off-screen pattern yok**: process baştan tek-amaçlı, iş bitince
/// tamamen kapanıyor. Editor için pencere lifecycle'ı klasik open/close.
Future<void> runEditorMode({
  required String inputPath,
  required String outputPath,
  required SettingsProvider settings,
}) async {
  final inputFile = File(inputPath);
  if (!await inputFile.exists()) {
    stderr.writeln('Editor mode: input dosyası yok: $inputPath');
    exit(2);
  }

  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1280, 800),
      center: true,
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
    ),
    () async {
      await windowManager.setFullScreen(true);
      await windowManager.setAlwaysOnTop(true);
      await windowManager.show();
      await windowManager.focus();
    },
  );

  final bytes = await inputFile.readAsBytes();

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Yakala — Düzenle',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    home: AnnotationEditor(
      imageBytes: bytes,
      onConfirm: (newBytes) async {
        try {
          await File(outputPath).writeAsBytes(newBytes, flush: true);
          await IpcClient.send({
            'cmd': 'ui_result',
            'mode': 'editor',
            'ok': true,
            'output': outputPath,
          });
        } catch (e) {
          stderr.writeln('Editor confirm hatası: $e');
        }
        exit(0);
      },
      onCancel: () async {
        await IpcClient.send({
          'cmd': 'ui_result',
          'mode': 'editor',
          'ok': false,
          'reason': 'user_cancelled',
        });
        exit(0);
      },
    ),
  ));

  // settings reference: gelecekte editor template renkleri vs. settings'ten
  // okumak isteyebiliriz; şu an sadece compile-time check için tutuluyor.
  // ignore: unused_local_variable
  final _ = settings;
}
