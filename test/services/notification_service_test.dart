import 'package:flutter_test/flutter_test.dart';
import 'package:yakala/services/notification_service.dart';

void main() {
  group('NotificationService.sanitize', () {
    test('newline → space', () {
      expect(NotificationService.sanitize('a\nb'), 'a b');
    });

    test('carriage return → space', () {
      expect(NotificationService.sanitize('a\rb'), 'a b');
    });

    test('CRLF → iki space', () {
      expect(NotificationService.sanitize('a\r\nb'), 'a  b');
    });

    test('multiple newlines hepsi replace', () {
      expect(NotificationService.sanitize('a\nb\nc\nd'), 'a b c d');
    });

    test('newline yoksa olduğu gibi döner', () {
      expect(NotificationService.sanitize('hello world'), 'hello world');
    });

    test('boş string güvenli', () {
      expect(NotificationService.sanitize(''), '');
    });

    test('Türkçe karakter korunur', () {
      expect(
        NotificationService.sanitize('şöğ\nçüı'),
        'şöğ çüı',
      );
    });

    test('AppleScript injection denemesi: çift-tırnak korunur (escape sonra yapılır)',
        () {
      // sanitize sadece \n / \r ile uğraşır; tırnak escape per-platform method'da.
      expect(
        NotificationService.sanitize('"; do evil ; "'),
        '"; do evil ; "',
      );
    });
  });

  group('NotificationService.show fail-safe', () {
    test('boş title/body throw etmez', () async {
      // Platform-dependent shell-out fail edebilir; throw edilmemeli.
      expect(() async => await NotificationService.show('', ''), returnsNormally);
    });

    test('newline içeren input crash etmez', () async {
      expect(
        () async => await NotificationService.show('a\nb', 'c\nd'),
        returnsNormally,
      );
    });
  });
}
