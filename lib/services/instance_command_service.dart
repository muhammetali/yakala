import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Tek-örnek (single-instance) IPC kanalı.
///
/// Birinci örnek bir kanal dinler. İkinci örnek başlatıldığında bu kanala
/// bir komut yazıp çıkar; birinci örnek komutu callback ile işler
/// (ör. "show_settings" → ayarlar penceresini aç).
///
/// `.desktop` launcher'a tıklayınca uygulama tray'de zaten çalışıyorsa
/// bu kanal sayesinde yeni süreç başlatmak yerine mevcut süreç UI'ı açar —
/// GApplication / KDBusService gibi GNOME/KDE entegrasyonlarının yaptığı şey.
///
/// Platform stratejisi:
///   - Linux / macOS: Unix domain socket (`<temp>/yakala.sock`).
///     Filesystem permission'ı sayesinde aynı user'a kapalı; ekstra auth
///     gerekmez.
///   - Windows: Unix soketi taşınabilir değil → TCP loopback (127.0.0.1) +
///     rastgele token. Aynı makinede başka user / başka uygulama loopback'e
///     bağlanabilir, bu yüzden komutun ilk parametresi olarak token isteriz.
///     Port + token `<temp>/yakala.port` dosyasına 'PORT TOKEN' formatında
///     yazılır; Windows temp dizini zaten kullanıcıya özeldir.
class InstanceCommandService {
  static const Duration _timeout = Duration(seconds: 2);

  /// Tüm desteklenen platformlarda IPC açık. (Eski Windows no-op davranışı
  /// kaldırıldı.)
  static bool get isSupported =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  static Future<String> _unixSocketPath() async {
    final dir = await getTemporaryDirectory();
    return '${dir.path}/yakala.sock';
  }

  static Future<String> _windowsHandshakeFilePath() async {
    final dir = await getTemporaryDirectory();
    return '${dir.path}/yakala.port';
  }

  ServerSocket? _server;
  StreamSubscription<Socket>? _sub;
  String? _windowsToken;

  Future<void> startServer({
    required Future<void> Function(String command) onCommand,
  }) async {
    if (!isSupported) return;
    if (Platform.isWindows) {
      await _startWindowsServer(onCommand);
    } else {
      await _startUnixServer(onCommand);
    }
  }

  Future<void> _startUnixServer(
    Future<void> Function(String) onCommand,
  ) async {
    final path = await _unixSocketPath();
    // Eski (stale) soket dosyasını temizle — bind aksi halde EADDRINUSE atar.
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    try {
      _server = await ServerSocket.bind(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      _sub = _server!.listen(
        (client) => _handleUnixClient(client, onCommand),
        onError: (Object e) => debugPrint('IPC server hatası: $e'),
      );
    } catch (e) {
      debugPrint('IPC server başlatılamadı: $e');
    }
  }

  Future<void> _startWindowsServer(
    Future<void> Function(String) onCommand,
  ) async {
    try {
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      _windowsToken = _generateToken();
      final port = _server!.port;
      final handshakePath = await _windowsHandshakeFilePath();
      // 'PORT TOKEN' tek satır. Atomic değil ama küçük dosya, kabul.
      await File(handshakePath).writeAsString(
        '$port $_windowsToken\n',
        flush: true,
      );
      _sub = _server!.listen(
        (client) => _handleWindowsClient(client, onCommand),
        onError: (Object e) => debugPrint('IPC server hatası: $e'),
      );
    } catch (e) {
      debugPrint('Windows IPC server başlatılamadı: $e');
    }
  }

  Future<void> _handleUnixClient(
    Socket client,
    Future<void> Function(String) onCommand,
  ) async {
    try {
      final bytes = await client
          .timeout(_timeout)
          .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
      final cmd = utf8.decode(bytes).trim();
      if (cmd.isNotEmpty) {
        await onCommand(cmd);
      }
    } catch (e) {
      debugPrint('IPC istemci hatası: $e');
    } finally {
      try {
        await client.close();
      } catch (_) {}
    }
  }

  Future<void> _handleWindowsClient(
    Socket client,
    Future<void> Function(String) onCommand,
  ) async {
    try {
      final bytes = await client
          .timeout(_timeout)
          .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
      final raw = utf8.decode(bytes).trim();
      // 'TOKEN COMMAND' bekleniyor. Token uzunluğu ve değeri sabit.
      final spaceIdx = raw.indexOf(' ');
      if (spaceIdx < 0) {
        debugPrint('IPC: format hatalı (token boşluk komut bekleniyor).');
        return;
      }
      final token = raw.substring(0, spaceIdx);
      final cmd = raw.substring(spaceIdx + 1).trim();
      if (_windowsToken == null || token != _windowsToken) {
        debugPrint('IPC: token doğrulanamadı, komut reddedildi.');
        return;
      }
      if (cmd.isNotEmpty) {
        await onCommand(cmd);
      }
    } catch (e) {
      debugPrint('IPC istemci hatası: $e');
    } finally {
      try {
        await client.close();
      } catch (_) {}
    }
  }

  /// Çalışan örneğe komut yollar. Başarısızsa false (örn. server yok / soket
  /// stale / handshake yok). Çağıran taraf sonra çıkmaya karar verir.
  static Future<bool> sendCommand(String command) async {
    if (!isSupported) return false;
    if (Platform.isWindows) {
      return _sendWindowsCommand(command);
    }
    return _sendUnixCommand(command);
  }

  static Future<bool> _sendUnixCommand(String command) async {
    Socket? socket;
    try {
      final path = await _unixSocketPath();
      if (!await File(path).exists()) return false;
      socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      ).timeout(_timeout);
      socket.add(utf8.encode(command));
      await socket.flush();
      return true;
    } catch (e) {
      debugPrint('IPC komut yollanamadı ($command): $e');
      return false;
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
  }

  static Future<bool> _sendWindowsCommand(String command) async {
    Socket? socket;
    try {
      final handshakePath = await _windowsHandshakeFilePath();
      final f = File(handshakePath);
      if (!await f.exists()) return false;
      final content = (await f.readAsString()).trim();
      final parts = content.split(' ');
      if (parts.length != 2) {
        debugPrint('IPC: handshake dosyası bozuk: $content');
        return false;
      }
      final port = int.tryParse(parts[0]);
      final token = parts[1];
      if (port == null) return false;
      socket = await Socket.connect(InternetAddress.loopbackIPv4, port)
          .timeout(_timeout);
      socket.add(utf8.encode('$token $command'));
      await socket.flush();
      return true;
    } catch (e) {
      debugPrint('IPC komut yollanamadı ($command): $e');
      return false;
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _server?.close();
    } catch (_) {}
    _server = null;
    try {
      if (Platform.isWindows) {
        final f = File(await _windowsHandshakeFilePath());
        if (await f.exists()) await f.delete();
      } else {
        final f = File(await _unixSocketPath());
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
    _windowsToken = null;
  }

  /// 16 byte cryptographic-quality rastgele → 32 hex karakter.
  static String _generateToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
