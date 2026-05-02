import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_painter/image_painter.dart';
import 'package:yakala/widgets/region_overlay.dart';

import '../helpers/mock_channels.dart';

/// 100x100 kırmızı PNG — RegionOverlay testleri için minimal background.
Uint8List _redPng() {
  final image = img.Image(width: 100, height: 100);
  img.fill(image, color: img.ColorRgb8(255, 0, 0));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  setUpAll(() {
    setupMockChannels();
  });

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('RegionOverlay Phase 1 (selecting)', () {
    testWidgets('initial phase\'ta hint bar görünür', (tester) async {
      await tester.pumpWidget(wrap(RegionOverlay(
        backgroundImage: _redPng(),
        imagePixelSize: const Size(100, 100),
        onConfirm: (_) {},
        onCancel: () {},
      )));
      await tester.pump();

      expect(find.textContaining('Sürükle: bölge seç'), findsOneWidget);
      // Toolbar henüz yok
      expect(find.text('Bitti'), findsNothing);
    });

    testWidgets('drag çok küçükse selection silinir, phase değişmez',
        (tester) async {
      await tester.pumpWidget(wrap(RegionOverlay(
        backgroundImage: _redPng(),
        imagePixelSize: const Size(100, 100),
        onConfirm: (_) {},
        onCancel: () {},
      )));
      await tester.pump();

      // Çok küçük drag — minimum 5x5 değil
      await tester.dragFrom(const Offset(50, 50), const Offset(2, 2));
      await tester.pump();

      // Toolbar görünmemeli (hala Phase 1)
      expect(find.text('Bitti'), findsNothing);
      expect(find.textContaining('Sürükle: bölge seç'), findsOneWidget);
    });

    testWidgets('Esc onCancel tetikler', (tester) async {
      var cancelled = false;
      await tester.pumpWidget(wrap(RegionOverlay(
        backgroundImage: _redPng(),
        imagePixelSize: const Size(100, 100),
        onConfirm: (_) {},
        onCancel: () => cancelled = true,
      )));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(cancelled, isTrue);
    });

    testWidgets('boyut göstergesi seçimle birlikte görünür', (tester) async {
      await tester.pumpWidget(wrap(SizedBox(
        width: 800,
        height: 600,
        child: RegionOverlay(
          backgroundImage: _redPng(),
          imagePixelSize: const Size(800, 600),
          onConfirm: (_) {},
          onCancel: () {},
        ),
      )));
      await tester.pump();

      // Selection draw — pan başlat ama bitirmeden ölçü göstergesi görünmeli
      final gesture = await tester.startGesture(const Offset(100, 100));
      await gesture.moveTo(const Offset(150, 150));
      await tester.pump();

      // 50x50 boyut metni görünmeli (drawing aşamasında)
      expect(find.textContaining('×'), findsOneWidget);

      // Drag bitir — annotating'e geçecek (test kapsamı dışı)
      await gesture.up();
    });
  });

  // ─────────────────── Phase 2 (annotating) — text aracı ───────────────────
  //
  // Regression koruması: "Yazı" butonu önce sadece `controller.setMode` çağırıp
  // hiçbir şey yapmıyordu (image_painter 0.7.1 canvas'ta tıkla→yaz mekanizması
  // sağlamadığı için metin asla eklenmiyordu). Fix: dialog ile metin alıp
  // `controller.addPaintInfo(PaintInfo(mode: text, ...))` çağırıyor.
  //
  // Toolbar Row production'da masaüstü ekranlar (1280px+) için tasarlandı.
  // Test default 800x600 viewport'unda overflow oluyor; bu yüzden bu grup
  // için surface size'ı artırıyoruz.
  group('RegionOverlay Phase 2 (annotating) — text aracı', () {
    /// Surface size'ı ayarlayıp overlay'i pump'lar. setSurfaceSize sadece
    /// `testWidgets` içinden çağrılabilir (`inTest` assertion); bu yüzden
    /// helper içinde tester üzerinden yapılıp `addTearDown` ile sıfırlanır.
    Future<void> pumpOverlay(
      WidgetTester tester, {
      void Function(Uint8List)? onConfirm,
    }) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() async => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1280,
              height: 720,
              child: RegionOverlay(
                backgroundImage: _redPng(),
                imagePixelSize: const Size(1280, 720),
                onConfirm: onConfirm ?? (_) {},
                onCancel: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    /// Phase 1'den Phase 2'ye geçer: 100x100'lük bir bölge çizip bırakır.
    /// `_confirmSelection` async (await `_cropBackground`) olduğu için ekstra
    /// pump'lar ile microtask + setState frame'i tüketilir.
    ///
    /// `runAsync`: ImagePainter.memory `ui.decodeImageFromList`'in callback'i
    /// real-time olmadan fire etmez — pump-only test zamanında widget unmount
    /// edilirken disposed-ValueNotifier assertion atar. Decode callback'inin
    /// tester teardown'dan önce çalışmasını sağlamak için fake-async dışında
    /// kısa bir gecikme bekliyoruz.
    Future<void> enterAnnotatingPhase(WidgetTester tester) async {
      final gesture = await tester.startGesture(const Offset(100, 100));
      await gesture.moveTo(const Offset(200, 200));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    /// `ImagePainter` widget'ı public, `controller` field'ı public.
    /// Toolbar'ın controller'ı = ImagePainter'ın controller'ı (paylaşılır).
    ImagePainterController readController(WidgetTester tester) {
      return tester
          .widget<ImagePainter>(find.byType(ImagePainter))
          .controller;
    }

    testWidgets('Yazı butonuna tıklayınca "Metin Ekle" dialog açılır',
        (tester) async {
      await pumpOverlay(tester);
      await enterAnnotatingPhase(tester);

      // Phase 2'ye geçildi (toolbar Bitti butonu görünür)
      expect(find.text('Bitti'), findsOneWidget);

      // Dialog henüz yok
      expect(find.text('Metin Ekle'), findsNothing);

      await tester.tap(find.byTooltip('Yazı'));
      await tester.pump();
      await tester.pump();

      // Dialog ve content'i
      expect(find.text('Metin Ekle'), findsOneWidget);
      expect(find.text('İptal'), findsOneWidget);
      expect(find.text('Ekle'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('İptal dialog\'u kapatır, paint history büyümez',
        (tester) async {
      await pumpOverlay(tester);
      await enterAnnotatingPhase(tester);

      final beforeCount = readController(tester).paintHistory.length;

      await tester.tap(find.byTooltip('Yazı'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('İptal'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Metin Ekle'), findsNothing);
      // Toolbar hâlâ ayakta
      expect(find.text('Bitti'), findsOneWidget);

      final ctrl = readController(tester);
      expect(ctrl.paintHistory.length, beforeCount);
      // Cancel yolunda mode freeStyle'a döner
      expect(ctrl.mode, PaintMode.freeStyle);
    });

    testWidgets(
        'Metni yazıp Ekle: paint history\'ye text PaintInfo eklenir, mode text kalır',
        (tester) async {
      await pumpOverlay(tester);
      await enterAnnotatingPhase(tester);

      final ctrlBefore = readController(tester);
      expect(ctrlBefore.paintHistory, isEmpty);
      expect(ctrlBefore.color, Colors.red); // default

      await tester.tap(find.byTooltip('Yazı'));
      await tester.pump();
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'merhaba');
      await tester.pump();
      await tester.tap(find.text('Ekle'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Metin Ekle'), findsNothing);

      final ctrl = readController(tester);
      expect(ctrl.paintHistory, hasLength(1));
      final info = ctrl.paintHistory.first;
      expect(info.mode, PaintMode.text);
      expect(info.text, 'merhaba');
      expect(info.offsets, isEmpty,
          reason: 'Boş offsets → image_painter render\'ı canvas merkezine koyar');
      expect(info.color, Colors.red);
      // Mode text olarak kalmalı: kullanıcı sürükleyerek pozisyonlayabilsin
      // (image_painter onTextUpdateMode mekanizması son text'i taşır).
      expect(ctrl.mode, PaintMode.text);
    });

    testWidgets(
        'Boş metinle Ekle: history büyümez, mode freeStyle\'a geri döner',
        (tester) async {
      await pumpOverlay(tester);
      await enterAnnotatingPhase(tester);

      await tester.tap(find.byTooltip('Yazı'));
      await tester.pump();
      await tester.pump();

      // Hiç metin girmeden direkt Ekle
      await tester.tap(find.text('Ekle'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Metin Ekle'), findsNothing);
      final ctrl = readController(tester);
      expect(ctrl.paintHistory, isEmpty);
      expect(ctrl.mode, PaintMode.freeStyle);
    });

    testWidgets(
        'Sadece boşluk içeren metin trim ile boşa düşer, history büyümez',
        (tester) async {
      await pumpOverlay(tester);
      await enterAnnotatingPhase(tester);

      await tester.tap(find.byTooltip('Yazı'));
      await tester.pump();
      await tester.pump();

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      await tester.tap(find.text('Ekle'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Metin Ekle'), findsNothing);
      final ctrl = readController(tester);
      expect(ctrl.paintHistory, isEmpty,
          reason: 'pop(tc.text.trim()) boş string döner → addPaintInfo skip');
      expect(ctrl.mode, PaintMode.freeStyle);
    });

    testWidgets('Metnin başındaki/sonundaki boşluklar trim edilir',
        (tester) async {
      await pumpOverlay(tester);
      await enterAnnotatingPhase(tester);

      await tester.tap(find.byTooltip('Yazı'));
      await tester.pump();
      await tester.pump();

      await tester.enterText(find.byType(TextField), '  selam  ');
      await tester.pump();
      await tester.tap(find.text('Ekle'));
      await tester.pump();
      await tester.pump();

      final ctrl = readController(tester);
      expect(ctrl.paintHistory, hasLength(1));
      expect(ctrl.paintHistory.first.text, 'selam');
    });
  });
}
