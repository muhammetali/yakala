import 'package:flutter_test/flutter_test.dart';
import 'package:yakala/utils/display_server.dart';

void main() {
  group('DisplayServerInfo.detect (test seams ile deterministik)', () {
    test('Linux değilse her zaman unknown', () {
      expect(
        DisplayServerInfo.detect(
          forceLinux: false,
          overrideEnv: const {'WAYLAND_DISPLAY': 'wayland-0'},
        ),
        DisplayServer.unknown,
      );
    });

    test('WAYLAND_DISPLAY set → wayland (en kesin sinyal)', () {
      expect(
        DisplayServerInfo.detect(
          forceLinux: true,
          overrideEnv: const {'WAYLAND_DISPLAY': 'wayland-0'},
        ),
        DisplayServer.wayland,
      );
    });

    test('WAYLAND_DISPLAY boş + XDG_SESSION_TYPE=wayland → wayland', () {
      expect(
        DisplayServerInfo.detect(
          forceLinux: true,
          overrideEnv: const {
            'WAYLAND_DISPLAY': '',
            'XDG_SESSION_TYPE': 'wayland',
          },
        ),
        DisplayServer.wayland,
      );
    });

    test('XDG_SESSION_TYPE=Wayland (case insensitive)', () {
      expect(
        DisplayServerInfo.detect(
          forceLinux: true,
          overrideEnv: const {'XDG_SESSION_TYPE': 'WaYlAnD'},
        ),
        DisplayServer.wayland,
      );
    });

    test('XDG_SESSION_TYPE=x11 → x11', () {
      expect(
        DisplayServerInfo.detect(
          forceLinux: true,
          overrideEnv: const {'XDG_SESSION_TYPE': 'x11'},
        ),
        DisplayServer.x11,
      );
    });

    test('Sadece DISPLAY set → x11 (fallback)', () {
      expect(
        DisplayServerInfo.detect(
          forceLinux: true,
          overrideEnv: const {'DISPLAY': ':0'},
        ),
        DisplayServer.x11,
      );
    });

    test('Hiçbir env yok → unknown (TTY / SSH headless)', () {
      expect(
        DisplayServerInfo.detect(forceLinux: true, overrideEnv: const {}),
        DisplayServer.unknown,
      );
    });

    test('WAYLAND_DISPLAY önceliği XDG_SESSION_TYPE üzerinde', () {
      // Eğer ikisi çelişirse (rare ama mümkün — sddm Wayland session'da
      // XDG_SESSION_TYPE='x11' set edebilir), WAYLAND_DISPLAY güvenilir.
      expect(
        DisplayServerInfo.detect(
          forceLinux: true,
          overrideEnv: const {
            'WAYLAND_DISPLAY': 'wayland-1',
            'XDG_SESSION_TYPE': 'x11',
          },
        ),
        DisplayServer.wayland,
      );
    });

    test('XDG_SESSION_TYPE bilinmeyen değer + DISPLAY var → x11 fallback', () {
      expect(
        DisplayServerInfo.detect(
          forceLinux: true,
          overrideEnv: const {
            'XDG_SESSION_TYPE': 'tty',
            'DISPLAY': ':0',
          },
        ),
        DisplayServer.x11,
      );
    });
  });
}
