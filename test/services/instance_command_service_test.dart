import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yakala/services/instance_command_service.dart';

/// `InstanceCommandService` Linux/macOS'ta Unix domain socket, Windows'ta
/// TCP loopback + token kullanır. Davranış testleri (server↔client) yalnızca
/// POSIX'te koşar; pure helper'lar (token üretimi, handshake parse, client
/// mesaj parse) her platformda koşar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDir;

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('yakala_ipc_test_');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getTemporaryDirectory' ||
          call.method == 'getApplicationDocumentsDirectory' ||
          call.method == 'getApplicationSupportDirectory') {
        return testDir.path;
      }
      return testDir.path;
    });
  });

  tearDown(() async {
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }
  });

  group('InstanceCommandService.isSupported', () {
    test('Linux/macOS/Windows üçünde de true (Windows TCP loopback ile)', () {
      expect(InstanceCommandService.isSupported, isTrue);
    });
  });

  group('InstanceCommandService.generateToken', () {
    test('32 karakter uzunluğunda hex string', () {
      final token = InstanceCommandService.generateToken();
      expect(token.length, 32);
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(token), isTrue,
          reason: 'token "$token" hex regex\'e uymadı');
    });

    test('arka arkaya çağrıldığında farklı tokenlar üretir', () {
      final tokens = List.generate(10, (_) => InstanceCommandService.generateToken());
      expect(tokens.toSet().length, 10,
          reason: 'token tekrarı = entropy yok demek');
    });
  });

  group('InstanceCommandService.formatHandshake', () {
    test('PORT TOKEN newline ile sonlanır', () {
      final s = InstanceCommandService.formatHandshake(54321, 'abcdef');
      expect(s, '54321 abcdef\n');
    });

    test('formatHandshake → parseHandshake round-trip', () {
      final t = InstanceCommandService.generateToken();
      final s = InstanceCommandService.formatHandshake(8080, t);
      final parsed = InstanceCommandService.parseHandshake(s);
      expect(parsed?.port, 8080);
      expect(parsed?.token, t);
    });
  });

  group('InstanceCommandService.parseHandshake', () {
    test('geçerli format: PORT TOKEN', () {
      final p = InstanceCommandService.parseHandshake('45678 abc123');
      expect(p?.port, 45678);
      expect(p?.token, 'abc123');
    });

    test('trailing newline tolere edilir', () {
      final p = InstanceCommandService.parseHandshake('1234 t\n');
      expect(p?.port, 1234);
      expect(p?.token, 't');
    });

    test('boş string → null', () {
      expect(InstanceCommandService.parseHandshake(''), isNull);
      expect(InstanceCommandService.parseHandshake('   '), isNull);
    });

    test('üç parça → null (format ihlali)', () {
      expect(
        InstanceCommandService.parseHandshake('1234 token extra'),
        isNull,
      );
    });

    test('tek parça → null', () {
      expect(InstanceCommandService.parseHandshake('1234'), isNull);
    });

    test('port int değil → null', () {
      expect(InstanceCommandService.parseHandshake('abcd token'), isNull);
    });

    test('boş token → null', () {
      expect(InstanceCommandService.parseHandshake('1234 '), isNull);
    });
  });

  group('InstanceCommandService.parseClientMessage', () {
    test('TOKEN COMMAND tek kelime komut', () {
      final m = InstanceCommandService.parseClientMessage('abc show_settings');
      expect(m?.token, 'abc');
      expect(m?.command, 'show_settings');
    });

    test('TOKEN COMMAND çok kelimeli komut — sadece ilk boşluk ayraç', () {
      final m = InstanceCommandService.parseClientMessage('tok cmd arg1 arg2');
      expect(m?.token, 'tok');
      expect(m?.command, 'cmd arg1 arg2');
    });

    test('boşluk yok → null (token ile cmd ayrılamaz)', () {
      expect(InstanceCommandService.parseClientMessage('justtoken'), isNull);
    });

    test('boş token (mesaj boşlukla başlıyor) → null', () {
      expect(InstanceCommandService.parseClientMessage(' cmd'), isNull);
    });

    test('boş command (token sonrası sadece boşluk) → token döner, command boş', () {
      final m = InstanceCommandService.parseClientMessage('tok ');
      expect(m?.token, 'tok');
      expect(m?.command, '');
    });
  });

  // POSIX-only davranış testleri. Windows'ta tüm bunlar no-op (sendCommand
  // false döner, server bind etmez) — onu ayrı bir testte doğrularız.
  group('InstanceCommandService (POSIX davranış)', () {
    test('startServer + sendCommand callback\'i tetikler', () async {
      final received = <String>[];
      final completer = Completer<void>();
      final svc = InstanceCommandService();
      try {
        await svc.startServer(onCommand: (cmd) async {
          received.add(cmd);
          if (!completer.isCompleted) completer.complete();
        });

        final ok = await InstanceCommandService.sendCommand('show_settings');
        expect(ok, isTrue);

        // Callback async — kısa bir süre bekle.
        await completer.future.timeout(const Duration(seconds: 2));
        expect(received, ['show_settings']);
      } finally {
        await svc.dispose();
      }
    }, skip: Platform.isWindows ? 'POSIX-only' : null);

    test('birden çok komut sırayla iletilir', () async {
      final received = <String>[];
      final svc = InstanceCommandService();
      try {
        await svc.startServer(onCommand: (cmd) async {
          received.add(cmd);
        });

        expect(await InstanceCommandService.sendCommand('show_settings'), isTrue);
        expect(await InstanceCommandService.sendCommand('capture_full'), isTrue);
        expect(await InstanceCommandService.sendCommand('capture_region'), isTrue);

        // Dispatch'ler asenkron — hepsinin işlenmesi için çok kısa bekle.
        for (var i = 0; i < 50 && received.length < 3; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(received, [
          'show_settings',
          'capture_full',
          'capture_region',
        ]);
      } finally {
        await svc.dispose();
      }
    }, skip: Platform.isWindows ? 'POSIX-only' : null);

    test('server yoksa sendCommand false döner', () async {
      // Hiçbir sunucu başlatılmadı — soket dosyası mevcut değil.
      final socketFile = File('${testDir.path}/yakala.sock');
      expect(await socketFile.exists(), isFalse);

      final ok = await InstanceCommandService.sendCommand('show_settings');
      expect(ok, isFalse);
    }, skip: Platform.isWindows ? 'POSIX-only' : null);

    test('stale soket dosyası temizlenir + bind başarılı', () async {
      // Önceki çalıştırmadan kalmış bir dosyayı taklit et.
      await File('${testDir.path}/yakala.sock').writeAsString('stale');

      final svc = InstanceCommandService();
      try {
        // Bind sırasında stale dosya silinmeli.
        await svc.startServer(onCommand: (_) async {});
        // Bind başarılıysa: gerçek bir komut iletimi de çalışmalı.
        final ok = await InstanceCommandService.sendCommand('focus');
        expect(ok, isTrue);
      } finally {
        await svc.dispose();
      }
    }, skip: Platform.isWindows ? 'POSIX-only' : null);

    test('dispose soket dosyasını siler', () async {
      final svc = InstanceCommandService();
      await svc.startServer(onCommand: (_) async {});

      final socketFile = File('${testDir.path}/yakala.sock');
      expect(await socketFile.exists(), isTrue);

      await svc.dispose();
      expect(await socketFile.exists(), isFalse);
    }, skip: Platform.isWindows ? 'POSIX-only' : null);

    test('dispose sonrası sendCommand false döner', () async {
      final svc = InstanceCommandService();
      await svc.startServer(onCommand: (_) async {});
      await svc.dispose();

      final ok = await InstanceCommandService.sendCommand('show_settings');
      expect(ok, isFalse);
    }, skip: Platform.isWindows ? 'POSIX-only' : null);

    test('callback exception fırlatırsa server hayatta kalır', () async {
      final received = <String>[];
      final svc = InstanceCommandService();
      try {
        await svc.startServer(onCommand: (cmd) async {
          received.add(cmd);
          if (cmd == 'boom') {
            throw StateError('intentional');
          }
        });

        // İlk komut callback içinde patlatır — server crash etmemeli.
        expect(await InstanceCommandService.sendCommand('boom'), isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // İkinci komut hala iletilebiliyor mu?
        expect(await InstanceCommandService.sendCommand('show_settings'), isTrue);
        for (var i = 0; i < 50 && received.length < 2; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(received, contains('show_settings'));
      } finally {
        await svc.dispose();
      }
    }, skip: Platform.isWindows ? 'POSIX-only' : null);

    test('boş komut callback\'i tetiklemez', () async {
      final received = <String>[];
      final svc = InstanceCommandService();
      try {
        await svc.startServer(onCommand: (cmd) async {
          received.add(cmd);
        });

        // Boş bir bağlantı — hiçbir veri gönderilmiyor.
        final socketPath = '${testDir.path}/yakala.sock';
        final socket = await Socket.connect(
          InternetAddress(socketPath, type: InternetAddressType.unix),
          0,
        );
        await socket.close();

        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(received, isEmpty);
      } finally {
        await svc.dispose();
      }
    }, skip: Platform.isWindows ? 'POSIX-only' : null);

    test('komutun trim\'i uygulanır (newline / boşluk)', () async {
      final received = <String>[];
      final svc = InstanceCommandService();
      try {
        await svc.startServer(onCommand: (cmd) async {
          received.add(cmd);
        });

        // sendCommand trim yapmaz; callback içinde trim'lenir.
        // Doğrudan socket üzerinden boşluklu mesaj yollayalım.
        final socketPath = '${testDir.path}/yakala.sock';
        final socket = await Socket.connect(
          InternetAddress(socketPath, type: InternetAddressType.unix),
          0,
        );
        socket.write('  show_settings\n');
        await socket.flush();
        await socket.close();

        for (var i = 0; i < 50 && received.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(received, ['show_settings']);
      } finally {
        await svc.dispose();
      }
    }, skip: Platform.isWindows ? 'POSIX-only' : null);
  });
}
