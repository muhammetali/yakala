import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yakala/models/capture_mode.dart';
import 'package:yakala/models/hotkey_config.dart';
import 'package:yakala/services/autostart_service.dart';

/// Kalıcı (SharedPreferences) ayar deposu.
/// Setter'lar değer değişmediyse no-op; gereksiz rebuild yok.
class SettingsProvider extends ChangeNotifier {
  static const _kStartAtLogin = 'start_at_login';
  static const _kSoundEffect = 'sound_effect';
  static const _kNotifications = 'notifications_enabled';
  static const _kShowEditor = 'show_editor_after_capture';
  static const _kSavePath = 'save_path';
  static const _kHotkey = 'hotkey_config';
  static const _kDefaultMode = 'default_capture_mode';

  final SharedPreferences _prefs;
  final AutostartService _autostart;

  SettingsProvider._(this._prefs, this._autostart);

  static Future<SettingsProvider> create(AutostartService autostart) async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsProvider._(prefs, autostart);
  }

  bool get startAtLogin => _prefs.getBool(_kStartAtLogin) ?? false;
  bool get soundEffect => _prefs.getBool(_kSoundEffect) ?? true;
  bool get notificationsEnabled => _prefs.getBool(_kNotifications) ?? true;
  bool get showEditorAfterCapture => _prefs.getBool(_kShowEditor) ?? true;
  String get savePath => _prefs.getString(_kSavePath) ?? '';

  HotkeyConfig get hotkey =>
      HotkeyConfig.fromJsonString(_prefs.getString(_kHotkey));

  CaptureMode get defaultCaptureMode {
    final i = _prefs.getInt(_kDefaultMode);
    if (i == null || i < 0 || i >= CaptureMode.values.length) {
      return CaptureMode.fullScreen;
    }
    return CaptureMode.values[i];
  }

  Future<void> setStartAtLogin(bool value) async {
    if (startAtLogin == value) return;
    await _prefs.setBool(_kStartAtLogin, value);
    await _autostart.setEnabled(value);
    notifyListeners();
  }

  Future<void> setSoundEffect(bool value) async {
    if (soundEffect == value) return;
    await _prefs.setBool(_kSoundEffect, value);
    notifyListeners();
  }

  Future<void> setNotificationsEnabled(bool value) async {
    if (notificationsEnabled == value) return;
    await _prefs.setBool(_kNotifications, value);
    notifyListeners();
  }

  Future<void> setShowEditorAfterCapture(bool value) async {
    if (showEditorAfterCapture == value) return;
    await _prefs.setBool(_kShowEditor, value);
    notifyListeners();
  }

  Future<void> setSavePath(String value) async {
    if (savePath == value) return;
    await _prefs.setString(_kSavePath, value);
    notifyListeners();
  }

  Future<void> setHotkey(HotkeyConfig config) async {
    final newSerialized = config.toJsonString();
    // Effective value compare — pref boşken default'la karşılaştırılan
    // edge case'i yakalar (default = default → no-op).
    if (hotkey.toJsonString() == newSerialized) return;
    await _prefs.setString(_kHotkey, newSerialized);
    notifyListeners();
  }

  Future<void> setDefaultCaptureMode(CaptureMode mode) async {
    if (defaultCaptureMode == mode) return;
    await _prefs.setInt(_kDefaultMode, mode.index);
    notifyListeners();
  }
}
