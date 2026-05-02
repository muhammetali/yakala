import 'dart:typed_data';
import 'dart:ui';

import 'package:yakala/services/overlay_controller.dart';

class RegionPayload {
  final Uint8List image;
  final Size logicalSize;
  const RegionPayload({required this.image, required this.logicalSize});
}

/// Region overlay'in widget tree ile CaptureService arasındaki köprüsü.
/// İki fazlı overlay (selection + in-place annotation) tek pencerede
/// tamamlanır; sonuç olarak annotated PNG bytes döner.
class RegionSelectorService extends OverlayController<Uint8List, RegionPayload> {
  Uint8List? get backgroundImage => payload?.image;
  Size? get logicalSize => payload?.logicalSize;

  Future<Uint8List?> startWith({
    required Uint8List image,
    required Size logicalSize,
  }) {
    return start(RegionPayload(image: image, logicalSize: logicalSize));
  }
}
