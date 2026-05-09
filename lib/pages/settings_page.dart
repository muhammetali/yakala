import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yakala/models/capture_mode.dart';
import 'package:yakala/providers/settings_provider.dart';

/// Settings sayfası — yalın ayar paneli. Daemon mimarisinde:
///   - Hotkey: GNOME custom shortcut (Linux) / NSEvent monitor (macOS)
///     yönetiyor; UI'de ayar yok, sadece nereye bakacağı bilgisi var.
///   - Autostart: daemon'un kendi `.desktop`/LaunchAgent'i; UI bir
///     opsiyon göstermiyor (install script kuruyor).
///
/// Settings dosyaya kaydedilir (~/.config/yakala/settings.json); daemon
/// bir sonraki capture'da mtime check ile reload eder.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final surfaceColor = colorScheme.surface;
    final onSurface = colorScheme.onSurface;
    final onSurfaceVariant = onSurface.withValues(alpha: 0.7);

    return Scaffold(
      backgroundColor: surfaceColor,
      appBar: AppBar(
        title: const Text('Ayarlar', style: TextStyle(fontSize: 16)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle('GENEL'),
                const Gap(10),
                _SwitchTile(
                  title: 'Bildirimler',
                  subtitle: 'Yakalama sonrası native bildirim göster',
                  value: settings.notificationsEnabled,
                  onChanged: settings.setNotificationsEnabled,
                ),
                _SwitchTile(
                  title: 'Ses Efekti',
                  subtitle: 'Ekran görüntüsü alındığında ses çal',
                  value: settings.soundEffect,
                  onChanged: settings.setSoundEffect,
                ),
                _SwitchTile(
                  title: 'Yakalama Sonrası Düzenle',
                  subtitle: 'Tüm ekran/pencere yakalamasından sonra editör aç '
                      '(Bölge yakalama her zaman editörü gösterir)',
                  value: settings.showEditorAfterCapture,
                  onChanged: settings.setShowEditorAfterCapture,
                ),

                const Gap(30),
                _SectionTitle('VARSAYILAN MOD'),
                const Gap(10),
                _ModeSelector(
                  current: settings.defaultCaptureMode,
                  onChanged: settings.setDefaultCaptureMode,
                ),

                const Gap(30),
                _SectionTitle('KISAYOL'),
                const Gap(10),
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.keyboard,
                              color: colorScheme.primary, size: 20),
                          const Gap(10),
                          Expanded(
                            child: Text(
                              Platform.isMacOS
                                  ? 'Sistem Ayarları → Klavye → '
                                      'Klavye Kısayolları altından '
                                      '"Yakala" kısayolunu özelleştirin.'
                                  : 'GNOME Ayarları → Klavye → '
                                      'Klavye Kısayolları altından '
                                      '"Yakala" kısayolunu özelleştirin.',
                              style: TextStyle(
                                color: onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Gap(8),
                      Row(
                        children: [
                          const Gap(30),
                          Expanded(
                            child: Text(
                              'Varsayılan: Super+Shift+C',
                              style: TextStyle(
                                color: onSurfaceVariant.withValues(alpha: 0.7),
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                          if (!Platform.isMacOS)
                            TextButton.icon(
                              icon: const Icon(Icons.copy, size: 14),
                              label: const Text('Komutu kopyala'),
                              onPressed: () {
                                Clipboard.setData(const ClipboardData(
                                  text: '/home/mali/.local/share/yakala/'
                                      'yakala-daemon --capture-fullscreen',
                                ));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Komut panoya kopyalandı'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                const Gap(30),
                _SectionTitle('KAYIT YERİ'),
                const Gap(10),
                _Card(
                  child: Row(
                    children: [
                      Icon(Icons.folder_open,
                          color: colorScheme.primary, size: 20),
                      const Gap(10),
                      Expanded(
                        child: Text(
                          settings.savePath.isEmpty
                              ? 'Sadece pano (disk kaydı yok)'
                              : settings.savePath,
                          style: TextStyle(color: onSurfaceVariant, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (settings.savePath.isNotEmpty)
                        IconButton(
                          tooltip: 'Temizle',
                          icon: Icon(Icons.clear,
                              size: 18, color: onSurfaceVariant),
                          onPressed: () => settings.setSavePath(''),
                        ),
                      TextButton(
                        onPressed: () => _pickFolder(settings),
                        child: const Text('Değiştir'),
                      ),
                    ],
                  ),
                ),

                const Gap(30),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Kapat'),
                    onPressed: () async {
                      await windowManager.close();
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickFolder(SettingsProvider settings) async {
    final path = await getDirectoryPath();
    if (path != null && path.isNotEmpty) {
      await settings.setSavePath(path);
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return Text(
      title,
      style: TextStyle(
        color: color.withValues(alpha: 0.5),
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final Future<void> Function(bool) onChanged;

  const _SwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;
    final onSurfaceVariant = onSurface.withValues(alpha: 0.7);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: onSurface, fontSize: 14)),
                const Gap(2),
                Text(
                  subtitle,
                  style: TextStyle(color: onSurfaceVariant, fontSize: 11),
                ),
              ],
            ),
          ),
          const Gap(8),
          Switch.adaptive(
            value: value,
            onChanged: (v) => onChanged(v),
            activeTrackColor: scheme.primary,
          ),
        ],
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  final CaptureMode current;
  final Future<void> Function(CaptureMode) onChanged;

  const _ModeSelector({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<CaptureMode>(
      segments: CaptureMode.values
          .map((m) => ButtonSegment(value: m, label: Text(m.label)))
          .toList(),
      selected: {current},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}
