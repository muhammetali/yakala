import 'dart:io';

import 'package:flutter/material.dart';
import 'package:yakala/modes/editor_mode.dart';
import 'package:yakala/modes/region_mode.dart';
import 'package:yakala/modes/settings_mode.dart';
import 'package:yakala/providers/settings_provider.dart';

/// Yakala UI binary — daemon tarafından on-demand spawn edilen tek-amaçlı
/// görsel araç.
///
/// Native daemon mimarisinde UI binary'si bir "daemon/sistem aracı" değil;
/// her invocation tek bir flow için açılır:
///   - `--mode=editor --input=<png> --output=<edit-png>`
///   - `--mode=region --input=<full-png> --output=<crop-png>`
///   - `--mode=settings`
///
/// Eski Flutter-only mimarideki tray, hotkey, off-screen pattern, single
/// instance yönetimi, region/annotation OverlayController completer'ları
/// bu binary'de YOK — hepsi C++ daemon'a (Linux) ya da Swift daemon'a
/// (macOS) taşındı. Bu binary mode'unu yapar ve tamamen kapanır.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final cli = _parseArgs(args);
  final settings = await SettingsProvider.create();

  switch (cli.mode) {
    case _Mode.editor:
      if (cli.input == null || cli.output == null) {
        stderr.writeln('--mode=editor için --input ve --output zorunlu');
        exit(2);
      }
      await runEditorMode(
        inputPath: cli.input!,
        outputPath: cli.output!,
        settings: settings,
      );
      break;

    case _Mode.region:
      if (cli.input == null || cli.output == null) {
        stderr.writeln('--mode=region için --input ve --output zorunlu');
        exit(2);
      }
      await runRegionMode(
        inputPath: cli.input!,
        outputPath: cli.output!,
        settings: settings,
      );
      break;

    case _Mode.settings:
      await runSettingsMode(settings: settings);
      break;
  }
}

enum _Mode { editor, region, settings }

class _CliArgs {
  final _Mode mode;
  final String? input;
  final String? output;
  const _CliArgs({required this.mode, this.input, this.output});
}

_CliArgs _parseArgs(List<String> args) {
  _Mode mode = _Mode.settings;
  String? input;
  String? output;

  for (final raw in args) {
    if (raw.startsWith('--mode=')) {
      final v = raw.substring('--mode='.length);
      switch (v) {
        case 'editor':
          mode = _Mode.editor;
          break;
        case 'region':
          mode = _Mode.region;
          break;
        case 'settings':
          mode = _Mode.settings;
          break;
        default:
          stderr.writeln('Bilinmeyen --mode değeri: $v (settings kullanıldı)');
      }
    } else if (raw.startsWith('--input=')) {
      input = raw.substring('--input='.length);
    } else if (raw.startsWith('--output=')) {
      output = raw.substring('--output='.length);
    } else if (raw == '--settings') {
      // Geriye dönük: eski Flutter binary'si `--settings` flag'i alıyordu.
      // Daemon hâlâ bunu gönderiyor (ui_spawner.cc), destekli kal.
      mode = _Mode.settings;
    }
  }

  return _CliArgs(mode: mode, input: input, output: output);
}
