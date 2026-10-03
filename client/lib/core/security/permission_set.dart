class PermissionSet {
  PermissionSet(Iterable<String> permissions)
      : _permissions = Set.unmodifiable(permissions);

  final Set<String> _permissions;

  bool allows(String permission) => _permissions.contains(permission);

  void require(String permission) {
    if (!allows(permission)) {
      throw StateError('Permission denied: $permission');
    }
  }
}
