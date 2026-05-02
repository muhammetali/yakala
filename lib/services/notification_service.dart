import 'dart:io';
import 'package:flutter/foundation.dart';

import '../utils/powershell.dart';

class NotificationService {
  static const _timeout = Duration(seconds: 4);

  /// Newline ve carriage return → space replace.
  /// Notification gövdesi tek satır olmalı; \n AppleScript'i veya stdout
  /// formatlamasını bozabilir.
  static String sanitize(String s) {
    return s.replaceAll('\n', ' ').replaceAll('\r', ' ');
  }

  static Future<void> show(String title, String body) async {
    final t = sanitize(title);
    final b = sanitize(body);
    try {
      if (Platform.isMacOS) {
        await _showMacOS(t, b);
      } else if (Platform.isLinux) {
        await _showLinux(t, b);
      } else if (Platform.isWindows) {
        await _showWindows(t, b);
      }
    } catch (e) {
      debugPrint('Notification gösterilemedi: $e');
    }
  }

  static Future<void> _showMacOS(String title, String body) async {
    final t = title.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    final b = body.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    await Process.run('osascript', [
      '-e',
      'display notification "$b" with title "$t"',
    ]).timeout(_timeout);
  }

  /// Linux dağıtım/DE çeşitliliği: notify-send (libnotify) çoğu yerde var ama
  /// minimal KDE / Alpine kurulumlarında olmayabilir. Sırasıyla notify-send →
  /// kdialog (KDE) → zenity (GTK fallback) deneriz. Hepsi başarısızsa
  /// stderr'e tek seferlik install hint yazarız (bildirim gösteren araç yok,
  /// recursive notification atamayız).
  static bool _linuxToolMissingLogged = false;

  static Future<void> _showLinux(String title, String body) async {
    if (await _tryRun('notify-send', ['--app-name=Yakala', title, body])) {
      return;
    }
    if (await _tryRun('kdialog', ['--title', title, '--passivepopup', body, '5'])) {
      return;
    }
    if (await _tryRun('zenity', ['--notification', '--text=$title: $body'])) {
      return;
    }
    if (!_linuxToolMissingLogged) {
      _linuxToolMissingLogged = true;
      debugPrint(
        'Bildirim gösterilemedi: sistemde notify-send / kdialog / zenity yok. '
        'Kurulum: sudo apt install libnotify-bin  (veya kde-cli-tools / zenity)',
      );
    }
  }

  static Future<bool> _tryRun(String cmd, List<String> args) async {
    try {
      final r = await Process.run(cmd, args).timeout(_timeout);
      return r.exitCode == 0;
    } on ProcessException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Windows: title ve body'yi env var üzerinden geçiriyoruz (PS injection güvenli).
  static Future<void> _showWindows(String title, String body) async {
    const script = r'''
[Windows.UI.Notifications.ToastNotificationManager,Windows.UI.Notifications,ContentType=WindowsRuntime] | Out-Null
$template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
$nodes = $template.GetElementsByTagName('text')
$nodes.Item(0).AppendChild($template.CreateTextNode($env:YAKALA_TITLE)) | Out-Null
$nodes.Item(1).AppendChild($template.CreateTextNode($env:YAKALA_BODY)) | Out-Null
$toast = [Windows.UI.Notifications.ToastNotification]::new($template)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Yakala').Show($toast)
''';
    await PowerShell.run(
      script: script,
      timeout: _timeout,
      environment: {'YAKALA_TITLE': title, 'YAKALA_BODY': body},
    );
  }
}
