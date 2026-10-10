import 'ui_composition.dart';
import 'ui_registry.dart';

List<UiEntryRegistration> orderedEntries(
  UiRegistry registry,
  UiMount Function(UiEntryRegistration) mountFor,
  bool Function(UiEntryRegistration) include,
) {
  final catalog = registry.entries;
  final originalOrder = {
    for (var index = 0; index < catalog.length; index++)
      catalog[index].id: index,
  };
  return catalog.where(include).toList()..sort((first, second) {
    final order = mountFor(first).order.compareTo(mountFor(second).order);
    return order == 0
        ? originalOrder[first.id]!.compareTo(originalOrder[second.id]!)
        : order;
  });
}

enum UiMountIssue {
  targetUnavailable,
  hostUnavailable,
  slotUnavailable,
  privateSlot,
  incompatibleSlot,
  missingContext,
  capacityExceeded,
  invalidContext,
  contextReadFailed,
  contentCycle,
}

class UiMountDiagnostic {
  const UiMountDiagnostic(this.issue, this.message);

  final UiMountIssue issue;
  final String message;

  bool get needsContext =>
      issue == UiMountIssue.missingContext ||
      issue == UiMountIssue.invalidContext;

  String get suggestion => switch (issue) {
    UiMountIssue.targetUnavailable => '检查模块是否启用，或移动、隐藏此入口。',
    UiMountIssue.hostUnavailable ||
    UiMountIssue.slotUnavailable => '重新选择可用的页面槽位，或恢复模块默认位置。',
    UiMountIssue.privateSlot ||
    UiMountIssue.incompatibleSlot => '移动到兼容的公开槽位；公开槽位不会授予业务权限。',
    UiMountIssue.missingContext => '绑定任务或项目；子页面也可由宿主在运行时提供。',
    UiMountIssue.capacityExceeded => '调整槽位内顺序，或将部分贡献移动、隐藏。',
    UiMountIssue.invalidContext => '重新绑定有效对象，或等待原对象恢复。',
    UiMountIssue.contextReadFailed => '稍后重试；无需删除挂载配置。',
    UiMountIssue.contentCycle => '将循环分支移动到其他位置，或暂时隐藏。',
  };
}

UiMountDiagnostic? mountDiagnostic(
  UiRegistry registry,
  UiEntryRegistration entry,
  UiMount mount, {
  PageContext context = const PageContext(),
  bool checkContext = true,
}) {
  final page = registry.page(entry.pageId);
  if (page == null) {
    return const UiMountDiagnostic(
      UiMountIssue.targetUnavailable,
      '目标页面不可用，模块可能已停用或移除',
    );
  }
  if (entry.content &&
      mount.placement != UiPlacement.page &&
      mount.placement != UiPlacement.hidden) {
    return const UiMountDiagnostic(
      UiMountIssue.incompatibleSlot,
      '内容贡献只能放入页面内容槽位',
    );
  }
  if (mount.placement == UiPlacement.page) {
    final host = registry.page(mount.pageId ?? '');
    if (host == null) {
      return const UiMountDiagnostic(UiMountIssue.hostUnavailable, '宿主页面不可用');
    }
    final slots = host.slots.where((slot) => slot.id == mount.slotId);
    if (slots.isEmpty) {
      return const UiMountDiagnostic(UiMountIssue.slotUnavailable, '目标槽位已移除');
    }
    final slot = slots.first;
    if (host.moduleId != entry.moduleId && !slot.isPublic) {
      return const UiMountDiagnostic(UiMountIssue.privateSlot, '此槽位未公开给其他模块');
    }
    if ((slot.kind == PageSlotKind.entries) == entry.content) {
      return const UiMountDiagnostic(
        UiMountIssue.incompatibleSlot,
        '入口与内容槽位类型不匹配',
      );
    }
    if (checkContext &&
        !context.merge(mount.context).satisfies(slot.requiredContext)) {
      return UiMountDiagnostic(
        UiMountIssue.missingContext,
        '槽位缺少上下文：${slot.requiredContext.join('、')}',
      );
    }
  }
  if (checkContext &&
      !context.merge(mount.context).satisfies(page.requiredContext)) {
    return UiMountDiagnostic(
      UiMountIssue.missingContext,
      '页面缺少上下文：${page.requiredContext.join('、')}',
    );
  }
  return null;
}

String? mountProblem(
  UiRegistry registry,
  UiEntryRegistration entry,
  UiMount mount, {
  PageContext context = const PageContext(),
  bool checkContext = true,
}) => mountDiagnostic(
  registry,
  entry,
  mount,
  context: context,
  checkContext: checkContext,
)?.message;

UiMountDiagnostic? layoutEntryDiagnostic(
  UiRegistry registry,
  UiEntryRegistration entry,
  UiMount Function(UiEntryRegistration) mountFor,
) {
  final mount = mountFor(entry);
  if (mount.placement == UiPlacement.hidden) return null;
  final structural = mountDiagnostic(
    registry,
    entry,
    mount,
    checkContext: false,
  );
  if (structural != null) return structural;
  if (mount.placement == UiPlacement.page) {
    final slot = registry
        .page(mount.pageId!)!
        .slots
        .firstWhere((slot) => slot.id == mount.slotId);
    if (slot.capacity != null) {
      final siblings = orderedEntries(registry, mountFor, (candidate) {
        final target = mountFor(candidate);
        return target.placement == UiPlacement.page &&
            target.pageId == mount.pageId &&
            target.slotId == mount.slotId;
      });
      if (siblings.indexWhere((candidate) => candidate.id == entry.id) >=
          slot.capacity!) {
        return const UiMountDiagnostic(
          UiMountIssue.capacityExceeded,
          '槽位容量不足，挂载配置已保留',
        );
      }
    }
  }
  return mountDiagnostic(registry, entry, mount);
}

int navigationVisibleCount({
  required int total,
  required int? limit,
  required double width,
  required double textScale,
  required bool desktop,
}) {
  if (total == 0) return 0;
  final requested = limit == null ? total : limit.clamp(1, total);
  if (desktop) return requested;
  final capacity = (width / (64 * textScale.clamp(1, 2))).floor().clamp(
    2,
    total + 1,
  );
  if (total <= requested && total <= capacity) return total;
  return requested.clamp(1, capacity - 1);
}

int headerVisibleCount({required double width, required bool desktop}) =>
    ((width - (desktop ? 216 : 0) - 140) / 48).floor().clamp(
      0,
      desktop ? 4 : 2,
    );

List<String> compositionWarnings(
  UiRegistry registry,
  UiMount Function(UiEntryRegistration) mountFor,
) {
  final graph = <String, List<String>>{};
  for (final entry in registry.entries.where((entry) => entry.content)) {
    final mount = mountFor(entry);
    if (mount.placement == UiPlacement.page &&
        mount.pageId != null &&
        mountProblem(registry, entry, mount, checkContext: false) == null) {
      graph.putIfAbsent(mount.pageId!, () => []).add(entry.pageId);
    }
  }
  final warnings = <String>{};
  final completed = <String>{};
  final active = <String>{};
  for (final root in graph.keys) {
    if (completed.contains(root)) continue;
    final stack = <(String, int)>[(root, 0)];
    active.add(root);
    while (stack.isNotEmpty) {
      final node = stack.last;
      final children = graph[node.$1] ?? const <String>[];
      if (node.$2 >= children.length) {
        completed.add(node.$1);
        active.remove(node.$1);
        stack.removeLast();
        continue;
      }
      stack[stack.length - 1] = (node.$1, node.$2 + 1);
      final child = children[node.$2];
      if (active.contains(child)) {
        warnings.add(
          '存在循环内容嵌套：${[...stack.map((frame) => frame.$1), child].join(' → ')}；对应分支将停止展开',
        );
      } else if (!completed.contains(child)) {
        stack.add((child, 0));
        active.add(child);
        if (stack.length == 8) warnings.add('嵌套达到 8 层，建议调整布局；没有深度硬上限');
      }
    }
  }
  return warnings.toList();
}
