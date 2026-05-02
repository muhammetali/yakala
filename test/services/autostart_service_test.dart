import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yakala/services/autostart_service.dart';

import '../helpers/mock_channels.dart';

void main() {
  setUpAll(() {
    setupMockChannels();
  });

  group('AutostartService dev mode (kReleaseMode == false)', () {
    test('isSupported false in test/dev mode', () {
      final s = AutostartService();
      expect(s.isSupported, isFalse);
      expect(kReleaseMode, isFalse,
          reason: 'Test ortamında kReleaseMode false olmalı');
    });

    test('initialize dev modda no-op (throw etmez)', () async {
      final s = AutostartService();
      expect(() async => await s.initialize(), returnsNormally);
    });

    test('setEnabled dev modda no-op (launch_at_startup çağırmaz)', () async {
      final s = AutostartService();
      expect(() async => await s.setEnabled(true), returnsNormally);
      expect(() async => await s.setEnabled(false), returnsNormally);
    });

    test('isEnabled dev modda false döner', () async {
      final s = AutostartService();
      expect(await s.isEnabled(), isFalse);
    });
  });

  group('AutostartService idempotency', () {
    test('birden fazla initialize çağrısı sorun çıkarmaz', () async {
      final s = AutostartService();
      await s.initialize();
      await s.initialize();
      await s.initialize();
      // Throw etmemeli
    });
  });
}
