import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class AiSecretStore {
  Future<String?> readApiKey();
  Future<void> writeApiKey(String value);
  Future<void> deleteApiKey();
}

class SecureAiSecretStore implements AiSecretStore {
  SecureAiSecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _apiKey = 'xudian.ai.apiKey';

  @override
  Future<String?> readApiKey() => _storage.read(key: _apiKey);

  @override
  Future<void> writeApiKey(String value) {
    if (value.trim().isEmpty) return deleteApiKey();
    return _storage.write(key: _apiKey, value: value.trim());
  }

  @override
  Future<void> deleteApiKey() => _storage.delete(key: _apiKey);
}
