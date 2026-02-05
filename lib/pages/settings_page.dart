import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gap/gap.dart';
import 'package:yakala/providers/app_state.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Theme colors
    final colorScheme = Theme.of(context).colorScheme;
    final surfaceColor = colorScheme.surface; // Material 3 surface
    final onSurface = colorScheme.onSurface;
    final onSurfaceVariant = onSurface.withValues(alpha: 0.7);

    return Scaffold(
      backgroundColor: surfaceColor,
      appBar: AppBar(
        title: const Text("Ayarlar", style: TextStyle(fontSize: 16)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.close, color: onSurfaceVariant),
          onPressed: () async {
            // Close via window manager or navigate back? 
            // Usually settings is a modal or separate view. 
            // In this app structure, we might want to go back to 'home' or hide window.
            context.read<AppState>().navigateTo(AppPage.home);
          },
        ),
      ),
      body: Consumer<AppState>(
        builder: (context, appState, child) {
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle("GENEL", onSurfaceVariant),
                const Gap(10),
                _buildSwitchTile(
                  "Başlangıçta Çalıştır", 
                  "Bilgisayar açıldığında otomatik başla", 
                  appState.startAtLogin, 
                  (v) => appState.toggleStartAtLogin(v),
                  onSurface,
                  onSurfaceVariant,
                  colorScheme.primary
                ),
                _buildSwitchTile(
                  "Ses Efekti", 
                  "Ekran görüntüsü alındığında ses çal", 
                  appState.soundEffect, 
                  (v) => appState.toggleSoundEffect(v),
                  onSurface,
                  onSurfaceVariant,
                  colorScheme.primary
                ),
                
                const Gap(30),
                _buildSectionTitle("KISAYOLLAR", onSurfaceVariant),
                const Gap(10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: onSurface.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Tüm Ekranı Yakala", style: TextStyle(color: onSurfaceVariant)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: onSurface.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: onSurface.withValues(alpha: 0.12)),
                        ),
                        child: Text("⌘ ⇧ C", style: TextStyle(color: onSurface, fontWeight: FontWeight.bold, fontFamily: 'Menlo')),
                      ),
                    ],
                  ),
                ),

                const Gap(30),
                _buildSectionTitle("KAYIT YERİ", onSurfaceVariant),
                const Gap(10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: onSurface.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.folder_open, color: colorScheme.primary, size: 20),
                      const Gap(10),
                      Expanded(
                        child: Text(appState.savePath, style: TextStyle(color: onSurfaceVariant, fontSize: 13)),
                      ),
                      TextButton(
                        onPressed: () {}, // TODO: Klasör seçici
                        child: const Text("Değiştir"),
                      )
                    ],
                  ),
                ),
              ],
            ),
          );
        }
      ),
    );
  }

  Widget _buildSectionTitle(String title, Color color) {
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

  Widget _buildSwitchTile(
    String title, 
    String subtitle, 
    bool value, 
    Function(bool) onChanged,
    Color titleColor,
    Color subtitleColor,
    Color activeColor
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: titleColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: titleColor, fontSize: 14)),
              const Gap(2),
              Text(subtitle, style: TextStyle(color: subtitleColor, fontSize: 11)),
            ],
          ),
          Switch.adaptive(
            value: value, 
            onChanged: onChanged,
            activeTrackColor: activeColor,
          ),
        ],
      ),
    );
  }
}
