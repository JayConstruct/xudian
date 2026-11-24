/// Optional plain-text presentation for reviewing the same frozen write plan.
/// This carries no authorization, writes, plan identity or commit behavior.
class PlanConfirmation {
  const PlanConfirmation._({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.acknowledgement,
    this.subject,
    this.quote = false,
    this.section,
    this.notice,
    this.icon,
    this.summaryOnly = false,
    this.items = const [],
  });

  final String title, message, confirmLabel;
  final String? acknowledgement, subject, section, icon, notice;
  final bool summaryOnly, quote;
  final List<({String title, String subtitle})> items;
  static const limits = {
    'title': 120,
    'message': 6000,
    'confirmLabel': 48,
    'acknowledgement': 1000,
    'subject': 120,
    'section': 120,
    'notice': 2000,
    'icon': 64,
  };

  factory PlanConfirmation.parse(Object? value) {
    if (value is! Map ||
        value.keys.any(
          (key) =>
              key != 'summaryOnly' &&
              key != 'presentation' &&
              key != 'items' &&
              !limits.containsKey(key),
        )) {
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

    if (value.containsKey('summaryOnly') && value['summaryOnly'] is! bool) {
      throw const FormatException('Invalid plan confirmation summaryOnly');
    }
    final items = <({String title, String subtitle})>[];
    if (value.containsKey('items')) {
      final rows = value['items'];
      if (value['summaryOnly'] != true || rows is! List || rows.length > 40) {
        throw const FormatException('Invalid plan confirmation items');
      }
      for (final row in rows) {
        if (row
            case {
              'title': final String title,
              'subtitle': final String subtitle,
            }
            when row.length == 2 &&
                title.trim().isNotEmpty &&
                title.length <= 300 &&
                subtitle.length <= 600) {
          items.add((title: title, subtitle: subtitle));
        } else {
          throw const FormatException('Invalid plan confirmation item');
        }
      }
    }
    if (value.containsKey('presentation') &&
        (value['presentation'] != 'quote' || value['subject'] == null)) {
      throw const FormatException('Invalid plan confirmation presentation');
    }
    return PlanConfirmation._(
      quote: value['presentation'] == 'quote',
      items: List.unmodifiable(items),
      subject: value.containsKey('subject') ? read('subject') : null,
      notice: value.containsKey('notice') ? read('notice') : null,
      section: value.containsKey('section') ? read('section') : null,
      icon: value.containsKey('icon') ? read('icon') : null,
      summaryOnly: value['summaryOnly'] == true,
      title: read('title'),
      message: read('message'),
      confirmLabel: read('confirmLabel'),
      acknowledgement: value.containsKey('acknowledgement')
          ? read('acknowledgement')
          : null,
    );
  }

  Map<String, Object?> toJson() => Map.unmodifiable({
    if (summaryOnly) 'summaryOnly': true,
    if (subject != null) 'subject': subject,
    if (quote) 'presentation': 'quote',
    if (section != null) 'section': section,
    if (notice != null) 'notice': notice,
    if (icon != null) 'icon': icon,
    if (items.isNotEmpty)
      'items': [
        for (final row in items) {'title': row.title, 'subtitle': row.subtitle},
      ],
    'title': title,
    'message': message,
    'confirmLabel': confirmLabel,
    if (acknowledgement != null) 'acknowledgement': acknowledgement,
  });
}
