import 'package:flutter/services.dart';

/// Reads the current platform identifier on every request. The host validates
/// it against its IANA database and chooses an explicit fallback when missing.
class SystemTimezonePlatform {
  const SystemTimezonePlatform();
  static const channel = MethodChannel('xudian.host/clock');

  Future<String?> resolve() async {
    final value = await channel.invokeMethod<Object?>('systemTimezone');
    return value is String ? value : null;
  }
}
