import 'package:flutter/widgets.dart';

/// Connects readiness of inline sections to their date page's visual commit.
/// Dates and gestures remain presentation state owned by the host.
class DateNavigationIntentScope extends InheritedWidget {
  const DateNavigationIntentScope({
    super.key,
    required this.revision,
    required this.reportReadiness,
    required this.forgetReadiness,
    required super.child,
  });

  final int revision;
  final void Function(Object owner, int revision, bool ready) reportReadiness;
  final void Function(Object owner) forgetReadiness;

  static DateNavigationIntentScope? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DateNavigationIntentScope>();

  @override
  bool updateShouldNotify(DateNavigationIntentScope oldWidget) =>
      revision != oldWidget.revision;
}
