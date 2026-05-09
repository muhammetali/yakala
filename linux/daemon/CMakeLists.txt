# Yakala Linux Daemon
#
# Bağımsız native daemon: tray icon, global hotkey, capture trigger, IPC.
# Flutter UI'ye `yakala-ui --mode=...` ile on-demand spawn ile bağlanır.
#
# Build:
#   cmake -S linux/daemon -B build/daemon-linux -DCMAKE_BUILD_TYPE=Release
#   cmake --build build/daemon-linux
#
# Bağımlılıklar (apt):
#   libayatana-appindicator3-dev libgtk-3-dev libdbus-1-dev nlohmann-json3-dev
#   libkeybinder-3.0-dev (X11 hotkey için, faz 1.5'te eklenir)

cmake_minimum_required(VERSION 3.16)
project(yakala_daemon
  VERSION 0.1.0
  LANGUAGES CXX
  DESCRIPTION "Yakala native daemon (tray + hotkey + capture + IPC)"
)

# Industrial standard: C++17, warnings as errors, position-independent code.
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

# Warning seviyesi — production'da -Werror açılabilir. Şu anda -Wall + -Wextra
# yeterli; faz olgunlaştığında -Werror'a geçilebilir.
add_compile_options(-Wall -Wextra -Wpedantic -Wno-unused-parameter)
# Optimization flag'leri CMake'in CMAKE_CXX_FLAGS_<CONFIG> ile gelir; manuel
# eklemiyoruz — generator expression'la liste-olarak geçen flag'ler bazı
# CMake sürümlerinde tek string'e merge oluyor (ör. "-O0 -g") ve gcc bunu
# tek argüman sanıyor.

# Bağımlılıklar
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK3 REQUIRED IMPORTED_TARGET gtk+-3.0)
pkg_check_modules(APPINDICATOR REQUIRED IMPORTED_TARGET ayatana-appindicator3-0.1)
pkg_check_modules(GIO REQUIRED IMPORTED_TARGET gio-2.0 gio-unix-2.0)
find_package(nlohmann_json 3.7.0 REQUIRED)
find_package(Threads REQUIRED)

# Daemon binary
add_executable(yakala-daemon
  src/main.cc
  src/logger.cc
  src/settings_loader.cc
  src/ipc_server.cc
  src/ui_spawner.cc
  src/tray.cc
  src/process_runner.cc
  src/capture.cc
  src/clipboard.cc
  src/notification.cc
  src/capture_orchestrator.cc
)

target_include_directories(yakala-daemon PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_link_libraries(yakala-daemon PRIVATE
  PkgConfig::GTK3
  PkgConfig::APPINDICATOR
  PkgConfig::GIO
  nlohmann_json::nlohmann_json
  Threads::Threads
)

# install-launcher.sh CMAKE_INSTALL_PREFIX'i kullanmıyor — bundle yolu sabit
# (~/.local/share/yakala/yakala-daemon). install target tanımlamayız; install
# script binary'yi build/daemon-linux/yakala-daemon yolundan kopyalar.
