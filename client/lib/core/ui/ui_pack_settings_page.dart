import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_select_field.dart';
import '../../app/design_system.dart';
import '../../features/settings/settings_widgets.dart';
import '../contracts/json_values.dart';
import '../module_host/host_providers.dart';
import '../modules/module_registry.dart';
import 'ui_component.dart';
import 'ui_pack.dart';
import 'ui_pack_providers.dart';

/// Recovery controls always use the built-in widgets, even when a pack fails.
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(restore ? '已恢复默认界面，业务数据保留' : '界面风格已保存')),
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
    final modules = <String, String>{
      for (final module in widget.registry?.modules ?? [])
        if (!packs.containsKey(module.manifest.id))
          module.manifest.id: module.manifest.id,
      if (host != null)
        for (final instance in host.instances.values)
          if (!instance.package.isUiPack)
            instance.package.id:
                instance.package.manifest['name'] as String? ??
                instance.package.id,
      for (final id
          in (draft ?? stored.asData?.value)?.modulePackIds.keys ?? <String>[])
        id: host?.instances[id]?.package.manifest['name'] as String? ?? id,
    };
    final ids = modules.keys.toList()..sort();
    return UiPackScope(
      defaultOnly: true,
      child: DetailPage(
        title: '界面风格',
        child: stored.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (failure, _) => Center(child: Text('无法读取界面风格：$failure')),
          data: (selection) {
            if (draft == null) baseline = draft = selection;
            return SettingsList(
              children: [
                const SettingsNote('选择全局风格，也可为模块单独设置。修改先保留为草稿，保存后应用。'),
                const SectionHeading(title: '全局风格'),
                ContentSurface(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _picker('全局界面', draft!.globalPackId, packs, (id) {
                        setState(() {
                          draft = draft!.copyWith(globalPackId: id);
                          error = null;
                        });
                      }),
                      if (packs[draft!.globalPackId] case final pack?)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(_packSummary(pack)),
                        ),
                      if (draft!.globalPackId != 'app.ui.default' &&
                          !packs.containsKey(draft!.globalPackId))
                        const Text('所选全局 UI 包不可用，当前使用默认界面；重新启用后恢复。'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const SectionHeading(title: '模块专属界面'),
                const SettingsNote('默认跟随全局风格。单独选择后，仅影响对应模块。'),
                if (ids.isEmpty) const SettingsNote('当前没有可单独设置的模块。'),
                if (ids.isNotEmpty)
                  ContentSurface(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        for (final id in ids) ...[
                          const SizedBox(height: 12),
                          _picker(
                            modules[id]!,
                            draft!.modulePackIds[id] ?? '',
                            packs,
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
                                draft = draft!.copyWith(
                                  modulePackIds: overrides,
                                );
                                error = null;
                              });
                            },
                            inherit: true,
                            fieldKey: id,
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                const SectionHeading(title: '保存与恢复'),
                if (error != null) ...[
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton(
                    onPressed: saving ? null : _reload,
                    child: const Text('重新读取已保存配置'),
                  ),
                ],
                ContentSurface(
                  padding: const EdgeInsets.all(18),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton(
                        onPressed: saving || !dirty ? null : () => _save(),
                        child: Text(saving ? '保存中…' : '保存风格'),
                      ),
                      OutlinedButton(
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
                      TextButton.icon(
                        onPressed: saving ? null : () => _save(restore: true),
                        icon: const Icon(Icons.restore),
                        label: const Text('恢复默认界面'),
                      ),
                    ],
                  ),
                ),
                const SettingsNote('预览仅使用模拟数据。退出预览不会保存；恢复默认仅重置界面选择，保留业务数据。'),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _picker(
    String label,
    String value,
    Map<String, UiPackDefinition> packs,
    ValueChanged<String> change, {
    bool inherit = false,
    String? fieldKey,
  }) {
    final packIds = packs.keys.toList()..sort();
    final options = <String, String>{
      if (inherit) '': '跟随全局',
      'app.ui.default': '内置默认',
      for (final id in packIds) id: '$id · ${packs[id]!.version}',
      if (value.isNotEmpty &&
          value != 'app.ui.default' &&
          !packs.containsKey(value))
        value: '$value（不可用，自动回退）',
    };
    return AppSelectField<String>(
      key: ValueKey((fieldKey ?? 'global', value)),
      value: value,
      label: label,
      options: [
        for (final entry in options.entries)
          AppSelectOption(value: entry.key, label: entry.value),
      ],
      onChanged: saving
          ? null
          : (value) {
              if (value != null) change(value);
            },
    );
  }

  String _packSummary(UiPackDefinition pack) {
    final labels = <String>{};
    for (final ref in pack.components.keys) {
      labels.add(switch (ref) {
        'ui.button@1' => '按钮',
        'ui.card@1' => '内容卡片',
        'ui.page.list@1' => '列表页',
        'ui.page.form@1' => '表单页',
        'ui.page.settings@1' => '设置页',
        'ui.page.detail@1' => '详情页',
        'ui.page.timeGrid@1' => '时间网格页',
        'ui.chrome.header@1' => '顶栏',
        'ui.chrome.bottomNav@1' => '底栏',
        'ui.chrome.sidebar@1' => '侧栏',
        _ when ref.startsWith('ui.') => '通用控件',
        _ => '扩展组件',
      });
    }
    return '包含：${[if (pack.tokens.isNotEmpty) '颜色与样式', ...labels].join('、')}';
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
              FilterChip(
                label: const Text('宽屏'),
                selected: wide,
                onSelected: (value) => setState(() => wide = value),
              ),
              FilterChip(
                label: const Text('深色'),
                selected: dark,
                onSelected: (value) => setState(() => dark = value),
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
                        setState(() => moduleId = value.isEmpty ? null : value);
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
                                  trailing: Icon(Icons.settings),
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
  );

  Widget _template() {
    final save = UiComponent(
      ref: 'ui.button@1',
      props: const {'label': '保存示例', 'disabled': false},
      events: {
        'press': (_) =>
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('模拟保存完成'))),
      },
      fallback: FilledButton(
        onPressed: () =>
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('模拟保存完成'))),
        child: const Text('保存示例'),
      ),
    );
    final input = TextField(
      controller: title,
      decoration: const InputDecoration(labelText: '标题'),
    );
    final fields = Column(
      children: [
        UiComponent(
          ref: 'ui.input@1',
          props: const {'label': '标题'},
          slots: {'control': input},
          fallback: input,
        ),
        SwitchListTile(
          title: const Text('已完成'),
          value: done,
          onChanged: (value) => setState(() => done = value),
        ),
      ],
    );
    final items = Column(
      children: [
        for (final label in ['整理本周计划', '阅读一篇文章', '检查项目进度'])
          CheckboxListTile(
            title: Text(label),
            value: done,
            onChanged: (value) => setState(() => done = value!),
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
