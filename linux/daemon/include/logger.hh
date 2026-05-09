#pragma once

#include <sstream>
#include <string>
#include <string_view>

namespace yakala::daemon {

// Tek-satır log seviyeleri. Industrial pattern — debug filtresi env üzerinden
// kontrol edilir (`YAKALA_LOG=debug yakala-daemon`).
enum class LogLevel {
  kDebug,
  kInfo,
  kWarn,
  kError,
};

// Logger global state'i. Process başında bir kez `init()` çağrılır.
// Thread-safe — birden çok thread aynı anda log yazabilir.
class Logger {
public:
  // Init: $YAKALA_LOG env'inden seviyeyi okur (debug/info/warn/error,
  // büyük-küçük harf duyarsız). Default: info. Stderr'e yazılır.
  static void init();

  // Doğrudan kullanmayın — `YAKALA_LOG_*` makrolarını tercih edin.
  static void log(LogLevel level, std::string_view tag, std::string_view msg);

  static LogLevel current_level();
  static bool is_enabled(LogLevel level);

private:
  Logger() = default;
};

namespace detail {

// stream-style log builder — operator<< ile mesaj inşa edilip dispose'da
// emit edilir.
class LogStream {
public:
  LogStream(LogLevel level, std::string_view tag);
  ~LogStream();

  template <typename T>
  LogStream& operator<<(const T& value) {
    if (enabled_) {
      buffer_ << value;
    }
    return *this;
  }

private:
  LogLevel level_;
  std::string_view tag_;
  bool enabled_;
  std::ostringstream buffer_;
};

}  // namespace detail

}  // namespace yakala::daemon

// Kullanım: YAKALA_LOG_INFO("tray") << "menu click " << item_id;
#define YAKALA_LOG_DEBUG(tag) \
  ::yakala::daemon::detail::LogStream(::yakala::daemon::LogLevel::kDebug, tag)
#define YAKALA_LOG_INFO(tag) \
  ::yakala::daemon::detail::LogStream(::yakala::daemon::LogLevel::kInfo, tag)
#define YAKALA_LOG_WARN(tag) \
  ::yakala::daemon::detail::LogStream(::yakala::daemon::LogLevel::kWarn, tag)
#define YAKALA_LOG_ERROR(tag) \
  ::yakala::daemon::detail::LogStream(::yakala::daemon::LogLevel::kError, tag)
