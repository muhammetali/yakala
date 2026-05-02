import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:yakala/services/region_selector_service.dart';

void main() {
  group('RegionSelectorService.startWith', () {
    test('image ve logicalSize payload\'a yazılır', () {
      final s = RegionSelectorService();
      final bytes = Uint8List.fromList([1, 2, 3]);
      const size = Size(1920, 1080);
      // ignore: unused_local_variable
      final f = s.startWith(image: bytes, logicalSize: size);
      expect(s.isActive, isTrue);
      expect(s.backgroundImage, bytes);
      expect(s.logicalSize, size);
    });

    test('confirm bytes ile resolve eder', () async {
      final s = RegionSelectorService();
      final input = Uint8List.fromList([1, 2, 3]);
      final f = s.startWith(image: input, logicalSize: const Size(800, 600));

      final output = Uint8List.fromList([4, 5, 6]);
      s.confirm(output);

      expect(await f, output);
      expect(s.isActive, isFalse);
      expect(s.backgroundImage, isNull);
      expect(s.logicalSize, isNull);
    });

    test('cancel null ile resolve', () async {
      final s = RegionSelectorService();
      final f = s.startWith(
        image: Uint8List.fromList([1]),
        logicalSize: const Size(100, 100),
      );
      s.cancel();
      expect(await f, isNull);
    });

    test('inactive durumda backgroundImage ve logicalSize null', () {
      final s = RegionSelectorService();
      expect(s.isActive, isFalse);
      expect(s.backgroundImage, isNull);
      expect(s.logicalSize, isNull);
    });
  });

  group('RegionPayload', () {
    test('image ve logicalSize sakladığı şekilde döner', () {
      final bytes = Uint8List.fromList([7, 8, 9]);
      const size = Size(640, 480);
      final payload = RegionPayload(image: bytes, logicalSize: size);
      expect(payload.image, bytes);
      expect(payload.logicalSize, size);
    });
  });
}
