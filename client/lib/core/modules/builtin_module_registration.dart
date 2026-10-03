import 'app_module.dart';

enum BuiltinModuleKind { native, declarative }

/// The shipped catalog remains available even while a module is disabled.
class BuiltinModuleRegistration {
  const BuiltinModuleRegistration({
    required this.module,
    required this.title,
    required this.description,
    this.kind = BuiltinModuleKind.native,
    this.canDisable = true,
  });

  final AppModule module;
  final String title;
  final String description;
  final BuiltinModuleKind kind;
  final bool canDisable;

  String get id => module.manifest.id;
}
