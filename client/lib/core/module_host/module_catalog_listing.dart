part of 'module_catalog_page.dart';

/// Search and display order depend only on the current directory snapshot.
class _CatalogListing {
  _CatalogListing(this.catalog)
    : categories =
          catalog.modules.values.map((item) => item.category).toSet().toList()
            ..sort(),
      _entries =
          [
            for (final (position, item) in catalog.modules.values.indexed)
              (
                item: item,
                position: position,
                searchFields: [
                  item.name,
                  item.description,
                  item.author,
                  item.id,
                  item.repository,
                ].map((value) => value.toLowerCase()).toList(),
              ),
          ]..sort((left, right) {
            final a = left.item, b = right.item;
            if (a.featured != b.featured) return a.featured ? -1 : 1;
            final byName = a.name.compareTo(b.name);
            return byName == 0
                ? left.position.compareTo(right.position)
                : byName;
          });

  final ModuleCatalog catalog;
  final List<String> categories;
  final List<({CatalogModule item, int position, List<String> searchFields})>
  _entries;

  Iterable<CatalogModule> matching(String search, String category) {
    final query = search.trim().toLowerCase();
    return _entries
        .where(
          (entry) =>
              (category == '全部分类' || entry.item.category == category) &&
              (query.isEmpty ||
                  entry.searchFields.any((field) => field.contains(query))),
        )
        .map((entry) => entry.item);
  }
}

CatalogVersion? _latestStableVersion(ModuleVersionIndex index) => index.versions
    .where(
      (version) =>
          !Version.parse(version.version).isPreRelease &&
          VersionConstraint.parse(version.manifest['hostApi'] as String)
              .allows(hostApiVersion),
    )
    .firstOrNull;
