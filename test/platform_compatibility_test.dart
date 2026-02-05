import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Platform Compatibility Checks', () {
    
    test('Pubspec contains Linux/Windows/MacOS dependencies', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      
      expect(pubspec.contains('screen_capturer:'), isTrue, reason: 'screen_capturer missing');
      expect(pubspec.contains('window_manager:'), isTrue, reason: 'window_manager missing');
      expect(pubspec.contains('hotkey_manager:'), isTrue, reason: 'hotkey_manager missing');
    });

    test('Project structure supports macOS and Linux', () {
      expect(Directory('macos').existsSync(), isTrue, reason: 'macos/ directory missing');
      expect(Directory('linux').existsSync(), isTrue, reason: 'linux/ directory missing');
    });

    test('Source code does not use hardcoded backslashes for paths', () {
      final libDir = Directory('lib');
      final dartFiles = libDir.listSync(recursive: true).where((e) => e.path.endsWith('.dart'));

      for (var file in dartFiles) {
        if (file is File) {
          final content = file.readAsStringSync();
          // Raw string ile kontrol: 'assets\' veya "assets\"
          if (content.contains(r"'assets\\") || content.contains(r'"assets\')) {
             fail("${file.path} contains hardcoded Windows path separator (assets\\...)");
          }
        }
      }
    });

    test('Tray icon asset exists for all platforms', () {
      expect(File('assets/app_icon.png').existsSync(), isTrue, reason: 'assets/app_icon.png missing');
    });
  });
}