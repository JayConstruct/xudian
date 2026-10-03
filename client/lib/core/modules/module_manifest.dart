class ModuleManifest {
  const ModuleManifest({
    required this.id,
    required this.version,
    required this.coreApi,
    this.dependencies = const [],
    this.requiresCapabilities = const [],
    this.permissions = const [],
  });

  final String id;
  final String version;
  final String coreApi;
  final List<String> dependencies;
  final List<String> requiresCapabilities;
  final List<String> permissions;

  void validate() {
    if (!RegExp(r'^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+$').hasMatch(id)) {
      throw StateError('Invalid module id: $id');
    }
    if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
      throw StateError('Invalid module version: $version');
    }
    if (coreApi.isEmpty) throw StateError('coreApi is required');
  }
}
