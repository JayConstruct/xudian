import '../modules/module_manifest.dart';

class DeclarativeModule {
  const DeclarativeModule({
    required this.formatVersion,
    required this.manifest,
    this.pages = const [],
    this.views = const [],
    this.fields = const [],
    this.templates = const [],
    this.rules = const [],
    this.layouts = const [],
  });

  final int formatVersion;
  final ModuleManifest manifest;
  final List<Map<String, Object?>> pages;
  final List<Map<String, Object?>> views;
  final List<Map<String, Object?>> fields;
  final List<Map<String, Object?>> templates;
  final List<Map<String, Object?>> rules;
  final List<Map<String, Object?>> layouts;
}
