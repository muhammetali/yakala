// Bu dosya geriye uyumluluk için bırakıldı. Gerçek testler:
//   test/models/hotkey_config_test.dart
//   test/providers/settings_provider_test.dart
//   test/services/*_test.dart
//   test/utils/*_test.dart
//   test/pages/settings_page_test.dart
//
// Buradaki tek smoke test framework'ün doğru kurulduğunu doğrular.

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('test framework reachable', () {
    expect(1 + 1, 2);
  });
}
