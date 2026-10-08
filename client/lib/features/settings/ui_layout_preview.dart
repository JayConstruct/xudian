import 'package:flutter/material.dart';

import '../../core/ui/ui_composition.dart';
import '../../core/ui/ui_layout_resolver.dart';
import '../../core/ui/ui_registry.dart';
import 'ui_layout.dart';

class UiLayoutPreview extends StatelessWidget {
  const UiLayoutPreview({
    super.key,
    required this.registry,
    required this.profile,
    required this.desktop,
    this.pageId,
  });

  final UiRegistry registry;
  final UiLayoutProfile profile;
  final bool desktop;
  final String? pageId;

  @override
  Widget build(BuildContext context) {
    final width = desktop ? 1024.0 : 390.0;
    final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
    List<UiEntryRegistration> at(UiPlacement placement) => orderedEntries(
      registry,
      profile.mountFor,
      (entry) => profile.mountFor(entry).placement == placement,
    );
    final main = at(UiPlacement.main);
    final header = at(UiPlacement.header);
    final visible = navigationVisibleCount(
      total: main.length,
      limit: profile.mainLimit,
      width: width - 24,
      textScale: textScale,
      desktop: desktop,
    );
    final headerLimit = headerVisibleCount(width: width, desktop: desktop);
    final host = registry.page(pageId ?? '');
    return AlertDialog(
      title: const Text('草稿结构预览'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('仅展示入口和槽位结构，不加载模块页面、不执行业务操作，也不保存草稿。'),
              const SizedBox(height: 12),
              if (pageId == null) ...[
                Text(
                  '${desktop ? '宽屏' : '窄屏'}示意宽度 ${width.toInt()}px；实际显示数量以屏幕空间和文字缩放为准。',
                ),
                _group(context, '顶部入口', header.take(headerLimit).toList()),
                _group(context, '主导航直显', main.take(visible).toList()),
                _group(context, '更多（含溢出入口）', [
                  ...at(UiPlacement.more),
                  ...main.skip(visible),
                  ...header.skip(headerLimit),
                ]),
                _group(context, '设置常用入口', at(UiPlacement.settings)),
                _group(context, '隐藏（不显示）', at(UiPlacement.hidden)),
                const Text('核心设置入口始终保留，不占用主导航直显上限。'),
              ] else ...[
                Text(host?.title ?? '宿主页面不可用，配置仍保留'),
                for (final slot in host?.slots ?? const <PageSlotDefinition>[])
                  _group(
                    context,
                    '${slot.label} · ${slotKindLabel(slot.kind)} · '
                    '${slot.isPublic ? '公开' : '私有'}'
                    '${slot.capacity == null ? '' : ' · 容量 ${slot.capacity}'}',
                    orderedEntries(registry, profile.mountFor, (entry) {
                      final mount = profile.mountFor(entry);
                      return mount.placement == UiPlacement.page &&
                          mount.pageId == pageId &&
                          mount.slotId == slot.id;
                    }),
                  ),
                _group(
                  context,
                  '失效槽位挂载',
                  orderedEntries(registry, profile.mountFor, (entry) {
                    final mount = profile.mountFor(entry);
                    return mount.placement == UiPlacement.page &&
                        mount.pageId == pageId &&
                        !(host?.slots.any((slot) => slot.id == mount.slotId) ??
                            false);
                  }),
                  showEmpty: false,
                ),
                const Text('子页面可能继续提供槽位；可切换编排范围查看。上下文有效性在运行时核验。'),
              ],
              for (final orphan in profile.mounts.entries.where(
                (item) =>
                    !registry.entries.any((entry) => entry.id == item.key) &&
                    (pageId == null
                        ? item.value.placement != UiPlacement.page
                        : item.value.pageId == pageId),
              ))
                ListTile(
                  leading: const Icon(Icons.warning_amber_outlined),
                  title: Text(orphan.key),
                  subtitle: const Text('模块或入口不可用，配置已保留'),
                ),
              for (final warning in compositionWarnings(
                registry,
                profile.mountFor,
              ))
                Text(
                  warning,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('返回编辑'),
        ),
      ],
    );
  }

  Widget _group(
    BuildContext context,
    String title,
    List<UiEntryRegistration> entries, {
    bool showEmpty = true,
  }) {
    if (entries.isEmpty && !showEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      initiallyExpanded: true,
      tilePadding: EdgeInsets.zero,
      title: Text(
        '$title · ${entries.length}',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      children: [
        if (entries.isEmpty)
          const Padding(padding: EdgeInsets.all(8), child: Text('暂无入口或内容')),
        for (final entry in entries) _item(context, entry),
      ],
    );
  }

  Widget _item(BuildContext context, UiEntryRegistration entry) {
    final diagnostic = layoutEntryDiagnostic(registry, entry, profile.mountFor);
    final pending = diagnostic?.issue == UiMountIssue.missingContext;
    final mount = profile.mountFor(entry);
    return ListTile(
      dense: true,
      leading: Icon(
        diagnostic == null
            ? entry.icon
            : pending
            ? Icons.info_outline
            : Icons.warning_amber_outlined,
      ),
      title: Text(entry.label),
      subtitle: Text(
        diagnostic == null
            ? '${entry.content ? '嵌入内容' : openingLabel(entry.opening)}'
                  '${mount.context.taskId != null || mount.context.projectId != null ? ' · 已绑定上下文，运行时核验' : ''}'
            : '${pending ? '上下文待检查' : '失效'}：${diagnostic.message}',
      ),
    );
  }
}

String slotKindLabel(PageSlotKind kind) => switch (kind) {
  PageSlotKind.entries => '入口按钮',
  PageSlotKind.tabs => '页签内容',
  PageSlotKind.sections => '纵向内容',
};

String openingLabel(UiOpening opening) => switch (opening) {
  UiOpening.workspace => '切换工作区',
  UiOpening.detail => '打开详情页',
  UiOpening.adaptivePanel => '打开自适应面板',
};
