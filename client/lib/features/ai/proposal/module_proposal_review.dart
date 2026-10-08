import 'package:flutter/material.dart';

import '../../../core/ui/module_ui_labels.dart';
import 'module_proposal.dart';

Future<bool> showModuleProposalReview({
  required BuildContext context,
  required ModuleProposal proposal,
}) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ModuleProposalReview(proposal: proposal),
      ) ??
      false;
}

class _ModuleProposalReview extends StatelessWidget {
  const _ModuleProposalReview({required this.proposal});

  final ModuleProposal proposal;

  String _sourceLabel(ModuleProposal proposal) {
    final source = proposal.provenance;
    return switch (source.origin) {
      'market' =>
        '来源：已审核市场包 · 发布者 ${source.publisherId ?? '-'}'
            ' · 审核 ${source.reviewId ?? '-'}',
      'local-package' => '来源：本地开发包（未审核）',
      'ai' => '来源：AI 生成/编辑',
      _ => '来源：本地配置',
    };
  }

  String _pageId(String value) =>
      value.contains('.') ? value : '${proposal.module.manifest.id}.$value';

  String _mountDescription(
    Map<String, Object?> mount,
    String pageId,
    String hostKey,
  ) {
    final placement = mount['placement'] ?? 'main';
    final target = placement == 'page'
        ? '${_pageId(mount[hostKey] as String)} / ${mount['slotId']}'
        : '$placement';
    final targetPages = proposal.module.pages.where(
      (page) => _pageId(page['id'] as String) == pageId,
    );
    final required = targetPages.isEmpty
        ? '由目标模块声明，运行时检查'
        : ((targetPages.single['requiredContext'] as List?)?.join('、') ?? '无');
    return '目标页面：$pageId\n默认位置：$target；顺序：${mount['order'] ?? 0}\n'
        '类型：${mount['content'] == true ? '嵌套内容' : '界面入口'}；'
        '打开方式：${mount['opening'] ?? 'workspace'}\n'
        '所需上下文：${required.isEmpty ? '无' : required}';
  }

  List<Widget> _compositionReview(BuildContext context) {
    if (proposal.module.formatVersion != 2) return const [];
    final changedPages = <String>{};
    final changedLayouts = <String>{};
    for (final change in proposal.diff.resources) {
      if (change.kind == 'page') {
        changedPages.addAll([...change.added, ...change.changed]);
      }
      if (change.kind == 'layout') {
        changedLayouts.addAll([...change.added, ...change.changed]);
      }
    }
    return [
      Text('页面组合与默认挂载', style: Theme.of(context).textTheme.titleSmall),
      const Text(
        '确认后应用默认挂载，已有用户布局优先。跨模块挂载不继承宿主权限；'
        '缺少上下文或目标不可用时提示失效并保留配置。',
      ),
      for (final page in proposal.module.pages.where(
        (page) => changedPages.contains(page['id']),
      )) ...[
        const SizedBox(height: 8),
        SelectableText(
          '页面：${_pageId(page['id'] as String)}；'
          '上下文：${(page['requiredContext'] as List?)?.join('、') ?? '无'}；'
          '保留局部位置：${page['retainPosition'] == true ? '是' : '否'}',
        ),
        for (final slot in page['slots'] as List? ?? const [])
          SelectableText(
            '槽位：${slot['id']}（${slot['kind'] ?? 'entries'}，'
            '${slot['public'] == true ? '公开给其他模块' : '本模块私有'}）；'
            '上下文：${(slot['requiredContext'] as List?)?.join('、') ?? '无'}',
          ),
        if (page['entry'] is Map)
          SelectableText(
            _mountDescription(
              (page['entry'] as Map?)?.cast<String, Object?>() ?? const {},
              _pageId(page['id'] as String),
              'targetPageId',
            ),
          ),
      ],
      for (final layout in proposal.module.layouts.where(
        (layout) => changedLayouts.contains(layout['id']),
      )) ...[
        const SizedBox(height: 8),
        SelectableText(
          '贡献：${layout['id']} · ${layout['label']}\n'
          '${_mountDescription(layout, _pageId(layout['pageId'] as String), 'hostPageId')}',
        ),
      ],
      const SizedBox(height: 12),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final diff = proposal.diff;
    return AlertDialog(
      title: const Text('确认功能变更'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                diff.fromVersion == null
                    ? '安装 ${diff.moduleId} ${diff.toVersion}'
                    : '更新 ${diff.moduleId}: '
                          '${diff.fromVersion} → ${diff.toVersion}',
              ),
              const SizedBox(height: 8),
              Text(
                _sourceLabel(proposal),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              if (diff.permissionsAdded.isNotEmpty) ...[
                Text('新增权限', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                for (final permission in diff.permissionsAdded)
                  Text('• ${modulePermissionLabel(permission)}'),
                const SizedBox(height: 12),
              ],
              if (diff.permissionsRemoved.isNotEmpty) ...[
                Text('移除权限', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                for (final permission in diff.permissionsRemoved)
                  Text('• ${modulePermissionLabel(permission)}'),
                const SizedBox(height: 12),
              ],
              for (final resource in diff.resources) ...[
                Text(
                  moduleResourceLabel(resource.kind),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (resource.added.isNotEmpty)
                  Text('新增：${resource.added.join('、')}'),
                if (resource.removed.isNotEmpty)
                  Text('删除：${resource.removed.join('、')}'),
                if (resource.changed.isNotEmpty)
                  Text('修改：${resource.changed.join('、')}'),
                const SizedBox(height: 10),
              ],
              ..._compositionReview(context),
              const Text(
                '确认后会立即安装或更新模块。可在版本历史中恢复旧配置；'
                '恢复配置不会撤销已创建的任务或已执行的自动化操作。',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('确认应用'),
        ),
      ],
    );
  }
}
