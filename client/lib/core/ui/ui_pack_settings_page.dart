import 'ui_icon.dart';
import 'native_ui.dart';
import 'ui_toast.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui_select_field.dart';
import 'ui_surfaces.dart';
import 'ui_feedback.dart';
import '../../features/settings/settings_widgets.dart';
import '../contracts/json_values.dart';
import '../module_host/host_providers.dart';
import '../modules/module_registry.dart';
import 'ui_component.dart';
import 'ui_pack.dart';
import 'ui_pack_providers.dart';

/// Drafts use the current UI. The reset control also works without a UI pack.
class UiPackSettingsPage extends ConsumerStatefulWidget {
  const UiPackSettingsPage({super.key, this.registry});
  final ModuleRegistry? registry;

  @override
  ConsumerState<UiPackSettingsPage> createState() => _UiPackSettingsPageState();
}

class _UiPackSettingsPageState extends ConsumerState<UiPackSettingsPage> {
  UiSelection? draft, baseline;
  bool saving = false;
  String? error;

  bool get dirty =>
      draft != null &&
      baseline != null &&
      canonicalJson(draft!.toJson()) != canonicalJson(baseline!.toJson());

  Future<void> _save({bool restore = false}) async {
    setState(() => saving = true);
    try {
      final controller = ref.read(uiSelectionProvider.notifier);
      if (restore) {
        await controller.restoreDefaults();
      } else {
        await controller.saveIfUnchanged(draft!, expected: baseline!);
      }
      if (!mounted) return;
      setState(() {
        baseline = draft = restore ? UiSelection() : draft;
        error = null;
      });
      AppToast.show(
        context,
        message: restore ? '已恢复默认界面，业务数据保留' : '界面风格已保存',
        kind: 'success',
      );
    } on StateError catch (failure) {
      if (mounted) setState(() => error = '${failure.message}；草稿保留');
    } catch (_) {
      if (mounted) setState(() => error = '保存失败，当前风格与草稿保留，请重试');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _reload() async {
    setState(() => saving = true);
    try {
      ref.invalidate(uiSelectionProvider);
      final latest = await ref.read(uiSelectionProvider.future);
      if (mounted) {
        setState(() {
          baseline = draft = latest;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = '读取失败，草稿保留，请重试');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stored = ref.watch(uiSelectionProvider);
    final packs =
        ref.watch(uiPackRegistryProvider).asData?.value ??
        const <String, UiPackDefinition>{};
    final host = ref.watch(moduleHostProvider).asData?.value;
    final packNames = {
      for (final id in packs.keys) id: host?.instances[id]?.package.title ?? id,
    };
    final modules = <String, String>{
      for (final module in widget.registry?.modules ?? [])
        if (!packs.containsKey(module.manifest.id))
          module.manifest.id: module.manifest.id,
      for (final module in widget.registry?.builtins ?? [])
        if (widget.registry!.isEnabled(module.id)) module.id: module.title,
      if (host != null)
        for (final instance in host.instances.values)
          if (!instance.package.isUiPack)
            instance.package.id: instance.package.title,
      for (final id
          in (draft ?? stored.asData?.value)?.modulePackIds.keys ?? <String>[])
        if (host?.instances[id] case final instance?)
          id: instance.package.title,
    };
    for (final id
        in (draft ?? stored.asData?.value)?.modulePackIds.keys ?? <String>[]) {
      modules.putIfAbsent(id, () => id);
    }
    final moduleIcons = {
      for (final entry in (widget.registry?.ui.entries ?? []).reversed)
        if (!entry.content) entry.moduleId: entry.icon,
    };
    final ids = modules.keys.toList()..sort();
    return DetailPage(
      title: '界面风格',
      settingsStyle: true,
      child: stored.when(
        loading: () =>
            const Center(child: NativeUi(child: CircularProgressIndicator())),
        error: (_, _) => Center(
          child: AppErrorState(
            message: '无法读取界面风格，请重试',
            onRetry: () => ref.invalidate(uiSelectionProvider),
          ),
        ),
        data: (selection) {
          if (draft == null) baseline = draft = selection;
          return SettingsList(
            footer: Row(
              children: [
                Expanded(
                  child: NativeUi(
                    child: OutlinedButton(
                      onPressed: saving
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => UiPackPreviewPage(
                                  packs: packs,
                                  selection: draft!,
                                  moduleIds: ids,
                                ),
                              ),
                            ),
                      child: const Text('预览草稿'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: NativeUi(
                    child: FilledButton(
                      onPressed: saving || !dirty ? null : () => _save(),
                      child: Text(saving ? '保存中…' : '保存风格'),
                    ),
                  ),
                ),
              ],
            ),
            children: [
              SettingsGroup(
                title: '全局风格',
                children: [
                  _picker(
                    '全局界面',
                    draft!.globalPackId,
                    packs,
                    packNames,
                    (id) => setState(() {
                      draft = draft!.copyWith(globalPackId: id);
                      error = null;
                    }),
                  ),
                ],
              ),
              SettingsGroup(
                title: '模块专属界面',
                children: [
                  if (ids.isEmpty) const ListTile(title: Text('当前没有可单独设置的模块。')),
                  for (final id in ids)
                    _picker(
                      modules[id]!,
                      draft!.modulePackIds[id] ?? '',
                      packs,
                      packNames,
                      (packId) {
                        final overrides = Map<String, String>.of(
                          draft!.modulePackIds,
                        );
                        if (packId.isEmpty) {
                          overrides.remove(id);
                        } else {
                          overrides[id] = packId;
                        }
                        setState(() {
                          draft = draft!.copyWith(modulePackIds: overrides);
                          error = null;
                        });
                      },
                      inherit: true,
                      fieldKey: id,
                      icon: moduleIcons[id] ?? Icons.extension_outlined,
                    ),
                ],
              ),
              UiPackScope(
                defaultOnly: true,
                child: SettingsGroup(
                  title: '恢复',
                  children: [
                    SettingsEntry(
                      title: '恢复默认界面',
                      subtitle: '重置界面风格选择，保留业务数据。',
                      icon: Icons.restore,
                      enabled: !saving,
                      onTap: () => _save(restore: true),
                      protected: true,
                    ),
                  ],
                ),
              ),
              if (error != null) ...[
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed: saving ? null : _reload,
                  child: const Text('重新读取已保存配置'),
                ),
              ],
              const SettingsNote('风格修改先存为草稿，保存后应用。'),
            ],
          );
        },
      ),
    );
  }

  Widget _picker(
    String label,
    String value,
    Map<String, UiPackDefinition> packs,
    Map<String, String> packNames,
    ValueChanged<String> change, {
    bool inherit = false,
    String? fieldKey,
    IconData icon = Icons.layers_outlined,
  }) {
    final packIds = packs.keys.toList()..sort();
    final options = <String, String>{
      if (inherit) '': '跟随全局',
      defaultUiPackId: '内置默认',
      for (final id in packIds) id: packNames[id]!,
      if (value.isNotEmpty &&
          value != defaultUiPackId &&
          !packs.containsKey(value))
        value: '$value（不可用，自动回退）',
    };
    return SettingsEntry(
      tileKey: ValueKey((fieldKey ?? 'global', value)),
      icon: icon,
      title: label,
      subtitle: options[value] ?? value,
      trailing: const UiIcon(Icons.expand_more, size: 18),
      enabled: !saving,
      onTap: () async {
        final result = await showSettingsModal<String>(
          context: context,
          builder: (context) => SettingsSheet(
            title: Text(inherit ? '$label的界面风格' : '选择全局风格'),
            expandedActions: true,
            content: SingleChildScrollView(
              child: SettingsGroupSurface(
                children: [
                  for (final entry in options.entries)
                    SettingsEntry(
                      title: entry.value,
                      subtitle: switch (entry.key) {
                        '' => '使用已保存的全局风格',
                        final id when packs.containsKey(id) =>
                          '$id · ${packs[id]!.version}',
                        _ => null,
                      },
                      icon: switch (entry.key) {
                        '' => Icons.sync,
                        defaultUiPackId => Icons.palette_outlined,
                        _ => Icons.layers_outlined,
                      },
                      trailing: value == entry.key
                          ? UiIcon(
                              Icons.check_rounded,
                              size: 19,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : const SizedBox.shrink(),
                      selected: value == entry.key,
                      onTap: () => Navigator.pop(context, entry.key),
                    ),
                ],
              ),
            ),
            actions: [
              NativeUi(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ),
            ],
          ),
        );
        if (result != null && mounted) change(result);
      },
    );
  }
}

/// This preview intentionally has no host operations or business repositories.
class UiPackPreviewPage extends StatefulWidget {
  const UiPackPreviewPage({
    super.key,
    required this.packs,
    required this.selection,
    this.moduleIds = const [],
  });
  final Map<String, UiPackDefinition> packs;
  final UiSelection selection;
  final List<String> moduleIds;

  @override
  State<UiPackPreviewPage> createState() => _UiPackPreviewPageState();
}

class _UiPackPreviewPageState extends State<UiPackPreviewPage> {
  bool wide = false, dark = false;
  String template = 'list';
  String? moduleId;
  final title = TextEditingController(text: '示例任务');
  bool done = false;

  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UiPackScope(
    defaultOnly: true,
    child: NativeUi(
      child: Scaffold(
        appBar: AppBar(title: const Text('界面预览 · 模拟数据')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                NativeUi(
                  child: FilterChip(
                    label: const Text('宽屏'),
                    selected: wide,
                    onSelected: (value) => setState(() => wide = value),
                  ),
                ),
                NativeUi(
                  child: FilterChip(
                    label: const Text('深色'),
                    selected: dark,
                    onSelected: (value) => setState(() => dark = value),
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: AppSelectField<String>(
                    key: const ValueKey('ui-preview-template'),
                    label: '页面类型',
                    value: template,
                    options: [
                      for (final entry in const {
                        'list': '列表页',
                        'form': '表单页',
                        'settings': '设置页',
                        'detail': '详情页',
                        'timeGrid': '时间网格页',
                      }.entries)
                        AppSelectOption(value: entry.key, label: entry.value),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => template = value);
                    },
                  ),
                ),
                if (widget.moduleIds.isNotEmpty)
                  SizedBox(
                    width: 220,
                    child: AppSelectField<String>(
                      label: '预览模块',
                      value: moduleId ?? '',
                      options: [
                        const AppSelectOption(value: '', label: '全局界面'),
                        for (final id in widget.moduleIds)
                          AppSelectOption(value: id, label: id),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(
                            () => moduleId = value.isEmpty ? null : value,
                          );
                        }
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('按钮和输入仅改变本次演示；不会创建任务、课程或修改已保存风格。'),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: wide ? 900 : 360,
                  child: Theme(
                    data: ThemeData(
                      brightness: dark ? Brightness.dark : Brightness.light,
                      useMaterial3: true,
                    ),
                    child: Builder(
                      builder: (context) => MediaQuery(
                        data: MediaQuery.of(context)
                            .copyWith(size: Size(wide ? 900 : 360, 640)),
                        child: UiPackScope(
                          previewPacks: widget.packs,
                          previewSelection: widget.selection,
                          child: Material(
                            child: Column(
                              children: [
                                UiComponent(
                                  ref: 'ui.chrome.header@1',
                                  fallback: const ListTile(
                                    title: Text('示例工作区'),
                                    trailing: UiIcon(Icons.settings),
                                  ),
                                ),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (wide)
                                      SizedBox(
                                        width: 150,
                                        child: UiComponent(
                                          ref: 'ui.chrome.sidebar@1',
                                          fallback: const Column(
                                            children: [
                                              ListTile(title: Text('今天')),
                                              ListTile(title: Text('项目')),
                                            ],
                                          ),
                                        ),
                                      ),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: UiPackScope(
                                          moduleId: moduleId,
                                          previewPacks: widget.packs,
                                          previewSelection: widget.selection,
                                          child: _template(),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (!wide)
                                  UiComponent(
                                    ref: 'ui.chrome.bottomNav@1',
                                    fallback: const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceAround,
                                        children: [
                                          Text('今天'),
                                          Text('项目'),
                                          Text('模块'),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _template() {
    final save = UiComponent(
      ref: 'ui.button@1',
      props: const {'label': '保存示例', 'disabled': false},
      events: {
        'press': (_) =>
            AppToast.show(context, message: '模拟保存完成', kind: 'success'),
      },
      fallback: FilledButton(
        onPressed: () =>
            AppToast.show(context, message: '模拟保存完成', kind: 'success'),
        child: const Text('保存示例'),
      ),
    );
    final input = NativeUi(
      child: TextField(
        controller: title,
        decoration: const InputDecoration(labelText: '标题'),
      ),
    );
    final fields = Column(
      children: [
        UiComponent(
          ref: 'ui.input@1',
          props: const {'label': '标题'},
          slots: {'control': input},
          fallback: input,
        ),
        NativeUi(
          child: SwitchListTile(
            title: const Text('已完成'),
            value: done,
            onChanged: (value) => setState(() => done = value),
          ),
        ),
      ],
    );
    final items = Column(
      children: [
        for (final label in ['整理本周计划', '阅读一篇文章', '检查项目进度'])
          NativeUi(
            child: CheckboxListTile(
              title: Text(label),
              value: done,
              onChanged: (value) => setState(() => done = value!),
            ),
          ),
      ],
    );
    final detail = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.text, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 12),
        const Text('这是一条用于查看布局和样式的模拟详情。'),
      ],
    );
    final grid = Table(
      border: TableBorder.all(color: Colors.grey),
      children: [
        for (final cells in [
          ['时间', '周一', '周二'],
          ['09:00', '示例课程', ''],
          ['10:00', '', '讨论'],
        ])
          TableRow(
            children: [
              for (final value in cells)
                Padding(padding: const EdgeInsets.all(8), child: Text(value)),
            ],
          ),
      ],
    );
    final slots = switch (template) {
      'form' => <String, Widget>{'fields': fields, 'actions': save},
      'settings' => <String, Widget>{'sections': fields},
      'detail' => <String, Widget>{'content': detail, 'actions': save},
      'timeGrid' => <String, Widget>{'grid': grid},
      _ => <String, Widget>{'items': items},
    };
    return UiComponent(
      ref: 'ui.page.$template@1',
      props: const {'title': '示例页面'},
      slots: slots,
      fallback: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('示例页面'),
          const SizedBox(height: 12),
          ...slots.values,
        ],
      ),
    );
  }
}
