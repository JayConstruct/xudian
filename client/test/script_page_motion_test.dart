import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/script_page.dart';
import 'package:task_app/core/ui/script_transition.dart';
import 'package:task_app/data/app_database.dart';

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory folder;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    folder = await Directory.systemTemp.createTemp('page-motion-');
    host = ModuleHost(store: store, directory: folder);
    await host.initialize();
    await host.install(
      await ScriptPackage.verify(
        await ScriptPackage.build(
          {
            'formatVersion': 3,
            'manifest': {
              'id': 'test.motion',
              'version': '1.0.0',
              'hostApi': '^1.43.0',
              'dataVersion': 1,
              'permissions': ['ui'],
              'dependencies': [],
            },
            'entryPoint': 'main.js',
            'pages': [],
            'services': [],
            'collections': [],
          },
          {
            'main.js': r'''
import {ui} from '@xudian/sdk';
export async function render({state={},event,formValues={}}) {
  state={...state};
  if(event?.type==='field') await ui.dialog({title:'sync',fields:[]});
  if(event?.type==='next') {state.page='detail';state.direction='forward';}
  if(event?.type==='back') {state.page='home';state.direction='back';}
  if(event?.type==='save') {
    state.count=(state.count||0)+1;
    state.saved=formValues.title;
    await ui.dialog({title:'submit',fields:[]});
  }
  const detail=state.page==='detail';
  return {state,tree:{type:'column',scrollKey:detail?'detail':'home',compact:true,queueInputActions:true,
    pageTransition:{direction:state.direction||'forward',duration:260},
    footerMessage:state.saved?{type:'notice',text:'已保存:'+state.saved,tone:'success'}:null,
    children:detail?[
      {type:'text',text:'详情'},
      {type:'button',text:'返回',event:{type:'back'}},
      ...Array.from({length:30},(_,i)=>({type:'text',text:'内容'+i}))
    ]:[
      {type:'input',key:'title',text:'名称',value:'',onChangeEvent:{type:'field',key:'title'}},
      {type:'listTile',title:'打开详情',event:{type:'next'}},
      {type:'text',text:'次数:'+(state.count||0)}
    ],
    footer:detail?null:
      {type:'button',text:'保存',variant:'filled',event:{type:'save'}}
  }};
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
    await folder.delete(recursive: true);
  });
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 18; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> mount(WidgetTester tester, {bool reduced = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Scaffold(
            body: ScriptPage(
              host: host,
              moduleId: 'test.motion',
              handler: 'render',
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  for (final reduced in [false, true]) {
    testWidgets(
      'bounded scroll page transitions and footer support reduced=$reduced',
      (tester) async {
        await mount(tester, reduced: reduced);
        final transition = find.byKey(
          const ValueKey('script-page-transition:content'),
        );
        final initialState = tester.state(transition);
        await tester.tap(find.text('打开详情'));
        await settle(tester);
        expect(find.text('详情'), findsOneWidget);
        expect(tester.state(transition), same(initialState));
        expect(
          tester.widget<ScriptTransition>(transition).fillViewport,
          isTrue,
        );
        expect(tester.getSize(transition).height.isFinite, isTrue);
        await tester.tap(find.text('返回'));
        await settle(tester);
        expect(find.text('打开详情'), findsOneWidget);
        expect(
          tester.widget<ScriptTransition>(transition).navigationDirection,
          'back',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'footer hides over intermediate frames and returns without a jump',
    (tester) async {
      await mount(tester);
      final presence = find.byKey(
        const ValueKey('script-page-footer-presence'),
      );
      final before = tester.getSize(presence).height;
      expect(before, greaterThan(0));
      await tester.tap(find.text('打开详情'));
      for (var i = 0; i < 30 && find.text('详情').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.text('详情'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getSize(presence).height, inExclusiveRange(0, before));
      expect(find.text('保存').hitTestable(), findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getSize(presence).height, 0);
      await tester.tap(find.text('返回'));
      await settle(tester);
      expect(tester.getSize(presence).height, closeTo(before, .1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'input refresh accepts one action then locks repeated submission',
    (tester) async {
      final syncing = Completer<void>(), submitting = Completer<void>();
      host.interaction = (_, method, args) async {
        if (method == 'ui.dialog') {
          if (args['title'] == 'sync') await syncing.future;
          if (args['title'] == 'submit') await submitting.future;
        }
        return null;
      };
      await mount(tester);
      await tester.enterText(find.byType(TextField), '最新名称');
      await tester.pump(const Duration(milliseconds: 160));
      await settle(tester);
      final button = find.widgetWithText(FilledButton, '保存');
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      await tester.tap(button);
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      syncing.complete();
      await settle(tester);
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      submitting.complete();
      await settle(tester);
      expect(find.text('次数:1'), findsOneWidget);
      expect(find.text('已保存:最新名称'), findsOneWidget);
      expect(
        tester.getBottomLeft(find.text('已保存:最新名称')).dy,
        lessThan(tester.getTopLeft(button).dy),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
