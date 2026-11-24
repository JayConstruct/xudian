import 'dart:convert';
import 'dart:io';

import 'package:task_app/core/module_host/module_package.dart';

Future<ScriptPackage> archivedCompactPack() => ScriptPackage.verify(
  File('../releases/modules/example.ui.compact-1.1.0.xmodule')
      .readAsBytesSync(),
  allowUnsignedLocal: true,
);

Future<ScriptPackage> sourcePackage(String id) async {
  final folder = Directory('../packages/modules/$id');
  final files = <String, String>{};
  await for (final file in folder.list(recursive: true)) {
    if (file is File && file.path.endsWith('.js')) {
      files[file.path.substring(folder.path.length + 1)] = await file
          .readAsString();
    }
  }
  return ScriptPackage.verify(
    await ScriptPackage.build(
      object(
        jsonDecode(await File('${folder.path}/module.json').readAsString()),
      ),
      files,
    ),
    allowUnsignedLocal: true,
  );
}

List<Map<String, Object?>> objects(Object? value) =>
    (value as List).map(object).toList();
List<Map<String, Object?>> nodes(Object? value) => value is Map
    ? [object(value), for (final child in value.values) ...nodes(child)]
    : value is List
    ? [for (final child in value) ...nodes(child)]
    : [];

Map<String, Object?> table(
  String id, {
  String zone = 'Asia/Shanghai',
  String monday = '2026-10-05',
  String start = '08:00',
  String end = '09:00',
}) => {
  'id': id,
  'name': id,
  'firstMonday': monday,
  'totalWeeks': 20,
  'timezone': zone,
  'displayWeekStart': 1,
  'periods': [
    {'number': 1, 'start': start, 'end': end},
  ],
};
