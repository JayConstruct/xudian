import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/contracts/json_values.dart';
import 'package:task_app/core/declarative/package/module_package.dart';
import 'package:task_app/core/module_host/module_package.dart';

void main() {
  final definition = <String, Object?>{
    'formatVersion': 3,
    'manifest': {
      'id': 'test.secure',
      'version': '1.0.0',
      'hostApi': '^1.0.0',
      'dataVersion': 1,
      'permissions': [],
      'dependencies': [],
    },
    'entryPoint': 'main.js',
    'collections': [],
    'services': [],
    'pages': [],
  };
  Archive decode(List<int> bytes) => ZipDecoder().decodeBytes(bytes);
  List<int> encode(Archive a) => ZipEncoder().encode(a)!;
  test('semantic prereleases and compatible host ranges are accepted; incompatible ranges reject', () async {
    await expectLater(
      ScriptPackage.build(definition, {
        'main.js': 'export const value=1;',
        'module.json': '{}',
      }),
      throwsFormatException,
    );
    final compatible = {
      ...definition,
      'manifest': {
        ...object(definition['manifest']),
        'version': '1.2.3-beta.1+local',
        'hostApi': '>=1.0.0 <2.0.0',
      },
    };
    final bytes = await ScriptPackage.build(compatible, {
      'main.js': 'export const value=1;',
    });
    expect(
      (await ScriptPackage.verify(bytes, allowUnsignedLocal: true)).version,
      '1.2.3-beta.1+local',
    );
    final incompatible = {
      ...definition,
      'manifest': {...object(definition['manifest']), 'hostApi': '^2.0.0'},
    };
    await expectLater(
      ScriptPackage.verify(
        await ScriptPackage.build(incompatible, {
          'main.js': 'export const value=1;',
        }),
        allowUnsignedLocal: true,
      ),
      throwsFormatException,
    );
  });
  test('unregistered files, traversal and duplicate paths rejected', () async {
    final bytes = await ScriptPackage.build(definition, {
      'main.js': 'export function value(){return 1;}',
    });
    for (final name in ['undeclared.js', '../escape.js', 'main.js']) {
      final archive = decode(bytes);
      archive.addFile(ArchiveFile(name, 1, [1]));
      await expectLater(
        ScriptPackage.verify(encode(archive), allowUnsignedLocal: true),
        throwsFormatException,
      );
    }
  });
  test(
    'file digest tampering rejected and original bytes are immutable',
    () async {
      final bytes = await ScriptPackage.build(definition, {
        'main.js': 'export const value=1;',
      });
      final archive = decode(bytes);
      final tampered = Archive();
      for (final file in archive.files) {
        tampered.addFile(
          file.name == 'main.js' ? ArchiveFile('main.js', 3, [2, 3, 4]) : file,
        );
      }
      await expectLater(
        ScriptPackage.verify(encode(tampered), allowUnsignedLocal: true),
        throwsFormatException,
      );
      final verified = await ScriptPackage.verify(
        bytes,
        allowUnsignedLocal: true,
      );
      expect(() => verified.bytes[0] = 0, throwsUnsupportedError);
      expect(() => verified.files['main.js']![0] = 0, throwsUnsupportedError);
    },
  );
  test(
    'verified files retain isolated snapshots and scripts remain independent',
    () async {
      final input = await ScriptPackage.build(definition, {
        'main.js': 'export const value="模块";',
        'helper.js': 'export const value=2;',
      });
      final original = Uint8List.fromList(input);
      final verification = ScriptPackage.verify(
        input,
        allowUnsignedLocal: true,
      );
      input.fillRange(0, input.length, 0);
      final verified = await verification;
      expect(verified.bytes, original);
      final restored = verified.withStoredOrigin('local');
      expect(restored.bytes, same(verified.bytes));
      expect(restored.files, same(verified.files));
      expect(restored.definition, same(verified.definition));
      expect(restored.origin, 'local');
      expect(restored.trusted, isTrue);
      final scripts = restored.scripts;
      scripts['main.js'] = 'caller replacement';
      scripts.remove('helper.js');
      expect(restored.scripts['main.js'], 'export const value="模块";');
      expect(restored.scripts['helper.js'], 'export const value=2;');
      expect(verified.scripts, restored.scripts);
      expect(() => restored.files['main.js']![0] = 0, throwsUnsupportedError);
    },
  );

  test(
    'stored and deflated file corruption never bypasses CRC or SHA checks',
    () async {
      final bytes = await ScriptPackage.build(definition, {
        'main.js': 'export const value=1;',
      });
      final archive = decode(bytes);
      final replaced = Archive();
      for (final file in archive.files) {
        final content = file.name == 'main.js'
            ? utf8.encode('export const value=2;')
            : file.content as List<int>;
        replaced.addFile(ArchiveFile(file.name, content.length, content));
      }
      await expectLater(
        ScriptPackage.verify(encode(replaced), allowUnsignedLocal: true),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'File integrity mismatch: main.js',
          ),
        ),
      );
      final stored = Archive();
      for (final file in archive.files) {
        final content = file.content as List<int>;
        stored.addFile(
          ArchiveFile(file.name, content.length, content)..compress = false,
        );
      }
      final corrupted = Uint8List.fromList(encode(stored));
      final headers = ZipDirectory.read(InputStream(corrupted)).fileHeaders;
      final main = headers.singleWhere(
        (header) => header.filename == 'main.js',
      );
      final local = ByteData.sublistView(corrupted);
      final offset = main.localHeaderOffset!;
      final contentOffset =
          offset +
          30 +
          local.getUint16(offset + 26, Endian.little) +
          local.getUint16(offset + 28, Endian.little);
      corrupted[contentOffset] ^= 1;
      await expectLater(
        ScriptPackage.verify(corrupted, allowUnsignedLocal: true),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'ZIP size or CRC mismatch',
          ),
        ),
      );
    },
  );

  test(
    'market signature covers both release and complete file manifest',
    () async {
      final key = await Ed25519().newKeyPair(),
          public = await key.extractPublicKey();
      final bytes = await ScriptPackage.build(definition, {
        'main.js': 'export const value=1;',
      });
      final archive = decode(bytes),
          manifestFile = archive.files.firstWhere(
            (f) => f.name == 'package.json',
          );
      final metadata = object(
        jsonDecode(utf8.decode(manifestFile.content as List<int>)),
      );
      final release = {
        'channel': 'market',
        'publisherId': 'publisher',
        'publishedAt': '2026-10-06T00:00:00Z',
        'review': {
          'status': 'approved',
          'reviewId': 'review',
          'policyVersion': '1',
          'reviewedAt': '2026-10-06T00:00:00Z',
        },
      };
      final signed = await Ed25519().sign(
        utf8.encode(
          canonicalJson({
            'packageFormat': 2,
            'release': release,
            'files': metadata['files'],
          }),
        ),
        keyPair: key,
      );
      final market = {
        ...metadata,
        'release': release,
        'signature': {
          'algorithm': 'ed25519',
          'keyId': 'key',
          'value': base64Encode(signed.bytes),
        },
      };
      final publishers = TrustedPublisherRegistry([
        TrustedPublisherKey(
          publisherId: 'publisher',
          keyId: 'key',
          publicKey: public.bytes,
        ),
      ]);
      Archive replace(Map<String, Object?> m) {
        final next = Archive();
        for (final f in archive.files) {
          if (f.name != 'package.json') next.addFile(f);
        }
        final json = utf8.encode(canonicalJson(m));
        next.addFile(ArchiveFile('package.json', json.length, json));
        return next;
      }

      expect(
        (await ScriptPackage.verify(
          encode(replace(market)),
          publishers: publishers,
        )).trusted,
        true,
      );
      await expectLater(
        ScriptPackage.verify(
          encode(
            replace({
              ...market,
              'release': {...release, 'summary': '篡改发布'},
            }),
          ),
          publishers: publishers,
        ),
        throwsFormatException,
      );
      final corruptedSignature = Uint8List.fromList(signed.bytes);
      corruptedSignature[0] ^= 1;
      await expectLater(
        ScriptPackage.verify(
          encode(
            replace({
              ...market,
              'signature': {
                ...object(market['signature']),
                'value': base64Encode(corruptedSignature),
              },
            }),
          ),
          publishers: publishers,
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Invalid package signature',
          ),
        ),
      );
    },
  );
  test(
    'build-pinned preinstalled digest and explicit unsigned source enforced',
    () async {
      final bytes = await ScriptPackage.build(definition, {
        'main.js': 'export const value=1;',
      });
      await expectLater(ScriptPackage.verify(bytes), throwsFormatException);
      await expectLater(
        ScriptPackage.verify(bytes, preinstalledDigest: 'bad'),
        throwsFormatException,
      );
      expect(
        (await ScriptPackage.verify(
          bytes,
          preinstalledDigest: await digest(bytes),
        )).origin,
        'preinstalled',
      );
    },
  );
}
