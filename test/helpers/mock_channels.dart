import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void setupMockChannels() {
  // TestDefaultBinaryMessengerBinding.instance kullanmadan önce binding garanti.
  TestWidgetsFlutterBinding.ensureInitialized();

  const windowManagerChannel = MethodChannel('window_manager');
  const screenCapturerChannel = MethodChannel('screen_capturer');
  const hotKeyChannel =
      MethodChannel('dev.leanflutter.plugins/hotkey_manager');
  const systemTrayChannel = MethodChannel('system_tray');
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  const launchAtStartupChannel = MethodChannel('launch_at_startup');
  const packageInfoChannel = MethodChannel('dev.fluttercommunity.plus/package_info');
  const screenRetrieverChannel = MethodChannel('dev.leanflutter.plugins/screen_retriever');

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  messenger.setMockMethodCallHandler(windowManagerChannel,
      (MethodCall call) async {
    if ([
      'isMinimized',
      'isVisible',
      'isFocused',
      'isPreventClose',
      'isSkippingTaskbar',
      'hasShadow',
      'isAlwaysOnTop',
      'isFullScreen',
      'isMaximized',
      'isClosable',
      'isMaximizable',
      'isMinimizable',
      'isResizable',
      'isMovable',
    ].contains(call.method)) {
      return false;
    }
    if (call.method == 'getBounds') {
      return {
        'x': 0.0,
        'y': 0.0,
        'width': 800.0,
        'height': 600.0,
      };
    }
    if (call.method == 'getSize') {
      return {'width': 800.0, 'height': 600.0};
    }
    if (call.method == 'getPosition') {
      return {'x': 0.0, 'y': 0.0};
    }
    if (call.method == 'getOpacity') return 1.0;
    if (call.method == 'getTitle') return 'Yakala';
    return null;
  });

  messenger.setMockMethodCallHandler(screenCapturerChannel,
      (MethodCall call) async {
    if (call.method == 'isAccessAllowed') return true;
    if (call.method == 'capture') {
      return {
        'imagePath': '/tmp/mock_capture.png',
        'imageWidth': 1920,
        'imageHeight': 1080,
      };
    }
    return null;
  });

  messenger.setMockMethodCallHandler(
      hotKeyChannel, (MethodCall call) async => null);
  messenger.setMockMethodCallHandler(
      systemTrayChannel, (MethodCall call) async => null);
  messenger.setMockMethodCallHandler(
      launchAtStartupChannel, (MethodCall call) async => null);

  messenger.setMockMethodCallHandler(screenRetrieverChannel,
      (MethodCall call) async {
    final mockDisplay = {
      'id': 'mock',
      'name': 'Mock Display',
      'size': {'width': 1920.0, 'height': 1080.0},
      'visiblePosition': {'dx': 0.0, 'dy': 0.0},
      'visibleSize': {'width': 1920.0, 'height': 1080.0},
      'scaleFactor': 1.0,
    };
    if (call.method == 'getPrimaryDisplay') {
      return mockDisplay;
    }
    if (call.method == 'getAllDisplays') {
      return {
        'displays': [mockDisplay],
      };
    }
    if (call.method == 'getCursorScreenPoint') {
      return {'dx': 0.0, 'dy': 0.0};
    }
    return null;
  });

  messenger.setMockMethodCallHandler(packageInfoChannel,
      (MethodCall call) async {
    if (call.method == 'getAll') {
      return {
        'appName': 'Yakala',
        'packageName': 'yakala',
        'version': '1.0.0',
        'buildNumber': '1',
        'buildSignature': '',
        'installerStore': '',
      };
    }
    return null;
  });

  messenger.setMockMethodCallHandler(pathProviderChannel,
      (MethodCall call) async {
    if (call.method == 'getTemporaryDirectory' ||
        call.method == 'getApplicationDocumentsDirectory' ||
        call.method == 'getApplicationSupportDirectory') {
      return '/tmp';
    }
    return '.';
  });

  // SharedPreferences in-memory mock
  SharedPreferences.setMockInitialValues({});
}
