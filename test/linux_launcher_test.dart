import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Linux programlar menüsü kaydı (launcher) için yapısal regression testi.
///
/// Asıl davranışsal test (kurulum + Ubuntu menüsünde görünme) sandbox dışı
/// kalıyor — burada en azından artefaktların ve şablonun zorunlu alanlarının
/// silinmediğinden / bozulmadığından emin oluruz.
void main() {
  group('Linux launcher artefaktları', () {
    test('yakala.desktop.template mevcut', () {
      expect(File('linux/yakala.desktop.template').existsSync(), isTrue,
          reason: 'linux/yakala.desktop.template silinmiş.');
    });

    test('install-launcher.sh mevcut + executable', () {
      final f = File('linux/install-launcher.sh');
      expect(f.existsSync(), isTrue,
          reason: 'linux/install-launcher.sh silinmiş.');
      // Executable bit kontrolü (POSIX). Windows'ta atla.
      if (!Platform.isWindows) {
        final stat = f.statSync();
        // mode'un user-execute bit'i (0o100) set olmalı.
        expect(stat.mode & 0x40, isNot(0),
            reason: 'install-launcher.sh executable değil; '
                'chmod +x linux/install-launcher.sh');
      }
    });

    test('linux/yakala.png launcher ikonu mevcut + PNG signature', () {
      final f = File('linux/yakala.png');
      expect(f.existsSync(), isTrue,
          reason: 'linux/yakala.png silinmiş.');
      final bytes = f.readAsBytesSync();
      // PNG magic number: 89 50 4E 47 0D 0A 1A 0A
      expect(bytes.length, greaterThan(8));
      expect(bytes.sublist(0, 8),
          [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    });

    test('.desktop template zorunlu Desktop Entry alanlarını içerir', () {
      final content =
          File('linux/yakala.desktop.template').readAsStringSync();
      expect(content, contains('[Desktop Entry]'));
      expect(content, contains('Type=Application'));
      expect(content, contains('Name=Yakala'));
      expect(content, contains('Icon=yakala'));
      // Tray uygulaması olduğu için terminal açılmamalı.
      expect(content, contains('Terminal=false'));
      // Categories — programlar menüsünde doğru kategoriye düşmesi için.
      expect(content, matches(RegExp(r'^Categories=.*Utility', multiLine: true)));
    });

    test('.desktop template Exec satırı --settings flag\'i geçirir', () {
      // Launcher'a tıklayınca uygulamanın ayarları açması bu flag'e bağlı;
      // silinirse regression olur.
      final content =
          File('linux/yakala.desktop.template').readAsStringSync();
      final execLine = RegExp(r'^Exec=.*$', multiLine: true).firstMatch(content);
      expect(execLine, isNotNull, reason: 'Exec satırı yok.');
      expect(execLine!.group(0)!, contains('__EXEC__'),
          reason: 'install-launcher.sh sed ile değiştireceği için '
              '__EXEC__ placeholder gerekli.');
      expect(execLine.group(0)!, contains('--settings'),
          reason: 'launcher tıklamasında ayarların açılabilmesi için '
              '--settings flag\'i geçilmeli.');
    });

    test('install-launcher.sh template\'i gerçekten kullanır', () {
      final sh = File('linux/install-launcher.sh').readAsStringSync();
      expect(sh, contains('yakala.desktop.template'),
          reason: 'install script template\'i okumalı.');
      expect(sh, contains('__EXEC__'),
          reason: 'install script __EXEC__ placeholder\'ını '
              'binary path ile değiştirmeli (sed).');
      expect(sh, contains('hicolor'),
          reason: 'ikon hicolor temasına yerleştirilmeli '
              '(GNOME/KDE\'nin standart yolu).');
      expect(sh, contains('.local/share/applications'),
          reason: 'kullanıcı bazlı applications dizinine yazılmalı.');
    });

    test('install-launcher.sh bundle\'ı stabil dizine kopyalar', () {
      // `flutter clean` launcher\'ı kırmasın diye build dizinindeki bundle
      // ~/.local/share/yakala'ya kopyalanmalı; Exec build path\'ine değil
      // bu stabil yola işaret etmeli.
      final sh = File('linux/install-launcher.sh').readAsStringSync();
      expect(sh, contains('.local/share/yakala'),
          reason: 'bundle stabil bir kurulum dizinine kopyalanmalı.');
      // cp -a (veya rsync benzeri) — mod/zaman koruyan tam kopya.
      expect(sh, matches(RegExp(r'\bcp\b\s+-a\b')),
          reason: 'bundle içeriği `cp -a` ile mod/zaman korunarak '
              'kopyalanmalı (.so dosyaları executable kalsın).');
      // Exec stabil yola sed ile gönderilmeli, build path\'ine değil.
      expect(sh, isNot(contains(r's|__EXEC__|$BUNDLE_SRC')),
          reason: 'Exec build dizinine değil, stabil install dizinine '
              'işaret etmeli.');
    });
  });
}
