import 'dart:async';
import 'package:flutter/foundation.dart';

/// Tek slot async overlay coordinator. CaptureService bir overlay başlatır,
/// completer üzerinden sonucu bekler; widget tree `isActive` üzerinden
/// hangi overlay'in açık olduğunu öğrenir.
///
/// `payload` overlay'e gönderilen ek veridir (örn region için image bytes,
/// annotation için input image bytes).
abstract class OverlayController<TResult, TPayload> extends ChangeNotifier {
  TPayload? _payload;
  Completer<TResult?>? _completer;

  bool get isActive => _completer != null;
  TPayload? get payload => _payload;

  Future<TResult?> start(TPayload payload) {
    final prev = _completer;
    if (prev != null && !prev.isCompleted) {
      prev.complete(null);
    }
    _payload = payload;
    _completer = Completer<TResult?>();
    notifyListeners();
    return _completer!.future;
  }

  void confirm(TResult result) {
    final c = _completer;
    if (c == null || c.isCompleted) return;
    c.complete(result);
    _reset();
  }

  void cancel() {
    final c = _completer;
    if (c == null || c.isCompleted) return;
    c.complete(null);
    _reset();
  }

  void _reset() {
    _completer = null;
    _payload = null;
    notifyListeners();
  }
}
