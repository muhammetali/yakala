import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// /tmp altındaki yakala_*.png dosyalarını temizler.
/// 24 saatten eski olanlar silinir; lock dosyasına dokunulmaz.
class TempCleanup {
  static const _maxAge = Duration(hours: 24);
  static final RegExp _yakalaFilePattern =
      RegExp(r'^yakala(_full|_edit)?_\d+\.png$');

  /// App startup'ta çağrılır. Eski yakala_*.png dosyalarını siler.
  static Future<int> sweepOld() async {
    try {
      final dir = await getTemporaryDirectory();
      final cutoff = DateTime.now().subtract(_maxAge);
      int deleted = 0;

      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.path.split(Platform.pathSeparator).last;
        if (!_yakalaFilePattern.hasMatch(name)) continue;
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            await entity.delete();
            deleted++;
          }
        } catch (_) {
          // skip
        }
      }
      if (deleted > 0) debugPrint('TempCleanup: $deleted eski dosya silindi.');
      return deleted;
    } catch (e) {
      debugPrint('TempCleanup hatası: $e');
      return 0;
    }
  }
}
