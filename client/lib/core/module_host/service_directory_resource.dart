import '../../data/app_database.dart';
import 'native_resource.dart';

/// Service availability (including absent optional providers) is a plan read.
class ServiceDirectoryResource implements NativeResource {
  ServiceDirectoryResource(this.baseline);
  final String Function() baseline;
  static const resourceId = 'host.serviceDirectory';

  @override
  String get id => resourceId;

  @override
  Future<void> validateReads(
    AppDatabase db,
    Map<String, Object?> baselines,
  ) async {
    if (baselines['registry'] != baseline()) {
      throw StateError('Service directory changed; prepare again');
    }
  }

  @override
  bool ownsWrite(Map<String, Object?> write) => false;

  @override
  Future<void> applyWrite(AppDatabase db, Map<String, Object?> write) async {
    throw StateError('Service directory is read only');
  }
}
