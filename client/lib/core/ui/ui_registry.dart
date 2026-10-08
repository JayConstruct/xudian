import 'app_destination.dart';
import 'ui_registration.dart';
import 'ui_slot.dart';
import 'ui_composition.dart';

class UiRegistry {
  final Map<UiSlot, List<UiRegistration>> _items = {};
  final Map<UiRegistration, String> _owners = {};
  List<UiEntryRegistration>? _entriesCache;
  List<UiPageRegistration>? _pagesCache;
  Map<String, UiPageRegistration>? _pageMap;

  void clear() {
    _items.clear();
    _owners.clear();
    _entriesCache = null;
    _pagesCache = null;
    _pageMap = null;
  }

  void register(
    UiRegistration registration, {
    String moduleId = 'app.unknown',
  }) {
    final list = _items.putIfAbsent(registration.slot, () => []);
    if (registration is WidgetRegistration &&
        list.whereType<WidgetRegistration>().any(
          (item) => item.id == registration.id,
        )) {
      throw StateError('Duplicate UI widget: ${registration.id}');
    }
    if (registration is NavigationRegistration) {
      final duplicate = list.whereType<NavigationRegistration>().any(
        (item) => item.destination.id == registration.destination.id,
      );
      if (duplicate) {
        throw StateError(
          'Duplicate navigation destination: '
          '${registration.destination.id}',
        );
      }
      if (entries.any((entry) => entry.id == registration.destination.id) ||
          pages.any(
            (page) =>
                page.id ==
                _destinationPageId(registration.destination.id, moduleId),
          )) {
        throw StateError(
          'Duplicate UI identity: ${registration.destination.id}',
        );
      }
    }
    if (registration is UiEntryRegistration &&
        entries.any((entry) => entry.id == registration.id)) {
      throw StateError('Duplicate UI entry: ${registration.id}');
    }
    if (registration is UiPageRegistration &&
        pages.any((page) => page.id == registration.id)) {
      throw StateError('Duplicate UI page: ${registration.id}');
    }
    _owners[registration] = moduleId;
    list.add(registration);
    _entriesCache = null;
    _pagesCache = null;
    _pageMap = null;
  }

  String ownerOf(UiRegistration registration) =>
      _owners[registration] ?? 'app.unknown';

  String _destinationPageId(String id, String moduleId) =>
      id.contains('.') ? id : '$moduleId.$id';

  List<UiEntryRegistration> get entries => _entriesCache ??= List.unmodifiable([
    for (final registration
        in _items[UiSlot.navigationPrimary] ?? const <UiRegistration>[])
      if (registration is UiEntryRegistration)
        registration
      else if (registration is NavigationRegistration)
        UiEntryRegistration(
          id: registration.destination.id,
          moduleId: ownerOf(registration),
          pageId: _destinationPageId(
            registration.destination.id,
            ownerOf(registration),
          ),
          label: registration.destination.label,
          icon: registration.destination.icon,
          selectedIcon: registration.destination.selectedIcon,
        ),
  ]);

  List<UiPageRegistration> get pages => _pagesCache ??= List.unmodifiable([
    for (final registration
        in _items[UiSlot.workspacePage] ?? const <UiRegistration>[])
      if (registration is UiPageRegistration) registration,
    for (final registration
        in _items[UiSlot.navigationPrimary] ?? const <UiRegistration>[])
      if (registration is NavigationRegistration)
        UiPageRegistration(
          id: _destinationPageId(
            registration.destination.id,
            ownerOf(registration),
          ),
          moduleId: ownerOf(registration),
          title: registration.destination.label,
          quickAdd: registration.destination.quickAdd,
          quickAddDefaults: registration.destination.quickAddDefaults,
          builder: (context, _) => registration.destination.builder(context),
        ),
  ]);

  UiPageRegistration? page(String id) =>
      (_pageMap ??= {for (final page in pages) page.id: page})[id];

  List<AppDestination> get primaryDestinations => List.unmodifiable(
    (_items[UiSlot.navigationPrimary] ?? const [])
        .whereType<NavigationRegistration>()
        .map((item) => item.destination),
  );

  List<UiRegistration> forSlot(UiSlot slot) =>
      List.unmodifiable(_items[slot] ?? const []);
}
