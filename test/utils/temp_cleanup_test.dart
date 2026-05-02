import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yakala/utils/temp_cleanup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDir;

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('yakala_tc_test_');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => testDir.path);
  });

  tearDown(() async {
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }
  });

  Future<File> createFile(String name, DateTime modified) async {
    final f = File('${testDir.path}/$name');
    await f.writeAsString('test');
    await f.setLastModified(modified);
    return f;
  }

  group('TempCleanup.sweepOld', () {
    test('24h üstü yakala_*.png dosyalarını siler', () async {
      final old = await createFile(
        'yakala_123.png',
        DateTime.now().subtract(const Duration(hours: 25)),
      );
      final deleted = await TempCleanup.sweepOld();
      expect(await old.exists(), isFalse);
      expect(deleted, 1);
    });

    test('24h altı dosyaları korur', () async {
      final recent = await createFile(
        'yakala_456.png',
        DateTime.now().subtract(const Duration(hours: 1)),
      );
      await TempCleanup.sweepOld();
      expect(await recent.exists(), isTrue);
    });

    test('yakala_full_* ve yakala_edit_* da silinir', () async {
      final f1 = await createFile(
        'yakala_full_111.png',
        DateTime.now().subtract(const Duration(hours: 25)),
      );
      final f2 = await createFile(
        'yakala_edit_222.png',
        DateTime.now().subtract(const Duration(hours: 25)),
      );
      await TempCleanup.sweepOld();
      expect(await f1.exists(), isFalse);
      expect(await f2.exists(), isFalse);
    });

    test('yakala.lock asla silinmez (regex match etmiyor)', () async {
      final lock = await createFile(
        'yakala.lock',
        DateTime.now().subtract(const Duration(days: 30)),
      );
      await TempCleanup.sweepOld();
      expect(await lock.exists(), isTrue);
    });

    test('yakala dışı dosyalara dokunmaz', () async {
      final other = await createFile(
        'random_file.png',
        DateTime.now().subtract(const Duration(hours: 25)),
      );
      final other2 = await createFile(
        'screenshot.png',
        DateTime.now().subtract(const Duration(hours: 25)),
      );
      await TempCleanup.sweepOld();
      expect(await other.exists(), isTrue);
      expect(await other2.exists(), isTrue);
    });

    test('regex tam eşleşme — yakala_abc.png eşleşmez (sayı bekliyor)',
        () async {
      final f = await createFile(
        'yakala_abc.png',
        DateTime.now().subtract(const Duration(hours: 25)),
      );
      await TempCleanup.sweepOld();
      expect(await f.exists(), isTrue);
    });

    test('boş dizin — return 0', () async {
      final deleted = await TempCleanup.sweepOld();
      expect(deleted, 0);
    });

    test('hata olursa exception fırlatmaz', () async {
      // Mock'u path olmayan bir yere işaret etsin
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        channel,
        (call) async => '/nonexistent/path/that/does/not/exist',
      );
      expect(() async => await TempCleanup.sweepOld(), returnsNormally);
    });
  });
}
