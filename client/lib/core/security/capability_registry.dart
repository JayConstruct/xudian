class CapabilityRegistry {
  CapabilityRegistry(Iterable<String> capabilities)
      : _capabilities = Set.unmodifiable(capabilities);

  final Set<String> _capabilities;

  bool has(String capability) => _capabilities.contains(capability);

  void requireAll(Iterable<String> capabilities) {
    for (final capability in capabilities) {
      if (!has(capability)) {
        throw StateError('Missing capability: $capability');
      }
    }
  }
}
