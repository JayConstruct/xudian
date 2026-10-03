import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/declarative/package/module_package.dart';
import 'package:task_app/core/declarative/package/module_package_verifier.dart';

void main() {
  const module = <String, Object?>{
    'formatVersion': 1,
    'manifest': {
      'id': 'app.package.sample',
      'version': '1.0.0',
      'coreApi': '1',
    },
  };

  test('unsigned local package is allowed only explicitly', () async {
    final digest = await _digest(module);
    final package = <String, Object?>{
      'packageFormat': 1,
      'module': module,
      'release': {
        'channel': 'local',
        'summary': '开发包',
      },
      'integrity': {
        'algorithm': 'sha256',
        'digest': digest,
      },
    };
    final verifier = ModulePackageVerifier(
      trustedPublishers: TrustedPublisherRegistry(),
    );

    await expectLater(
      verifier.verify(package),
      throwsStateError,
    );

    final verified = await verifier.verify(
      package,
      allowUnsignedLocal: true,
    );
    expect(verified.trusted, isFalse);
    expect(verified.provenance.origin, 'local-package');
    expect(verified.provenance.packageDigest, digest);
  });

  test('approved market package verifies trusted ed25519 signature', () async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final digest = await _digest(module);
    final release = <String, Object?>{
      'channel': 'market',
      'publisherId': 'xudian.official',
      'publishedAt': '2026-09-29T12:00:00Z',
      'summary': '审核通过模块',
      'review': {
        'status': 'approved',
        'reviewId': 'review-001',
        'reviewedAt': '2026-09-29T11:00:00Z',
        'policyVersion': '2026-09',
      },
    };
    final integrity = <String, Object?>{
      'algorithm': 'sha256',
      'digest': digest,
    };
    final signedPayload = <String, Object?>{
      'packageFormat': 1,
      'module': module,
      'release': release,
      'integrity': integrity,
    };
    final signature = await algorithm.sign(
      _canonicalBytes(signedPayload),
      keyPair: keyPair,
    );

    final package = <String, Object?>{
      ...signedPayload,
      'signature': {
        'algorithm': 'ed25519',
        'keyId': 'release-2026',
        'value': base64Encode(signature.bytes),
      },
    };
    final verifier = ModulePackageVerifier(
      trustedPublishers: TrustedPublisherRegistry([
        TrustedPublisherKey(
          publisherId: 'xudian.official',
          keyId: 'release-2026',
          publicKey: publicKey.bytes,
        ),
      ]),
    );

    final verified = await verifier.verify(package);
    expect(verified.trusted, isTrue);
    expect(verified.provenance.origin, 'market');
    expect(verified.provenance.publisherId, 'xudian.official');
    expect(verified.provenance.reviewId, 'review-001');
    expect(verified.provenance.signatureKeyId, 'release-2026');

    final tamperedSignature = Map<String, Object?>.from(package);
    final signatureMap =
        Map<String, Object?>.from(package['signature'] as Map);
    final signatureBytes =
        base64Decode(signatureMap['value'] as String);
    signatureBytes[0] ^= 0x01;
    signatureMap['value'] = base64Encode(signatureBytes);
    tamperedSignature['signature'] = signatureMap;

    await expectLater(
      verifier.verify(tamperedSignature),
      throwsStateError,
    );
  });

  test('market package rejects untrusted key and tampering', () async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final digest = await _digest(module);
    final release = <String, Object?>{
      'channel': 'market',
      'publisherId': 'unknown.publisher',
      'publishedAt': '2026-09-29T12:00:00Z',
      'review': {
        'status': 'approved',
        'reviewId': 'review-002',
        'reviewedAt': '2026-09-29T11:00:00Z',
        'policyVersion': '2026-09',
      },
    };
    final integrity = <String, Object?>{
      'algorithm': 'sha256',
      'digest': digest,
    };
    final payload = <String, Object?>{
      'packageFormat': 1,
      'module': module,
      'release': release,
      'integrity': integrity,
    };
    final signature = await algorithm.sign(
      _canonicalBytes(payload),
      keyPair: keyPair,
    );
    final package = <String, Object?>{
      ...payload,
      'signature': {
        'algorithm': 'ed25519',
        'keyId': 'unknown-key',
        'value': base64Encode(signature.bytes),
      },
    };
    final verifier = ModulePackageVerifier(
      trustedPublishers: TrustedPublisherRegistry(),
    );

    await expectLater(
      verifier.verify(package),
      throwsStateError,
    );

    final tampered = Map<String, Object?>.from(package);
    tampered['module'] = {
      ...module,
      'fields': [
        {'id': 'extra', 'label': '额外', 'type': 'text'},
      ],
    };
    await expectLater(
      verifier.verify(
        tampered,
        allowUnsignedLocal: true,
      ),
      throwsFormatException,
    );
  });
}

Future<String> _digest(Object? value) async {
  final hash = await Sha256().hash(_canonicalBytes(value));
  return hash.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

List<int> _canonicalBytes(Object? value) =>
    utf8.encode(jsonEncode(_normalize(value)));

Object? _normalize(Object? value) {
  if (value is Map) {
    final entries = value.entries
        .map((entry) => MapEntry('${entry.key}', entry.value))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return {
      for (final entry in entries)
        entry.key: _normalize(entry.value),
    };
  }
  if (value is List) {
    return value.map(_normalize).toList(growable: false);
  }
  return value;
}
