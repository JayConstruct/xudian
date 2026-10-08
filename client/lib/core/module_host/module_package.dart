import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:pub_semver/pub_semver.dart';

import '../contracts/json_values.dart';
import '../declarative/package/module_package.dart';
import '../ui/ui_pack.dart';

Map<String, Object?> object(Object? value, [String label = 'value']) {
  if (value is! Map) throw FormatException('$label must be an object');
  return value.cast<String, Object?>();
}

String string(Object? value, String label) {
  if (value is! String || value.isEmpty) {
    throw FormatException('Invalid $label');
  }
  return value;
}

Future<String> digest(List<int> bytes) async =>
    (await Sha256().hash(bytes)).bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
bool safePath(String path) =>
    RegExp(r'^[a-zA-Z0-9_@.-]+(/[a-zA-Z0-9_@.-]+)*$').hasMatch(path) &&
    !path.split('/').any((part) => part == '.' || part == '..');

class ScriptPackage {
  ScriptPackage._(
    this.bytes,
    this.packageDigest,
    this.definition,
    this.files,
    this.release,
    this.trusted,
    this.origin, [
    UiPackDefinition? compiledUiPack,
  ]) {
    final manifest = object(definition['manifest']);
    id = string(manifest['id'], 'module id');
    version = string(manifest['version'], 'version');
    if (!RegExp(r'^[a-z][a-z0-9]*(\.[a-z][a-z0-9_-]*)+$').hasMatch(id) ||
        !RegExp(
          r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$',
        ).hasMatch(version)) {
      throw const FormatException('Invalid module id or semantic version');
    }
    Version.parse(version);
    for (final key in ['description', 'author']) {
      if (manifest[key] != null && manifest[key] is! String) {
        throw FormatException('$key must be a string');
      }
    }
    if (id == 'app.ui.default') {
      throw const FormatException('Default UI identity is reserved');
    }
    if (manifest['kind'] != null &&
        !['script', 'uiPack'].contains(manifest['kind'])) {
      throw const FormatException('Unsupported module kind');
    }
    if (definition['formatVersion'] != 3 ||
        !VersionConstraint.parse(string(manifest['hostApi'], 'host API range'))
            .allows(Version(1, 8, 0))) {
      throw const FormatException(
        'Unsupported module format or host interface',
      );
    }
    if (manifest['dataVersion'] is! int ||
        (manifest['dataVersion'] as int) < 1) {
      throw const FormatException('Invalid data version');
    }
    final dependencyIds = <String>{};
    for (final raw in manifest['dependencies'] as List? ?? []) {
      final id = raw is String
          ? raw
          : string(object(raw)['moduleId'], 'dependency');
      if (!dependencyIds.add(id) || id == this.id) {
        throw const FormatException('Duplicate or cyclic module dependency');
      }
      if (raw is! String) {
        VersionConstraint.parse(
          string(object(raw)['version'], 'dependency version'),
        );
      }
    }
    if (isUiPack) {
      if (dataVersion != 1 ||
          definition.containsKey('entryPoint') ||
          files.keys.any((name) => name.toLowerCase().endsWith('.js')) ||
          permissions.isNotEmpty) {
        throw const FormatException(
          'UI packs cannot contain executable capabilities',
        );
      }
      for (final key in ['collections', 'services', 'pages']) {
        if (definition[key] is! List || (definition[key] as List).isNotEmpty) {
          throw FormatException('UI pack $key must be empty');
        }
      }
      for (final key in ['contributions', 'interruptHandlers', 'automations']) {
        if (definition.containsKey(key) &&
            (definition[key] is! List ||
                (definition[key] as List).isNotEmpty)) {
          throw FormatException('UI pack $key must be empty');
        }
      }
      if (definition.containsKey('migrations') &&
          object(definition['migrations'], 'migrations').isNotEmpty) {
        throw const FormatException('UI packs cannot define migrations');
      }
      for (final key in ['serviceDependencies', 'httpOrigins']) {
        if (manifest.containsKey(key) &&
            (manifest[key] is! List || (manifest[key] as List).isNotEmpty)) {
          throw FormatException('UI pack $key must be empty');
        }
      }
      _uiPack =
          compiledUiPack ??
          UiPackDefinition.parse(
            moduleId: id,
            version: version,
            digest: packageDigest,
            source: object(definition['uiPack'], 'uiPack'),
          );
    } else {
      if (definition.containsKey('uiPack')) {
        throw const FormatException('Only UI packs can provide UI definitions');
      }
      final entry = string(definition['entryPoint'], 'entry point');
      if (!files.containsKey(entry) || !entry.endsWith('.js')) {
        throw const FormatException(
          'Entry point must reference packaged JavaScript',
        );
      }
    }
    final collectionIds = <String>{};
    for (final raw in definition['collections'] as List? ?? []) {
      final c = object(raw);
      if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$')
              .hasMatch(string(c['id'], 'collection')) ||
          !collectionIds.add(c['id'] as String)) {
        throw const FormatException('Invalid collection');
      }
      object(c['schema'], 'collection schema');
    }
    final services = <String>{};
    for (final raw in definition['services'] as List? ?? []) {
      final s = object(raw);
      final key = '${s['id']}@${s['major']}';
      if (!services.add(key) ||
          s['major'] is! int ||
          (s['major'] as int) < 1 ||
          !['query', 'command'].contains(s['kind'])) {
        throw const FormatException('Invalid service');
      }
      string(s['handler'], 'service handler');
      object(s['input']);
      object(s['output']);
    }
    for (final permission in permissions) {
      if (permission.trim().isEmpty) {
        throw const FormatException('Invalid permission');
      }
    }
  }
  final Uint8List bytes;
  final String packageDigest;
  final Map<String, Object?> definition;
  final Map<String, Uint8List> files;
  final Map<String, Object?> release;
  final bool trusted;
  final String origin;
  late final String id, version;
  UiPackDefinition? _uiPack;
  bool get isUiPack => manifest['kind'] == 'uiPack';
  UiPackDefinition? get uiPack => _uiPack;
  Map<String, Object?> get manifest => object(definition['manifest']);
  List<String> get permissions =>
      (manifest['permissions'] as List? ?? []).cast<String>();
  List<String> get dependencies => {
    for (final raw in manifest['dependencies'] as List? ?? [])
      raw is String ? raw : object(raw)['moduleId'] as String,
    for (final ref in requiredServices)
      if (ref['moduleId'] != id && ref['moduleId'] != 'app.host')
        ref['moduleId'] as String,
  }.toList();
  List<Map<String, Object?>> get requiredServices => [
    for (final raw in manifest['serviceDependencies'] as List? ?? [])
      object(raw),
    for (final permission in permissions)
      if (RegExp(r'^services\.(query|command):([^/]+)/(.+)@([1-9]\d*)$')
          .hasMatch(permission))
        () {
          final match = RegExp(
            r'^services\.(query|command):([^/]+)/(.+)@([1-9]\d*)$',
          ).firstMatch(permission)!;
          return <String, Object?>{
            'moduleId': match[2],
            'serviceId': match[3],
            'majorVersion': int.parse(match[4]!),
            'kind': match[1],
          };
        }(),
  ];
  bool acceptsDependency(String id, String version) {
    for (final raw in manifest['dependencies'] as List? ?? []) {
      if (raw is! String && object(raw)['moduleId'] == id) {
        return VersionConstraint.parse(object(raw)['version'] as String)
            .allows(Version.parse(version));
      }
    }
    return true;
  }

  int get dataVersion => manifest['dataVersion'] as int;
  String get title => manifest['name'] as String? ?? id;
  String get description {
    final value = manifest['description'] as String?;
    return value == null || value.trim().isEmpty ? '作者未提供说明' : value;
  }

  String get author => manifest['author'] as String? ?? '作者未提供';
  Map<String, String> get scripts => {
    for (final entry in files.entries)
      if (entry.key.endsWith('.js')) entry.key: utf8.decode(entry.value),
  };

  ScriptPackage withStoredOrigin(String origin) => ScriptPackage._(
    bytes,
    packageDigest,
    definition,
    files,
    release,
    true,
    origin,
    _uiPack,
  );

  static Future<ScriptPackage> verify(
    List<int> input, {
    bool allowUnsignedLocal = false,
    String? preinstalledDigest,
    TrustedPublisherRegistry? publishers,
  }) async {
    if (input.length > 16 * 1024 * 1024) {
      throw const FormatException('Package too large');
    }
    final bytes = Uint8List.fromList(input).asUnmodifiableView();
    final directory = ZipDirectory.read(InputStream(bytes));
    if (directory.fileHeaders.length > 256 ||
        directory.numberOfThisDisk != 0 ||
        directory.diskWithTheStartOfTheCentralDirectory != 0) {
      throw const FormatException('Unsupported ZIP directory');
    }
    final files = <String, Uint8List>{};
    var total = 0;
    final offsets = <int>{};
    for (final header in directory.fileHeaders) {
      final file = header.file!, name = header.filename;
      final size = header.uncompressedSize ?? -1,
          mode = (header.externalFileAttributes ?? 0) >> 16;
      if (!safePath(name) ||
          name.endsWith('/') ||
          files.containsKey(name) ||
          size < 0 ||
          size > 2 * 1024 * 1024 ||
          (mode & 0xF000) != 0 && (mode & 0xF000) != 0x8000 ||
          header.generalPurposeBitFlag & 1 != 0 ||
          ![0, 8].contains(header.compressionMethod) ||
          name != file.filename ||
          file.compressionMethod != header.compressionMethod ||
          !offsets.add(header.localHeaderOffset!)) {
        throw const FormatException(
          'Unsafe, duplicate, encrypted or oversized package path',
        );
      }
      total += size;
      if (total > 16 * 1024 * 1024) {
        throw const FormatException('Expanded package too large');
      }
      final output = _LimitedOutput(size);
      if (header.compressionMethod == 0) {
        output.writeInputStream(file.rawContent!);
      } else {
        Inflate.stream(file.rawContent!, output);
      }
      final content = output.getBytes();
      if (content.length != size || getCrc32(content) != header.crc32) {
        throw const FormatException('ZIP size or CRC mismatch');
      }
      files[name] = Uint8List.fromList(content).asUnmodifiableView();
    }
    final metadata = files.remove('package.json');
    if (metadata == null) throw const FormatException('Missing package.json');
    final package = object(jsonDecode(utf8.decode(metadata)));
    if (package['packageFormat'] != 2) {
      throw const FormatException('Unsupported package format');
    }
    final release = object(package['release']);
    final listed = <String>{};
    for (final raw in package['files'] as List) {
      final row = object(raw);
      final path = string(row['path'], 'file path');
      if (!safePath(path) || path == 'package.json' || !listed.add(path)) {
        throw const FormatException('Invalid file manifest');
      }
      final content = files[path];
      if (content == null ||
          content.length != row['size'] ||
          await digest(content) != row['sha256']) {
        throw FormatException('File integrity mismatch: $path');
      }
    }
    if (listed.length != files.length) {
      throw const FormatException('Unregistered package files');
    }
    final packageDigest = await digest(bytes);
    final channel = release['channel'];
    bool trusted = false;
    String origin;
    if (preinstalledDigest != null) {
      if (packageDigest != preinstalledDigest) {
        throw const FormatException('Preinstalled digest mismatch');
      }
      trusted = true;
      origin = 'preinstalled';
    } else if (channel == 'local') {
      if (!allowUnsignedLocal || package['signature'] != null) {
        throw const FormatException(
          'Unsigned local package requires explicit local review',
        );
      }
      origin = 'local';
    } else if (channel == 'market') {
      final signature = object(package['signature']);
      final publisher = string(release['publisherId'], 'publisher');
      final key = publishers?.find(
        publisher,
        string(signature['keyId'], 'key id'),
      );
      final review = object(release['review']);
      if (key == null ||
          signature['algorithm'] != 'ed25519' ||
          review['status'] != 'approved' ||
          review['reviewId'] is! String ||
          review['policyVersion'] is! String ||
          DateTime.tryParse('${release['publishedAt']}') == null ||
          DateTime.tryParse('${review['reviewedAt']}') == null) {
        throw const FormatException('Untrusted market release');
      }
      final signed = utf8.encode(
        canonicalJson({
          'packageFormat': 2,
          'release': release,
          'files': package['files'],
        }),
      );
      if (!await Ed25519().verify(
        signed,
        signature: Signature(
          base64Decode(signature['value'] as String),
          publicKey: SimplePublicKey(key.publicKey, type: KeyPairType.ed25519),
        ),
      )) {
        throw const FormatException('Invalid package signature');
      }
      trusted = true;
      origin = 'market';
    } else {
      throw const FormatException('Unsupported release source');
    }
    final definitionFile = files['module.json'];
    if (definitionFile == null) {
      throw const FormatException('Missing module.json');
    }
    return ScriptPackage._(
      bytes,
      packageDigest,
      object(freezeJson(jsonDecode(utf8.decode(definitionFile)))),
      Map.unmodifiable(files),
      object(freezeJson(release)),
      trusted,
      origin,
    );
  }

  static Future<Uint8List> build(
    Map<String, Object?> definition,
    Map<String, String> sources, {
    Map<String, Object?> release = const {'channel': 'local'},
  }) async {
    if (sources.containsKey('module.json') ||
        sources.containsKey('package.json')) {
      throw const FormatException(
        'Package metadata is generated from definition',
      );
    }
    final files = <String, List<int>>{
      'module.json': utf8.encode(canonicalJson(definition)),
      for (final entry in sources.entries) entry.key: utf8.encode(entry.value),
    };
    final names = files.keys.toList()..sort();
    final manifest = {
      'packageFormat': 2,
      'release': release,
      'files': [
        for (final name in names)
          {
            'path': name,
            'size': files[name]!.length,
            'sha256': await digest(files[name]!),
          },
      ],
    };
    files['package.json'] = utf8.encode(canonicalJson(manifest));
    final archive = Archive();
    for (final entry in files.entries) {
      archive.addFile(
        ArchiveFile(entry.key, entry.value.length, entry.value)
          ..lastModTime = 0,
      );
    }
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }
}

class _LimitedOutput extends OutputStream {
  _LimitedOutput(this.maximum) : super(size: maximum);
  final int maximum;
  void check(int count) {
    if (length + count > maximum) {
      throw const FormatException('ZIP expansion exceeds declared size');
    }
  }

  @override
  void writeByte(int value) {
    check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, [int? len]) {
    check(len ?? bytes.length);
    super.writeBytes(bytes, len);
  }

  @override
  void writeInputStream(InputStreamBase stream) {
    check(stream.length);
    super.writeInputStream(stream);
  }
}
