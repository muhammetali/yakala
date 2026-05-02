import 'dart:typed_data';

import 'package:yakala/services/overlay_controller.dart';

/// Yakalama sonrası annotation editor'ün CaptureService ile köprüsü.
/// `start(image)` editor'ü açar; kullanıcı "Bitti" derse annotated bytes,
/// "İptal" derse null döner.
class AnnotationService extends OverlayController<Uint8List, Uint8List> {
  Uint8List? get imageBytes => payload;
}
