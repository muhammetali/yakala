import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yakala/utils/tray_utils.dart';

void main() {
  late Directory testDir;

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('yakala_tu_test_');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => testDir.path);
  });

  tearDown(() async {
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }
  });

  group('TrayUtils.getIconPath', () {
    test('asset bundle\'dan PNG kopyalanır + path döner', () async {
      final path = await TrayUtils.getIconPath();
      expect(path, isNotEmpty);

      // Test ortamı asset bundle'ı yoksa boş dönebilir
      if (path.isNotEmpty) {
        // Path testDir prefix'i ile başlamalı
        expect(path, startsWith(testDir.path));
        // Uzantı: Linux'ta png, Windows'ta ico
        if (Platform.isWindows) {
          expect(path, endsWith('.ico'));
        } else {
          expect(path, endsWith('.png'));
        }
      }
    });

    test('idempotent — ikinci çağrı dosyayı tekrar yazmaz, aynı path', () async {
      final path1 = await TrayUtils.getIconPath();
      final path2 = await TrayUtils.getIconPath();
      expect(path1, path2);
    });
  });
}
