import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/native_command_approval.dart';
import 'package:task_app/core/module_host/plan_confirmation.dart';
import 'package:task_app/core/module_host/script_page.dart';
import 'package:task_app/data/app_database.dart';

const reference = {
  'moduleId': 'test.command',
  'serviceId': 'save',
  'majorVersion': 1,
};
const input = {'id': 'a', 'title': '保存内容'};
const write = {'collection': 'notes', 'id': 'a', 'value': input};

void main() {
  test(
    'a native capability freezes exact service and input and is single use',
    () {
      final mutable = {'id': 'a', 'title': '保存内容'};
      final approval = NativeCommandApproval.fromInteraction({
        'ref': reference,
        'input': mutable,
      })!;
      mutable['title'] = 'changed after click';
      expect(
        approval.allows(
          reference: reference,
          input: input,
          writes: [write],
          confirmation: null,
        ),
        true,
      );
      expect(
        approval.allows(
          reference: reference,
          input: input,
          writes: [write],
          confirmation: null,
        ),
        false,
      );
    },
  );

  test('wrong input, service, deletion, batch or acknowledgement consume authority', () {
    final acknowledgement = PlanConfirmation.parse({
      'title': '风险',
      'message': '需要核对',
      'confirmLabel': '继续',
      'acknowledgement': '我已核对风险',
    });
    final cases = [
      {
        'input': {...input, 'title': 'unexpected'},
      },
      {
        'reference': {...reference, 'serviceId': 'different'},
      },
      {
        'reference': {...reference, 'majorVersion': 2},
      },
      {
        'writes': [
          {...write, 'value': null},
        ],
      },
      {
        'writes': [
          {
            ...write,
            'value': {...input, 'deletedAt': '2026-10-23'},
          },
        ],
      },
      {
        'writes': [
          write,
          {...write, 'id': 'b'},
        ],
      },
      {'writes': <Object?>[]},
      {'confirmation': acknowledgement},
    ];
    for (final candidate in cases) {
      final approval = NativeCommandApproval.fromInteraction({
        'ref': reference,
        'input': input,
      })!;
      expect(
        approval.allows(
          reference: candidate['reference'] ?? reference,
          input: candidate['input'] ?? input,
          writes: (candidate['writes'] as List<Object?>?) ?? [write],
          confirmation: candidate['confirmation'] as PlanConfirmation?,
        ),
        false,
        reason: '$candidate',
      );
      expect(
        approval.allows(
          reference: reference,
          input: input,
          writes: [write],
          confirmation: null,
        ),
        false,
      );
    }
  });

  test(
    'form mappings freeze only submitted fields and require present values',
    () {
      final binding = {
        'ref': reference,
        'input': {'id': 'a'},
        'fields': {'title': 'name'},
      };
      expect(NativeCommandApproval.fromInteraction(binding), isNull);
      expect(
        NativeCommandApproval.fromInteraction(
          binding,
          submittedValues: {'unmapped': '保存内容'},
        ),
        isNull,
      );
      final approval = NativeCommandApproval.fromInteraction(
        binding,
        submittedValues: {'name': '保存内容', 'unmapped': 'ignored'},
      )!;
      expect(
        approval.allows(
          reference: reference,
          input: input,
          writes: [write],
          confirmation: null,
        ),
        true,
      );
    },
  );

  group('actual page interactions', () {
    late AppDatabase db;
    late CollectionStore store;
    late ModuleHost host;
    late Directory directory;
    var reviews = 0;
    Object? formResult;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      store = CollectionStore(db);
      directory = await Directory.systemTemp.createTemp('native-command-');
      host = ModuleHost(store: store, directory: directory);
      await host.initialize();
      reviews = 0;
      formResult = null;
      host.interaction = (_, method, args) async {
        if (method == 'ui.review') reviews++;
        if (method == 'ui.dialog') return formResult;
        return false;
      };
      await host.install(
        await ScriptPackage.verify(
          await ScriptPackage.build(
            {
              'formatVersion': 3,
              'manifest': {
                'id': 'test.command',
                'version': '1.0.0',
                'hostApi': '^1.38.0',
                'dataVersion': 1,
                'permissions': ['ui'],
              },
              'entryPoint': 'main.js',
              'pages': [],
              'collections': [
                {
                  'id': 'notes',
                  'schema': {'type': 'object'},
                  'indexes': [],
                },
              ],
              'services': [
                {
                  'id': 'save',
                  'major': 1,
                  'kind': 'command',
                  'handler': 'save',
                  'input': {'type': 'object'},
                  'output': {'type': 'object'},
                  'confirmation': 'host',
                },
              ],
            },
            {
              'main.js': r'''
import {services,ui} from '@xudian/sdk';
const ref={moduleId:'test.command',serviceId:'save',majorVersion:1};
const input={id:'a',title:'保存内容'};
export function save(v) {
  return {writes:[{collection:'notes',id:v.id,value:v}],result:{saved:true}};
}
export async function render({context={},event,state={},formValues={}}={}) {
  if(event?.type==='save') {
    const plan=await services.prepare(ref,context.wrong?{...input,title:'wrong'}:input);
    if(await ui.review(plan.planId)) {
      await services.commit(plan.planId);state={saved:true};
    }
    if(context.twice)await ui.review(plan.planId);
  }
  if(event?.type==='form') {
    const submitted=await ui.dialog({title:'编辑',fields:[],command:{
      ref,input:{id:'a'},fields:{title:'name'}}});
    if(submitted) {
      const plan=await services.prepare(ref,{id:'a',title:submitted.name});
      if(await ui.review(plan.planId)) {
        await services.commit(plan.planId);state={saved:true};
      }
    }
  }
  if(event?.type==='saveQuick') {
    const plan=await services.prepare(ref,{id:'a',title:formValues.quickTitle});
    if(await ui.review(plan.planId)) {
      await services.commit(plan.planId);state={saved:true};
    }
  }
  const command={ref,input};
  return {state,tree:{type:'column',children:[
    {type:'text',text:state.saved?'已保存':'未保存'},
    {type:'button',text:'原生保存',event:{type:'save'},command},
    {type:'button',text:'未绑定',event:{type:'save'}},
    {type:'button',text:'打开表单',event:{type:'form'}},
    {type:'input',key:'quickTitle',text:'快建标题',event:{type:'saveQuick'},
      command:{ref,input:{id:'a',title:{bind:['formValues','quickTitle']}}}},
    {type:'taskItem',title:'勾选任务',completed:false,event:{type:'save'},command}
  ]}};
}
''',
            },
          ),
          allowUnsignedLocal: true,
        ),
      );
    });
    tearDown(() async {
      await host.close();
      await store.close();
      await db.close();
      await directory.delete(recursive: true);
    });
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    Future<void> show(
      WidgetTester tester, [
      Map<String, Object?> context = const {},
    ]) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScriptPage(
              host: host,
              moduleId: 'test.command',
              handler: 'render',
              pageContext: context,
            ),
          ),
        ),
      );
      await settle(tester);
    }

    Future<List<Object?>> records(WidgetTester tester) async =>
        (await tester.runAsync(
          () => store.query(host.instances['test.command']!.actor, 'notes', {}),
        ))!;

    testWidgets('a native bound button saves once without a second dialog', (
      tester,
    ) async {
      await show(tester, {'twice': true});
      await tester.tap(find.text('原生保存'));
      await settle(tester);
      expect(find.text('已保存'), findsOneWidget);
      expect(await records(tester), hasLength(1));
      expect(reviews, 1); // The repeated review needs its own confirmation.
      await tester.pumpWidget(const SizedBox.shrink());
    });
    testWidgets(
      'a real task checkbox supplies the same single-command capability',
      (tester) async {
        await show(tester);
        await tester.tap(find.byType(Checkbox));
        await settle(tester);
        expect(find.text('已保存'), findsOneWidget);
        expect(reviews, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
    testWidgets('keyboard submission freezes the current bound input value', (
      tester,
    ) async {
      await show(tester);
      await tester.enterText(find.byType(TextField), '键盘输入');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      final saved = object((await records(tester)).single);
      expect(saved['title'], '键盘输入');
      expect(reviews, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });
    testWidgets('an unbound event and mismatched command both require review', (
      tester,
    ) async {
      await show(tester, {'wrong': true});
      await tester.tap(find.text('原生保存'));
      await settle(tester);
      expect(reviews, 1);
      await tester.tap(find.text('未绑定'));
      await settle(tester);
      expect(reviews, 2);
      expect(await records(tester), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
    test(
      'a scripted event with identical JSON does not supply native authority',
      () async {
        await host.invokePage('test.command', 'render', {
          'event': {'type': 'save'},
        });
        expect(reviews, 1);
        expect(
          await store.query(host.instances['test.command']!.actor, 'notes', {}),
          isEmpty,
        );
      },
    );
    testWidgets(
      'a submitted form authorizes its mapped command and cancellation does not',
      (tester) async {
        await show(tester);
        await tester.tap(find.text('打开表单'));
        await settle(tester);
        expect(await records(tester), isEmpty);
        expect(reviews, 0);
        formResult = {'name': '保存内容'};
        await tester.tap(find.text('打开表单'));
        await settle(tester);
        expect(find.text('已保存'), findsOneWidget);
        expect(reviews, 0);
        await tester.tap(find.text('未绑定'));
        await settle(tester);
        expect(
          reviews,
          1,
        ); // A later workflow cannot reuse the form submission.
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });
}
