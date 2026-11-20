part of 'ui_layout_page.dart';

extension _UiLayoutInspector on _UiLayoutPageState {
  Widget _inspector() {
    final entries = widget.registry.ui.entries.where(
      (entry) => entry.id == selectedId,
    );
    if (entries.isEmpty) {
      final mount = profile.mounts[selectedId];
      if (mount == null) {
        return const Center(child: Text('选择一项以编辑位置、顺序和上下文'));
      }
      return ListView(
        key: const ValueKey('layout-inspector'),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '编辑 · $selectedId',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(_location(mount)),
          const Text('模块或入口不可用，配置已保留；恢复模块后可重新使用。'),
          NativeUi(
            child: TextButton.icon(
              onPressed: saving
                  ? null
                  : () {
                      _setProfile(profile.withoutMount(selectedId!));
                    },
              icon: const UiIcon(Icons.delete_outline),
              label: const Text('清理失效配置'),
            ),
          ),
        ],
      );
    }
    final entry = entries.single;
    final mount = profile.mountFor(entry);
    final diagnostic = layoutEntryDiagnostic(
      widget.registry.ui,
      entry,
      profile.mountFor,
    );
    final editable = !saving && _editable(entry);
    final siblings = _siblings(entry);
    final index = siblings.indexWhere((other) => other.id == entry.id);
    final filtered = search.trim().isNotEmpty || onlyProblems;
    return ListView(
      key: const ValueKey('layout-inspector'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '编辑 · ${entry.label}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(entry.content ? '嵌入内容' : openingLabel(entry.opening)),
        if (showIdentifiers)
          Text('${entry.id}\n模块：${entry.moduleId}\n页面：${entry.pageId}'),
        if (!editable && !saving) const Text('模块固定槽位，不可调整位置、顺序或上下文。'),
        if (mount.placement == UiPlacement.page)
          for (final slot
              in widget.registry.ui.page(mount.pageId ?? '')?.slots ??
                  const <PageSlotDefinition>[])
            if (slot.id == mount.slotId)
              Text(
                '${slot.label} · ${slot.isPublic ? '公开' : '私有'} · '
                '${slotKindLabel(slot.kind)} · ${slot.editable ? '可编排' : '模块固定'}'
                '${slot.capacity == null ? '' : ' · 容量 ${slot.capacity}'}',
              ),
        if (diagnostic != null) ...[
          const SizedBox(height: 12),
          Text(
            '${diagnostic.issue == UiMountIssue.missingContext ? '上下文待检查' : '失效'}：${diagnostic.message}\n${diagnostic.suggestion}',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          NativeUi(
            child: TextButton(
              onPressed: () => AppToast.show(
                context,
                message: '配置保持不变，条件恢复后可重新使用',
                kind: 'info',
              ),
              child: const Text('暂时保留'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        SettingsGroup(
          children: [
            SettingsEntry(
              title: '调整位置',
              subtitle: _location(mount, position: index + 1),
              icon: Icons.place_outlined,
              enabled: editable,
              onTap: () => _target(entry),
            ),
            SettingsEntry(
              title: '补充上下文',
              subtitle:
                  mount.context.taskId == null &&
                      mount.context.projectId == null
                  ? '由宿主提供'
                  : '已指定上下文',
              icon: Icons.link,
              enabled: editable,
              onTap: () => _context(entry),
            ),
          ],
        ),
        Text(
          '分组顺序 · ${index + 1} / ${siblings.length}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Wrap(
          spacing: 4,
          children: [
            NativeUi(
              child: IconButton(
                tooltip: '上移',
                onPressed: editable && !filtered && index > 0
                    ? () => _placeAt(entry, index - 1)
                    : null,
                icon: const UiIcon(Icons.arrow_upward),
              ),
            ),
            NativeUi(
              child: IconButton(
                tooltip: '下移',
                onPressed: editable && !filtered && index < siblings.length - 1
                    ? () => _placeAt(entry, index + 1)
                    : null,
                icon: const UiIcon(Icons.arrow_downward),
              ),
            ),
            NativeUi(
              child: TextButton(
                onPressed: editable && index > 0
                    ? () => _placeAt(entry, 0)
                    : null,
                child: const Text('置顶'),
              ),
            ),
            NativeUi(
              child: TextButton(
                onPressed: editable && index < siblings.length - 1
                    ? () => _placeAt(entry, siblings.length - 1)
                    : null,
                child: const Text('置底'),
              ),
            ),
          ],
        ),
        if (filtered) const SettingsNote('筛选时暂停相邻上移和下移。置顶、置底及指定位置使用完整分组。'),
        SettingsGroup(
          children: [
            SettingsEntry(
              title: '移到指定项之前',
              icon: Icons.vertical_align_top,
              enabled: editable && siblings.length > 1,
              onTap: () => _anchor(entry, false),
            ),
            SettingsEntry(
              title: '移到指定项之后',
              icon: Icons.vertical_align_bottom,
              enabled: editable && siblings.length > 1,
              onTap: () => _anchor(entry, true),
            ),
            if (profile.mounts.containsKey(entry.id))
              SettingsEntry(
                title: '恢复此项默认',
                icon: Icons.restore,
                enabled: editable,
                onTap: () => _setProfile(profile.withoutMount(entry.id)),
              ),
          ],
        ),
        if (mount.placement == UiPlacement.page)
          NativeUi(
            child: TextButton(
              onPressed: editable
                  ? () => _move(
                      entry,
                      UiMount(
                        placement: UiPlacement.hidden,
                        context: mount.context,
                      ),
                    )
                  : null,
              child: const Text('移除挂载'),
            ),
          ),
      ],
    );
  }
}
