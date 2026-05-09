#include "logger.hh"

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <iomanip>
#include <mutex>
#include <sstream>

namespace yakala::daemon {

namespace {

std::atomic<LogLevel> g_level{LogLevel::kInfo};
std::mutex g_mutex;

LogLevel parse_level(const char* s) {
  if (!s) return LogLevel::kInfo;
  std::string lower(s);
  for (char& c : lower) c = static_cast<char>(std::tolower(c));
  if (lower == "debug") return LogLevel::kDebug;
  if (lower == "info") return LogLevel::kInfo;
  if (lower == "warn" || lower == "warning") return LogLevel::kWarn;
  if (lower == "error") return LogLevel::kError;
  return LogLevel::kInfo;
}

const char* level_label(LogLevel level) {
  switch (level) {
    case LogLevel::kDebug: return "DEBUG";
    case LogLevel::kInfo:  return "INFO ";
    case LogLevel::kWarn:  return "WARN ";
    case LogLevel::kError: return "ERROR";
  }
  return "?????";
}

std::string current_timestamp() {
  using namespace std::chrono;
  const auto now = system_clock::now();
  const auto ms = duration_cast<milliseconds>(now.time_since_epoch()) % 1000;
  const auto t = system_clock::to_time_t(now);
  std::tm tm_buf{};
  // localtime_r — POSIX thread-safe variant. localtime() global state'e
  // yazıyor → race condition.
  localtime_r(&t, &tm_buf);
  std::ostringstream oss;
  oss << std::put_time(&tm_buf, "%H:%M:%S")
      << '.' << std::setw(3) << std::setfill('0') << ms.count();
  return oss.str();
}

}  // namespace

void Logger::init() {
  g_level.store(parse_level(std::getenv("YAKALA_LOG")));
}

LogLevel Logger::current_level() {
  return g_level.load();
}

bool Logger::is_enabled(LogLevel level) {
  return static_cast<int>(level) >= static_cast<int>(g_level.load());
}

void Logger::log(LogLevel level, std::string_view tag, std::string_view msg) {
  if (!is_enabled(level)) return;
  // Mutex — birden çok thread aynı anda fputs çağırırsa stderr buffering
  // satırları karıştırabilir. Tek lock ile satır atomicity garantisi.
  std::lock_guard<std::mutex> guard(g_mutex);
  std::fprintf(stderr, "[%s] %s [Yakala/%.*s] %.*s\n",
               current_timestamp().c_str(),
               level_label(level),
               static_cast<int>(tag.size()), tag.data(),
               static_cast<int>(msg.size()), msg.data());
  std::fflush(stderr);
}

namespace detail {

LogStream::LogStream(LogLevel level, std::string_view tag)
    : level_(level), tag_(tag), enabled_(Logger::is_enabled(level)) {}

LogStream::~LogStream() {
  if (enabled_) {
    Logger::log(level_, tag_, buffer_.str());
  }
}

}  // namespace detail

}  // namespace yakala::daemon
