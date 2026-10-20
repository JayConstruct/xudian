import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/data_change_review.dart';
import 'package:task_app/core/module_host/inline_plan_review.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/plan_confirmation.dart';
import 'package:task_app/core/module_host/script_page.dart';
import 'package:task_app/data/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;
  late ModuleActor actor;
  var serial = 0;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('inline-plan-');
    host = ModuleHost(store: store, directory: directory);
    await host.initialize();
    await host.install(
      await ScriptPackage.verify(
        await ScriptPackage.build(
          {
            'formatVersion': 3,
            'manifest': {
              'id': 'test.inline',
              'version': '1.0.0',
              'hostApi': '^1.27.0',
              'dataVersion': 1,
                'permissions': ['ui'],
            },
            'entryPoint': 'main.js',
            'pages': [],
            'services': [],
            'collections': [
              {
                'id': 'notes',
                'schema': {
                  'type': 'object',
                  'properties': {
                    'id': {'type': 'string'},
                    'title': {'type': 'string'},
                  },
                  'required': ['id', 'title'],
                },
                'indexes': [],
              },
            ],
          },
          {
            'main.js': r'''
import {ui, services} from '@xudian/sdk';
export async function render(input) {
  const context=input.context||{}, event=input.event||{};
  let saved=false;
  if(event.type==='save') {
    if(context.wait) await ui.dialog({title:'Pause',fields:[]});
    if(await ui.review(context.targetPlanId||context.planId)) {
      await services.commit(context.targetPlanId||context.planId);
      saved=true;
    }
  }
  return {state:{saved},tree:{type:'column',
    planReview:{planId:context.planId,eventType:'save'},
    children:[{type:'text',text:saved?'已保存':'脚本预览'},
      {type:'button',text:'正文模拟确认',event:{type:'save'}}],
    footer:{type:'row',children:[
      {type:'button',text:'取消',event:{type:'cancel'}},
      {type:'button',text:'确认导入',event:{type:'save'}}]}}};
}
export async function twice(input) {
  return [await ui.review(input.planId),await ui.review(input.planId)];
}
''',
          },
        ),
        allowUnsignedLocal: true,
      ),
    );
    actor = host.instances['test.inline']!.actor;
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  Future<ChangePlan> plan(String title, {bool adopted = false}) async {
    final snapshot = SnapshotSession(actor, 'inline-${serial++}')
      ..result = {'title': title};
    if (adopted) snapshot.approvals.add({'provider': actor.moduleId});
    await store.stage(snapshot, actor, {
      'writes': [
        {
          'collection': 'notes',
          'id': 'a',
          'value': {'id': 'a', 'title': title},
        },
      ],
    });
    final frozen = store.seal(snapshot);
    return adopted ? store.adoptProviderPlan(frozen.id, actor) : frozen;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> show(
    WidgetTester tester,
    Map<String, Object?> context, {
    bool largeText = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(largeText ? 1.5 : 1),
          ),
          child: Scaffold(
            body: ScriptPage(
              host: host,
              moduleId: actor.moduleId,
              handler: 'render',
              pageContext: context,
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  test(
    'native approval is exact, single use, and cannot approve acknowledgement',
    () async {
      final frozen = await plan('冻结数据');
      final clone = ChangePlan(
        frozen.id,
        frozen.caller,
        frozen.requestId,
        frozen.content,
        frozen.createdAt,
      );
      final wrong = InlinePlanApproval(frozen);
      expect(wrong.allows(clone, null), isFalse);
      expect(wrong.allows(frozen, null), isFalse);
      final single = InlinePlanApproval(frozen);
      expect(single.allows(frozen, null), isTrue);
      expect(single.allows(frozen, null), isFalse);
      final acknowledged = InlinePlanApproval(frozen);
      expect(
        acknowledged.allows(
          frozen,
          PlanConfirmation.parse({
            'title': '确认',
            'message': '需额外同意',
            'confirmLabel': '确认',
            'acknowledgement': '同意风险',
          }),
        ),
        isFalse,
      );
      expect(acknowledged.allows(frozen, null), isFalse);
    },
  );

  test('inline native callback supports adopted plans and is removed after invocation', () async {
    final frozen = await plan('采用计划', adopted: true);
    final approval = InlinePlanApproval(frozen);
    var reviews = 0;
    host.interaction = (_, method, args) async {
      if (method == 'ui.review') reviews++;
      return false;
    };
    expect(
      await host.invokePage(actor.moduleId, 'twice', {
        'planId': frozen.id,
      }, onInlineReview: approval.allows),
      [true, false],
    );
    expect(reviews, 1);
    expect(
      await host.invokePage(actor.moduleId, 'twice', {'planId': frozen.id}),
      [false, false],
    );
    expect(reviews, 3);
  });

  test(
    'a script declaration and event do not grant approval without native click',
    () async {
      final frozen = await plan('未经点击');
      var reviews = 0;
      host.interaction = (_, method, args) async {
        if (method == 'ui.review') reviews++;
        return false;
      };
      await host.invokePage(actor.moduleId, 'render', {
        'context': {'planId': frozen.id},
        'event': {'type': 'save'},
      });
      expect(reviews, 1);
      expect(await store.get(actor, 'notes', 'a'), isNull);
    },
  );

  testWidgets(
    'native fixed confirmation shows frozen details and commits adopted plan once without modal',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late ChangePlan frozen;
      await tester.runAsync(() async {
        frozen = await plan('真实冻结标题', adopted: true);
      });
      var reviews = 0;
      host.interaction = (_, method, args) async {
        if (method == 'ui.review') reviews++;
        return false;
      };
      await show(tester, {'planId': frozen.id}, largeText: true);
      expect(find.text('实际变更：新增 1 · 修改 0 · 删除 0'), findsOneWidget);
      final confirm = find.widgetWithText(FilledButton, '确认导入');
      expect(tester.getRect(confirm).bottom, lessThanOrEqualTo(780));
      await tester.tap(find.byTooltip('查看实际变更详情'));
      await tester.pumpAndSettle();
      expect(find.byType(DataChangeReview), findsOneWidget);
      expect(find.text('新增 · 真实冻结标题'), findsOneWidget);
      Navigator.of(tester.element(find.byType(DataChangeReview))).pop();
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await settle(tester);
      expect(reviews, 0);
      expect(find.text('已保存'), findsOneWidget);
      await tester.runAsync(() async {
        expect(object(await store.get(actor, 'notes', 'a'))['title'], '真实冻结标题');
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'body event falls back; native confirmation cannot substitute a different plan',
    (tester) async {
      late ChangePlan frozen, other;
      await tester.runAsync(() async {
        frozen = await plan('显示的计划');
        other = await plan('偷换的计划');
      });
      var reviews = 0;
      host.interaction = (_, method, args) async {
        if (method == 'ui.review') reviews++;
        return false;
      };
      await show(tester, {'planId': frozen.id, 'targetPlanId': other.id});
      await tester.tap(find.text('正文模拟确认'));
      await settle(tester);
      expect(reviews, 1);
      await tester.tap(find.widgetWithText(FilledButton, '确认导入'));
      await settle(tester);
      expect(reviews, 2);
      await tester.runAsync(() async {
        expect(await store.get(actor, 'notes', 'a'), isNull);
      });
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'changing page context while handler waits invalidates native approval',
    (tester) async {
      late ChangePlan frozen;
      await tester.runAsync(() async {
        frozen = await plan('旧页面');
      });
      final waiting = Completer<void>();
      final release = Completer<Object?>();
      var reviews = 0;
      host.interaction = (_, method, args) async {
        if (method == 'ui.dialog') {
          waiting.complete();
          return release.future;
        }
        if (method == 'ui.review') reviews++;
        return false;
      };
      await show(tester, {'planId': frozen.id, 'wait': true, 'pageId': 'old'});
      await tester.tap(find.widgetWithText(FilledButton, '确认导入'));
      await settle(tester);
      expect(
        waiting.isCompleted,
        isTrue,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((e) => e.data)
            .join('\n'),
      );
      await show(tester, {'planId': frozen.id, 'pageId': 'new'});
      release.complete(null);
      await settle(tester);
      expect(reviews, 1);
      await tester.runAsync(() async {
        expect(await store.get(actor, 'notes', 'a'), isNull);
      });
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
