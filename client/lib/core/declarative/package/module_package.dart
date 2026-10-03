import 'dart:convert';

import 'module_install_provenance.dart';

class VerifiedModulePackage {
  const VerifiedModulePackage({
    required this.moduleSource,
    required this.provenance,
    required this.channel,
    required this.publisherId,
    required this.summary,
    required this.reviewStatus,
    required this.trusted,
  });

  final Map<String, Object?> moduleSource;
  final ModuleInstallProvenance provenance;
  final String channel;
  final String? publisherId;
  final String? summary;
  final String reviewStatus;
  final bool trusted;
}

class TrustedPublisherKey {
  const TrustedPublisherKey({
    required this.publisherId,
    required this.keyId,
    required this.publicKey,
  });

  final String publisherId;
  final String keyId;
  final List<int> publicKey;
}

class TrustedPublisherRegistry {
  TrustedPublisherRegistry([
    Iterable<TrustedPublisherKey> keys = const [],
  ]) : _keys = {
          for (final key in keys)
            '${key.publisherId}:${key.keyId}': key,
        };

  factory TrustedPublisherRegistry.fromJson(
    Map<String, Object?> source,
  ) {
    if (source['formatVersion'] != 1) {
      throw const FormatException(
        'Unsupported trusted publisher formatVersion',
      );
    }
    final keys = source['keys'];
    if (keys is! List) {
      throw const FormatException(
        'trusted publisher keys must be an array',
      );
    }

    final parsed = <TrustedPublisherKey>[];
    for (final raw in keys) {
      if (raw is! Map) {
        throw const FormatException(
          'trusted publisher key must be an object',
        );
      }
      final publisherId = raw['publisherId'];
      final keyId = raw['keyId'];
      final algorithm = raw['algorithm'];
      final publicKey = raw['publicKey'];
      if (publisherId is! String ||
          publisherId.isEmpty ||
          keyId is! String ||
          keyId.isEmpty ||
          algorithm != 'ed25519' ||
          publicKey is! String ||
          publicKey.isEmpty) {
        throw const FormatException(
          'invalid trusted publisher key entry',
        );
      }
      final bytes = base64Decode(publicKey);
      if (bytes.length != 32) {
        throw const FormatException(
          'ed25519 public key must be 32 bytes',
        );
      }
      parsed.add(
        TrustedPublisherKey(
          publisherId: publisherId,
          keyId: keyId,
          publicKey: bytes,
        ),
      );
    }
    return TrustedPublisherRegistry(parsed);
  }

  final Map<String, TrustedPublisherKey> _keys;

  TrustedPublisherKey? find(String publisherId, String keyId) =>
      _keys['$publisherId:$keyId'];
}
