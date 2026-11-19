part of 'ui_layout_page.dart';

extension _UiLayoutChanges on _UiLayoutPageState {
  String _location(UiMount? mount, {int? position}) {
    if (mount == null) return '无配置';
    final host = widget.registry.ui.page(mount.pageId ?? '');
    final slots = host?.slots.where((slot) => slot.id == mount.slotId);
    final location = mount.placement == UiPlacement.page
        ? '${host?.title ?? '不可用页面'} / '
              '${slots == null || slots.isEmpty ? '不可用槽位' : slots.first.label}'
        : placementLabel(mount.placement);
    return '$location · ${position == null ? '排序值 ${mount.order}' : '第 $position 项'}'
        '${mount.context.taskId == null ? '' : ' · 指定任务'}'
        '${mount.context.projectId == null ? '' : ' · 指定项目'}';
  }

  List<(String, String, String)> _changes() {
    if (baseline == null || draft == null) return const [];
    final entries = {
      for (final entry in widget.registry.ui.entries) entry.id: entry,
    };
    return [
      for (final wide in [false, true]) ...[
        if (baseline!.profile(wide).mainLimit != draft!.profile(wide).mainLimit)
          (
            '${wide ? '宽屏' : '窄屏'} · 主导航直显上限',
            baseline!.profile(wide).mainLimit?.toString() ?? '不限制',
            draft!.profile(wide).mainLimit?.toString() ?? '不限制',
          ),
        if (baseline!.profile(wide).morePageEnabled !=
            draft!.profile(wide).morePageEnabled)
          (
            '${wide ? '宽屏' : '窄屏'} · 更多页面',
            baseline!.profile(wide).morePageEnabled ? '启用' : '关闭',
            draft!.profile(wide).morePageEnabled ? '启用' : '关闭',
          ),
        for (final id in {
          ...baseline!.profile(wide).mounts.keys,
          ...draft!.profile(wide).mounts.keys,
        })
          if (baseline!.profile(wide).mounts[id] !=
              draft!.profile(wide).mounts[id])
            (
              '${wide ? '宽屏' : '窄屏'} · ${entries[id]?.label ?? id}',
              '${_location(baseline!.profile(wide).mounts[id] ?? entries[id]?.defaultMount)}'
                  '${baseline!.profile(wide).mounts.containsKey(id) ? '' : '（模块默认）'}',
              '${_location(draft!.profile(wide).mounts[id] ?? entries[id]?.defaultMount)}'
                  '${draft!.profile(wide).mounts.containsKey(id) ? '' : '（模块默认）'}'
                  '${(baseline!.profile(wide).mounts[id] ?? entries[id]?.defaultMount)?.context != (draft!.profile(wide).mounts[id] ?? entries[id]?.defaultMount)?.context ? ' · 上下文配置有变化' : ''}',
            ),
      ],
    ];
  }

  void _reviewChanges() {
    final changes = _changes();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => NativeUi(
        child: AlertDialog(
          title: Text('草稿变更 · ${changes.length} 项'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('包括两套屏幕配置和所有编排范围；尚未保存。'),
                  if (changes.isEmpty) const Text('与进入编辑器时的配置一致。'),
                  for (final change in changes)
                    NativeUi(
                      child: ListTile(
                        title: Text(change.$1),
                        subtitle: Text('原：${change.$2}\n新：${change.$3}'),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            NativeUi(
              child: TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('返回编辑'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
