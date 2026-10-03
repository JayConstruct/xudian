import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'module_install_provenance.dart';
import 'module_package.dart';

class ModulePackageVerifier {
  ModulePackageVerifier({
    required this.trustedPublishers,
  });

  final TrustedPublisherRegistry trustedPublishers;

  Future<VerifiedModulePackage> verify(
    Map<String, Object?> package, {
    bool allowUnsignedLocal = false,
  }) async {
    const allowedTop = {
      'packageFormat',
      'module',
      'release',
      'integrity',
      'signature',
    };
    for (final key in package.keys) {
      if (!allowedTop.contains(key)) {
        throw FormatException('Unknown package key: $key');
      }
    }
    if (package['packageFormat'] != 1) {
      throw const FormatException('Unsupported packageFormat');
    }

    final module = _object(package['module'], 'module');
    final release = _object(package['release'], 'release');
    final integrity = _object(package['integrity'], 'integrity');
    final signature = package['signature'] == null
        ? null
        : _object(package['signature'], 'signature');

    _rejectUnknown(
      release,
      const {
        'channel',
        'publisherId',
        'publishedAt',
        'summary',
        'review',
      },
      'release',
    );
    _rejectUnknown(
      integrity,
      const {'algorithm', 'digest'},
      'integrity',
    );
    if (signature != null) {
      _rejectUnknown(
        signature,
        const {'algorithm', 'keyId', 'value'},
        'signature',
      );
    }

    final channel = _string(release['channel'], 'release.channel');
    if (channel != 'local' && channel != 'market') {
      throw FormatException('Unsupported release channel: $channel');
    }

    final publisherId = release['publisherId'] as String?;
    final summary = release['summary'] as String?;
    final review = release['review'] == null
        ? const <String, Object?>{}
        : _object(release['review'], 'release.review');
    _rejectUnknown(
      review,
      const {
        'status',
        'reviewId',
        'reviewedAt',
        'policyVersion',
      },
      'release.review',
    );
    final reviewStatus = review['status'] as String? ?? 'unreviewed';
    final reviewId = review['reviewId'] as String?;
    final reviewedAt = review['reviewedAt'] as String?;
    final policyVersion = review['policyVersion'] as String?;
    final publishedAt = release['publishedAt'] as String?;

    final algorithm =
        _string(integrity['algorithm'], 'integrity.algorithm');
    if (algorithm != 'sha256') {
      throw FormatException('Unsupported digest algorithm: $algorithm');
    }
    final expectedDigest =
        _string(integrity['digest'], 'integrity.digest').toLowerCase();
    final actualDigest = await _sha256Hex(_canonicalBytes(module));
    if (expectedDigest != actualDigest) {
      throw const FormatException('Module package digest mismatch');
    }

    if (channel == 'local') {
      if (signature != null) {
        throw const FormatException(
          'Local packages must not claim market signatures',
        );
      }
      if (!allowUnsignedLocal) {
        throw StateError(
          'Unsigned local package import is not allowed',
        );
      }
      return VerifiedModulePackage(
        moduleSource: module,
        provenance: ModuleInstallProvenance(
          origin: 'local-package',
          packageDigest: actualDigest,
        ),
        channel: channel,
        publisherId: publisherId,
        summary: summary,
        reviewStatus: reviewStatus,
        trusted: false,
      );
    }

    if (publisherId == null || publisherId.trim().isEmpty) {
      throw const FormatException(
        'Market package requires publisherId',
      );
    }
    if (publishedAt == null ||
        DateTime.tryParse(publishedAt) == null) {
      throw const FormatException(
        'Market package requires valid publishedAt',
      );
    }
    if (reviewedAt == null ||
        DateTime.tryParse(reviewedAt) == null) {
      throw const FormatException(
        'Approved market package requires reviewedAt',
      );
    }
    if (policyVersion == null || policyVersion.trim().isEmpty) {
      throw const FormatException(
        'Approved market package requires policyVersion',
      );
    }
    if (reviewStatus != 'approved' ||
        reviewId == null ||
        reviewId.trim().isEmpty) {
      throw StateError(
        'Market package is not approved',
      );
    }
    if (signature == null) {
      throw const FormatException(
        'Market package requires signature',
      );
    }

    final sigAlgorithm =
        _string(signature['algorithm'], 'signature.algorithm');
    if (sigAlgorithm != 'ed25519') {
      throw FormatException(
        'Unsupported signature algorithm: $sigAlgorithm',
      );
    }
    final keyId = _string(signature['keyId'], 'signature.keyId');
    final value = _string(signature['value'], 'signature.value');
    final trusted = trustedPublishers.find(publisherId, keyId);
    if (trusted == null) {
      throw StateError(
        'Untrusted publisher key: $publisherId/$keyId',
      );
    }

    final signedPayload = <String, Object?>{
      'packageFormat': 1,
      'module': module,
      'release': release,
      'integrity': integrity,
    };
    final signatureBytes = base64Decode(value);
    final publicKey = SimplePublicKey(
      trusted.publicKey,
      type: KeyPairType.ed25519,
    );
    final valid = await Ed25519().verify(
      _canonicalBytes(signedPayload),
      signature: Signature(
        signatureBytes,
        publicKey: publicKey,
      ),
    );
    if (!valid) {
      throw StateError('Invalid package signature');
    }

    return VerifiedModulePackage(
      moduleSource: module,
      provenance: ModuleInstallProvenance(
        origin: 'market',
        publisherId: publisherId,
        packageDigest: actualDigest,
        reviewId: reviewId,
        signatureKeyId: keyId,
      ),
      channel: channel,
      publisherId: publisherId,
      summary: summary,
      reviewStatus: reviewStatus,
      trusted: true,
    );
  }

  void _rejectUnknown(
    Map<String, Object?> value,
    Set<String> allowed,
    String name,
  ) {
    for (final key in value.keys) {
      if (!allowed.contains(key)) {
        throw FormatException('Unknown $name key: $key');
      }
    }
  }

  Map<String, Object?> _object(Object? value, String name) {
    if (value is! Map) {
      throw FormatException('$name must be an object');
    }
    return value.map((key, item) => MapEntry('$key', item));
  }

  String _string(Object? value, String name) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$name must be a non-empty string');
    }
    return value.trim();
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

  Future<String> _sha256Hex(List<int> bytes) async {
    final hash = await Sha256().hash(bytes);
    return hash.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
