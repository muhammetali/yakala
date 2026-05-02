import 'package:flutter_test/flutter_test.dart';
import 'package:yakala/services/overlay_controller.dart';

class _IntController extends OverlayController<int, String> {}

void main() {
  group('OverlayController', () {
    test('initial state is inactive with null payload', () {
      final c = _IntController();
      expect(c.isActive, isFalse);
      expect(c.payload, isNull);
    });

    test('start activates and stores payload', () {
      final c = _IntController();
      // ignore: unused_local_variable
      final f = c.start('hello');
      expect(c.isActive, isTrue);
      expect(c.payload, 'hello');
    });

    test('confirm completes future with given result and resets', () async {
      final c = _IntController();
      final f = c.start('p');
      c.confirm(42);
      expect(await f, 42);
      expect(c.isActive, isFalse);
      expect(c.payload, isNull);
    });

    test('cancel completes future with null and resets', () async {
      final c = _IntController();
      final f = c.start('p');
      c.cancel();
      expect(await f, isNull);
      expect(c.isActive, isFalse);
    });

    test('second start cancels first with null', () async {
      final c = _IntController();
      final first = c.start('a');
      final second = c.start('b');
      // First future resolves to null because second start cancelled it
      expect(await first, isNull);
      expect(c.isActive, isTrue);
      expect(c.payload, 'b');
      c.confirm(99);
      expect(await second, 99);
    });

    test('confirm after complete is no-op (no throw)', () async {
      final c = _IntController();
      final f = c.start('p');
      c.confirm(1);
      expect(await f, 1);
      // Subsequent calls must not throw
      c.confirm(2);
      c.cancel();
      expect(c.isActive, isFalse);
    });

    test('cancel without active start is no-op', () {
      final c = _IntController();
      expect(() => c.cancel(), returnsNormally);
      expect(c.isActive, isFalse);
    });

    test('notifyListeners fires on start, confirm, cancel', () {
      final c = _IntController();
      var n = 0;
      c.addListener(() => n++);

      c.start('a'); // 1
      c.confirm(1); // 2 (reset)
      expect(n, 2);

      c.start('b'); // 3
      c.cancel(); // 4 (reset)
      expect(n, 4);
    });
  });
}
