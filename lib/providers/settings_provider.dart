import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:yakala/models/capture_mode.dart';

/// Daemon ile paylaşılan JSON dosya tabanlı ayar deposu.
///
/// **Path**: XDG Base Directory'ye uygun olarak `$XDG_CONFIG_HOME/yakala/
/// settings.json` (genelde `~/.config/yakala/settings.json`). macOS'ta da
/// aynı yol kullanılır — daemon (Swift) bu dosyayı okur, UI yazar.
///
/// **Atomic write**: write-to-tmp + rename pattern. Daemon mtime check ile
/// reload tetiklenir.
///
/// **Ne yok**: SharedPreferences'ta tutulan `hotkey` ve `start_at_login`
/// alanları kaldırıldı:
///   - hotkey: GNOME custom shortcut (Linux) / NSEvent monitor (macOS)
///     altyapısı yönetiyor — UI sadece bilgi gösteriyor.
///   - start_at_login: daemon'un kendi autostart .desktop'u / LaunchAgent
///     plist'i yönetiyor — install script kuruyor.
class SettingsProvider extends ChangeNotifier {
  static const _kDefaultCaptureMode = 'default_capture_mode';
  static const _kShowEditor = 'show_editor_after_capture';
  static const _kSoundEffect = 'sound_effect';
  static const _kNotifications = 'notifications_enabled';
  static const _kSavePath = 'save_path';

  final File _file;

  // Cached state — tüm setter/getter bu map üzerinden çalışır.
  CaptureMode _defaultCaptureMode = CaptureMode.fullScreen;
  bool _showEditorAfterCapture = true;
  bool _soundEffect = true;
  bool _notificationsEnabled = true;
  String _savePath = '';

  SettingsProvider._(this._file);

  /// Diskten yükleme + dizin garantisi. UI başlangıcında bir kez çağrılır.
  static Future<SettingsProvider> create() async {
    final path = _resolvePath();
    final file = File(path);
    final provider = SettingsProvider._(file);
    await provider._load();
    return provider;
  }

  static String _resolvePath() {
    final env = Platform.environment;
    String base;
    if (Platform.isMacOS) {
      // macOS'ta XDG yerine standart Application Support — daemon Swift
      // tarafı da burayı kullanacak.
      final home = env['HOME'] ?? '';
      base = p.join(home, 'Library', 'Application Support');
    } else {
      // Linux: XDG_CONFIG_HOME üstün, yoksa $HOME/.config.
      final xdg = env['XDG_CONFIG_HOME'];
      if (xdg != null && xdg.isNotEmpty) {
        base = xdg;
      } else {
        final home = env['HOME'] ?? env['USERPROFILE'] ?? '';
        base = p.join(home, '.config');
      }
    }
    return p.join(base, 'yakala', 'settings.json');
  }

  Future<void> _load() async {
    if (!await _file.exists()) {
      // Dosya yok — default değerler. UI ilk kayıtta dosyayı oluşturur.
      return;
    }
    try {
      final content = await _file.readAsString();
      if (content.trim().isEmpty) return;
      final j = jsonDecode(content) as Map<String, dynamic>;

      final modeStr = j[_kDefaultCaptureMode] as String?;
      if (modeStr != null) {
        // String "fullScreen" / "region" / "window" → enum
        for (final m in CaptureMode.values) {
          if (m.name == modeStr) {
            _defaultCaptureMode = m;
            break;
          }
        }
      }
      _showEditorAfterCapture = j[_kShowEditor] as bool? ?? _showEditorAfterCapture;
      _soundEffect = j[_kSoundEffect] as bool? ?? _soundEffect;
      _notificationsEnabled = j[_kNotifications] as bool? ?? _notificationsEnabled;
      _savePath = j[_kSavePath] as String? ?? _savePath;
    } catch (e) {
      debugPrint('SettingsProvider: load hatası (default kullanılıyor): $e');
    }
  }

  Future<void> _save() async {
    final j = <String, dynamic>{
      _kDefaultCaptureMode: _defaultCaptureMode.name,
      _kShowEditor: _showEditorAfterCapture,
      _kSoundEffect: _soundEffect,
      _kNotifications: _notificationsEnabled,
      _kSavePath: _savePath,
    };
    final content = const JsonEncoder.withIndent('  ').convert(j);

    try {
      await _file.parent.create(recursive: true);
      // Atomic write: tmp + rename. Daemon mtime/inode değişikliğini
      // tek seferde görür; partial-write race yok.
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(content, flush: true);
      await tmp.rename(_file.path);
    } catch (e) {
      debugPrint('SettingsProvider: save hatası: $e');
    }
  }

  // Getter'lar
  CaptureMode get defaultCaptureMode => _defaultCaptureMode;
  bool get showEditorAfterCapture => _showEditorAfterCapture;
  bool get soundEffect => _soundEffect;
  bool get notificationsEnabled => _notificationsEnabled;
  String get savePath => _savePath;

  // Setter'lar — değer değişmediyse no-op; aksi halde mem cache + disk + notify.
  Future<void> setDefaultCaptureMode(CaptureMode mode) async {
    if (_defaultCaptureMode == mode) return;
    _defaultCaptureMode = mode;
    await _save();
    notifyListeners();
  }

  Future<void> setShowEditorAfterCapture(bool value) async {
    if (_showEditorAfterCapture == value) return;
    _showEditorAfterCapture = value;
    await _save();
    notifyListeners();
  }

  Future<void> setSoundEffect(bool value) async {
    if (_soundEffect == value) return;
    _soundEffect = value;
    await _save();
    notifyListeners();
  }

  Future<void> setNotificationsEnabled(bool value) async {
    if (_notificationsEnabled == value) return;
    _notificationsEnabled = value;
    await _save();
    notifyListeners();
  }

  Future<void> setSavePath(String value) async {
    if (_savePath == value) return;
    _savePath = value;
    await _save();
    notifyListeners();
  }
}
