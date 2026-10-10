import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/contracts/command_bus.dart';
import 'package:task_app/core/contracts/query_bus.dart';
import 'package:task_app/core/modules/app_module.dart';
import 'package:task_app/core/modules/module_context.dart';
import 'package:task_app/core/modules/module_manifest.dart';
import 'package:task_app/core/modules/module_registry.dart';
import 'package:task_app/core/security/capability_registry.dart';
import 'package:task_app/core/ui/ui_registration.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/features/ai/assistant_runtime.dart';
import 'package:task_app/features/ai/provider/assistant_model.dart';
import 'package:task_app/features/ai/settings/ai_secret_store.dart';
import 'package:task_app/features/ai/settings/ai_settings_store.dart';
import 'package:task_app/features/settings/app_preferences.dart';
import 'package:task_app/features/settings/ui_layout.dart';
import 'package:task_app/features/tasks/application/providers.dart';
import 'package:task_app/features/tasks/data/task_store.dart';
import 'package:task_app/features/tasks/integration/task_command_bindings.dart';
import 'package:task_app/features/tasks/integration/task_query_bindings.dart';

const _apiKey = 'private-api-key-never-in-message-data';
const _notes = 'private-task-notes-never-shared';
final _timestamp = DateTime(2026, 10, 6, 12);

class _AssistantModule implements AppModule {
  @override
  ModuleManifest get manifest => const ModuleManifest(
    id: 'app.ai',
    version: '1.0.0',
    coreApi: '1',
    permissions: ['tasks.read', 'tasks.write', 'ui.register'],
  );

  @override
  List<UiRegistration> get ui => const [];
}

class _Settings implements AiSettingsStore {
  int loads = 0;

  @override
  Future<AiSettings> load() async {
    loads++;
    return const AiSettings(
      endpoint: 'https://model.example/v1/chat/completions',
      model: 'runtime-test-model',
    );
  }

  @override
  Future<void> save({required String endpoint, required String model}) async =>
      throw StateError('Runtime must not change model settings');
}

class _Secrets implements AiSecretStore {
  int reads = 0;

  @override
  Future<String?> readApiKey() async {
    reads++;
    return _apiKey;
  }

  @override
  Future<void> writeApiKey(String value) async =>
      throw StateError('Runtime must not write credentials');

  @override
  Future<void> deleteApiKey() async =>
      throw StateError('Runtime must not delete credentials');
}

class _ModelRequest {
  _ModelRequest({
    required this.endpoint,
    required this.model,
    required this.apiKey,
    required List<AssistantMessage> messages,
    required List<AssistantToolSchema> tools,
    required this.cancellation,
  }) : messages = List.unmodifiable(messages),
       tools = List.unmodifiable(tools);

  final Uri endpoint;
  final String model;
  final String apiKey;
  final List<AssistantMessage> messages;
  final List<AssistantToolSchema> tools;
  final AiRequestCancellation? cancellation;

  Map<String, Object?> result(String id) => jsonDecode(
    messages.lastWhere((message) => message.toolCallId == id).content,
  ) as Map<String, Object?>;
}

class _Model implements AssistantModel {
  _Model(this.respond);

  final FutureOr<AssistantModelReply> Function(_ModelRequest request, int round)
  respond;
  final requests = <_ModelRequest>[];
  final firstRequest = Completer<_ModelRequest>();

  @override
  Future<AssistantModelReply> complete({
    required Uri endpoint,
    required String model,
    required String apiKey,
    required List<AssistantMessage> messages,
    required List<AssistantToolSchema> tools,
    AiRequestCancellation? cancellation,
  }) async {
    final request = _ModelRequest(
      endpoint: endpoint,
      model: model,
      apiKey: apiKey,
      messages: messages,
      tools: tools,
      cancellation: cancellation,
    );
    requests.add(request);
    if (!firstRequest.isCompleted) firstRequest.complete(request);
    return respond(request, requests.length);
  }
}

_Model _script(List<AssistantModelReply> replies) => _Model((request, round) {
  if (round > replies.length) throw StateError('Unexpected model replay');
  return replies[round - 1];
});

AssistantToolCall _call(
  String name,
  Map<String, Object?> arguments, {
  String id = 'call-1',
}) => AssistantToolCall(id: id, name: name, arguments: arguments);

AssistantToolCall _update(String taskId, {String id = 'call-1'}) =>
    _call('task_update', {
      'id': taskId,
      'changes': {'title': 'Assistant changed title'},
    }, id: id);

AssistantModelReply _calls(List<AssistantToolCall> calls) =>
    AssistantModelReply(text: '', calls: calls);

AssistantModelReply _done() => AssistantModelReply(text: 'Done');

class _ExpiringGrant extends AssistantGrant {
  _ExpiringGrant({super.delegated = true, super.writeTasks = true})
    : super(shareTasks: true);

  bool expireNow = false;

  @override
  bool get expired => expireNow || super.expired;
}

class _RecordingQueries extends QueryBus {
  _RecordingQueries(this.delegate, {this.afterRead});

  final QueryBus delegate;
  final Future<void> Function()? afterRead;
  final payloads = <Map<String, Object?>>[];

  @override
  Future<Object?> execute(
    ModuleContext context,
    String id, [
    Map<String, Object?> payload = const {},
  ]) async {
    expect(id, 'task.list');
    payloads.add(payload);
    final result = await delegate.execute(context, id, payload);
    await afterRead?.call();
    return result;
  }
}

class _InterceptCommands extends CommandBus {
  _InterceptCommands(this.delegate, this.afterCommand);

  final CommandBus delegate;
  final Future<void> Function(
    String command,
    Map<String, Object?> payload,
    Object? result,
  )
  afterCommand;
  final payloads = <Map<String, Object?>>[];
  final results = <Object?>[];

  @override
  Future<Object?> execute(
    ModuleContext context,
    String id, [
    Map<String, Object?> payload = const {},
  ]) async {
    final result = await delegate.execute(context, id, payload);
    payloads.add(payload);
    results.add(result);
    await afterCommand(id, payload, result);
    return result;
  }
}

class _Harness {
  _Harness(
    this.model, {
    Completer<void>? prepareGate,
    bool recordQueries = false,
    Completer<void>? queryGate,
    Future<void> Function(
      String command,
      Map<String, Object?> payload,
      Object? result,
    )?
    afterCommand,
  }) {
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async => database),
        assistantModelProvider.overrideWithValue(model),
        aiSettingsStoreProvider.overrideWith((ref) async => settings),
        aiSecretStoreProvider.overrideWithValue(secrets),
        if (afterCommand != null)
          commandBusProvider.overrideWith((ref) async {
            final delegate = CommandBus();
            registerTaskCommands(
              delegate,
              await ref.read(taskCommandServiceProvider.future),
            );
            final intercepted = _InterceptCommands(delegate, afterCommand);
            commands = intercepted;
            return intercepted;
          }),
        if (recordQueries || queryGate != null)
          queryBusProvider.overrideWith((ref) async {
            final delegate = QueryBus();
            registerTaskQueries(
              delegate,
              await ref.read(taskQueryServiceProvider.future),
            );
            final recording = _RecordingQueries(
              delegate,
              afterRead: queryGate == null
                  ? null
                  : () async {
                      reading.complete();
                      await queryGate.future;
                    },
            );
            queries = recording;
            return recording;
          }),
        if (prepareGate != null)
          taskStoreProvider.overrideWith((ref) async {
            preparing.complete();
            await prepareGate.future;
            return TaskStore(database);
          }),
      ],
    );
    controller = container.read(assistantControllerProvider(registry));
    addTearDown(() async {
      await controller.clearHistory();
      container.dispose();
      registry.dispose();
      await database.close();
    });
  }

  final _Model model;
  final database = AppDatabase(NativeDatabase.memory());
  final registry = ModuleRegistry([
    _AssistantModule(),
  ], capabilities: CapabilityRegistry([]));
  final settings = _Settings();
  final secrets = _Secrets();
  final preparing = Completer<void>();
  final reading = Completer<void>();
  late final ProviderContainer container;
  late final AssistantController controller;
  _RecordingQueries? queries;
  _InterceptCommands? commands;

  void grant({bool delegated = false, String? projectId}) =>
      controller.setGrant(
        AssistantGrant(
          shareTasks: true,
          writeTasks: true,
          settings: true,
          layout: true,
          delegated: delegated,
          projectId: projectId,
        ),
      );

  Future<void> project(String id) async {
    await database
        .into(database.projects)
        .insert(
          ProjectsCompanion.insert(
            id: id,
            name: id,
            createdAt: _timestamp,
            updatedAt: _timestamp,
          ),
        );
  }

  Future<void> task(
    String id, {
    String? projectId,
    String? parentTaskId,
    bool archived = false,
    bool deleted = false,
  }) async {
    await database
        .into(database.tasks)
        .insert(
          TasksCompanion.insert(
            id: id,
            title: 'Original $id',
            notes: const Value(_notes),
            projectId: Value(projectId),
            parentTaskId: Value(parentTaskId),
            archivedAt: Value(archived ? _timestamp : null),
            deletedAt: Value(deleted ? _timestamp : null),
            createdAt: _timestamp,
            updatedAt: _timestamp,
          ),
        );
  }

  Future<Task> readTask(String id) => (database.select(
    database.tasks,
  )..where((task) => task.id.equals(id))).getSingle();

  Future<void> editTask(String id, TasksCompanion changes) async {
    await (database.update(
      database.tasks,
    )..where((task) => task.id.equals(id))).write(changes);
  }

  Future<List<ChangeOperation>> journal() =>
      database.select(database.changeOperations).get();

  Future<Map<String, Object?>?> stored(String key) async {
    final row = await (database.select(
      database.appSettings,
    )..where((setting) => setting.key.equals(key))).getSingleOrNull();
    return row == null ? null : jsonDecode(row.value) as Map<String, Object?>;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'no grant or expired grant never reads credentials or calls model',
    () async {
      final harness = _Harness(_script([_done()]));
      await harness.controller.send('Create a task');
      expect(harness.controller.error, contains('请先授权'));
      harness.controller.setGrant(AssistantGrant(expiresAt: DateTime(2000)));
      await harness.controller.send('Create a task');
      expect(harness.model.requests, isEmpty);
      expect(harness.settings.loads, 0);
      expect(harness.secrets.reads, 0);
      expect(
        await harness.database.select(harness.database.tasks).get(),
        isEmpty,
      );
      expect(await harness.journal(), isEmpty);
    },
  );

  test(
    'manual approval prepares without writing and applies only once',
    () async {
      final harness = _Harness(
        _script([
          _calls([_update('task-1')]),
          _done(),
        ]),
      );
      await harness.task('task-1');
      harness.grant();
      await harness.controller.send('Rename task');
      expect(harness.controller.error, isNull);
      expect(harness.controller.awaitingApproval, isTrue);
      expect(harness.controller.busy, isFalse);
      expect(harness.controller.pending.single.title, '修改任务');
      expect((await harness.readTask('task-1')).title, 'Original task-1');
      expect(await harness.journal(), isEmpty);
      expect(harness.model.requests, hasLength(1));
      await harness.controller.send('Must not replace pending work');
      expect(harness.model.requests, hasLength(1));
      await harness.controller.approvePending();
      await harness.controller.approvePending();
      expect(
        (await harness.readTask('task-1')).title,
        'Assistant changed title',
      );
      expect(await harness.journal(), hasLength(1));
      expect(harness.controller.audit.single.status, '已执行');
      expect(harness.controller.awaitingApproval, isFalse);
      expect(harness.model.requests, hasLength(2));
      expect(harness.model.requests.last.result('call-1')['applied'], isTrue);
    },
  );

  test('rejecting prepared writes records rejection without effects', () async {
    final harness = _Harness(
      _script([
        _calls([_update('task-1')]),
      ]),
    );
    await harness.task('task-1');
    harness.grant();
    await harness.controller.send('Rename task');
    harness.controller.rejectPending();
    await harness.controller.approvePending();
    expect(harness.controller.awaitingApproval, isFalse);
    expect((await harness.readTask('task-1')).title, 'Original task-1');
    expect(await harness.journal(), isEmpty);
    expect(
      harness.controller.audit.any((item) => item.status == '已拒绝'),
      isTrue,
    );
    expect(harness.model.requests, hasLength(1));
  });

  test('task access and write grants stay independent', () async {
    final harness = _Harness(
      _script([
        _calls([_update('task-1')]),
        _done(),
      ]),
    );
    await harness.task('task-1');
    harness.controller.setGrant(AssistantGrant(shareTasks: true));
    await harness.controller.send('Rename task');
    final names = harness.model.requests.first.tools.map((tool) => tool.name);
    expect(names, contains('tasks_list'));
    expect(names, isNot(contains('task_update')));
    expect(
      harness.model.requests.last.result('call-1')['error'],
      contains('未获授权'),
    );
    expect(harness.controller.awaitingApproval, isFalse);
    expect(await harness.journal(), isEmpty);
  });

  test(
    'scoped grant denies foreign task writes, reads and parent creation',
    () async {
      final harness = _Harness(
        _script([
          _calls([
            _update('foreign', id: 'update'),
            _call('task_complete', {
              'id': 'foreign',
              'completed': true,
            }, id: 'complete'),
            _call('tasks_list', {'projectId': 'outside'}, id: 'read'),
            _call('task_create', {
              'title': 'Child',
              'parentTaskId': 'foreign',
            }, id: 'create'),
          ]),
          _done(),
        ]),
      );
      await harness.project('inside');
      await harness.project('outside');
      await harness.task('foreign', projectId: 'outside');
      harness.grant(delegated: true, projectId: 'inside');
      await harness.controller.send('Modify tasks');
      for (final id in ['update', 'complete', 'read', 'create']) {
        expect(harness.model.requests.last.result(id)['error'], contains('授权'));
      }
      expect((await harness.readTask('foreign')).title, 'Original foreign');
      expect((await harness.readTask('foreign')).completedAt, isNull);
      expect(
        await harness.database.select(harness.database.tasks).get(),
        hasLength(1),
      );
      expect(await harness.journal(), isEmpty);
      expect(harness.controller.awaitingApproval, isFalse);
    },
  );

  test(
    'tasks_list executes native all filter and shares no notes or credentials',
    () async {
      final harness = _Harness(
        _script([
          _calls([
            _call('tasks_list', {'query': 'visible'}, id: 'read'),
          ]),
          _done(),
        ]),
        recordQueries: true,
      );
      await harness.project('inside');
      await harness.project('outside');
      await harness.task('visible', projectId: 'inside');
      await harness.task('visible-foreign', projectId: 'outside');
      await harness.task(
        'visible-archived',
        projectId: 'inside',
        archived: true,
      );
      await harness.task('visible-deleted', projectId: 'inside', deleted: true);
      await harness.task('visible-unscoped');
      harness.grant(projectId: 'inside');
      await harness.controller.send('List visible tasks');
      expect(harness.queries!.payloads.single, {
        'filter': {
          'all': [
            {'field': 'deleted', 'op': 'eq', 'value': false},
            {'field': 'archived', 'op': 'eq', 'value': false},
            {'field': 'projectId', 'op': 'eq', 'value': 'inside'},
          ],
        },
      });
      final result = harness.model.requests.last.result('read');
      expect(result.containsKey('error'), isFalse);
      expect((result['tasks'] as List).map((task) => task['id']), ['visible']);
      final task = (result['tasks'] as List).single as Map;
      expect(task['completed'], isFalse);
      expect(task.containsKey('completedAt'), isFalse);
      expect(task.containsKey('notes'), isFalse);
      expect(result['truncated'], isFalse);
      for (final request in harness.model.requests) {
        expect(request.apiKey, _apiKey);
        expect(request.model, 'runtime-test-model');
        final data = jsonEncode({
          'messages': request.messages
              .map((message) => message.toJson())
              .toList(),
          'tools': request.tools.map((tool) => tool.toJson()).toList(),
        });
        expect(data, isNot(contains(_apiKey)));
        expect(data, isNot(contains(_notes)));
        expect(data, isNot(contains('visible-foreign')));
      }
      final schema = harness.model.requests.first.tools.singleWhere(
        (tool) => tool.name == 'tasks_list',
      );
      expect(schema.parameters['type'], 'object');
      expect((schema.parameters['properties'] as Map).keys, [
        'query',
        'projectId',
      ]);
      expect(schema.parameters['additionalProperties'], isFalse);
    },
  );

  for (final interruption in ['stop', 'revoke', 'disable', 'expire']) {
    test(
      '$interruption during model await ignores late text and writes',
      () async {
        final reply = Completer<AssistantModelReply>();
        final harness = _Harness(_Model((request, round) => reply.future));
        await harness.task('task-1');
        final grant = _ExpiringGrant();
        harness.controller.setGrant(grant);
        final sending = harness.controller.send('Rename task');
        final request = await harness.model.firstRequest.future;
        expect(harness.controller.busy, isTrue);
        switch (interruption) {
          case 'stop':
            harness.controller.stop();
          case 'revoke':
            harness.controller.setGrant(null);
          case 'disable':
            harness.registry.remove('app.ai');
          case 'expire':
            grant.expireNow = true;
        }
        if (interruption != 'expire') {
          expect(request.cancellation!.cancelled, isTrue);
        }
        reply.complete(
          AssistantModelReply(text: 'Late text', calls: [_update('task-1')]),
        );
        await sending;
        expect((await harness.readTask('task-1')).title, 'Original task-1');
        expect(await harness.journal(), isEmpty);
        expect(harness.controller.awaitingApproval, isFalse);
        expect(harness.controller.busy, isFalse);
        expect(
          harness.controller.messages.where((item) => item.role == 'assistant'),
          isEmpty,
        );
        expect(harness.model.requests, hasLength(1));
      },
    );
  }

  for (final revoke in [false, true]) {
    test(
      'pending prepare has no effects when ${revoke ? 'revoked' : 'stopped'}',
      () async {
        final gate = Completer<void>();
        final harness = _Harness(
          _script([
            _calls([_update('task-1')]),
          ]),
          prepareGate: gate,
        );
        await harness.task('task-1');
        harness.grant(delegated: true);
        final sending = harness.controller.send('Rename task');
        await harness.preparing.future;
        expect(harness.controller.awaitingApproval, isFalse);
        expect(await harness.journal(), isEmpty);
        if (revoke) {
          harness.controller.setGrant(null);
        } else {
          harness.controller.stop();
        }
        gate.complete();
        await sending;
        expect(harness.controller.awaitingApproval, isFalse);
        expect((await harness.readTask('task-1')).title, 'Original task-1');
        expect(await harness.journal(), isEmpty);
      },
    );
  }

  for (final field in [
    'title',
    'notes',
    'projectId',
    'parentTaskId',
    'priority',
    'dueDate',
    'plannedDate',
    'completedAt',
    'archivedAt',
    'deletedAt',
  ]) {
    test(
      'same-second stale $field rejects prepared task full snapshot',
      () async {
        final harness = _Harness(
          _script([
            _calls([_update('task-1')]),
          ]),
        );
        await harness.project('new-project');
        await harness.task('task-1');
        harness.grant();
        await harness.controller.send('Rename task');
        expect(harness.controller.awaitingApproval, isTrue);
        final before = await harness.readTask('task-1');
        final changes = switch (field) {
          'title' => const TasksCompanion(title: Value('User changed title')),
          'notes' => const TasksCompanion(notes: Value('User changed notes')),
          'projectId' => const TasksCompanion(projectId: Value('new-project')),
          'parentTaskId' => const TasksCompanion(
            parentTaskId: Value('new-parent'),
          ),
          'priority' => const TasksCompanion(priority: Value(3)),
          'dueDate' => const TasksCompanion(dueDate: Value('2026-10-07')),
          'plannedDate' => const TasksCompanion(
            plannedDate: Value('2026-10-08'),
          ),
          'completedAt' => TasksCompanion(completedAt: Value(_timestamp)),
          'archivedAt' => TasksCompanion(archivedAt: Value(_timestamp)),
          _ => TasksCompanion(deletedAt: Value(_timestamp)),
        };
        await harness.editTask('task-1', changes);
        final concurrent = await harness.readTask('task-1');
        expect(concurrent.updatedAt, before.updatedAt);
        await harness.controller.approvePending();
        expect(harness.controller.error, isNotNull);
        expect(await harness.readTask('task-1'), concurrent);
        expect(await harness.journal(), isEmpty);
        expect(harness.controller.canUndo, isFalse);
        expect(harness.model.requests, hasLength(1));
      },
    );
  }

  for (final dirtyDraft in [false, true]) {
    test(
      'layout ${dirtyDraft ? 'dirty draft' : 'CAS conflict'} blocks approval',
      () async {
        final harness = _Harness(
          _script([
            _calls([
              _call('layout_patch', {'profile': 'narrow', 'mainLimit': 2}),
            ]),
          ]),
        );
        harness.grant();
        await harness.controller.send('Adjust layout');
        expect(harness.controller.awaitingApproval, isTrue);
        expect(harness.controller.pending.single.layout!.narrow.mainLimit, 2);
        expect(await harness.stored(UiLayoutController.storageKey), isNull);
        final baseline = await harness.container.read(uiLayoutProvider.future);
        final editor = Object();
        if (dirtyDraft) {
          final sessions = harness.container.read(
            uiLayoutEditorSessionsProvider,
          );
          sessions.open(editor);
          sessions.markDirty(editor, true);
        } else {
          await harness.container
              .read(uiLayoutProvider.notifier)
              .save(
                UiLayout(
                  narrow: baseline.narrow,
                  wide: UiLayoutProfile(mainLimit: 7),
                ),
              );
        }
        await harness.controller.approvePending();
        expect(
          harness.controller.error,
          contains(dirtyDraft ? '草稿' : '其他操作修改'),
        );
        final current = await harness.container.read(uiLayoutProvider.future);
        expect(current.narrow.toJson(), baseline.narrow.toJson());
        expect(
          current.wide.mainLimit,
          dirtyDraft ? baseline.wide.mainLimit : 7,
        );
        expect(harness.controller.canUndo, isFalse);
        expect(harness.model.requests, hasLength(1));
      },
    );
  }

  test(
    'successful task undo restores only changed fields with guarded snapshot',
    () async {
      final harness = _Harness(
        _script([
          _calls([_update('task-1')]),
          _done(),
        ]),
      );
      await harness.task('task-1');
      harness.grant(delegated: true);
      await harness.controller.send('Rename task');
      expect(harness.controller.error, isNull);
      expect(harness.controller.canUndo, isTrue);
      await harness.controller.undoLast();
      final restored = await harness.readTask('task-1');
      expect(restored.title, 'Original task-1');
      expect(restored.notes, _notes);
      expect(harness.controller.canUndo, isFalse);
      expect(harness.controller.error, isNull);
      expect(await harness.journal(), hasLength(2));
      expect(harness.model.requests, hasLength(2));
    },
  );

  test(
    'conflicting same-second undo preserves concurrent notes and title',
    () async {
      final harness = _Harness(
        _script([
          _calls([_update('task-1')]),
          _done(),
        ]),
      );
      await harness.task('task-1');
      harness.grant(delegated: true);
      await harness.controller.send('Rename task');
      final applied = await harness.readTask('task-1');
      await harness.editTask(
        'task-1',
        const TasksCompanion(notes: Value('Concurrent notes')),
      );
      expect((await harness.readTask('task-1')).updatedAt, applied.updatedAt);
      await harness.controller.undoLast();
      expect(harness.controller.error, contains('变化'));
      final current = await harness.readTask('task-1');
      expect(current.title, 'Assistant changed title');
      expect(current.notes, 'Concurrent notes');
      expect(await harness.journal(), hasLength(1));
    },
  );

  test('layout apply and undo preserve independent wide profile', () async {
    final harness = _Harness(
      _script([
        _calls([
          _call('layout_patch', {'profile': 'narrow', 'mainLimit': 2}),
        ]),
        _done(),
      ]),
    );
    final original = UiLayout(
      narrow: UiLayoutProfile(mainLimit: 5),
      wide: UiLayoutProfile(mainLimit: 8),
    );
    await harness.container.read(uiLayoutProvider.future);
    await harness.container.read(uiLayoutProvider.notifier).save(original);
    harness.grant(delegated: true);
    await harness.controller.send('Adjust narrow layout');
    final applied = await harness.container.read(uiLayoutProvider.future);
    expect(applied.narrow.mainLimit, 2);
    expect(applied.wide.toJson(), original.wide.toJson());
    expect(harness.controller.canUndo, isTrue);
    await harness.controller.undoLast();
    expect(
      await harness.stored(UiLayoutController.storageKey),
      original.toJson(),
    );
    expect(harness.controller.error, isNull);
    expect(harness.controller.canUndo, isFalse);
  });

  test('layout undo rejects concurrent profile changes', () async {
    final harness = _Harness(
      _script([
        _calls([
          _call('layout_patch', {'profile': 'narrow', 'mainLimit': 2}),
        ]),
        _done(),
      ]),
    );
    harness.grant(delegated: true);
    await harness.controller.send('Adjust narrow layout');
    final applied = await harness.container.read(uiLayoutProvider.future);
    final concurrent = UiLayout(
      narrow: applied.narrow,
      wide: UiLayoutProfile(mainLimit: 9),
    );
    await harness.container.read(uiLayoutProvider.notifier).save(concurrent);
    await harness.controller.undoLast();
    expect(harness.controller.error, contains('其他操作修改'));
    expect(
      await harness.stored(UiLayoutController.storageKey),
      concurrent.toJson(),
    );
  });

  test(
    'same-round duplicate tool IDs do not apply any prepared writes',
    () async {
      final harness = _Harness(
        _script([
          _calls([
            _call('task_create', {'title': 'First'}),
            _call('task_create', {'title': 'Second'}),
          ]),
        ]),
      );
      harness.grant(delegated: true);
      await harness.controller.send('Create tasks');
      expect(harness.controller.error, contains('ID 重复'));
      expect(
        await harness.database.select(harness.database.tasks).get(),
        isEmpty,
      );
      expect(await harness.journal(), isEmpty);
      expect(harness.controller.awaitingApproval, isFalse);
    },
  );

  for (final changedArguments in [false, true]) {
    test(
      'cross-round duplicate tool ID ${changedArguments ? 'changed' : 'same'} never replays writes',
      () async {
        final harness = _Harness(
          _script([
            _calls([
              _call('task_create', {'title': 'First'}),
            ]),
            _calls([
              _call('task_create', {
                'title': changedArguments ? 'Second' : 'First',
              }),
            ]),
            _done(),
          ]),
        );
        harness.grant(delegated: true);
        await harness.controller.send('Create one task');
        final tasks = await harness.database
            .select(harness.database.tasks)
            .get();
        expect(tasks.single.title, 'First');
        expect(await harness.journal(), hasLength(1));
        expect(
          harness.controller.audit.where((item) => item.status == '已执行'),
          hasLength(1),
        );
        final results = harness.model.requests.last.messages
            .where((message) => message.toolCallId == 'call-1')
            .map((message) => jsonDecode(message.content) as Map)
            .toList();
        expect(results, hasLength(2));
        if (changedArguments) {
          expect(results.last['error'], contains('参数发生变化'));
        } else {
          expect(results.last, results.first);
        }
      },
    );
  }

  test(
    'expiration after prepare blocks manual approval without effects',
    () async {
      final grant = _ExpiringGrant(delegated: false);
      final harness = _Harness(
        _script([
          _calls([_update('task-1')]),
        ]),
      );
      await harness.task('task-1');
      harness.controller.setGrant(grant);
      await harness.controller.send('Rename task');
      expect(harness.controller.awaitingApproval, isTrue);
      grant.expireNow = true;
      await harness.controller.approvePending();
      expect((await harness.readTask('task-1')).title, 'Original task-1');
      expect(await harness.journal(), isEmpty);
      expect(harness.model.requests, hasLength(1));
    },
  );

  test('mutation budget spans requests and stops at twenty writes', () async {
    final model = _Model(
      (request, round) => round.isOdd
          ? _calls([
              _call('task_create', {
                'title': 'Created $round',
              }, id: 'create-$round'),
            ])
          : _done(),
    );
    final harness = _Harness(model);
    harness.grant(delegated: true);
    for (
      var operation = 0;
      operation < AssistantController.maxMutations;
      operation++
    ) {
      await harness.controller.send('Create one task');
      expect(harness.controller.error, isNull);
    }
    await harness.controller.send('Exceed grant budget');
    expect(harness.controller.error, contains('20次'));
    expect(
      await harness.database.select(harness.database.tasks).get(),
      hasLength(20),
    );
    expect(await harness.journal(), hasLength(20));
    expect(harness.controller.awaitingApproval, isFalse);
    expect(model.requests, hasLength(41));
  });

  test('round budget ends read-only loop after eight model requests', () async {
    final harness = _Harness(
      _Model(
        (request, round) =>
            _calls([_call('ui_catalog', {}, id: 'read-$round')]),
      ),
    );
    harness.grant();
    await harness.controller.send('Read catalog repeatedly');
    expect(harness.model.requests, hasLength(AssistantController.maxRounds));
    expect(harness.controller.error, contains('8次'));
    expect(harness.controller.busy, isFalse);
    expect(await harness.journal(), isEmpty);
  });

  test('tool budget rejects oversized round before any effects', () async {
    final harness = _Harness(
      _script([
        _calls(
          List.generate(
            25,
            (index) => _call('task_create', {
              'title': 'Task $index',
            }, id: 'create-$index'),
          ),
        ),
      ]),
    );
    harness.grant(delegated: true);
    await harness.controller.send('Too many tasks');
    expect(harness.controller.error, contains('工具调用达到上限'));
    expect(
      await harness.database.select(harness.database.tasks).get(),
      isEmpty,
    );
    expect(await harness.journal(), isEmpty);
    expect(harness.controller.awaitingApproval, isFalse);
  });

  test('partial apply failure keeps prior success, skips later writes and allows undo', () async {
    final harness = _Harness(
      _script([
        _calls([
          _update('first', id: 'first'),
          _update('second', id: 'second'),
          _call('task_create', {'title': 'Never created'}, id: 'third'),
        ]),
      ]),
    );
    await harness.task('first');
    await harness.task('second');
    harness.grant();
    await harness.controller.send('Modify tasks');
    expect(harness.controller.pending, hasLength(3));
    await harness.editTask(
      'second',
      const TasksCompanion(notes: Value('Concurrent edit')),
    );
    await harness.controller.approvePending();
    expect((await harness.readTask('first')).title, 'Assistant changed title');
    expect((await harness.readTask('second')).title, 'Original second');
    expect((await harness.readTask('second')).notes, 'Concurrent edit');
    expect(
      await harness.database.select(harness.database.tasks).get(),
      hasLength(2),
    );
    expect(await harness.journal(), hasLength(1));
    expect(harness.controller.error, contains('变化'));
    expect(harness.controller.audit.map((item) => item.status).first, '已执行');
    expect(harness.controller.audit[1].status, startsWith('未完成'));
    expect(harness.controller.audit.last.status, '未执行：上一操作失败');
    expect(harness.controller.canUndo, isTrue);
    expect(harness.controller.awaitingApproval, isFalse);
    expect(harness.model.requests, hasLength(1));
    await harness.controller.undoLast();
    expect((await harness.readTask('first')).title, 'Original first');
    expect((await harness.readTask('second')).notes, 'Concurrent edit');
    expect(await harness.journal(), hasLength(2));
  });

  for (final completion in [false, true]) {
    test(
      'atomic ${completion ? 'completion' : 'update'} undo guard excludes postcommit edit and model data',
      () async {
        late _Harness harness;
        harness = _Harness(
          _script([
            _calls([
              completion
                  ? _call('task_complete', {'id': 'task-1', 'completed': true})
                  : _update('task-1'),
            ]),
            _done(),
          ]),
          afterCommand: (command, payload, result) async {
            expect(payload['expectedValues'], isA<Map>());
            expect((result as Map)['notes'], _notes);
            await harness.editTask(
              'task-1',
              const TasksCompanion(notes: Value('Postcommit user edit')),
            );
          },
        );
        await harness.task('task-1');
        harness.grant(delegated: true);
        await harness.controller.send('Change task');
        expect(harness.controller.error, isNull);
        expect(harness.controller.canUndo, isTrue);
        final result = harness.model.requests.last.result('call-1');
        expect(result, {'id': 'task-1', 'applied': true});
        for (final request in harness.model.requests) {
          final wire = jsonEncode(
            request.messages.map((message) => message.toJson()).toList(),
          );
          expect(wire, isNot(contains(_notes)));
          expect(wire, isNot(contains(_apiKey)));
          expect(wire, isNot(contains('expectedValues')));
          expect(wire, isNot(contains('updatedAt')));
          expect(wire, isNot(contains('Postcommit user edit')));
        }
        await harness.controller.undoLast();
        expect(harness.controller.error, contains('变化'));
        expect(harness.commands!.results, hasLength(1));
        final current = await harness.readTask('task-1');
        expect(current.notes, 'Postcommit user edit');
        expect(current.completedAt != null, completion);
        expect(
          current.title,
          completion ? 'Original task-1' : 'Assistant changed title',
        );
        expect(await harness.journal(), hasLength(1));
      },
    );
  }

  test(
    'read-only grant deadline drops awaited query result without sharing tasks',
    () async {
      final gate = Completer<void>();
      final harness = _Harness(
        _script([
          _calls([_call('tasks_list', {}, id: 'read')]),
        ]),
        queryGate: gate,
      );
      await harness.task('task-1');
      final grant = _ExpiringGrant(delegated: false, writeTasks: false);
      harness.controller.setGrant(grant);
      final sending = harness.controller.send('List tasks');
      await harness.reading.future;
      expect(
        harness.model.requests.first.tools.map((tool) => tool.name),
        isNot(contains('task_update')),
      );
      expect(harness.controller.awaitingApproval, isFalse);
      grant.expireNow = true;
      gate.complete();
      await sending;
      expect(harness.controller.error, contains('授权失效'));
      expect(harness.model.requests, hasLength(1));
      expect(
        harness.model.requests.single.messages.where(
          (message) => message.role == 'tool',
        ),
        isEmpty,
      );
      expect(harness.controller.awaitingApproval, isFalse);
      expect(harness.controller.busy, isFalse);
      expect(await harness.journal(), isEmpty);
    },
  );

  test('retained conversation preserves completed text across sends', () async {
    final harness = _Harness(
      _script([AssistantModelReply(text: 'Previous reply'), _done()]),
    );
    harness.controller.setGrant(AssistantGrant());
    await harness.controller.send('First prompt');
    await harness.controller.send('Follow-up prompt');
    expect(
      harness.model.requests.last.messages.map((message) => message.role),
      ['system', 'user', 'assistant', 'user'],
    );
    expect(harness.model.requests.last.messages[1].content, 'First prompt');
    expect(harness.model.requests.last.messages[2].content, 'Previous reply');
    expect(
      harness.model.requests.last.messages.last.content,
      'Follow-up prompt',
    );
    expect(
      harness.model.requests.last.tools.map((tool) => tool.name),
      isNot(contains('tasks_list')),
    );
  });

  test(
    'duplicate tool ID retained across sends never replays task creation',
    () async {
      final create = _call('task_create', {
        'title': 'Create once',
      }, id: 'same-id');
      final harness = _Harness(
        _script([
          _calls([create]),
          _done(),
          _calls([create]),
          _done(),
        ]),
      );
      harness.grant(delegated: true);
      await harness.controller.send('Create task');
      await harness.controller.send('Follow up on previous result');
      expect(
        harness.model.requests[2].messages.any(
          (message) => message.toolCallId == 'same-id',
        ),
        isTrue,
      );
      expect(
        await harness.database.select(harness.database.tasks).get(),
        hasLength(1),
      );
      expect(await harness.journal(), hasLength(1));
    },
  );

  test('successful completion undo restores native completed state', () async {
    final harness = _Harness(
      _script([
        _calls([
          _call('task_complete', {'id': 'task-1', 'completed': true}),
        ]),
        _done(),
      ]),
    );
    await harness.task('task-1');
    harness.grant(delegated: true);
    await harness.controller.send('Complete task');
    expect((await harness.readTask('task-1')).completedAt, isNotNull);
    expect(harness.model.requests.last.result('call-1'), {
      'id': 'task-1',
      'applied': true,
    });
    await harness.controller.undoLast();
    final restored = await harness.readTask('task-1');
    expect(restored.completedAt, isNull);
    expect(restored.title, 'Original task-1');
    expect(restored.notes, _notes);
    expect(harness.controller.error, isNull);
    expect(harness.controller.canUndo, isFalse);
    expect(await harness.journal(), hasLength(2));
  });

  test(
    'revocation after commit records true success but stops later actions',
    () async {
      late _Harness harness;
      harness = _Harness(
        _script([
          _calls([
            _update('first', id: 'first'),
            _update('second', id: 'second'),
          ]),
        ]),
        afterCommand: (command, payload, result) async {
          expect(command, 'task.updateFields');
          harness.controller.setGrant(null);
        },
      );
      await harness.task('first');
      await harness.task('second');
      harness.grant(delegated: true);
      await harness.controller.send('Rename tasks');
      expect(
        (await harness.readTask('first')).title,
        'Assistant changed title',
      );
      expect((await harness.readTask('second')).title, 'Original second');
      expect(await harness.journal(), hasLength(1));
      expect(
        harness.controller.audit.any((item) => item.status == '已执行'),
        isTrue,
      );
      expect(harness.controller.grant, isNull);
      expect(harness.controller.canUndo, isFalse);
      expect(harness.controller.awaitingApproval, isFalse);
      expect(harness.model.requests, hasLength(1));
    },
  );

  for (final newSend in [false, true]) {
    test(
      '${newSend ? 'new send' : 'stop'} clears epoch-bound temporary undo',
      () async {
        final harness = _Harness(
          _script([
            _calls([_update('task-1')]),
            _done(),
            if (newSend) _done(),
          ]),
        );
        await harness.task('task-1');
        harness.grant(delegated: true);
        await harness.controller.send('Rename task');
        expect(harness.controller.canUndo, isTrue);
        if (newSend) {
          await harness.controller.send('Hello');
        } else {
          harness.controller.stop();
        }
        expect(harness.controller.canUndo, isFalse);
        await harness.controller.undoLast();
        expect(
          (await harness.readTask('task-1')).title,
          'Assistant changed title',
        );
        expect(await harness.journal(), hasLength(1));
      },
    );
  }

  test('manual mixed prepare failure preserves valid pending action without early write', () async {
    final harness = _Harness(
      _script([
        _calls([
          _update('task-1', id: 'valid'),
          _call('task_create', {
            'title': 'Invalid',
            'priority': 9,
          }, id: 'invalid'),
        ]),
        _done(),
      ]),
    );
    await harness.task('task-1');
    harness.grant();
    await harness.controller.send('Rename and create');
    expect(harness.controller.pending, hasLength(1));
    expect(await harness.journal(), isEmpty);
    expect((await harness.readTask('task-1')).title, 'Original task-1');
    await harness.controller.approvePending();
    expect(
      harness.model.requests.last.result('invalid')['error'],
      isA<String>(),
    );
    expect(harness.model.requests.last.result('valid')['applied'], isTrue);
    expect(await harness.journal(), hasLength(1));
    expect(
      await harness.database.select(harness.database.tasks).get(),
      hasLength(1),
    );
  });

  test(
    'expiration during pending prepare never publishes or applies action',
    () async {
      final gate = Completer<void>();
      final harness = _Harness(
        _script([
          _calls([_update('task-1')]),
        ]),
        prepareGate: gate,
      );
      await harness.task('task-1');
      final grant = _ExpiringGrant();
      harness.controller.setGrant(grant);
      final sending = harness.controller.send('Rename task');
      await harness.preparing.future;
      grant.expireNow = true;
      gate.complete();
      await sending;
      expect(harness.controller.error, contains('授权失效'));
      expect(harness.controller.pending, isEmpty);
      expect((await harness.readTask('task-1')).title, 'Original task-1');
      expect(await harness.journal(), isEmpty);
      expect(harness.model.requests, hasLength(1));
    },
  );

  test(
    'model context over 256 KiB stops continuation before next model call',
    () async {
      final harness = _Harness(
        _script([
          AssistantModelReply(
            text: '过' * 90000,
            calls: [_call('ui_catalog', {}, id: 'read')],
          ),
          _done(),
        ]),
      );
      harness.controller.setGrant(AssistantGrant());
      await harness.controller.send('Read catalog');
      expect(harness.controller.error, contains('上下文过大'));
      expect(harness.model.requests, hasLength(1));
      expect(harness.controller.busy, isFalse);
      expect(await harness.journal(), isEmpty);
      await harness.controller.send('Start fresh');
      expect(harness.model.requests.last.messages, hasLength(2));
      expect(harness.controller.error, isNull);
    },
  );

  test(
    'completed conversation resets past eighty thousand characters',
    () async {
      final harness = _Harness(
        _script([
          AssistantModelReply(text: 'Previous context ${'text' * 20000}'),
          _done(),
        ]),
      );
      harness.controller.setGrant(AssistantGrant());
      await harness.controller.send('First prompt');
      await harness.controller.send('Fresh prompt');
      expect(harness.model.requests.last.messages, hasLength(2));
      expect(harness.model.requests.last.messages.last.content, 'Fresh prompt');
      expect(harness.model.requests.last.messages.first.role, 'system');
    },
  );

  test('completed conversation resets past one hundred messages', () async {
    final harness = _Harness(_Model((request, round) => _done()));
    harness.controller.setGrant(AssistantGrant());
    for (var turn = 0; turn < 51; turn++) {
      await harness.controller.send('Prompt $turn');
    }
    expect(harness.model.requests, hasLength(51));
    expect(harness.model.requests.last.messages, hasLength(2));
    expect(harness.model.requests.last.messages.last.content, 'Prompt 50');
    expect(harness.controller.error, isNull);
  });

  test('tool budget is cumulative across model rounds', () async {
    final harness = _Harness(
      _script([
        _calls(
          List.generate(
            12,
            (index) => _call('ui_catalog', {}, id: 'read-$index'),
          ),
        ),
        _calls(
          List.generate(
            13,
            (index) => _call('task_create', {
              'title': 'Task $index',
            }, id: 'create-$index'),
          ),
        ),
      ]),
    );
    harness.grant(delegated: true);
    await harness.controller.send('Exceed cumulative budget');
    expect(harness.controller.error, contains('工具调用达到上限'));
    expect(harness.model.requests, hasLength(2));
    expect(
      await harness.database.select(harness.database.tasks).get(),
      isEmpty,
    );
    expect(await harness.journal(), isEmpty);
  });

  test('settings apply and undo restore preferences without connection or secret writes', () async {
    final harness = _Harness(
      _script([
        _calls([
          _call('settings_patch', {'reduceMotion': true, 'haptics': false}),
        ]),
        _done(),
      ]),
    );
    harness.grant(delegated: true);
    await harness.controller.send('Adjust preferences');
    expect(await harness.stored(AppPreferencesController.storageKey), {
      'theme': 'system',
      'reduceMotion': true,
      'haptics': false,
    });
    expect(harness.controller.canUndo, isTrue);
    await harness.controller.undoLast();
    expect(
      await harness.stored(AppPreferencesController.storageKey),
      const AppPreferences().toJson(),
    );
    expect(harness.controller.error, isNull);
    expect(harness.controller.canUndo, isFalse);
  });

  test(
    'prepare errors are tool errors without effects or pending writes',
    () async {
      final harness = _Harness(
        _script([
          _calls([
            _call('task_update', {
              'id': 'task-1',
              'changes': {'notes': 'Forbidden'},
            }, id: 'notes'),
            _call('settings_patch', {'apiKey': 'Forbidden'}, id: 'settings'),
            _call('task_create', {
              'title': 'Bad date',
              'dueDate': '2026-02-30',
            }, id: 'date'),
          ]),
          _done(),
        ]),
      );
      await harness.task('task-1');
      harness.grant(delegated: true);
      await harness.controller.send('Invalid operations');
      for (final id in ['notes', 'settings', 'date']) {
        expect(harness.model.requests.last.result(id)['error'], isA<String>());
      }
      expect(await harness.journal(), isEmpty);
      expect(harness.controller.awaitingApproval, isFalse);
      expect(await harness.stored(AppPreferencesController.storageKey), isNull);
      expect((await harness.readTask('task-1')).notes, _notes);
      expect(
        await harness.database.select(harness.database.tasks).get(),
        hasLength(1),
      );
    },
  );
}
