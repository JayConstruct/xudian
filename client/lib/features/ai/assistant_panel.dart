import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules/module_registry.dart';
import '../../data/app_database.dart';
import '../settings/ui_layout_page.dart';
import '../settings/ui_layout_preview.dart';
import '../tasks/application/providers.dart';
import 'assistant_runtime.dart';
import 'settings/ai_connection_page.dart';

class AssistantPanel extends ConsumerStatefulWidget {
  const AssistantPanel({
    super.key,
    required this.registry,
    required this.developerBuilder,
  });

  final ModuleRegistry registry;
  final WidgetBuilder developerBuilder;

  @override
  ConsumerState<AssistantPanel> createState() => _AssistantPanelState();
}

class _AssistantPanelState extends ConsumerState<AssistantPanel> {
  final navigatorKey = GlobalKey<NavigatorState>();
  final inputController = TextEditingController();
  final inputFocus = FocusNode();
  final workspaceRevision = ValueNotifier(0);
  bool developerOpened = false;
  bool granting = false;
  bool approving = false;
  String? localError;

  @override
  void dispose() {
    inputController.dispose();
    inputFocus.dispose();
    workspaceRevision.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() operation) async {
    setState(() => localError = null);
    workspaceRevision.value++;
    try {
      await operation();
    } catch (_) {
      if (mounted) {
        setState(() => localError = '操作失败，请检查连接或重试。');
        workspaceRevision.value++;
      }
    }
  }

  Future<void> _approve(AssistantController controller) async {
    if (approving || controller.busy || !controller.awaitingApproval) return;
    approving = true;
    workspaceRevision.value++;
    try {
      await _run(controller.approvePending);
    } finally {
      if (mounted) {
        approving = false;
        workspaceRevision.value++;
      }
    }
  }

  Future<void> _send(AssistantController controller) async {
    final text = inputController.text.trim();
    if (text.isEmpty ||
        !controller.enabled ||
        controller.busy ||
        controller.awaitingApproval ||
        controller.grant == null ||
        controller.grant!.expired) {
      return;
    }
    inputController.clear();
    await _run(() => controller.send(text));
  }

  Future<void> _grant(AssistantController controller) async {
    if (granting) return;
    setState(() => granting = true);
    workspaceRevision.value++;
    try {
      final grant = await showDialog<AssistantGrant>(
        context: navigatorKey.currentState!.overlay!.context,
        useRootNavigator: false,
        builder: (_) => const _GrantDialog(),
      );
      if (mounted && grant != null && controller.enabled) {
        controller.setGrant(grant);
      }
    } finally {
      if (mounted) {
        setState(() => granting = false);
        workspaceRevision.value++;
      }
    }
  }

  Future<void> _clear(AssistantController controller) async {
    final confirmed = await showDialog<bool>(
      context: navigatorKey.currentState!.overlay!.context,
      useRootNavigator: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空本地对话？'),
        content: const Text('对话和执行记录保存在本机。清空不会撤销已完成的操作。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted && !controller.busy) {
      await _run(controller.clearHistory);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(assistantControllerProvider(widget.registry));
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        developerOpened = developerOpened || controller.advanced;
        return Material(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'AI 助手',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('assistant-stop'),
                      tooltip: '停止执行',
                      onPressed: controller.stop,
                      icon: const Icon(Icons.stop_circle_outlined),
                    ),
                    IconButton(
                      key: const ValueKey('assistant-revoke'),
                      tooltip: '撤销本次授权',
                      onPressed: () => controller.setGrant(null),
                      icon: const Icon(Icons.shield_outlined),
                    ),
                    IconButton(
                      key: const ValueKey('assistant-minimize'),
                      tooltip: '最小化（不停止已批准的执行）',
                      onPressed: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        controller.minimize();
                      },
                      icon: const Icon(Icons.minimize),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ScaffoldMessenger(
                  child: HeroControllerScope.none(
                    child: Navigator(
                      key: navigatorKey,
                      onGenerateRoute: (_) => MaterialPageRoute<void>(
                        builder: (routeContext) =>
                            _workspace(routeContext, controller),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _workspace(BuildContext context, AssistantController controller) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller,
        inputController,
        workspaceRevision,
      ]),
      builder: (context, _) {
        developerOpened = developerOpened || controller.advanced;
        return Scaffold(
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      SegmentedButton<bool>(
                        key: const ValueKey('assistant-mode'),
                        segments: const [
                          ButtonSegment(value: false, label: Text('对话')),
                          ButtonSegment(value: true, label: Text('高级开发')),
                        ],
                        selected: {controller.advanced},
                        onSelectionChanged: controller.enabled
                            ? (selected) {
                                FocusManager.instance.primaryFocus?.unfocus();
                                controller.setAdvanced(selected.single);
                              }
                            : null,
                      ),
                      IconButton(
                        key: const ValueKey('assistant-connection'),
                        tooltip: '模型连接设置',
                        onPressed: () => navigatorKey.currentState!.push<void>(
                          MaterialPageRoute(
                            builder: (_) => const AiConnectionPage(),
                          ),
                        ),
                        icon: const Icon(Icons.settings_ethernet),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: controller.advanced ? 1 : 0,
                  children: [
                    ExcludeFocus(
                      excluding: controller.advanced,
                      child: TickerMode(
                        enabled: !controller.advanced,
                        child: _conversation(context, controller),
                      ),
                    ),
                    ExcludeFocus(
                      excluding: !controller.advanced,
                      child: TickerMode(
                        enabled: controller.advanced,
                        child: developerOpened
                            ? Builder(builder: widget.developerBuilder)
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _conversation(BuildContext context, AssistantController controller) {
    final grant = controller.grant;
    final permitted = grant != null && !grant.expired;
    final canSend =
        permitted &&
        controller.enabled &&
        !controller.busy &&
        !controller.awaitingApproval;
    return ListView(
      key: const PageStorageKey('assistant-conversation'),
      padding: const EdgeInsets.all(12),
      children: [
        const Text('描述目标 → 查看提案 → 批准一次执行。最小化后，对话与执行状态仍会保留。'),
        const SizedBox(height: 8),
        Text(
          !controller.enabled
              ? 'AI 模块已关闭。'
              : controller.awaitingApproval
              ? '等待你检查并批准；准备提案不会改动数据库。'
              : controller.busy
              ? '正在处理；可随时停止或撤销授权。'
              : '就绪',
          key: const ValueKey('assistant-status'),
        ),
        if (permitted)
          Text(
            '已授权发送描述与界面元数据'
            '${grant.shareTasks ? ' · 分享任务字段' : ''}'
            '${grant.writeTasks ? ' · 写入任务' : ''}'
            '${grant.navigate ? ' · 导航' : ''}'
            '${grant.settings ? ' · 设置' : ''}'
            '${grant.layout ? ' · 布局' : ''}'
            '${grant.projectId == null ? ' · 全部项目' : ' · 限定项目'}'
            '${grant.delegated ? ' · 本次会话 30 分钟内最多 20 次操作' : ' · 每次操作需批准'}',
            key: const ValueKey('assistant-grant-status'),
          )
        else
          Text(grant?.expired == true ? '本次授权已过期，请重新授权。' : '发送前需要你的授权。'),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              key: const ValueKey('assistant-grant'),
              onPressed: !controller.enabled || granting
                  ? null
                  : () => _grant(controller),
              icon: const Icon(Icons.verified_user_outlined),
              label: Text(permitted ? '调整授权' : '授权发送'),
            ),
            TextButton.icon(
              key: const ValueKey('assistant-undo'),
              onPressed: controller.canUndo && !controller.busy
                  ? () => _run(controller.undoLast)
                  : null,
              icon: const Icon(Icons.undo),
              label: const Text('撤销上次执行'),
            ),
            TextButton(
              key: const ValueKey('assistant-clear'),
              onPressed: controller.busy || controller.awaitingApproval
                  ? null
                  : () => _clear(controller),
              child: const Text('清空记录'),
            ),
          ],
        ),
        if (controller.messages.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('例如：帮我规划今天的任务，先展示变更，不要直接修改。'),
          ),
        for (final message in controller.messages)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_roleLabel(message.role)),
                  const SizedBox(height: 4),
                  SelectableText(message.text),
                ],
              ),
            ),
          ),
        if (controller.error != null || localError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SelectableText(
              controller.error ?? localError!,
              key: const ValueKey('assistant-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        for (final preview in controller.pending)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preview.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (final change in preview.changes)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('• $change'),
                    ),
                  if (preview.layout != null)
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final desktop in [false, true])
                          TextButton(
                            onPressed: () => showDialog<void>(
                              context: context,
                              useRootNavigator: false,
                              builder: (_) => SingleChildScrollView(
                                child: UiLayoutPreview(
                                  registry: widget.registry.ui,
                                  profile: preview.layout!.profile(desktop),
                                  desktop: desktop,
                                ),
                              ),
                            ),
                            child: Text(desktop ? '预览宽屏' : '预览窄屏'),
                          ),
                        TextButton(
                          onPressed: controller.busy
                              ? null
                              : () => navigatorKey.currentState!.push<void>(
                                  MaterialPageRoute(
                                    builder: (_) => UiLayoutPage(
                                      registry: widget.registry,
                                      initialDraft: preview.layout,
                                    ),
                                  ),
                                ),
                          child: const Text('手动编辑草稿'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        if (controller.pending.isNotEmpty) ...[
          const Text('检查以上所有变更后，批准本次提案；未批准不会执行。'),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                key: const ValueKey('assistant-approve'),
                onPressed:
                    controller.awaitingApproval &&
                        !controller.busy &&
                        !approving &&
                        permitted &&
                        controller.enabled
                    ? () => _approve(controller)
                    : null,
                child: const Text('批准一次'),
              ),
              OutlinedButton(
                key: const ValueKey('assistant-reject'),
                onPressed: controller.rejectPending,
                child: const Text('拒绝提案'),
              ),
            ],
          ),
        ],
        if (controller.audit.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('执行记录（仅本机保存）', style: Theme.of(context).textTheme.titleSmall),
          for (final item in controller.audit)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('${item.title} · ${item.status}'),
            ),
        ],
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('assistant-input'),
          controller: inputController,
          focusNode: inputFocus,
          enabled: controller.enabled && !controller.busy,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: '描述你想做的事',
            hintText: '可先写草稿；授权后才会发送',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: const ValueKey('assistant-send'),
            onPressed: canSend && inputController.text.trim().isNotEmpty
                ? () => _send(controller)
                : null,
            icon: const Icon(Icons.send_outlined),
            label: const Text('发送'),
          ),
        ),
      ],
    );
  }

  String _roleLabel(String role) {
    if (role == 'user' || role.endsWith('.user')) return '你';
    if (role == 'tool' || role.endsWith('.tool')) return '工具结果';
    if (role == 'system' || role.endsWith('.system')) return '状态';
    return '助手';
  }
}

class _GrantDialog extends ConsumerStatefulWidget {
  const _GrantDialog();

  @override
  ConsumerState<_GrantDialog> createState() => _GrantDialogState();
}

class _GrantDialogState extends ConsumerState<_GrantDialog> {
  bool shareTasks = false;
  bool writeTasks = false;
  bool navigate = true;
  bool settings = false;
  bool layout = false;
  bool delegated = false;
  String? projectId;
  List<Project>? projects;
  bool loading = true;
  String? projectError;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    setState(() {
      loading = true;
      projectError = null;
    });
    try {
      final database = await ref.read(databaseProvider.future);
      final loaded = await (database.select(
        database.projects,
      )..where((row) => row.archivedAt.isNull())).get();
      if (mounted) setState(() => projects = loaded);
    } catch (_) {
      if (mounted) setState(() => projectError = '读取本地项目失败；请重试后再授权任务访问。');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.all(8),
    title: const Text('授权本次 AI 会话'),
    scrollable: true,
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '点击授权后，仅在你发送时，才会向配置的模型服务发送你的描述和界面元数据（模块、页面、入口及布局）。授权前不会联系模型。',
          ),
          const SizedBox(height: 8),
          const Text('任务字段默认不分享；以下数据访问与操作权限分别选择。授权仅本次会话有效，不会持久保存。'),
          CheckboxListTile(
            key: const ValueKey('assistant-share-tasks'),
            contentPadding: EdgeInsets.zero,
            title: const Text('分享任务字段'),
            subtitle: const Text('允许发送范围内任务的标题、优先级、日期与状态；不发送备注或密钥。'),
            value: shareTasks,
            onChanged: (value) => setState(() => shareTasks = value ?? false),
          ),
          CheckboxListTile(
            key: const ValueKey('assistant-write-tasks'),
            contentPadding: EdgeInsets.zero,
            title: const Text('允许任务写入'),
            subtitle: const Text('直接操作仅限选定范围，还需开启字段分享；任务变更可能触发已启用的自动化规则。'),
            value: writeTasks,
            onChanged: (value) => setState(() => writeTasks = value ?? false),
          ),
          if (loading)
            const Text('正在读取本地项目…')
          else if (projectError != null) ...[
            Text(projectError!),
            TextButton(onPressed: _loadProjects, child: const Text('重试项目读取')),
          ] else
            DropdownButtonFormField<String>(
              key: const ValueKey('assistant-project-scope'),
              initialValue: projectId ?? '',
              isExpanded: true,
              decoration: const InputDecoration(labelText: '任务访问 / 写入范围'),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('全部项目（含未归属任务）', overflow: TextOverflow.ellipsis),
                ),
                for (final project in projects ?? <Project>[])
                  DropdownMenuItem(
                    value: project.id,
                    child: Text(project.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => projectId = value == '' ? null : value),
            ),
          CheckboxListTile(
            key: const ValueKey('assistant-allow-navigation'),
            contentPadding: EdgeInsets.zero,
            title: const Text('允许应用内导航'),
            value: navigate,
            onChanged: (value) => setState(() => navigate = value ?? false),
          ),
          CheckboxListTile(
            key: const ValueKey('assistant-allow-settings'),
            contentPadding: EdgeInsets.zero,
            title: const Text('允许修改支持的应用设置'),
            value: settings,
            onChanged: (value) => setState(() => settings = value ?? false),
          ),
          CheckboxListTile(
            key: const ValueKey('assistant-allow-layout'),
            contentPadding: EdgeInsets.zero,
            title: const Text('允许修改入口与页面布局'),
            value: layout,
            onChanged: (value) => setState(() => layout = value ?? false),
          ),
          CheckboxListTile(
            key: const ValueKey('assistant-delegated'),
            contentPadding: EdgeInsets.zero,
            title: const Text('有限委托：本次会话 30 分钟，最多 20 次操作'),
            subtitle: const Text('在所选权限和项目范围内自动执行支持的操作；未勾选时逐次批准。'),
            value: delegated,
            onChanged: (value) => setState(() => delegated = value ?? false),
          ),
          const Text(
            '不预先批准删除等破坏性操作、外部操作或密钥访问；当前工具不提供这些能力。你可随时停止执行或撤销授权。对话与状态仅保存在本机。',
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const ValueKey('assistant-confirm-grant'),
        onPressed: (shareTasks || writeTasks) && (loading || projects == null)
            ? null
            : () => Navigator.pop(
                context,
                AssistantGrant(
                  shareTasks: shareTasks,
                  writeTasks: writeTasks,
                  navigate: navigate,
                  settings: settings,
                  layout: layout,
                  delegated: delegated,
                  projectId: projectId,
                  expiresAt: delegated
                      ? DateTime.now().add(const Duration(minutes: 30))
                      : null,
                ),
              ),
        child: const Text('授权'),
      ),
    ],
  );
}
