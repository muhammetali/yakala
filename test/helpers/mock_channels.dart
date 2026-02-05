import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void setupMockChannels() {
  const MethodChannel windowManagerChannel = MethodChannel('window_manager');
  const MethodChannel screenCapturerChannel = MethodChannel('screen_capturer');
  const MethodChannel hotKeyChannel = MethodChannel('hotkey_manager');
  const MethodChannel systemTrayChannel = MethodChannel('system_tray');
  const MethodChannel pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(windowManagerChannel, (MethodCall methodCall) async {
    // Boolean dönmesi gereken metotlar
    if (['isMinimized', 'isVisible', 'isFocused', 'isPreventClose', 'isSkippingTaskbar', 'hasShadow', 'isAlwaysOnTop']
        .contains(methodCall.method)) {
      return false; 
    }
    // Void dönenler (show, hide, focus vb.)
    return null;
  });

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(screenCapturerChannel, (MethodCall methodCall) async {
    if (methodCall.method == 'capture') {
      return {
        'imagePath': '/tmp/mock_capture.png',
        'imageWidth': 1920,
        'imageHeight': 1080,
      };
    }
    return null;
  });

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(hotKeyChannel, (MethodCall methodCall) async {
    return null;
  });

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(systemTrayChannel, (MethodCall methodCall) async {
    return null;
  });

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProviderChannel, (MethodCall methodCall) async {
    // PathProvider çağrıları
    if (methodCall.method == 'getTemporaryDirectory' || methodCall.method == 'getApplicationDocumentsDirectory') {
      return '/tmp'; // Mock path
    }
    return '.';
  });
}