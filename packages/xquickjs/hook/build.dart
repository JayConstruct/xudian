import 'dart:io';

import 'package:hooks/hooks.dart';
import 'package:code_assets/code_assets.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    if (input.config.code.targetOS == OS.linux && Platform.isLinux) {
      final library = input.outputDirectory.resolve('libxquickjs.so');
      final sources = [
        'src/bridge.c',
        'src/vendor/quickjs.c',
        'src/vendor/libregexp.c',
        'src/vendor/libunicode.c',
        'src/vendor/dtoa.c',
      ];
      final result = await Process.run('gcc', [
        '-shared',
        '-fPIC',
        '-std=gnu11',
        '-O2',
        '-funsigned-char',
        '-pthread',
        '-DNDEBUG',
        '-D_GNU_SOURCE',
        '-DQUICKJS_NG_BUILD',
        '-Isrc/vendor',
        ...sources,
        '-lm',
        '-o',
        library.toFilePath(),
      ], workingDirectory: input.packageRoot.toFilePath());
      if (result.exitCode != 0) throw StateError('${result.stderr}');
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: 'xquickjs.dart',
          linkMode: DynamicLoadingBundled(),
          file: library,
        ),
      );
      output.dependencies.addAll(sources.map(input.packageRoot.resolve));
      output.dependencies.addAll(
        Directory.fromUri(input.packageRoot.resolve('src/vendor/'))
            .listSync()
            .whereType<File>()
            .map((file) => file.uri),
      );
      return;
    }
    final windows = input.config.code.targetOS == OS.windows;
    await CBuilder.library(
      name: 'xquickjs',
      assetName: 'xquickjs.dart',
      sources: [
        'src/bridge.c',
        'src/vendor/quickjs.c',
        'src/vendor/libregexp.c',
        'src/vendor/libunicode.c',
        'src/vendor/dtoa.c',
      ],
      includes: ['src/vendor'],
      defines: {
        'QUICKJS_NG_BUILD': null,
        'NDEBUG': null,
        '_GNU_SOURCE': null,
        if (windows) '_CRT_SECURE_NO_WARNINGS': null,
      },
      flags: [
        if (!windows) ...['-std=gnu11', '-O2', '-funsigned-char', '-pthread'],
      ],
      libraries: [if (!windows) 'm'],
    ).run(input: input, output: output);
  });
}
