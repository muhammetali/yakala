import 'dart:io';

/// Linux session türünü tespit eder. WAYLAND_DISPLAY tek başına yeterli değil:
/// bazı oturum yöneticileri (sddm, gdm bazı sürümler) Wayland session'da
/// bu env'i set etmez ama XDG_SESSION_TYPE=wayland yine de doğru.
/// Sıralama: önce WAYLAND_DISPLAY (en kesin sinyal — soket adı), sonra
/// XDG_SESSION_TYPE.
enum DisplayServer { wayland, x11, unknown }

class DisplayServerInfo {
  static DisplayServer detect() {
    if (!Platform.isLinux) return DisplayServer.unknown;
    final env = Platform.environment;
    final wayland = env['WAYLAND_DISPLAY'];
    if (wayland != null && wayland.isNotEmpty) return DisplayServer.wayland;
    final sessionType = env['XDG_SESSION_TYPE']?.toLowerCase();
    if (sessionType == 'wayland') return DisplayServer.wayland;
    if (sessionType == 'x11') return DisplayServer.x11;
    final display = env['DISPLAY'];
    if (display != null && display.isNotEmpty) return DisplayServer.x11;
    return DisplayServer.unknown;
  }

  static bool get isWayland => detect() == DisplayServer.wayland;
  static bool get isX11 => detect() == DisplayServer.x11;
}
