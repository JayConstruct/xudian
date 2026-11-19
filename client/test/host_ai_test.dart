import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/collection_store.dart';

import 'support/module_fixtures.dart' show sourcePackage;

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory dir;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    dir = await Directory.systemTemp.createTemp('host-ai-');
    host = ModuleHost(store: store, directory: dir);
    await host.initialize();
    await host.install(await sourcePackage('app.ai'));
    final actor = host.instances['app.ai']!.actor;
    final p = await host.prepare(
      actor,
      const ServiceRef('app.ai', 'ai.connection.save', 1),
      {
        'connection': {
          'endpoint': 'https://model.example/v1',
          'model': 'test',
          'credential': 'opaque',
        },
      },
    );
    host.review(p.id, actor);
    await host.commit(actor, p.id);
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await dir.delete(recursive: true);
  });
  Map<String, Object?> candidate(String version, {bool network = false}) => {
    'definition': {
      'formatVersion': 3,
      'manifest': {
        'id': 'private.generated',
        'name': '生成模块',
        'version': version,
        'hostApi': '^1.0.0',
        'dataVersion': 1,
        'permissions': ['ui'],
        'dependencies': [],
      },
      'entryPoint': 'main.js',
      'collections': [],
      'pages': [
        {
          'id': 'private.generated.home',
          'title': '生成页面',
          'handler': 'render',
          'entry': {
            'id': 'private.generated.home',
            'opening': 'workspace',
            'placement': 'main',
          },
        },
      ],
      'services': [],
    },
    'files': {
      'main.js':
          "${network ? "import {http} from '@xudian/sdk';" : ''} export ${network ? 'async ' : ''}function render() { ${network ? "await http.request({url:'https://example.com'});" : ''} return {state:{},tree:{type:'text',text:'$version'}}; }",
    },
  };
  Future<Object?> render(Map<String, Object?> input) =>
      host.invokePage('app.ai', 'render', input);
  test('protected source editor previews and updates private modules without AI installed', () async {
    await host.uninstall('app.ai');
    var approvals = 0;
    host.interaction = (actor, method, args) async {
      expect(actor.moduleId, 'app.host');
      expect(method, 'packages.review');
      approvals++;
      return true;
    };
    expect(await host.editLocalPackage(candidate('1.0.0')), true);
    expect(await host.editLocalPackage(candidate('1.0.1')), true);
    expect(approvals, 2);
    expect(host.instances.keys, ['private.generated']);
    expect(
      object(await host.invokePage('private.generated', 'render', {}))['tree'],
      {'type': 'text', 'text': '1.0.1'},
    );
  });
  test('AI chats and persists history with no task package', () async {
    host.interaction = (actor, method, args) async {
      if (method == 'ui.review') return true;
      if (method == 'http.request') {
        return {
          'status': 200,
          'body': jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': '你好'},
              },
            ],
          }),
        };
      }
      throw StateError('Unexpected bridge: $method');
    };
    final view = object(
      await render({
        'event': {'type': 'send'},
        'formValues': {'message': '你好'},
        'state': {},
      }),
    );
    expect(object(view['state'])['messages'], hasLength(2));
    expect(
      object(
        await store.get(
          host.instances['app.ai']!.actor,
          'history',
          'conversation',
        ),
      )['messages'],
      hasLength(2),
    );
    expect(host.instances.keys, ['app.ai']);
  });
  test(
    'AI advanced generation previews, reviews, installs and updates private JS',
    () async {
      var version = '1.0.0';
      host.interaction = (actor, method, args) async {
        if (method == 'ui.review' || method == 'packages.review') return true;
        if (method == 'http.request') {
          return {
            'status': 200,
            'body': jsonEncode({
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'content': jsonEncode(candidate(version)),
                  },
                },
              ],
            }),
          };
        }
        throw StateError('Unexpected bridge $method');
      };
      await render({
        'event': {'type': 'send'},
        'formValues': {'message': '生成模块'},
        'state': {'advanced': true},
      });
      expect(host.instances['private.generated']!.package.version, '1.0.0');
      version = '1.0.1';
      await render({
        'event': {'type': 'send'},
        'formValues': {'message': '更新模块'},
        'state': {'advanced': true},
      });
      expect(host.instances['private.generated']!.package.version, '1.0.1');
      expect(
        object(
          await host.invokePage('private.generated', 'render', {}),
        )['tree'],
        {'type': 'text', 'text': '1.0.1'},
      );
    },
  );
  test(
    'cancelled advanced review cannot install after a late approval',
    () async {
      final reviewing = Completer<void>(), decision = Completer<bool>();
      host.interaction = (actor, method, args) async {
        if (method == 'ui.review') return true;
        if (method == 'packages.review') {
          reviewing.complete();
          return decision.future;
        }
        if (method == 'http.request') {
          return {
            'status': 200,
            'body': jsonEncode({
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'content': jsonEncode(candidate('1.0.0')),
                  },
                },
              ],
            }),
          };
        }
        if (method == 'http.cancel') return null;
        throw StateError('Unexpected bridge $method');
      };
      final work = render({
        'event': {'type': 'send'},
        'formValues': {'message': '生成'},
        'state': {'advanced': true},
      });
      final expectation = expectLater(work, throwsStateError);
      await reviewing.future;
      await host.invokeInterrupt('app.ai', 'cancel');
      decision.complete(true);
      await expectation;
      expect(host.instances.containsKey('private.generated'), false);
    },
  );
  test(
    'preview rejects network even when candidate declares HTTP permission',
    () async {
      host.interaction = (actor, method, args) async {
        if (method == 'ui.review' || method == 'packages.review') return true;
        if (method == 'http.request') {
          return {
            'status': 200,
            'body': jsonEncode({
              'choices': [
                {
                  'message': {
                    'role': 'assistant',
                    'content': jsonEncode(candidate('1.0.0', network: true)),
                  },
                },
              ],
            }),
          };
        }
        throw StateError('Unexpected bridge $method');
      };
      await expectLater(
        render({
          'event': {'type': 'send'},
          'formValues': {'message': '生成'},
          'state': {'advanced': true},
        }),
        throwsStateError,
      );
      expect(host.instances.containsKey('private.generated'), false);
    },
  );
  test(
    'script AI deduplicates tools and conditionally undoes unchanged task',
    () async {
      await host.install(await sourcePackage('app.tasks'));
      final owner = host.instances['app.tasks']!.actor;
      Future<Object?> taskCommand(String id, Map<String, Object?> input) async {
        final p = await host.prepare(
          owner,
          ServiceRef('app.tasks', id, 1),
          input,
        );
        host.review(p.id, owner);
        return host.commit(owner, p.id);
      }

      final created = object(
        await taskCommand('task.create', {'title': '初始标题'}),
      );
      final toolIndex = host
          .directoryServices()
          .map(object)
          .where((s) => s['tool'] != null && s['moduleId'] != 'app.ai')
          .toList()
          .indexWhere((s) => s['id'] == 'task.updateFields');
      var requests = 0;
      host.interaction = (actor, method, args) async {
        if (method == 'ui.review' || method == 'grants.request') return true;
        if (method == 'http.request') {
          requests++;
          final call = {
            'id': 'same-tool',
            'type': 'function',
            'function': {
              'name': 'service_$toolIndex',
              'arguments': jsonEncode({
                'id': created['id'],
                'changes': {'title': 'AI修改'},
              }),
            },
          };
          return {
            'status': 200,
            'body': jsonEncode({
              'choices': [
                {
                  'message': requests.isOdd
                      ? {
                          'role': 'assistant',
                          'content': null,
                          'tool_calls': [call, call],
                        }
                      : {'role': 'assistant', 'content': '已更新'},
                },
              ],
            }),
          };
        }
        throw StateError('Unexpected bridge $method');
      };
      final before =
          (await store.sql(
                "SELECT COUNT(*) AS count FROM host_operations WHERE module_id='app.tasks'",
              )).single['count']
              as int;
      var view = object(
        await render({
          'event': {'type': 'send'},
          'formValues': {'message': '改标题'},
          'state': {},
        }),
      );
      expect(
        (await store.sql(
          "SELECT COUNT(*) AS count FROM host_operations WHERE module_id='app.tasks'",
        )).single['count'],
        before + 1,
      );
      expect(object(view['state'])['lastUndo'], isNotNull);
      await render({
        'event': {'type': 'undo'},
        'state': view['state'],
      });
      expect(
        object(
          await store.get(owner, 'tasks', created['id'] as String),
        )['title'],
        '初始标题',
      );
      view = object(
        await render({
          'event': {'type': 'send'},
          'formValues': {'message': '再改'},
          'state': {},
        }),
      );
      await taskCommand('task.updateFields', {
        'id': created['id'],
        'changes': {'title': '用户之后修改'},
      });
      await expectLater(
        render({
          'event': {'type': 'undo'},
          'state': view['state'],
        }),
        throwsStateError,
      );
      expect(
        object(
          await store.get(owner, 'tasks', created['id'] as String),
        )['title'],
        '用户之后修改',
      );
    },
  );
  test(
    'project AI review scopes the batch and writes only after approval',
    () async {
      await host.install(await sourcePackage('app.tasks'));
      final owner = host.instances['app.tasks']!.actor;
      final creation = await host.prepare(
        owner,
        const ServiceRef('app.tasks', 'project.create', 1),
        {'name': '交付'},
      );
      host.review(creation.id, owner);
      final project = object(await host.commit(owner, creation.id));
      var approve = false, requests = 0, reviews = 0;
      host.interaction = (_, method, args) async {
        if (method == 'grants.request') return true;
        if (method == 'ui.review') {
          final confirmation = args['confirmation'];
          if (confirmation == null) return true;
          final display = object(confirmation);
          expect(display['title'], '审核项目拆解');
          expect(display['message'], contains('审核分类 · 检查附件 · 15 分钟'));
          reviews++;
          expect(await store.query(owner, 'tasks', {}), isEmpty);
          return approve;
        }
        if (method == 'http.request') {
          requests++;
          return {
            'status': 200,
            'body': jsonEncode({
              'choices': [
                {
                  'message': requests.isOdd
                      ? {
                          'role': 'assistant',
                          'content': null,
                          'tool_calls': [
                            {
                              'id': 'draft',
                              'type': 'function',
                              'function': {
                                'name': 'service_0',
                                'arguments': jsonEncode({
                                  'projectId': 'model-suggested-id',
                                  'items': [
                                    {
                                      'title': '检查附件',
                                      'path': ['审核分类'],
                                      'estimatedMinutes': 15,
                                    },
                                  ],
                                }),
                              },
                            },
                          ],
                        }
                      : {'role': 'assistant', 'content': '已生成拆解方案'},
                },
              ],
            }),
          };
        }
        throw StateError('Unexpected bridge $method');
      };
      final input = {
        'context': {
          'pageId': 'app.ai.projectDraft',
          'projectId': project['id'],
          'projectName': '交付',
        },
        'event': {'type': 'send'},
        'formValues': {'message': '拆解交付工作'},
      };
      await host.invokePage('app.ai', 'render', input);
      expect(await store.query(owner, 'tasks', {}), isEmpty);
      approve = true;
      await host.invokePage('app.ai', 'render', input);
      expect(reviews, 2);
      final task = object((await store.query(owner, 'tasks', {})).single);
      expect(task['projectId'], project['id']);
      expect(task['estimatedMinutes'], 15);
      expect(await store.query(owner, 'projectActivity', {}), hasLength(1));
    },
  );
}
