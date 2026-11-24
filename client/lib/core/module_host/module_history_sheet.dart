import 'package:flutter/material.dart';
import 'package:pub_semver/pub_semver.dart';

import '../../features/settings/settings_widgets.dart';
import 'module_host.dart';
import 'review_widgets.dart';

String _date(Object? raw, {bool includeTime = true}) {
  final value = DateTime.tryParse('$raw')?.toLocal();
  if (value == null) return raw?.toString() ?? '';
  final day = '${value.month}月${value.day}日';
  return includeTime ? '$day · ${_clock(value)}' : day;
}

String _clock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

Future<T?> _select<T>(
  BuildContext context,
  String title,
  List<Widget> Function(BuildContext) rows, {
  String dismiss = '取消',
}) => showSettingsModal<T>(
  compactFrame: true,
  context: context,
  builder: (sheet) => SettingsSheet(
    title: Text(title),
    showClose: true,
    expandedActions: true,
    content: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows(sheet),
      ),
    ),
    actions: [
      OutlinedButton(
        onPressed: () => Navigator.pop(sheet),
        child: Text(dismiss),
      ),
    ],
  ),
);

Future<void> showModuleSnapshots(
  BuildContext context,
  ModuleHost host,
  String id,
  String name,
) async {
  final records = await host.store.sql(
    'SELECT id,version,data_version,created_at FROM host_snapshots WHERE module_id=? ORDER BY created_at DESC',
    [id],
  );
  if (!context.mounted) return;
  final selected = await _select<Map<String, Object?>>(
    context,
    '数据快照恢复',
    (sheet) => [
      if (records.isEmpty)
        const SettingsEmptyState(
          grouped: false,
          title: '没有可恢复快照',
          detail: '此模块尚无历史数据快照。',
          icon: Icons.restore,
        )
      else
        SettingsGroup(
          bottomSpacing: 8,
          title: name,
          children: [
            for (final row in records)
              SettingsEntry(
                title: _date(row['created_at']),
                subtitle: '版本 ${row['version']} · 数据版本 ${row['data_version']}',
                icon: Icons.restore,
                onTap: () => Navigator.pop(sheet, row),
              ),
          ],
        ),
    ],
    dismiss: records.isEmpty ? '关闭' : '取消',
  );
  if (selected == null || !context.mounted) return;
  if (await showReviewConfirmation(
    context,
    title: '恢复旧快照？',
    confirmLabel: '恢复快照',
    children: [
      ReviewSubject(
        title: name,
        subtitle:
            '版本 ${selected['version']} · ${_date(selected['created_at'])}',
        icon: Icons.restore,
      ),
      ReviewFacts(
        title: '恢复对象',
        items: [
          (title: '模块', subtitle: id),
          (title: '快照', subtitle: selected['id'] as String),
        ],
      ),
      const ReviewNotice('当前数据将保留为新快照。恢复时会切换版本和数据，快照之后的修改不会自动合并。'),
    ],
  )) {
    await host.recoverSnapshot(id, selected['id'] as String);
  }
}

Future<void> showModuleVersions(
  BuildContext context,
  ModuleHost host,
  String id,
  String name,
  String current,
) async {
  final versions = await host.store.sql(
    'SELECT version,origin,digest FROM host_packages WHERE module_id=?',
    [id],
  );
  versions.sort(
    (a, b) =>
        Version.parse(b['version'] as String)
            .compareTo(Version.parse(a['version'] as String)),
  );
  if (!context.mounted) return;
  final selected = await _select<String>(
    context,
    '版本历史',
    (sheet) => [
      SettingsGroup(
        bottomSpacing: 8,
        title: name,
        children: [
          for (final row in versions)
            Builder(
              builder: (_) {
                final version = row['version'] as String;
                final origin = switch (row['origin']) {
                  'preinstalled' => '内置模块',
                  'market' => '模块商店',
                  'local' => '本地模块',
                  final other => '$other',
                };
                return SettingsEntry(
                  title: version == current ? '$version · 当前' : version,
                  icon: Icons.layers_outlined,
                  subtitle: '$origin\n${row['digest']}',
                  onTap: version == current
                      ? null
                      : () => Navigator.pop(sheet, version),
                );
              },
            ),
        ],
      ),
    ],
  );
  if (selected == null || !context.mounted) return;
  if (await showReviewConfirmation(
    context,
    title: '回退到 $selected？',
    confirmLabel: '确认回退',
    children: [
      ReviewSubject(title: name, subtitle: id, icon: Icons.layers_outlined),
      ReviewFacts(
        title: '目标版本',
        items: [
          (title: '当前', subtitle: current),
          (title: '回退至', subtitle: selected),
        ],
      ),
      const Text('切换到所选版本并保留当前兼容数据。'),
    ],
  )) {
    await host.rollback(id, selected);
  }
}

Future<void> showModuleRuns(
  BuildContext context,
  ModuleHost host,
  String id,
) async {
  final records = await host.automationHistory(id);
  final rules = host.instances[id]?.package.definition['rules'] as List? ?? [];
  final titles = {
    for (final rule in rules.whereType<Map>())
      rule['id']: rule['title'] ?? rule['name'],
  };
  final groups = <String, List<Map<String, Object?>>>{};
  records.sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
  for (final row in records) {
    final time = DateTime.tryParse('${row['created_at']}')?.toLocal();
    final day = time == null
        ? _date(row['created_at'])
        : '${time.year}-${time.month}-${time.day}';
    groups.putIfAbsent(day, () => []).add(row);
  }
  if (!context.mounted) return;
  final retry = await _select<String>(
    context,
    '规则执行记录',
    (sheet) => [
      if (records.isEmpty)
        const SettingsEmptyState(
          grouped: false,
          title: '没有执行记录',
          detail: '此模块尚无规则执行记录。',
          icon: Icons.history,
        ),
      for (final group in groups.values)
        SettingsGroup(
          bottomSpacing: 8,
          title: _date(group.first['created_at'], includeTime: false),
          children: [
            for (final row in group)
              Builder(
                builder: (_) {
                  final failed = row['status'] == 'failure';
                  final time = DateTime.tryParse('${row['created_at']}')
                      ?.toLocal();
                  final status = switch (row['status']) {
                    'failure' => '执行失败',
                    'success' => '已执行',
                    'skipped' => '已跳过',
                    final other => '$other',
                  };
                  return SettingsEntry(
                    title:
                        '${titles[row['rule_id']] ?? row['rule_id']} · $status',
                    subtitle: [
                      if (time != null || row['message'] != null)
                        [
                          if (time != null) _clock(time),
                          if (row['message'] != null) row['message'],
                        ].join(' · '),
                      '重试来源 · ${row['retry_of'] ?? row['source_execution_id'] ?? '无'}',
                    ].join('\n'),
                    icon: failed
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline_rounded,
                    trailing: failed
                        ? TextButton(
                            onPressed: () => Navigator.pop(sheet, row['id']),
                            child: const Text('重试'),
                          )
                        : null,
                  );
                },
              ),
          ],
        ),
    ],
    dismiss: '关闭',
  );
  if (retry != null) await host.retryHistoricalAutomation(id, retry);
}
