import 'package:flutter/material.dart';

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
                  Text('• $permission'),
                const SizedBox(height: 12),
              ],
              if (diff.permissionsRemoved.isNotEmpty) ...[
                Text('移除权限', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                for (final permission in diff.permissionsRemoved)
                  Text('• $permission'),
                const SizedBox(height: 12),
              ],
              for (final resource in diff.resources) ...[
                Text(
                  resource.kind,
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
              const Text('确认后会立即应用；已有版本仍保留，可从版本历史回退。'),
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
