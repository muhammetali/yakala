import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Daemon'un Unix domain socket'ine kısa-yaşamlı mesaj gönderir.
///
/// Mesaj formatı: JSON line-delimited (`'\n'` terminator). Daemon mesajı
/// oku → `{"cmd": "..."}` parse et → ilgili handler.
///
/// Best-effort: socket yoksa veya bağlanılamazsa false döner. UI exit
/// flow'u devam eder — daemon'a haber gitmemesi UI'nin temiz çıkışını
/// engellemez.
class IpcClient {
  static String _resolveSocketPath() {
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      return '$home/Library/Application Support/Yakala/daemon.sock';
    }
    final xdgRuntime = Platform.environment['XDG_RUNTIME_DIR'];
    if (xdgRuntime != null && xdgRuntime.isNotEmpty) {
      return '$xdgRuntime/yakala-daemon.sock';
    }
    return '/tmp/yakala-daemon-${Platform.environment['USER'] ?? 'unknown'}.sock';
  }

  /// JSON map'ini line-delimited olarak gönderir, socket'i kapatır.
  /// Timeout 2sn — daemon yanıtsız ise UI bloke kalmasın.
  static Future<bool> send(Map<String, dynamic> message) async {
    final path = _resolveSocketPath();
    if (!await File(path).exists()) {
      debugPrint('IpcClient: socket yok ($path) — daemon çalışmıyor mu?');
      return false;
    }
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      ).timeout(const Duration(seconds: 2));
      socket.add(utf8.encode('${jsonEncode(message)}\n'));
      await socket.flush();
      return true;
    } catch (e) {
      debugPrint('IpcClient: send hatası: $e');
      return false;
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
  }
}
