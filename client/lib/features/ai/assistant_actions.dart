import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/contracts/json_values.dart';
import '../../core/modules/module_context.dart';
import '../../core/modules/module_registry.dart';
import '../../core/ui/app_navigation.dart';
import '../../core/ui/page_context_validation.dart';
import '../../core/ui/ui_composition.dart';
import '../../core/ui/ui_layout_resolver.dart';
import '../../core/ui/ui_page_host.dart';
import '../../data/app_database.dart';
import '../settings/app_preferences.dart';
import '../settings/settings_page.dart';
import '../settings/ui_layout.dart';
import '../settings/ui_layout_page.dart';
import '../tasks/application/providers.dart';
import '../tasks/domain/task_snapshot.dart';
import 'provider/assistant_model.dart';

class AssistantGrant {
  AssistantGrant({
    this.shareTasks = false,
    this.writeTasks = false,
    this.navigate = true,
    this.settings = false,
    this.layout = false,
    this.delegated = false,
    this.projectId,
    DateTime? expiresAt,
  }) : expiresAt = expiresAt ?? DateTime.now().add(const Duration(minutes: 30));

  final bool shareTasks;
  final bool writeTasks;
  final bool navigate;
  final bool settings;
  final bool layout;
  final bool delegated;
  final String? projectId;
  final DateTime expiresAt;
  bool get expired => !DateTime.now().isBefore(expiresAt);
}

class AssistantActionPreview {
  const AssistantActionPreview({
    required this.title,
    required this.changes,
    this.layout,
  });
  final String title;
  final List<String> changes;
  final UiLayout? layout;
}

class AssistantAppliedAction {
  const AssistantAppliedAction(this.result, {this.undo});
  final Map<String, Object?> result;
  final Future<void> Function()? undo;
}

class AssistantPreparedAction {
  const AssistantPreparedAction({
    required this.call,
    required this.preview,
    required this.resourceKey,
    required this.apply,
    this.readOnly = false,
  });
  final AssistantToolCall call;
  final AssistantActionPreview preview;
  final String resourceKey;
  final Future<AssistantAppliedAction> Function() apply;
  final bool readOnly;
}

const assistantToolNames = {
  'ui_catalog',
  'tasks_list',
  'task_create',
  'task_update',
  'task_complete',
  'app_open',
  'settings_patch',
  'layout_patch',
};

Map<String, Object?> _objectSchema(
  Map<String, Object?> properties,
  List<String> required,
) => {
  'type': 'object',
  'properties': properties,
  'required': required,
  'additionalProperties': false,
};

const _stringSchema = {'type': 'string'};
const _dateSchema = {
  'type': ['string', 'null'],
  'description': 'YYYY-MM-DD，null 清除日期',
};

List<AssistantToolSchema> assistantToolSchemas(AssistantGrant grant) => [
  AssistantToolSchema(
    name: 'ui_catalog',
    description: '获取可用页面、入口和槽位的稳定 ID。不含任务正文。',
    parameters: _objectSchema({}, []),
  ),
  if (grant.shareTasks)
    AssistantToolSchema(
      name: 'tasks_list',
      description: '查询已授权范围的任务，最多50项；只发送标题、优先级、计划日期和状态。',
      parameters: _objectSchema({
        'query': _stringSchema,
        'projectId': {
          'type': ['string', 'null'],
        },
      }, []),
    ),
  if (grant.shareTasks && grant.writeTasks) ...[
    AssistantToolSchema(
      name: 'task_create',
      description: '创建任务或子任务。不能删除任务或修改其他项目。',
      parameters: _objectSchema(
        {
          'title': _stringSchema,
          'projectId': {
            'type': ['string', 'null'],
          },
          'parentTaskId': {
            'type': ['string', 'null'],
          },
          'priority': {'type': 'integer', 'minimum': 0, 'maximum': 3},
          'dueDate': _dateSchema,
          'plannedDate': _dateSchema,
        },
        ['title'],
      ),
    ),
    AssistantToolSchema(
      name: 'task_update',
      description: '修改任务标题、优先级或日期；不要改变用户未要求的字段。',
      parameters: _objectSchema(
        {
          'id': _stringSchema,
          'changes': _objectSchema({
            'title': _stringSchema,
            'priority': {'type': 'integer', 'minimum': 0, 'maximum': 3},
            'dueDate': _dateSchema,
            'plannedDate': _dateSchema,
          }, []),
        },
        ['id', 'changes'],
      ),
    ),
    AssistantToolSchema(
      name: 'task_complete',
      description: '标记任务完成或重新打开。',
      parameters: _objectSchema(
        {
          'id': _stringSchema,
          'completed': {'type': 'boolean'},
        },
        ['id', 'completed'],
      ),
    ),
  ],
  if (grant.navigate)
    AssistantToolSchema(
      name: 'app_open',
      description: '打开应用设置、布局设置或已登记入口。不会关闭已有表单。',
      parameters: _objectSchema(
        {
          'target': {
            'type': 'string',
            'enum': ['settings', 'layout', 'entry'],
          },
          'entryId': _stringSchema,
        },
        ['target'],
      ),
    ),
  if (grant.settings)
    AssistantToolSchema(
      name: 'settings_patch',
      description: '调整主题、减少动画或触觉反馈。不能改模型端点、密钥或权限。',
      parameters: _objectSchema({
        'theme': {
          'type': 'string',
          'enum': ['system', 'light', 'dark'],
        },
        'reduceMotion': {'type': 'boolean'},
        'haptics': {'type': 'boolean'},
      }, []),
    ),
  if (grant.layout)
    AssistantToolSchema(
      name: 'layout_patch',
      description: '修改一套屏幕配置的入口位置、槽位、顺序及直显上限。保留其他配置；一次调用可同时调整多个入口。',
      parameters: _objectSchema(
        {
          'profile': {
            'type': 'string',
            'enum': ['narrow', 'wide'],
          },
          'mainLimit': {
            'type': ['integer', 'null'],
            'minimum': 1,
          },
          'mounts': {
            'type': 'array',
            'maxItems': 40,
            'items': _objectSchema(
              {
                'entryId': _stringSchema,
                'placement': {
                  'type': 'string',
                  'enum': UiPlacement.values
                      .map((placement) => placement.name)
                      .toList(),
                },
                'pageId': _stringSchema,
                'slotId': _stringSchema,
                'order': {'type': 'integer'},
                'taskId': {
                  'type': ['string', 'null'],
                },
                'projectId': {
                  'type': ['string', 'null'],
                },
              },
              ['entryId', 'placement'],
            ),
          },
        },
        ['profile'],
      ),
    ),
];

class AssistantActions {
  AssistantActions(this.ref, this.registry, this.checkActive);
  final Ref ref;
  final ModuleRegistry registry;
  final void Function() checkActive;

  ModuleContext get _context {
    checkActive();
    final module = registry.modules
        .where((module) => module.manifest.id == 'app.ai')
        .firstOrNull;
    if (module == null) throw StateError('AI 插件已关闭');
    return ModuleContext(
      moduleId: 'app.ai',
      permissions: module.manifest.permissions,
    );
  }

  void requireTool(String name, AssistantGrant grant) {
    checkActive();
    if (grant.expired) throw StateError('授权已到期，请重新授权');
    if (!assistantToolSchemas(grant).any((tool) => tool.name == name)) {
      throw StateError('工具未获授权：$name');
    }
    if (name.startsWith('task')) {
      _context.require(name == 'tasks_list' ? 'tasks.read' : 'tasks.write');
    } else {
      _context.require('ui.register');
    }
  }

  Future<AssistantPreparedAction> prepare(
    AssistantToolCall call,
    AssistantGrant grant,
  ) async {
    requireTool(call.name, grant);
    final arguments = (freezeJson(call.arguments) as Map)
        .cast<String, Object?>();
    switch (call.name) {
      case 'ui_catalog':
        _keys(arguments, const {}, const {});
        return _read(call, '读取界面结构', () async {
          final layout = await ref.read(uiLayoutProvider.future);
          checkActive();
          return {
            'entries': [
              for (final entry in registry.ui.entries.take(500))
                {
                  'id': entry.id,
                  'label': entry.label,
                  'pageId': entry.pageId,
                  'content': entry.content,
                  'opening': entry.opening.name,
                },
            ],
            'pages': [
              for (final page in registry.ui.pages.take(500))
                {
                  'id': page.id,
                  'title': page.title,
                  'requiredContext': page.requiredContext,
                  'slots': [
                    for (final slot in page.slots)
                      {
                        'id': slot.id,
                        'label': slot.label,
                        'kind': slot.kind.name,
                        'public': slot.isPublic,
                        'editable': slot.editable,
                        'capacity': slot.capacity,
                        'requiredContext': slot.requiredContext,
                      },
                  ],
                },
            ],
            'truncated':
                registry.ui.entries.length > 500 ||
                registry.ui.pages.length > 500,
            'layout': {
              for (final name in ['narrow', 'wide'])
                name: {
                  'mainLimit': layout.profile(name == 'wide').mainLimit,
                  'mounts': {
                    for (final entry in registry.ui.entries.take(500))
                      entry.id: {
                        for (final value
                            in layout
                                .profile(name == 'wide')
                                .mountFor(entry)
                                .toJson()
                                .entries)
                          if (value.key != 'taskId' && value.key != 'projectId')
                            value.key: value.value,
                        'hasContext':
                            layout
                                .profile(name == 'wide')
                                .mountFor(entry)
                                .context !=
                            const PageContext(),
                      },
                  },
                },
            },
          };
        });
      case 'tasks_list':
        _keys(arguments, const {'query', 'projectId'}, const {});
        final query = arguments['query'] == null
            ? ''
            : _string(arguments, 'query', max: 300);
        final projectId = _project(arguments, grant);
        return _read(call, '查询授权范围任务', () async {
          final bus = await ref.read(queryBusProvider.future);
          checkActive();
          final rows = await bus.execute(_context, 'task.list', {
            'filter': {
              'all': [
                {'field': 'deleted', 'op': 'eq', 'value': false},
                {'field': 'archived', 'op': 'eq', 'value': false},
                if (projectId != null)
                  {'field': 'projectId', 'op': 'eq', 'value': projectId},
              ],
            },
          }) as List;
          final matches = rows.cast<Map>().where(
            (row) =>
                '${row['title']}'.toLowerCase().contains(query.toLowerCase()),
          );
          return {
            'tasks': [
              for (final task in matches.take(50))
                {
                  for (final key in [
                    'id',
                    'projectId',
                    'parentTaskId',
                    'title',
                    'priority',
                    'dueDate',
                    'plannedDate',
                    'completed',
                  ])
                    key: task[key],
                },
            ],
            'truncated': matches.length > 50,
          };
        });
      case 'task_create':
        _keys(
          arguments,
          const {
            'title',
            'projectId',
            'parentTaskId',
            'priority',
            'dueDate',
            'plannedDate',
          },
          const {'title'},
        );
        _taskChanges(arguments, creation: true);
        final projectId = _project(arguments, grant);
        final parentId = _optionalId(arguments, 'parentTaskId');
        if (parentId != null) {
          final parent = await _task(parentId, grant);
          if (parent.projectId != projectId) {
            throw StateError('子任务必须与父任务属于同一项目');
          }
        }
        if (projectId != null) {
          final store = await ref.read(taskStoreProvider.future);
          final project = await store.findProject(projectId);
          if (project == null || project.archivedAt != null) {
            throw StateError('项目不可用');
          }
        }
        final payload = {...arguments, 'projectId': projectId};
        return AssistantPreparedAction(
          call: call,
          resourceKey: 'create:${call.id}',
          preview: AssistantActionPreview(
            title: '创建任务',
            changes: List.unmodifiable([
              _string(arguments, 'title', max: 300),
              if (arguments['plannedDate'] != null)
                '计划日期：${arguments['plannedDate']}',
              '创建操作暂不支持助手撤销，请确认后执行。',
            ]),
          ),
          apply: () async {
            requireTool(call.name, grant);
            final bus = await ref.read(commandBusProvider.future);
            requireTool(call.name, grant);
            final result =
                await bus.execute(_context, 'task.create', payload) as Map;
            return AssistantAppliedAction(result.cast<String, Object?>());
          },
        );
      case 'task_update':
      case 'task_complete':
        final completion = call.name == 'task_complete';
        _keys(
          arguments,
          completion ? const {'id', 'completed'} : const {'id', 'changes'},
          completion ? const {'id', 'completed'} : const {'id', 'changes'},
        );
        final task = await _task(_string(arguments, 'id'), grant);
        final changes = completion
            ? <String, Object?>{'completed': _boolean(arguments, 'completed')}
            : _map(arguments, 'changes');
        if (!completion) _taskChanges(changes);
        return AssistantPreparedAction(
          call: call,
          resourceKey: 'task:${task.id}',
          preview: AssistantActionPreview(
            title: completion ? '调整任务完成状态' : '修改任务',
            changes: List.unmodifiable([
              task.title,
              for (final entry in changes.entries)
                '${_fieldLabel(entry.key)}：${entry.value ?? '清除'}',
            ]),
          ),
          apply: () async {
            requireTool(call.name, grant);
            final bus = await ref.read(commandBusProvider.future);
            requireTool(call.name, grant);
            final result = await bus.execute(
              _context,
              completion ? 'task.setCompleted' : 'task.updateFields',
              {
                'id': task.id,
                'expectedValues': taskStateSnapshot(task),
                if (completion)
                  'completed': changes['completed']
                else
                  'changes': changes,
              },
            );
            final after = (result as Map).cast<String, Object?>();
            return AssistantAppliedAction(
              {'id': task.id, 'applied': true},
              undo: () async {
                requireTool(call.name, grant);
                await bus.execute(
                  _context,
                  completion ? 'task.setCompleted' : 'task.updateFields',
                  {
                    'id': task.id,
                    'expectedValues': after,
                    if (completion)
                      'completed': task.completedAt != null
                    else
                      'changes': {
                        for (final key in changes.keys)
                          key: taskStateSnapshot(task)[key],
                      },
                  },
                );
              },
            );
          },
        );
      case 'settings_patch':
        _keys(arguments, const {'theme', 'reduceMotion', 'haptics'}, const {});
        if (arguments.isEmpty) throw ArgumentError('设置变更不能为空');
        final before = await ref.read(appPreferencesProvider.future);
        final theme = arguments.containsKey('theme')
            ? ThemeMode.values.byName(_string(arguments, 'theme'))
            : before.themeMode;
        final after = before.copyWith(
          themeMode: theme,
          reduceMotion: arguments.containsKey('reduceMotion')
              ? _boolean(arguments, 'reduceMotion')
              : before.reduceMotion,
          haptics: arguments.containsKey('haptics')
              ? _boolean(arguments, 'haptics')
              : before.haptics,
        );
        return AssistantPreparedAction(
          call: call,
          resourceKey: 'settings',
          preview: AssistantActionPreview(
            title: '调整外观设置',
            changes: List.unmodifiable([
              for (final entry in arguments.entries)
                '${entry.key}：${entry.value}',
            ]),
          ),
          apply: () async {
            requireTool(call.name, grant);
            await ref
                .read(appPreferencesProvider.notifier)
                .saveIfUnchanged(after, expected: before);
            return AssistantAppliedAction(
              {'applied': true},
              undo: () async {
                requireTool(call.name, grant);
                await ref
                    .read(appPreferencesProvider.notifier)
                    .saveIfUnchanged(before, expected: after);
              },
            );
          },
        );
      case 'layout_patch':
        return _layout(call, arguments, grant);
      case 'app_open':
        _keys(arguments, const {'target', 'entryId'}, const {'target'});
        final target = _string(arguments, 'target');
        if (!{'settings', 'layout', 'entry'}.contains(target)) {
          throw ArgumentError('未知页面目标');
        }
        final entryId = target == 'entry'
            ? _string(arguments, 'entryId')
            : null;
        if (target != 'entry' && arguments.containsKey('entryId')) {
          throw ArgumentError('此目标不接受入口 ID');
        }
        final candidates = registry.ui.entries.where(
          (entry) => entry.id == entryId && !entry.content,
        );
        final entry = candidates.firstOrNull;
        if (target == 'entry' && entry == null) throw StateError('入口不可用');
        final navigationContext = ref
            .read(appNavigationProvider)
            .navigatorKey
            .currentContext;
        final wide =
            navigationContext != null &&
            MediaQuery.sizeOf(navigationContext).width >= 820;
        final mount = entry == null
            ? null
            : (await ref.read(uiLayoutProvider.future))
                  .profile(wide)
                  .mountFor(entry);
        if (entry != null) {
          final problem = mountProblem(registry.ui, entry, mount!);
          if (problem != null) throw StateError(problem);
          if (mount.context.taskId != null || mount.context.projectId != null) {
            final valid = await ref.read(
              pageContextValidityProvider(mount.context).future,
            );
            if (!valid) throw StateError('入口上下文失效');
          }
        }
        return AssistantPreparedAction(
          call: call,
          resourceKey: 'navigation:${call.id}',
          preview: AssistantActionPreview(
            title: '打开页面',
            changes: [
              entry?.label ?? (target == 'settings' ? '应用设置' : '入口与页面布局'),
            ],
          ),
          apply: () async {
            requireTool(call.name, grant);
            if (entry != null &&
                !registry.ui.entries.any(
                  (candidate) => identical(candidate, entry),
                )) {
              throw StateError('入口已发生变化，请重新选择');
            }
            if (entry != null) {
              final latest = (await ref.read(uiLayoutProvider.future))
                  .profile(wide)
                  .mountFor(entry);
              if (latest != mount) throw StateError('入口挂载已变化，请重新选择');
              if (!await ref.read(
                pageContextValidityProvider(mount!.context).future,
              )) {
                throw StateError('入口上下文失效');
              }
              requireTool(call.name, grant);
            }
            final page = switch (target) {
              'settings' => SettingsPage(registry: registry),
              'layout' => UiLayoutPage(registry: registry),
              _ => Scaffold(
                appBar: AppBar(title: Text(entry!.label)),
                body: UiPageHost(
                  registry: registry,
                  pageId: entry.pageId,
                  pageContext: mount!.context,
                  mountPath: [entry.id],
                ),
              ),
            };
            ref.read(appNavigationProvider).open(page, name: entryId ?? target);
            return AssistantAppliedAction({'opened': entryId ?? target});
          },
        );
      default:
        throw StateError('未知工具：${call.name}');
    }
  }

  AssistantPreparedAction _read(
    AssistantToolCall call,
    String title,
    Future<Map<String, Object?>> Function() read,
  ) => AssistantPreparedAction(
    call: call,
    resourceKey: 'read:${call.id}',
    readOnly: true,
    preview: AssistantActionPreview(title: title, changes: const []),
    apply: () async => AssistantAppliedAction(await read()),
  );

  String? _project(Map<String, Object?> arguments, AssistantGrant grant) {
    final requested = _optionalId(arguments, 'projectId');
    if (grant.projectId != null &&
        requested != null &&
        requested != grant.projectId) {
      throw StateError('目标不在已授权项目范围内');
    }
    return grant.projectId ?? requested;
  }

  Future<Task> _task(String id, AssistantGrant grant) async {
    final store = await ref.read(taskStoreProvider.future);
    final task = await store.findTask(id);
    checkActive();
    if (task == null || task.deletedAt != null || task.archivedAt != null) {
      throw StateError('任务不可用');
    }
    if (grant.projectId != null && task.projectId != grant.projectId) {
      throw StateError('任务不在已授权项目范围内');
    }
    return task;
  }

  Future<AssistantPreparedAction> _layout(
    AssistantToolCall call,
    Map<String, Object?> arguments,
    AssistantGrant grant,
  ) async {
    _keys(
      arguments,
      const {'profile', 'mainLimit', 'mounts'},
      const {'profile'},
    );
    final profileName = _string(arguments, 'profile');
    if (!{'narrow', 'wide'}.contains(profileName)) {
      throw ArgumentError('屏幕配置须为 narrow 或 wide');
    }
    if (!arguments.containsKey('mainLimit') &&
        !arguments.containsKey('mounts')) {
      throw ArgumentError('布局变更不能为空');
    }
    final before = await ref.read(uiLayoutProvider.future);
    if (before.warning != null) throw StateError('布局配置损坏，请先在设置中处理');
    final wide = profileName == 'wide';
    var profile = before.profile(wide);
    if (arguments.containsKey('mainLimit')) {
      final limit = arguments['mainLimit'];
      if (limit != null && (limit is! int || limit < 1)) {
        throw ArgumentError('直显上限须为正整数或 null');
      }
      profile = UiLayoutProfile(
        mainLimit: limit as int?,
        mounts: profile.mounts,
      );
    }
    final rawMounts = arguments['mounts'] ?? const [];
    if (rawMounts is! List || rawMounts.length > 40) {
      throw ArgumentError('一次最多调整40个入口');
    }
    final changes = <String>[];
    final seen = <String>{};
    for (final raw in rawMounts) {
      if (raw is! Map) throw ArgumentError('挂载须为对象');
      final item = raw.cast<String, Object?>();
      _keys(
        item,
        const {
          'entryId',
          'placement',
          'pageId',
          'slotId',
          'order',
          'taskId',
          'projectId',
        },
        const {'entryId', 'placement'},
      );
      final id = _string(item, 'entryId');
      if (!seen.add(id)) throw ArgumentError('入口不能重复挂载');
      final entry = registry.ui.entries
          .where((entry) => entry.id == id)
          .firstOrNull;
      if (entry == null) throw StateError('入口不可用：$id');
      final original = profile.mountFor(entry);
      _editable(original);
      final placement = UiPlacement.values.byName(_string(item, 'placement'));
      if (placement != UiPlacement.page &&
          (item.containsKey('pageId') || item.containsKey('slotId'))) {
        throw ArgumentError('全局位置不能指定页面槽位');
      }
      final mount = UiMount.fromJson({
        for (final value in item.entries)
          if (value.key != 'entryId') value.key: value.value,
        if (!item.containsKey('taskId') && original.context.taskId != null)
          'taskId': original.context.taskId,
        if (!item.containsKey('projectId') &&
            original.context.projectId != null)
          'projectId': original.context.projectId,
      });
      _editable(mount);
      final problem = mountProblem(
        registry.ui,
        entry,
        mount,
        checkContext: false,
      );
      if (problem != null) throw StateError(problem);
      if (mount.context != original.context &&
          (mount.context.taskId != null || mount.context.projectId != null)) {
        if (!grant.shareTasks) throw StateError('绑定业务上下文需要任务访问授权');
        if (mount.context.taskId != null) {
          await _task(mount.context.taskId!, grant);
        }
        if (grant.projectId != null &&
            mount.context.projectId != null &&
            mount.context.projectId != grant.projectId) {
          throw StateError('上下文超出授权项目');
        }
        if (!await ref.read(
          pageContextValidityProvider(mount.context).future,
        )) {
          throw StateError('上下文对象不存在或关联不匹配');
        }
      }
      profile = profile.withMount(id, mount);
      changes.add(
        '${entry.label} → ${placementLabel(mount.placement)}${mount.slotId == null ? '' : ' / ${mount.slotId}'}',
      );
    }
    if (arguments.containsKey('mainLimit')) {
      changes.add('主导航直显上限：${profile.mainLimit ?? '不限制'}（不含更多）');
    }
    for (final entry in registry.ui.entries) {
      final issue = layoutEntryDiagnostic(registry.ui, entry, profile.mountFor);
      if (issue != null && seen.contains(entry.id)) {
        changes.add('${entry.label}：${issue.message}；配置可保留');
      }
    }
    changes.addAll(compositionWarnings(registry.ui, profile.mountFor));
    final after = UiLayout(
      narrow: wide ? before.narrow : profile,
      wide: wide ? profile : before.wide,
    );
    final stamp = _registryStamp();
    return AssistantPreparedAction(
      call: call,
      resourceKey: 'layout',
      preview: AssistantActionPreview(
        title: '${wide ? '宽屏' : '窄屏'}入口编排',
        changes: List.unmodifiable(changes),
        layout: after,
      ),
      apply: () async {
        requireTool(call.name, grant);
        if (stamp != _registryStamp()) throw StateError('模块或槽位已变化，请重新生成布局');
        if (ref.read(uiLayoutEditorSessionsProvider).hasDirtyEditors) {
          throw StateError('布局编辑器有未保存草稿，请先保存或取消');
        }
        await ref
            .read(uiLayoutProvider.notifier)
            .saveIfUnchanged(after, expected: before);
        return AssistantAppliedAction(
          {'applied': true, 'profile': profileName},
          undo: () async {
            requireTool(call.name, grant);
            if (ref.read(uiLayoutEditorSessionsProvider).hasDirtyEditors) {
              throw StateError('请先处理布局编辑器草稿');
            }
            await ref
                .read(uiLayoutProvider.notifier)
                .saveIfUnchanged(before, expected: after);
          },
        );
      },
    );
  }

  void _editable(UiMount mount) {
    if (mount.placement != UiPlacement.page) return;
    final slot = registry.ui
        .page(mount.pageId ?? '')
        ?.slots
        .where((slot) => slot.id == mount.slotId)
        .firstOrNull;
    if (slot != null && !slot.editable) throw StateError('模块固定槽位不可调整');
  }

  String _registryStamp() => canonicalJson({
    'modules': [
      for (final module in registry.modules)
        {'id': module.manifest.id, 'version': module.manifest.version},
    ],
    'pages': [
      for (final page in registry.ui.pages)
        {
          'id': page.id,
          'slots': [
            for (final slot in page.slots)
              {
                'id': slot.id,
                'public': slot.isPublic,
                'editable': slot.editable,
                'kind': slot.kind.name,
                'capacity': slot.capacity,
                'context': slot.requiredContext,
              },
          ],
        },
    ],
  });
}

void _keys(
  Map<String, Object?> arguments,
  Set<String> allowed,
  Set<String> required,
) {
  if (arguments.keys.any((key) => !allowed.contains(key)) ||
      !arguments.keys.toSet().containsAll(required)) {
    throw ArgumentError('工具参数包含未知字段或缺少必填字段');
  }
}

String _string(Map<String, Object?> arguments, String key, {int max = 200}) {
  final value = arguments[key];
  if (value is! String || value.trim().isEmpty || value.length > max) {
    throw ArgumentError('无效参数：$key');
  }
  return value.trim();
}

String? _optionalId(Map<String, Object?> arguments, String key) =>
    arguments[key] == null ? null : _string(arguments, key);

bool _boolean(Map<String, Object?> arguments, String key) {
  final value = arguments[key];
  if (value is! bool) throw ArgumentError('无效布尔参数：$key');
  return value;
}

Map<String, Object?> _map(Map<String, Object?> arguments, String key) {
  final value = arguments[key];
  if (value is! Map) throw ArgumentError('参数须为对象：$key');
  return value.cast<String, Object?>();
}

void _taskChanges(Map<String, Object?> changes, {bool creation = false}) {
  if (!creation) {
    _keys(changes, const {
      'title',
      'priority',
      'dueDate',
      'plannedDate',
    }, const {});
  }
  if (changes.isEmpty) throw ArgumentError('任务变更不能为空');
  if (changes.containsKey('title')) _string(changes, 'title', max: 300);
  if (changes.containsKey('priority')) {
    final priority = changes['priority'];
    if (priority is! int || priority < 0 || priority > 3) {
      throw ArgumentError('优先级须为0到3');
    }
  }
  for (final key in ['dueDate', 'plannedDate']) {
    final date = changes[key];
    if (date == null) continue;
    if (date is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
      throw ArgumentError('日期须为 YYYY-MM-DD');
    }
    final parsed = DateTime.tryParse(date);
    if (parsed == null ||
        '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}' !=
            date) {
      throw ArgumentError('日期不存在');
    }
  }
}

String _fieldLabel(String field) => switch (field) {
  'title' => '标题',
  'priority' => '优先级',
  'plannedDate' => '计划日期',
  'dueDate' => '截止日期',
  'completed' => '完成状态',
  _ => field,
};
