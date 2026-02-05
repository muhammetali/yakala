import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class TrayUtils {
  /// Asset dosyasını (örn: assets/app_icon.png) geçici dizine kopyalar ve dosya yolunu döner.
  /// SystemTray paketi assetleri doğrudan okuyamadığı için bu gereklidir.
  static Future<String> getIconPath() async {
    final directory = await getTemporaryDirectory();
    // Platforma göre uzantı seçimi (Windows .ico sever, diğerleri .png)
    final extension = Platform.isWindows ? 'ico' : 'png'; 
    final fileName = 'app_icon.$extension';
    final filePath = '${directory.path}/$fileName';
    final file = File(filePath);

    if (!await file.exists()) {
      // Windows için ico dosyamız yoksa png kullanmayı deneriz (veya bir ico asset eklemek gerekir)
      // Şimdilik elimizdeki tek asset olan png'yi kullanıyoruz.
      final assetPath = 'assets/app_icon.png';
      
      try {
        final byteData = await rootBundle.load(assetPath);
        await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      } catch (e) {
        debugPrint("İkon dosyası oluşturulamadı: $e");
        return '';
      }
    }
    return filePath;
  }
}
