typedef _Navigation = ({bool present, String? todayDate});

/// Classifies branches of an immutable page result before widgets are built.
class ScriptDateNavigation {
  ScriptDateNavigation(Object? tree) {
    _root = _inspect(tree);
  }

  static const _none = (present: false, todayDate: null);
  final _branches = Expando<_Navigation>();
  late final _Navigation _root;

  bool get present => _root.present;
  String? get todayDate => _root.todayDate;

  // Native fallbacks and UI-pack examples can synthesize nodes outside the
  // original tree. Classify those on demand without retaining past builds.
  bool contains(Map<String, Object?> node) => _inspect(node).present;

  _Navigation _inspect(Object? node) {
    if (node is! Map && node is! List) return _none;
    final cached = _branches[node!];
    if (cached != null) return cached;
    var present = false;
    String? todayDate;
    final Iterable<Object?> children;
    if (node is Map) {
      present =
          node['type'] == 'dayOverview' || node['ref'] == 'ui.dayOverview@1';
      if (present) {
        final props = node['type'] == 'dayOverview' ? node : node['props'];
        final date = props is Map ? props['todayDate'] : null;
        if (date is String) todayDate = date;
      }
      children = node.values;
    } else {
      children = node as List;
    }
    for (final child in children) {
      final branch = _inspect(child);
      if (branch.present) present = true;
      todayDate ??= branch.todayDate;
    }
    final result = present ? (present: true, todayDate: todayDate) : _none;
    _branches[node] = result;
    return result;
  }
}
