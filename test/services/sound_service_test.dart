import 'package:flutter_test/flutter_test.dart';
import 'package:yakala/services/sound_service.dart';

void main() {
  setUp(() {
    SoundService.debugReset();
  });

  group('SoundService cooldown', () {
    test('initial state — wouldPlay true', () {
      expect(SoundService.wouldPlay(DateTime.now()), isTrue);
      expect(SoundService.debugLastPlayed, isNull);
    });

    test('playCaptureSound son tetiklenme zamanını işler', () async {
      await SoundService.playCaptureSound();
      expect(SoundService.debugLastPlayed, isNotNull);
    });

    test('cooldown içinde tekrar çağrı no-op (lastPlayed güncellemiyor)',
        () async {
      await SoundService.playCaptureSound();
      final t1 = SoundService.debugLastPlayed!;

      // 100ms sonra (cooldown 800ms)
      await Future.delayed(const Duration(milliseconds: 100));
      await SoundService.playCaptureSound();
      final t2 = SoundService.debugLastPlayed!;

      // İkinci çağrı no-op olduğu için aynı timestamp kalır
      expect(t1, t2);
    });

    test('cooldown sonrası ikinci çağrı geçer', () async {
      await SoundService.playCaptureSound();
      final t1 = SoundService.debugLastPlayed!;

      // 850ms bekle (cooldown 800ms)
      await Future.delayed(const Duration(milliseconds: 850));

      // wouldPlay artık true
      expect(SoundService.wouldPlay(DateTime.now()), isTrue);

      await SoundService.playCaptureSound();
      final t2 = SoundService.debugLastPlayed!;
      expect(t2.isAfter(t1), isTrue);
    });

    test('debugReset cooldown\'u temizler', () async {
      await SoundService.playCaptureSound();
      expect(SoundService.debugLastPlayed, isNotNull);
      SoundService.debugReset();
      expect(SoundService.debugLastPlayed, isNull);
      expect(SoundService.wouldPlay(DateTime.now()), isTrue);
    });

    test('peş peşe 10 çağrı throw etmez', () async {
      for (var i = 0; i < 10; i++) {
        await SoundService.playCaptureSound();
      }
      // Cooldown sayesinde çoğu no-op; hata fırlatmamalı
    });
  });
}
