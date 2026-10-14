/// Business text carried across Dart/JavaScript error boundaries, without
/// repeated exception wrappers or stack frames. Full errors remain available
/// separately for diagnostics.
String scriptErrorMessage(Object error) {
  var text =
      (error is StateError
              ? error.message.toString()
              : error is FormatException
              ? error.message
              : error.toString())
          .trim();
  final lines = text.split('\n');
  final frame = lines.indexWhere(
    (line) => RegExp(
      r'^\s+at\s+.+(?:\([^)]*:\d+(?::\d+)?\)|\(native\)|\[native code\]|:\d+(?::\d+)?)\s*$|^\s*#\d+\s+',
    ).hasMatch(line),
  );
  if (frame >= 0) text = lines.take(frame).join('\n').trim();
  final wrapper = RegExp(
    r'^(?:Bad state|(?:[A-Za-z_$][\w.$]*)?(?:Error|Exception)):\s*',
  );
  String strip(String value) {
    var result = value;
    while (wrapper.hasMatch(result)) {
      result = result.replaceFirst(wrapper, '').trimLeft();
    }
    return result.trim();
  }

  text = strip(text);
  // Some JS engines include the exception heading again before their frames.
  final parts = text.split('\n');
  if (parts.length > 1 && strip(parts.last) == strip(parts.first)) {
    text = parts.take(parts.length - 1).join('\n').trim();
  }
  return text.isEmpty ? '模块操作失败，请重试。' : text;
}
