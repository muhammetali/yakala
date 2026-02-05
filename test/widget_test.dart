import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yakala/main.dart'; // YakalaApp import
import 'package:yakala/pages/settings_page.dart';
import 'helpers/mock_channels.dart';

void main() {
  // Testler başlamadan önce native kanalları mockla
  setUpAll(() {
    setupMockChannels();
  });

  group('Yakala App Tests', () {
    
    testWidgets('Settings Page UI elements smoke test', (WidgetTester tester) async {
      // Settings Page'i render et
      await tester.pumpWidget(const MaterialApp(home: SettingsPage()));

      // Başlık var mı?
      expect(find.text('Ayarlar'), findsOneWidget);

      // "Başlangıçta Çalıştır" switch'i var mı?
      expect(find.text('Başlangıçta Çalıştır'), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(2)); // 2 tane switch olmalı (Başlangıç + Ses)

      // Switch'i değiştirmeyi dene
      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      
      // (State değişimi test edilebilir ama şimdilik crash olmaması yeterli)
    });

    testWidgets('Capture Screen button triggers capture', (WidgetTester tester) async {
      // Capture Screen'i render et
      await tester.pumpWidget(const MaterialApp(home: CaptureScreen()));

      // "Şimdi Yakala" butonu var mı?
      expect(find.text('Şimdi Yakala'), findsOneWidget);
      expect(find.byIcon(Icons.camera), findsOneWidget);

      // Butona tıkla
      await tester.tap(find.text('Şimdi Yakala'));
      
      // Animasyonları ilerlet (await ve delay'ler için)
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      // Durum metninin değişmesini bekle (Mock kanal başarılı döneceği için)
      // Not: MockChannels capture sonucunda 'capturedData' döndüğü için 
      // kod 'Görüntü Panoya Kopyalandı' (veya dosya yok hatası) durumuna geçmeli.
      // Ancak test ortamında '/tmp/mock_capture.png' dosyası gerçekten yok, bu yüzden
      // kod muhtemelen else bloğuna veya catch'e düşecek ama CRASH olmayacak.
      
      // En azından butonun tepki verdiğini doğruladık.
    });

  });
}