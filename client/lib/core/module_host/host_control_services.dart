import 'dart:convert';

import '../contracts/json_values.dart';
import '../modules/module_registry.dart';
import '../ui/ui_composition.dart';
import '../ui/ui_layout_resolver.dart';
import '../../features/settings/app_preferences.dart';
import '../../features/settings/ui_layout.dart';
import 'collection_store.dart';
import 'module_host.dart';
import 'module_package.dart';

/// Protected host controls exposed through the same authorization and reviewed
/// plan protocol as script services. No AI/task business controller is involved.
void registerHostControlServices(
  ModuleHost host,
  ModuleRegistry registry, {
  required bool Function() hasDirtyLayout,
}) {
  String stamp() => canonicalJson({
    'modules': [
      for (final m in registry.modules)
        {'id': m.manifest.id, 'version': m.manifest.version},
    ],
    'pages': [
      for (final p in registry.ui.pages)
        {
          'id': p.id,
          'slots': [
            for (final s in p.slots)
              {
                'id': s.id,
                'public': s.isPublic,
                'editable': s.editable,
                'kind': s.kind.name,
              },
          ],
        },
    ],
    'entries': [for (final e in registry.ui.entries) e.id],
  });
  void service(
    String id,
    String kind,
    Map<String, Object?> input,
    Future<Object?> Function(ModuleActor, Object?, SnapshotSession) handler, {
    Map<String, Object?>? undo,
  }) {
    host.nativeServices[id] = NativeHostService({
      'id': id,
      'major': 1,
      'kind': kind,
      'handler': id,
      'input': input,
      'output': {'type': 'object'},
      'tool': {'description': id, 'inputSchema': input, 'undo': ?undo},
    }, handler);
  }

  Future<Map<String, Object?>> read(
    String key,
    Map<String, Object?> fallback,
    SnapshotSession session,
  ) async {
    final rows = await host.store.sql(
      'SELECT value FROM app_settings WHERE key=?',
      [key],
    );
    final raw = rows.isEmpty ? null : rows.single['value'] as String;
    if (session.nativeReads.containsKey(key) &&
        session.nativeReads[key] != raw) {
      throw StateError('Host setting changed while preparing');
    }
    session.nativeReads[key] = raw;
    final staged = session
        .writes[RecordKey('app.host', 'host-controls', 'settings', key).key];
    if (staged != null) return object(object(staged['value'])['values']);
    return raw == null ? fallback : object(jsonDecode(raw));
  }

  void write(
    String key,
    Map<String, Object?> before,
    Map<String, Object?> after,
    SnapshotSession session,
  ) {
    if (canonicalJson(before) == canonicalJson(after)) return;
    final record = RecordKey('app.host', 'host-controls', 'settings', key);
    final existing = session.writes[record.key];
    session.writes[record.key] = {
      'moduleId': 'app.host',
      'space': 'host-controls',
      'collection': 'settings',
      'id': key,
      'before':
          existing?['before'] ?? freezeJson({'id': key, 'values': before}),
      'value': freezeJson({'id': key, 'values': after}),
    };
    session.approvals.add({
      'hostRegistry': stamp(),
      'layout': key == UiLayoutController.storageKey,
    });
  }

  Map<String, Object?> values(Object? value) => object(value);
  const stringSchema = {'type': 'string'};
  final preferencesSchema = {
    'type': 'object',
    'properties': {
      'theme': {
        'type': 'string',
        'enum': ['system', 'light', 'dark'],
      },
      'reduceMotion': {'type': 'boolean'},
      'haptics': {'type': 'boolean'},
    },
    'additionalProperties': false,
  };
  service(
    'settings.get',
    'query',
    {'type': 'object'},
    (_, input, session) async => read(
      AppPreferencesController.storageKey,
      const AppPreferences().toJson(),
      session,
    ),
  );
  service(
    'settings.patch',
    'command',
    {
      'type': 'object',
      'required': ['changes'],
      'properties': {
        'changes': preferencesSchema,
        'expected': preferencesSchema,
      },
      'additionalProperties': false,
    },
    (_, input, session) async {
      final args = values(input),
          before = await read(
            AppPreferencesController.storageKey,
            const AppPreferences().toJson(),
            session,
          );
      if (args.containsKey('expected') &&
          canonicalJson(args['expected']) != canonicalJson(before)) {
        throw StateError('外观设置已变化，不能应用旧方案');
      }
      final after = {...before, ...object(args['changes'])};
      write(AppPreferencesController.storageKey, before, after, session);
      return {'before': before, 'after': after, 'applied': true};
    },
    undo: {
      'serviceId': 'settings.patch',
      'input': {
        'changes': {
          'bind': ['result', 'before'],
        },
        'expected': {
          'bind': ['result', 'after'],
        },
      },
    },
  );
  service(
    'layout.get',
    'query',
    {'type': 'object'},
    (_, input, session) async =>
        read(UiLayoutController.storageKey, UiLayout().toJson(), session),
  );
  service(
    'layout.patch',
    'command',
    {
      'type': 'object',
      'properties': {
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
          'items': {'type': 'object'},
        },
        'replace': {'type': 'object'},
        'expected': {'type': 'object'},
      },
      'additionalProperties': false,
    },
    (caller, input, session) async {
      if (hasDirtyLayout()) throw StateError('布局编辑器有未保存草稿，请先处理');
      final args = values(input),
          before = await read(
            UiLayoutController.storageKey,
            UiLayout().toJson(),
            session,
          );
      if (args.containsKey('expected') &&
          canonicalJson(args['expected']) != canonicalJson(before)) {
        throw StateError('布局已变化，不能应用旧方案');
      }
      var layout = UiLayout.fromJson(before);
      if (args['replace'] != null) {
        if (args['expected'] == null) throw StateError('恢复布局必须指定当前状态');
        layout = UiLayout.fromJson(object(args['replace']));
      } else {
        if (!['narrow', 'wide'].contains(args['profile'])) {
          throw const FormatException('需要 narrow 或 wide 配置');
        }
        if (!args.containsKey('mainLimit') && !args.containsKey('mounts')) {
          throw const FormatException('布局修改不能为空');
        }
        final wide = args['profile'] == 'wide';
        var profile = layout.profile(wide);
        if (args.containsKey('mainLimit')) {
          profile = UiLayoutProfile(
            mainLimit: args['mainLimit'] as int?,
            mounts: profile.mounts,
          );
        }
        final seen = <String>{};
        for (final raw in args['mounts'] as List? ?? []) {
          final mount = object(raw), id = string(mount['entryId'], 'entryId');
          if (!seen.add(id)) throw const FormatException('重复入口');
          final entry = registry.ui.entries
              .where((e) => e.id == id)
              .firstOrNull;
          if (entry == null) throw StateError('入口已不可用');
          final original = profile.mountFor(entry);
          bool editable(UiMount m) =>
              m.placement != UiPlacement.page ||
              (registry.ui
                      .page(m.pageId ?? '')
                      ?.slots
                      .where((s) => s.id == m.slotId)
                      .firstOrNull
                      ?.editable ??
                  true);
          if (!editable(original)) throw StateError('模块固定槽位不可修改');
          final next = UiMount.fromJson({...mount}..remove('entryId'));
          if (!editable(next)) throw StateError('模块固定槽位不可修改');
          if (next.context != original.context &&
              next.context != const PageContext()) {
            throw StateError('新业务上下文需要通过该业务页面绑定');
          }
          final problem = mountProblem(
            registry.ui,
            entry,
            next,
            checkContext: false,
          );
          if (problem != null) throw StateError(problem);
          profile = profile.withMount(id, next);
        }
        layout = UiLayout(
          narrow: wide ? layout.narrow : profile,
          wide: wide ? profile : layout.wide,
        );
      }
      final after = layout.toJson();
      write(UiLayoutController.storageKey, before, after, session);
      return {
        'before': before,
        'after': after,
        'applied': true,
        'warnings': compositionWarnings(
          registry.ui,
          layout.profile(args['profile'] == 'wide').mountFor,
        ),
      };
    },
    undo: {
      'serviceId': 'layout.patch',
      'input': {
        'replace': {
          'bind': ['result', 'before'],
        },
        'expected': {
          'bind': ['result', 'after'],
        },
      },
    },
  );
  service(
    'navigation.list',
    'query',
    {'type': 'object'},
    (_, input, session) async => {
      'entries': [
        for (final e in registry.ui.entries)
          {
            'id': e.id,
            'label': e.label,
            'page': e.pageId,
            'opening': e.opening.name,
          },
      ],
      'controls': ['settings', 'layout'],
    },
  );
  service(
    'navigation.open',
    'command',
    {
      'type': 'object',
      'required': ['target'],
      'properties': {
        'target': {
          'type': 'string',
          'enum': ['settings', 'layout', 'entry'],
        },
        'entryId': stringSchema,
      },
      'additionalProperties': false,
    },
    (_, input, session) async {
      final args = values(input);
      String page;
      if (args['target'] == 'entry') {
        final entry = registry.ui.entries
            .where((e) => e.id == args['entryId'])
            .firstOrNull;
        if (entry == null) throw StateError('入口不可用');
        page = entry.pageId;
      } else {
        page = 'app.host.${args['target']}';
      }
      session.approvals.add({'hostRegistry': stamp()});
      return {'navigate': page, 'applied': true};
    },
  );
  host.validateNativePlan = (plan) {
    for (final approval in (plan.content['approvals'] as List).map(object)) {
      if (approval['hostRegistry'] != null &&
          approval['hostRegistry'] != stamp()) {
        throw StateError('模块或槽位已变化，请重新准备');
      }
      if (approval['layout'] == true && hasDirtyLayout()) {
        throw StateError('布局编辑器有未保存草稿，请先处理');
      }
    }
  };
}
