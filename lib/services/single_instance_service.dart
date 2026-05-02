import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Aynı anda yalnızca bir Yakala örneğinin çalışmasını sağlar.
///
/// Atomic test-and-set: `File.openSync(mode: writeOnlyAppend)` + flock yerine
/// platform-bağımsız "atomic create" kullanır. POSIX'te O_EXCL semantiği
/// `File.openSync(mode: writeOnly)` ile sağlanmaz; bunun yerine `pathExists`
/// kontrolü + atomic rename pattern uygulanır.
///
/// İmza: pid + timestamp. Lock dosyası canlı PID içermiyorsa "stale" sayılır
/// ve overwrite edilebilir.
class SingleInstanceService {
  File? _lockFile;

  /// true = bu örnek tek; false = başka canlı örnek var, çıkılmalı.
  Future<bool> acquire() async {
    try {
      final dir = await getTemporaryDirectory();
      final lockPath = '${dir.path}/yakala.lock';
      final lockFile = File(lockPath);

      // Atomic-ish: önce candidate dosyasına yaz, sonra rename
      final candidate = File('$lockPath.$pid.tmp');
      await candidate.writeAsString('$pid\n${DateTime.now().toIso8601String()}');

      if (await lockFile.exists()) {
        final content = (await lockFile.readAsString()).trim();
        final firstLine = content.split('\n').first.trim();
        final existingPid = int.tryParse(firstLine);
        if (existingPid != null && existingPid != pid && _isProcessAlive(existingPid)) {
          await candidate.delete();
          debugPrint('Yakala zaten çalışıyor (PID $existingPid).');
          return false;
        }
        // Stale lock — devral
        await lockFile.delete();
      }

      // Rename atomic on POSIX
      await candidate.rename(lockPath);
      _lockFile = File(lockPath);
      return true;
    } catch (e) {
      debugPrint('Single-instance kontrol hatası: $e');
      // Hata durumunda lock'tan çekinmeyip devam et (kullanıcı engellenemez).
      return true;
    }
  }

  Future<void> release() async {
    try {
      final f = _lockFile;
      if (f != null && await f.exists()) {
        // Sahip olduğumuzu doğrula (başka örnek devraldıysa silmeyiz)
        final content = (await f.readAsString()).trim();
        final firstLine = content.split('\n').first.trim();
        if (int.tryParse(firstLine) == pid) {
          await f.delete();
        }
      }
    } catch (_) {
      // best-effort cleanup
    }
  }

  bool _isProcessAlive(int pid) {
    try {
      if (Platform.isWindows) {
        final result = Process.runSync(
          'tasklist',
          ['/FI', 'PID eq $pid', '/NH'],
          runInShell: true,
        );
        return result.stdout.toString().contains('$pid');
      } else {
        final result = Process.runSync('kill', ['-0', '$pid']);
        return result.exitCode == 0;
      }
    } catch (_) {
      return false;
    }
  }
}
