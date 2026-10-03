class ModuleContext {
  ModuleContext({
    required this.moduleId,
    required Iterable<String> permissions,
  }) : permissions = Set.unmodifiable(permissions);

  const ModuleContext.system()
      : moduleId = 'app.core.system',
        permissions = const {'*'};

  final String moduleId;
  final Set<String> permissions;

  bool allows(String permission) =>
      permissions.contains('*') || permissions.contains(permission);

  void require(String permission) {
    if (!allows(permission)) {
      throw StateError(
        'Module $moduleId lacks required permission: $permission',
      );
    }
  }
}
