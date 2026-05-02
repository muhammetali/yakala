import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yakala/services/annotation_service.dart';

void main() {
  group('AnnotationService', () {
    test('start image\'i payload olarak saklar', () {
      final s = AnnotationService();
      final bytes = Uint8List.fromList([1, 2, 3]);
      // ignore: unused_local_variable
      final f = s.start(bytes);
      expect(s.isActive, isTrue);
      expect(s.imageBytes, bytes);
      expect(s.payload, bytes);
    });

    test('confirm annotated bytes ile resolve eder', () async {
      final s = AnnotationService();
      final input = Uint8List.fromList([1, 2, 3]);
      final f = s.start(input);

      final output = Uint8List.fromList([10, 20, 30]);
      s.confirm(output);

      expect(await f, output);
      expect(s.isActive, isFalse);
      expect(s.imageBytes, isNull);
    });

    test('cancel null ile resolve', () async {
      final s = AnnotationService();
      final f = s.start(Uint8List.fromList([1]));
      s.cancel();
      expect(await f, isNull);
    });

    test('imageBytes payload alias\'ı', () {
      final s = AnnotationService();
      final bytes = Uint8List.fromList([42]);
      s.start(bytes);
      expect(s.imageBytes, s.payload);
    });

    test('inactive durumda imageBytes null', () {
      final s = AnnotationService();
      expect(s.imageBytes, isNull);
    });
  });
}
