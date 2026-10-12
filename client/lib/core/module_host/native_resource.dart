import '../../data/app_database.dart';

/// Trusted native resources participate in the collection commit transaction.
/// Scripts cannot register adapters or supply the callbacks themselves.
abstract interface class NativeResource {
  String get id;

  Future<void> validateReads(AppDatabase db, Map<String, Object?> baselines);

  bool ownsWrite(Map<String, Object?> write);

  Future<void> applyWrite(AppDatabase db, Map<String, Object?> write);
}
