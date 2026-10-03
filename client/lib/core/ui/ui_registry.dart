import 'app_destination.dart';
import 'ui_registration.dart';
import 'ui_slot.dart';

class UiRegistry {
  final Map<UiSlot, List<UiRegistration>> _items = {};

  void clear() => _items.clear();

  void register(UiRegistration registration) {
    final list = _items.putIfAbsent(registration.slot, () => []);
    if (registration is NavigationRegistration) {
      final duplicate = list
          .whereType<NavigationRegistration>()
          .any((item) => item.destination.id == registration.destination.id);
      if (duplicate) {
        throw StateError('Duplicate navigation destination: '
            '${registration.destination.id}');
      }
    }
    list.add(registration);
  }

  List<AppDestination> get primaryDestinations => List.unmodifiable(
        (_items[UiSlot.navigationPrimary] ?? const [])
            .whereType<NavigationRegistration>()
            .map((item) => item.destination),
      );

  List<UiRegistration> forSlot(UiSlot slot) =>
      List.unmodifiable(_items[slot] ?? const []);
}
