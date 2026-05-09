// swift-tools-version:5.7
//
// Yakala macOS Native Daemon
//
// Swift Package Manager build:
//   cd macos/daemon
//   swift build -c release
// Sonuç: macos/daemon/.build/release/yakala-daemon
//
// Bağımlılıklar: sadece Apple framework'leri (AppKit, ScreenCaptureKit,
// Carbon, Network). Üçüncü taraf paket yok — endüstriyel pattern,
// dependency churn önlenir.
//
// Build artifact'i `bash macos/install-launcher.sh` ile
// /Applications/Yakala.app/Contents/Helpers/ altına kurulur.

import PackageDescription

let package = Package(
  name: "yakala-daemon",
  platforms: [
    // ScreenCaptureKit minimum macOS 12.3. Carbon hotkey API tüm sürümlerde.
    .macOS(.v13),
  ],
  products: [
    .executable(name: "yakala-daemon", targets: ["YakalaDaemon"]),
  ],
  dependencies: [
    // Bilinçli olarak SPM dependency yok.
  ],
  targets: [
    .executableTarget(
      name: "YakalaDaemon",
      path: "Sources/YakalaDaemon"
    ),
  ]
)
