import 'dart:convert';

import 'package:flutter/material.dart';

import '../contracts/json_values.dart';
import '../ui/native_ui.dart';

enum DataChangeKind { add, update, delete, unchanged }

class DataFieldChange {
  const DataFieldChange(
    this.field,
    this.before,
    this.after, {
    required this.hadBefore,
    required this.hasAfter,
  });
  final String field;
  final Object? before, after;
  final bool hadBefore, hasAfter;
}

class DataRecordChange {
  const DataRecordChange(this.write, this.kind);
  final Map<String, Object?> write;
  final DataChangeKind kind;
  String get moduleId => write['moduleId'] as String;
  String get collection => write['collection'] as String;
  String get id => write['id'] as String;
  String get label {
    for (final record in [write['value'], write['before']]) {
      if (record is! Map) continue;
      for (final field in ['title', 'name']) {
        final value = record[field];
        if (value is String && value.trim().isNotEmpty) return value;
      }
    }
    return id;
  }

  String get action => switch (kind) {
    DataChangeKind.add => '新增',
    DataChangeKind.update => '修改',
    DataChangeKind.delete => '删除',
    DataChangeKind.unchanged => '内容未变',
  };
  List<DataFieldChange> get fields {
    final before = write['before'] as Map<String, Object?>? ?? const {};
    final after = write['value'] as Map<String, Object?>? ?? const {};
    return [
      for (final field in {...before.keys, ...after.keys})
        if (before.containsKey(field) != after.containsKey(field) ||
            canonicalJson(before[field]) != canonicalJson(after[field]))
          DataFieldChange(
            field,
            before[field],
            after[field],
            hadBefore: before.containsKey(field),
            hasAfter: after.containsKey(field),
          ),
    ];
  }
}

/// Recognizes only the frozen actual plan payload, never package previews or
/// an arbitrary result with a `writes` member. Unknown writes fail as a whole.
class DataChangeSummary {
  const DataChangeSummary._(this.details, this.records);
  final Map<String, Object?> details;
  final List<DataRecordChange> records;
  Set<String> get moduleIds => records
      .where((record) => record.kind != DataChangeKind.unchanged)
      .map((record) => record.moduleId)
      .toSet();
  int count(DataChangeKind kind) =>
      records.where((record) => record.kind == kind).length;
  int get changedCount => records.length - count(DataChangeKind.unchanged);

  static DataChangeSummary? tryParse(Object? details) {
    if (details is! Map ||
        details.keys.any(
          (key) => !const {'planId', 'writes', 'result'}.contains(key),
        ) ||
        details['planId'] is! String ||
        (details['planId'] as String).trim().isEmpty ||
        details['writes'] is! List) {
      return null;
    }
    try {
      final frozen = freezeJson(details) as Map<String, Object?>;
      final records = <DataRecordChange>[];
      final identities = <String>{};
      for (final raw in frozen['writes'] as List) {
        if (raw is! Map<String, Object?> ||
            raw.keys.any(
              (key) => !const {
                'moduleId',
                'space',
                'collection',
                'id',
                'before',
                'value',
              }.contains(key),
            ) ||
            !raw.containsKey('before') ||
            !raw.containsKey('value')) {
          return null;
        }
        for (final key in ['moduleId', 'space', 'collection', 'id']) {
          if (raw[key] is! String || (raw[key] as String).isEmpty) return null;
        }
        for (final key in ['before', 'value']) {
          final record = raw[key];
          if (record != null &&
              (record is! Map<String, Object?> || record['id'] != raw['id'])) {
            return null;
          }
        }
        if (!identities.add(
          jsonEncode([
            raw['moduleId'],
            raw['space'],
            raw['collection'],
            raw['id'],
          ]),
        )) {
          return null;
        }
        final before = raw['before'], after = raw['value'];
        final kind = canonicalJson(before) == canonicalJson(after)
            ? DataChangeKind.unchanged
            : before == null
            ? DataChangeKind.add
            : after == null
            ? DataChangeKind.delete
            : DataChangeKind.update;
        records.add(DataRecordChange(raw, kind));
      }
      return DataChangeSummary._(frozen, List.unmodifiable(records));
    } on Object {
      return null;
    }
  }
}

/// Presentation only: no reads, writes, review or commit calls.
class DataChangeReview extends StatelessWidget {
  const DataChangeReview({super.key, required this.summary});
  final DataChangeSummary summary;
  static const previewLimit = 20;
  static const fieldPreviewLimit = 12;

  String _value(Object? value, bool exists) =>
      !exists ? '（字段不存在）' : const JsonEncoder.withIndent('  ').convert(value);

  Widget _fieldValue(String label, Object? value, bool exists) {
    final text = _value(value, exists);
    if (text.length <= 600) {
      return SelectableText(
        '$label：$text',
        scrollPhysics: const NeverScrollableScrollPhysics(),
      );
    }
    return NativeUi(
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text('$label：内容较长，展开查看完整值（${text.length} 个字符）'),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              text,
              scrollPhysics: const NeverScrollableScrollPhysics(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fields(List<DataFieldChange> fields) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final field in fields)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                field.field,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              _fieldValue('之前', field.before, field.hadBefore),
              _fieldValue('之后', field.after, field.hasAfter),
            ],
          ),
        ),
    ],
  );

  Widget _record(BuildContext context, DataRecordChange record) {
    final fields = record.fields;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${record.action} · ${record.label}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: record.kind == DataChangeKind.delete
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          ),
          Text('${record.moduleId} · ${record.collection}'),
          if (record.kind == DataChangeKind.delete)
            const Text(
              '此记录将被删除',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          _fields(fields.take(fieldPreviewLimit).toList()),
          if (fields.length > fieldPreviewLimit)
            NativeUi(
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('其余 ${fields.length - fieldPreviewLimit} 个变化字段'),
                children: [_fields(fields.skip(fieldPreviewLimit).toList())],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show destructive writes first, including when a batch exceeds the limit.
    final records = [
      ...summary.records.where(
        (record) => record.kind == DataChangeKind.delete,
      ),
      ...summary.records.where(
        (record) => record.kind != DataChangeKind.delete,
      ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          summary.changedCount == 0
              ? '没有实际数据变化'
              : '将影响 ${summary.moduleIds.length} 个模块：新增 ${summary.count(DataChangeKind.add)} 条，修改 ${summary.count(DataChangeKind.update)} 条，删除 ${summary.count(DataChangeKind.delete)} 条',
        ),
        if (summary.moduleIds.isNotEmpty)
          Text('涉及模块：${summary.moduleIds.join('、')}'),
        if (summary.count(DataChangeKind.delete) > 0)
          Text(
            '包含 ${summary.count(DataChangeKind.delete)} 条删除，请核对后确认',
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.bold,
            ),
          ),
        if (summary.count(DataChangeKind.unchanged) > 0)
          Text('${summary.count(DataChangeKind.unchanged)} 条记录内容未变'),
        const SizedBox(height: 8),
        const Text('以下为已生成计划中的前后对比。提交前会再次核对数据；如已变化，本计划不会执行，需要重新生成并审核。'),
        for (final record in records.take(previewLimit))
          _record(context, record),
        if (records.length > previewLimit)
          Text(
            '摘要显示前 $previewLimit 条（删除优先），共 ${records.length} 条；其余 ${records.length - previewLimit} 条请在全量原始详情中核对。',
          ),
        NativeUi(
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('全量原始详情'),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  const JsonEncoder.withIndent('  ').convert(summary.details),
                  scrollPhysics: const NeverScrollableScrollPhysics(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
