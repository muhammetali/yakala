import 'package:screen_capturer/screen_capturer.dart' as sc;

enum CaptureMode {
  fullScreen,
  region,
  window;

  String get label {
    switch (this) {
      case CaptureMode.fullScreen:
        return 'Tüm Ekran';
      case CaptureMode.region:
        return 'Bölge Seç';
      case CaptureMode.window:
        return 'Pencere';
    }
  }

  sc.CaptureMode toScreenCapturerMode() {
    switch (this) {
      case CaptureMode.fullScreen:
        return sc.CaptureMode.screen;
      case CaptureMode.region:
        return sc.CaptureMode.region;
      case CaptureMode.window:
        return sc.CaptureMode.window;
    }
  }
}
