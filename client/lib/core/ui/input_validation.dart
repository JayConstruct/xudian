String? validateNumberInput(
  String text, {
  bool integer = false,
  num? min,
  num? max,
}) {
  if (text.isEmpty) return null;
  final value = num.tryParse(text);
  if (value == null || !value.isFinite) return '请输入有效数字';
  if (integer && value != value.truncateToDouble()) return '请输入整数';
  if (min != null && value < min || max != null && value > max) {
    return '请输入允许范围内的数字';
  }
  return null;
}
