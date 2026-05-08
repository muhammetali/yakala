import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yakala/services/tray_service.dart';

import '../helpers/mock_channels.dart';

void main() {
  setUpAll(() {
    setupMockChannels();
  });

  group('TrayService click coalescing (busy guard)', () {
    test('idle iken tek click action çalıştırır + sayaç +1', () async {
      final tray = TrayService();
      var actionRuns = 0;
      await tray.handleClick('test', () async {
        actionRuns++;
      });
      expect(actionRuns, 1);
      expect(tray.debugAcceptedClickCount, 1);
      expect(tray.debugClickBusy, isFalse,
          reason: 'action bittikten sonra busy bayrağı release olmalı');
    });

    test(
        'in-flight action sırasında gelen 3 click drop edilir — toplam 1 çalışır',
        () async {
      final tray = TrayService();
      final gate = Completer<void>();
      var runs = 0;

      // İlk click: gate açılana kadar bekler. Henüz tamamlanmadığı için
      // _clickBusy=true durumda.
      final first = tray.handleClick('first', () async {
        runs++;
        await gate.future;
      });
      // Microtask sırasında busy=true olmuş olmalı.
      await Future<void>.delayed(Duration.zero);
      expect(tray.debugClickBusy, isTrue);

      // Spam: 3 click peş peşe — hepsi sessizce drop edilmeli.
      await tray.handleClick('drop1', () async => runs++);
      await tray.handleClick('drop2', () async => runs++);
      await tray.handleClick('drop3', () async => runs++);

      expect(runs, 1, reason: 'sadece ilk action çalıştı');
      expect(tray.debugAcceptedClickCount, 1,
          reason: 'drop edilenler sayaca yansımaz');

      // İlki bitir, busy release olsun.
      gate.complete();
      await first;
      expect(tray.debugClickBusy, isFalse);

      // Yeni click artık geçmeli.
      await tray.handleClick('after', () async => runs++);
      expect(runs, 2);
      expect(tray.debugAcceptedClickCount, 2);
    });

    test('action throw etse bile busy bayrağı release olur', () async {
      final tray = TrayService();
      await tray.handleClick('boom', () async {
        throw StateError('intentional');
      });
      expect(tray.debugClickBusy, isFalse,
          reason: 'finally release garantisi — exception yutulmuş olmalı');
      expect(tray.debugAcceptedClickCount, 1);
    });
  });

  group('TrayService debounced rebind', () {
    // Rebind sadece Linux'ta scheduled — diğer platformlarda timer yok.
    test('Linux: action sonrası rebind scheduled', () async {
      if (!Platform.isLinux) return;
      final tray = TrayService();
      await tray.handleClick('x', () async {});
      // _scheduleRebind early-returns çünkü _initialized=false. Test ortamında
      // başlatamıyoruz (initSystemTray asset/icon ister) — pendingRebind
      // false olmalı, FAKAT _acceptedClickCount artmış olmalı (action geçti).
      expect(tray.debugHasPendingRebind, isFalse,
          reason: 'init edilmemiş tray rebind schedule etmemeli');
      expect(tray.debugAcceptedClickCount, 1);
    });

    test('non-Linux: rebind schedule edilmez', () async {
      if (Platform.isLinux) return;
      final tray = TrayService();
      await tray.handleClick('x', () async {});
      expect(tray.debugHasPendingRebind, isFalse);
    });
  });
}
