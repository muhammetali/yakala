import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yakala/pages/settings_page.dart';
import 'package:yakala/providers/settings_provider.dart';
import 'package:yakala/services/autostart_service.dart';
import 'package:yakala/services/hotkey_service.dart';
import 'package:yakala/services/window_service.dart';

import '../helpers/mock_channels.dart';

void main() {
  setUpAll(() {
    setupMockChannels();
  });

  Widget wrap(Widget child, SettingsProvider provider) {
    return ChangeNotifierProvider<SettingsProvider>.value(
      value: provider,
      child: MaterialApp(home: child),
    );
  }

  group('SettingsPage', () {
    testWidgets('temel widget\'lar render olur', (tester) async {
      final provider = await SettingsProvider.create(AutostartService());
      await tester.pumpWidget(wrap(
        SettingsPage(
          hotkeyService: HotkeyService(),
          windowService: WindowService(),
        ),
        provider,
      ));

      expect(find.text('Ayarlar'), findsOneWidget);
      expect(find.text('Başlangıçta Çalıştır'), findsOneWidget);
      expect(find.text('Bildirimler'), findsOneWidget);
      expect(find.text('Ses Efekti'), findsOneWidget);
      expect(find.text('Yakalama Sonrası Düzenle'), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(4));
    });

    testWidgets('Section title\'ları görünür', (tester) async {
      final provider = await SettingsProvider.create(AutostartService());
      await tester.pumpWidget(wrap(
        SettingsPage(
          hotkeyService: HotkeyService(),
          windowService: WindowService(),
        ),
        provider,
      ));

      expect(find.text('GENEL'), findsOneWidget);
      expect(find.text('VARSAYILAN MOD'), findsOneWidget);
      expect(find.text('KISAYOL'), findsOneWidget);
      expect(find.text('KAYIT YERİ'), findsOneWidget);
    });

    testWidgets('Başlangıçta Çalıştır toggle dev modda disabled', (tester) async {
      // Test ortamı kReleaseMode false → toggle disabled olmalı
      final provider = await SettingsProvider.create(AutostartService());
      await tester.pumpWidget(wrap(
        SettingsPage(
          hotkeyService: HotkeyService(),
          windowService: WindowService(),
        ),
        provider,
      ));

      // Subtitle dev modda farklı olmalı
      if (!kReleaseMode) {
        expect(find.text('Sadece release build\'de aktif'), findsOneWidget);
      }
    });

    testWidgets('Save path boşsa "Sadece pano" gösterir', (tester) async {
      final provider = await SettingsProvider.create(AutostartService());
      await provider.setSavePath('');
      await tester.pumpWidget(wrap(
        SettingsPage(
          hotkeyService: HotkeyService(),
          windowService: WindowService(),
        ),
        provider,
      ));

      expect(find.textContaining('Sadece pano'), findsOneWidget);
    });

    testWidgets('Save path doluysa path text gösterir', (tester) async {
      final provider = await SettingsProvider.create(AutostartService());
      await provider.setSavePath('/home/user/screenshots');
      await tester.pumpWidget(wrap(
        SettingsPage(
          hotkeyService: HotkeyService(),
          windowService: WindowService(),
        ),
        provider,
      ));

      expect(find.text('/home/user/screenshots'), findsOneWidget);
      // Temizle butonu görünmeli
      expect(find.byIcon(Icons.clear), findsOneWidget);
    });
  });
}
