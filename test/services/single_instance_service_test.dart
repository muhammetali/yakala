import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yakala/services/single_instance_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDir;

  setUp(() async {
    // Her test için izole temp dizini
    testDir = await Directory.systemTemp.createTemp('yakala_si_test_');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getTemporaryDirectory') return testDir.path;
      return testDir.path;
    });
  });

  tearDown(() async {
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }
  });

  group('SingleInstanceService', () {
    test('temiz state\'de acquire başarılı + lock dosyası yazıldı', () async {
      final s = SingleInstanceService();
      expect(await s.acquire(), isTrue);
      final lock = File('${testDir.path}/yakala.lock');
      expect(await lock.exists(), isTrue);
      final content = await lock.readAsString();
      expect(content, contains('$pid'));
    });

    test('stale lock (ölü PID) devralınır', () async {
      // Çok büyük PID — neredeyse kesinlikle ölü
      const deadPid = 999999;
      await File('${testDir.path}/yakala.lock')
          .writeAsString('$deadPid\n2024-01-01T00:00:00');

      final s = SingleInstanceService();
      expect(await s.acquire(), isTrue);

      final content =
          await File('${testDir.path}/yakala.lock').readAsString();
      expect(content, contains('$pid')); // Bizim PID yazıldı
      expect(content, isNot(contains('999999')));
    });

    test('canlı PID lock\'u tutuyorsa acquire false döner', () async {
      // Test process'in kendi PID'si canlı; ama "existingPid != pid"
      // koşulu yüzünden bu kendi-PID kontrolü "stale" gibi davranır.
      // Gerçek başka canlı PID'i taklit etmek için: bir sleep process spawn
      // edip onun PID'sini lock'a yazıyoruz.
      final dummy = await Process.start('sleep', ['10']);
      try {
        await File('${testDir.path}/yakala.lock').writeAsString('${dummy.pid}');
        final s = SingleInstanceService();
        expect(await s.acquire(), isFalse);
      } finally {
        dummy.kill();
        await dummy.exitCode;
      }
    });

    test('release sadece sahip olunan lock\'u siler', () async {
      final s = SingleInstanceService();
      await s.acquire();
      final lock = File('${testDir.path}/yakala.lock');
      expect(await lock.exists(), isTrue);

      // Başka process devraldı taklidi — lock içeriğini değiştir
      await lock.writeAsString('999999');

      await s.release();
      // Lock dokunulmamış olmalı (biz sahip değiliz artık)
      expect(await lock.exists(), isTrue);
      expect(await lock.readAsString(), '999999');
    });

    test('release sahibi olduğumuz lock\'u temizler', () async {
      final s = SingleInstanceService();
      await s.acquire();
      final lock = File('${testDir.path}/yakala.lock');
      expect(await lock.exists(), isTrue);

      await s.release();
      expect(await lock.exists(), isFalse);
    });

    test('release lock yokken çağrılırsa hata vermez', () async {
      final s = SingleInstanceService();
      // acquire çağrılmadı
      expect(() async => await s.release(), returnsNormally);
    });

    test('lock içeriği bozuksa stale sayılır + devralınır', () async {
      await File('${testDir.path}/yakala.lock').writeAsString('not-a-number');
      final s = SingleInstanceService();
      expect(await s.acquire(), isTrue);
    });
  });
}
