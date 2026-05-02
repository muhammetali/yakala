class CaptureResult {
  final bool success;
  final String? imagePath;
  final String? savedToDisk;
  final String? error;

  const CaptureResult._({
    required this.success,
    this.imagePath,
    this.savedToDisk,
    this.error,
  });

  factory CaptureResult.ok({required String imagePath, String? savedToDisk}) {
    return CaptureResult._(
      success: true,
      imagePath: imagePath,
      savedToDisk: savedToDisk,
    );
  }

  factory CaptureResult.cancelled() {
    return const CaptureResult._(success: false, error: 'cancelled');
  }

  factory CaptureResult.failed(String message) {
    return CaptureResult._(success: false, error: message);
  }

  bool get isCancelled => !success && error == 'cancelled';
}
