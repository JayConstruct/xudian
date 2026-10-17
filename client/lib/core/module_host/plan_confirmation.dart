/// Optional plain-text presentation for reviewing the same frozen write plan.
/// This carries no authorization, writes, plan identity or commit behavior.
class PlanConfirmation {
  const PlanConfirmation._({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.acknowledgement,
  });

  final String title, message, confirmLabel;
  final String? acknowledgement;
  static const limits = {
    'title': 120,
    'message': 6000,
    'confirmLabel': 48,
    'acknowledgement': 1000,
  };

  factory PlanConfirmation.parse(Object? value) {
    if (value is! Map || value.keys.any((key) => !limits.containsKey(key))) {
      throw const FormatException('Invalid plan confirmation fields');
    }
    String read(String key) {
      final text = value[key];
      if (text is! String ||
          text.trim().isEmpty ||
          text.length > limits[key]!) {
        throw FormatException('Invalid plan confirmation $key');
      }
      return text.trim();
    }

    return PlanConfirmation._(
      title: read('title'),
      message: read('message'),
      confirmLabel: read('confirmLabel'),
      acknowledgement: value.containsKey('acknowledgement')
          ? read('acknowledgement')
          : null,
    );
  }

  Map<String, Object?> toJson() => Map.unmodifiable({
    'title': title,
    'message': message,
    'confirmLabel': confirmLabel,
    if (acknowledgement != null) 'acknowledgement': acknowledgement,
  });
}
