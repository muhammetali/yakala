import 'package:flutter_test/flutter_test.dart';
import 'package:yakala/utils/powershell.dart';

void main() {
  group('PowerShell.buildArgs', () {
    test('zorunlu bayraklar her zaman aynı sırada gelir', () {
      final args = PowerShell.buildArgs('Write-Host hi');
      expect(args.take(5).toList(), [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
      ]);
    });

    test('-Command bayrağı son flag, script en son eleman', () {
      final args = PowerShell.buildArgs('Write-Host hi');
      final cmdIdx = args.indexOf('-Command');
      expect(cmdIdx, args.length - 2,
          reason: '-Command bayrağı sondan ikinci olmalı, script en son.');
      expect(args.last, 'Write-Host hi');
    });

    test('Bypass bayrağı politikadan önce gelir', () {
      final args = PowerShell.buildArgs('x');
      final epIdx = args.indexOf('-ExecutionPolicy');
      expect(args[epIdx + 1], 'Bypass',
          reason: '-ExecutionPolicy ardından Bypass değeri gelmeli.');
    });

    test('aynı script iki kez build edilince argüman listeleri eşit', () {
      const script = '\$env:YAKALA_BODY';
      expect(PowerShell.buildArgs(script), PowerShell.buildArgs(script));
    });

    test('script boş string olabilir — PowerShell tarafı reject edebilir ama '
        'helper exception fırlatmaz', () {
      expect(() => PowerShell.buildArgs(''), returnsNormally);
      expect(PowerShell.buildArgs('').last, '');
    });

    test('script newline içerebilir — buildArgs içeriğe karışmaz', () {
      const multiline = 'Add-Type -AssemblyName x\nWrite-Host y';
      expect(PowerShell.buildArgs(multiline).last, multiline);
    });

    test('script özel PowerShell karakterleri içerebilir, çünkü tek '
        'argüman olarak geçer (shell parsing yok)', () {
      const tricky = r'$env:YAKALA_OUT; Remove-Item C:\foo';
      final args = PowerShell.buildArgs(tricky);
      expect(args.last, tricky);
      // Helper içinde quote eklenmemeli; argv olarak geçtiği için OS'a
      // doğrudan tek bir parametre olarak ulaşır.
      expect(args.where((a) => a.startsWith('"')).toList(), isEmpty);
    });

    test('argüman listesi tam olarak 6 eleman (5 flag + script)', () {
      expect(PowerShell.buildArgs('x').length, 6);
    });
  });
}
