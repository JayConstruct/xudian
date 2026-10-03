import '../ui/ui_registration.dart';
import 'module_manifest.dart';

abstract interface class AppModule {
  ModuleManifest get manifest;
  List<UiRegistration> get ui => const [];
}
