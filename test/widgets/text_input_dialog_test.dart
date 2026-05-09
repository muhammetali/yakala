import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yakala/widgets/text_input_dialog.dart';

import '../helpers/mock_channels.dart';

/// Bu test paketi `TextInputDialog`'un iki invariant'ını koruyor:
///
/// 1. **Dispose safety:** Yerel `TextEditingController` + `await showDialog`
///    pattern'i, dialog kapanma transition'ı sırasında "TextEditingController
///    used after dispose" assertion'ına yol açıyordu. Bu widget controller'ı
///    `State.dispose`'a bağlar — Flutter framework `dispose`'u widget
///    ağaçtan tamamen çıkınca (animasyon bittikten sonra) çağırdığı için
///    race koşulu yapısal olarak imkansız. Test: dialog dismiss + pumpAndSettle
///    ile herhangi bir exception fırlamamalı.
///
/// 2. **API kontratı:** boş ya da yalnız-whitespace input → `null` (kullanıcı
///    "Ekle"e basmış olsa bile). Caller "anlamlı bir metin commit edildi mi"
///    sorusunu tek not-null check ile çözebilsin diye.
void main() {
  setUpAll(setupMockChannels);

  Future<void> openDialog(
    WidgetTester tester, {
    String title = 'Metin',
    String? hint,
    String? initial,
    void Function(String? result)? onResult,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  final r = await TextInputDialog.show(
                    ctx,
                    title: title,
                    hintText: hint,
                    initialValue: initial,
                    useRootNavigator: false,
                  );
                  onResult?.call(r);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('TextInputDialog', () {
    testWidgets('açılır ve title + hint render olur', (tester) async {
      await openDialog(tester, title: 'Metin Ekle', hint: 'ipucu yazısı');
      expect(find.text('Metin Ekle'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Ekle'), findsOneWidget);
      expect(find.text('İptal'), findsOneWidget);
      // hint TextField içinde InputDecoration.hintText olarak gösterilir
      expect(find.text('ipucu yazısı'), findsOneWidget);
    });

    testWidgets('Trim edilmiş metin Ekle ile döner', (tester) async {
      String? result = 'sentinel';
      await openDialog(tester, onResult: (r) => result = r);
      await tester.enterText(find.byType(TextField), '  selam  ');
      await tester.tap(find.text('Ekle'));
      await tester.pumpAndSettle();
      expect(result, 'selam');
    });

    testWidgets('Boş metin + Ekle → null (cancel-eşdeğeri)',
        (tester) async {
      String? result = 'sentinel';
      await openDialog(tester, onResult: (r) => result = r);
      // hiç metin girmeden Ekle'ye bas
      await tester.tap(find.text('Ekle'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });

    testWidgets('Sadece whitespace → null', (tester) async {
      String? result = 'sentinel';
      await openDialog(tester, onResult: (r) => result = r);
      await tester.enterText(find.byType(TextField), '   \n\t  ');
      await tester.tap(find.text('Ekle'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });

    testWidgets('İptal → null', (tester) async {
      String? result = 'sentinel';
      await openDialog(tester, onResult: (r) => result = r);
      await tester.enterText(find.byType(TextField), 'kaydedilmemeli');
      await tester.tap(find.text('İptal'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });

    testWidgets('Klavye ile submit (TextInputAction.done)', (tester) async {
      String? result = 'sentinel';
      await openDialog(tester, onResult: (r) => result = r);
      await tester.enterText(find.byType(TextField), 'klavyeden');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(result, 'klavyeden');
    });

    testWidgets('initialValue prefill', (tester) async {
      await openDialog(tester, initial: 'önceden');
      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.controller!.text, 'önceden');
    });

    // KRİTİK REGRESSION TEST:
    // Eski implementasyonda yerel TextEditingController, await showDialog
    // sonrası dispose ediliyordu — kapanma transition'ı sırasında TextField'ın
    // AnimatedBuilder'ları disposed controller'a addListener çağırıp
    // "TextEditingController used after dispose" assertion'ı atıyordu.
    // Bu testler dialog'un kapanmasını TAM olarak `pumpAndSettle` ile bekliyor;
    // o pencere içinde HİÇBİR exception yakalanmamalı.
    testWidgets(
        'REGRESSION: Ekle ile kapanırken TextEditingController dispose hatası fırlamaz',
        (tester) async {
      await openDialog(tester);
      await tester.enterText(find.byType(TextField), 'merhaba');
      await tester.tap(find.text('Ekle'));
      // Kapanma animasyonu sırasında controller'a erişen widget'lar
      // çalışırsa burada exception yakalanır.
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Dialog kapanmış olmalı
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets(
        'REGRESSION: İptal ile kapanırken dispose hatası fırlamaz',
        (tester) async {
      await openDialog(tester);
      await tester.enterText(find.byType(TextField), 'iptal');
      await tester.tap(find.text('İptal'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets(
        'REGRESSION: Boş input + Ekle (null pop) ile kapanırken hata fırlamaz',
        (tester) async {
      await openDialog(tester);
      await tester.tap(find.text('Ekle'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets(
        'REGRESSION: Geri sayfa ile kapanırsa dispose tutarlı çalışır',
        (tester) async {
      await openDialog(tester);
      await tester.enterText(find.byType(TextField), 'x');
      // Programatik olarak Navigator.pop — barrierDismissible:false olduğu
      // için dışarı tıklama çalışmaz, ama navigator pop simulasyonu
      // dialog'un kapanma yolundan birini test eder.
      final navState = tester.state<NavigatorState>(find.byType(Navigator).first);
      navState.pop();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
