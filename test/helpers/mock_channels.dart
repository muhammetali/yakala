import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// `window_manager` channel'ına yapılan tüm method call'larının kaydı.
/// Her test başında list'i `clear()` ile sıfırla, sonra inceleme yap.
final List<String> windowManagerCalls = <String>[];

void setupMockChannels() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const windowManagerChannel = MethodChannel('window_manager');
  const screenRetrieverChannel =
      MethodChannel('dev.leanflutter.plugins/screen_retriever');

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  messenger.setMockMethodCallHandler(windowManagerChannel,
      (MethodCall call) async {
    windowManagerCalls.add(call.method);
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
      return {'x': 0.0, 'y': 0.0, 'width': 800.0, 'height': 600.0};
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
    if (call.method == 'getPrimaryDisplay') return mockDisplay;
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
}
