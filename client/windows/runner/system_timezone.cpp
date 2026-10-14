#include "system_timezone.h"

#include <windows.h>
#include <icu.h>

#include <cstring>

std::optional<std::string> ReadSystemTimezone() {
  DYNAMIC_TIME_ZONE_INFORMATION timezone{};
  if (GetDynamicTimeZoneInformation(&timezone) == TIME_ZONE_ID_INVALID ||
      timezone.TimeZoneKeyName[0] == L'\0' ||
      timezone.DynamicDaylightTimeDisabled) {
    return std::nullopt;
  }

  // ICU's cached default can outlive an OS setting change. Resolve the freshly
  // read Windows key instead. Use system DLLs without a mandatory import, so
  // older Windows versions can still start and report an explicit fallback.
  // API: https://unicode-org.github.io/icu-docs/apidoc/dev/icu4c/ucal_8h.html
  HMODULE library = LoadLibraryExW(L"icu.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (!library) {
    library = LoadLibraryExW(L"icuin.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
  }
  if (!library) return std::nullopt;
  auto address = GetProcAddress(library, "ucal_getTimeZoneIDForWindowsID");
  if (!address) {
    FreeLibrary(library);
    return std::nullopt;
  }
  // Both pointers have the platform pointer representation. Copying avoids an
  // MSVC warning about a FARPROC cast when warnings are treated as errors.
  decltype(&ucal_getTimeZoneIDForWindowsID) convert = nullptr;
  static_assert(sizeof(convert) == sizeof(address));
  std::memcpy(&convert, &address, sizeof(convert));
  UChar result[128]{};
  UChar windows_id[128]{};
  for (size_t index = 0; index < 128; ++index) {
    windows_id[index] = static_cast<UChar>(timezone.TimeZoneKeyName[index]);
  }
  UErrorCode status = U_ZERO_ERROR;
  const auto length = convert(
      windows_id, -1,
      nullptr, result, 128, &status);
  FreeLibrary(library);
  if (U_FAILURE(status) || length <= 0 || length >= 128) return std::nullopt;

  // IANA identifiers are ASCII. Reject unexpected output rather than corrupting
  // it or guessing a region from Windows' current numeric offset.
  std::string identifier;
  identifier.reserve(length);
  for (int32_t index = 0; index < length; ++index) {
    if (result[index] == 0 || result[index] > 0x7f) return std::nullopt;
    identifier.push_back(static_cast<char>(result[index]));
  }
  return identifier;
}
