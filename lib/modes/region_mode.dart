import 'dart:io';

import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yakala/providers/settings_provider.dart';
import 'package:yakala/utils/ipc_client.dart';
import 'package:yakala/widgets/region_overlay.dart';

/// Region mode — daemon tam ekran PNG verir, kullanıcı bir bölge seçer ve
/// (opsiyonel) annotation yapar; kırpılmış sonuç output path'e yazılır.
///
/// CLI: `yakala --mode=region --input=<full-screen-png> --output=<cropped-png>`
///
/// Lifecycle:
///   1. windowManager init + fullscreen + frameless + alwaysOnTop
///   2. PNG (tam ekran) oku
///   3. RegionOverlay mount — kullanıcı bölge seçer + annotation yapar
///   4. Confirm → annotated PNG'yi output'a yaz, IPC ile bildir, exit(0)
///   5. Cancel → IPC ile bildir, exit(0)
Future<void> runRegionMode({
  required String inputPath,
  required String outputPath,
  required SettingsProvider settings,
}) async {
  final inputFile = File(inputPath);
  if (!await inputFile.exists()) {
    stderr.writeln('Region mode: input dosyası yok: $inputPath');
    exit(2);
  }

  await windowManager.ensureInitialized();

  // Ekran boyutunu al — region overlay screen-fitting yapar.
  final display = await screenRetriever.getPrimaryDisplay();
  final logicalSize = display.size;

  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: logicalSize,
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Colors.transparent,
      skipTaskbar: true,
    ),
    () async {
      await windowManager.setAsFrameless();
      await windowManager.setSize(logicalSize);
      await windowManager.setPosition(Offset.zero);
      await windowManager.setFullScreen(true);
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setResizable(false);
      await windowManager.show();
      await windowManager.focus();
    },
  );

  final bytes = await inputFile.readAsBytes();

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Yakala — Bölge',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    home: Scaffold(
      backgroundColor: Colors.black,
      body: RegionOverlay(
        backgroundImage: bytes,
        imagePixelSize: logicalSize,
        onConfirm: (annotatedBytes) async {
          try {
            await File(outputPath).writeAsBytes(annotatedBytes, flush: true);
            await IpcClient.send({
              'cmd': 'ui_result',
              'mode': 'region',
              'ok': true,
              'output': outputPath,
            });
          } catch (e) {
            stderr.writeln('Region confirm hatası: $e');
          }
          exit(0);
        },
        onCancel: () async {
          await IpcClient.send({
            'cmd': 'ui_result',
            'mode': 'region',
            'ok': false,
            'reason': 'user_cancelled',
          });
          exit(0);
        },
      ),
    ),
  ));

  // ignore: unused_local_variable
  final _ = settings;
}
