import 'package:system_tray/system_tray.dart';
import 'package:yakala/models/capture_mode.dart';
import 'package:yakala/utils/tray_utils.dart';

class TrayService {
  final SystemTray _tray = SystemTray();
  bool _initialized = false;

  Future<void> initialize({
    required String hotkeyLabel,
    required Future<void> Function(CaptureMode) onCapture,
    required Future<void> Function() onSettings,
    required Future<void> Function() onQuit,
  }) async {
    if (_initialized) return;
    final iconPath = await TrayUtils.getIconPath();

    await _tray.initSystemTray(
      title: 'Yakala',
      iconPath: iconPath,
      toolTip: 'Yakala — $hotkeyLabel',
    );

    final menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(
        label: CaptureMode.fullScreen.label,
        image: 'assets/icons/full_screen.png',
        onClicked: (_) => onCapture(CaptureMode.fullScreen),
      ),
      MenuItemLabel(
        label: CaptureMode.region.label,
        image: 'assets/icons/region.png',
        onClicked: (_) => onCapture(CaptureMode.region),
      ),
      MenuItemLabel(
        label: CaptureMode.window.label,
        image: 'assets/icons/window.png',
        onClicked: (_) => onCapture(CaptureMode.window),
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Ayarlar',
        image: 'assets/icons/settings.png',
        onClicked: (_) => onSettings(),
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Çıkış',
        image: 'assets/icons/quit.png',
        onClicked: (_) => onQuit(),
      ),
    ]);

    await _tray.setContextMenu(menu);
    _initialized = true;
  }

  /// Hotkey değişince tooltip'i günceller.
  Future<void> updateTooltip(String hotkeyLabel) async {
    if (!_initialized) return;
    try {
      await _tray.setToolTip('Yakala — $hotkeyLabel');
    } catch (e) {
      // Bazı sürümler setToolTip desteklemiyor — sessiz geç.
    }
  }

  Future<void> dispose() async {
    if (!_initialized) return;
    await _tray.destroy();
    _initialized = false;
  }
}
