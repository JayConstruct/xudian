#ifndef RUNNER_SYSTEM_TIMEZONE_H_
#define RUNNER_SYSTEM_TIMEZONE_H_

#include <optional>
#include <string>

// Resolves the current Windows key using the OS ICU/CLDR mapping. Missing
// mappings return nullopt; Dart validates IANA IDs and labels its fallback.
std::optional<std::string> ReadSystemTimezone();

#endif  // RUNNER_SYSTEM_TIMEZONE_H_
