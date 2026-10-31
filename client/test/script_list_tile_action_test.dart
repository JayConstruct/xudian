import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/script_page.dart';
import 'package:task_app/core/ui/ui_icons.dart';
import 'package:task_app/data/app_database.dart';

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory folder;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    folder = await Directory.systemTemp.createTemp('list-tile-action-');
    host = ModuleHost(store: store, directory: folder);
    await host.initialize();
    final bytes = await ScriptPackage.build(
      {
        'formatVersion': 3,
        'manifest': {
          'id': 'test.actions',
          'version': '1.0.0',
          'hostApi': '^1.41.0',
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
export async function render({state={},event,context={}}) {
  state={...state};
  if(event) {
    state.history=[...(state.history||[]),event.type];
    if(event.type==='hold') await ui.dialog({title:'等待',fields:[]});
  }
  return {state,tree:{type:'column',compact:true,children:[
    {type:'card',children:[{
      type:'listTile',key:'summary',icon:'location',title:'地点',
      subtitle:'图书馆302 · 一楼自习区',event:{type:'edit'},
      disabled:!!context.disabled,
      ...(context.trailing?{trailing:'已添加',trailingAccent:true}:{}),
      trailingAction:{icon:context.tonal?'add':'close',label:'移除地点',
        tonal:!!context.tonal,disabled:!!context.actionDisabled,event:{type:'remove'}}
    }]},
    {type:'listTile',key:'info-only',title:'仅操作的信息行',
      trailingAction:{icon:'add',label:'添加信息',event:{type:'add'}}},
    {type:'listTile',key:'legacy',title:'原有导航',trailing:'查看',event:{type:'legacy'}},
    {type:'button',text:'等待操作',event:{type:'hold'}},
    {type:'text',text:'事件：'+(state.history||[]).join(',')}
  ]}};
}
''',
      },
    );
    await host.install(
      await ScriptPackage.verify(bytes, allowUnsignedLocal: true),
    );
  });

  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await folder.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> mount(
    WidgetTester tester, {
    Map<String, Object?> context = const {},
    TextScaler scaler = TextScaler.noScaling,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: MediaQuery(
          data: MediaQueryData(size: const Size(320, 900), textScaler: scaler),
          child: Scaffold(
            body: ScriptPage(
              host: host,
              moduleId: 'test.actions',
              handler: 'render',
              pageContext: context,
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets(
    'secondary action is labelled, retains a 48dp target and does not trigger the tile event',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await mount(tester);
      expect(
        tester.getSemantics(find.byTooltip('移除地点')).getSemanticsData().tooltip,
        '移除地点',
      );
      final action = find.byTooltip('移除地点');
      final target = find
          .ancestor(of: action, matching: find.byType(IconButton))
          .first;
      expect(tester.getSize(target).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
      await tester.tap(action);
      await settle(tester);
      expect(find.text('事件：remove'), findsOneWidget);
      await tester.tap(find.text('地点'));
      await settle(tester);
      expect(find.text('事件：remove,edit'), findsOneWidget);
      await tester.tap(find.byTooltip('添加信息'));
      await settle(tester);
      expect(find.text('事件：remove,edit,add'), findsOneWidget);
      await tester.tap(find.text('原有导航'));
      await settle(tester);
      expect(find.text('事件：remove,edit,add,legacy'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'tonal action and trailing text remain usable at 320dp with large text in $brightness',
      (tester) async {
        await mount(
          tester,
          context: {'tonal': true, 'trailing': true},
          scaler: TextScaler.linear(2),
          brightness: brightness,
        );
        final action = find.byTooltip('移除地点');
        final target = find
            .ancestor(of: action, matching: find.byType(IconButton))
            .first;
        final surface = tester.widget<Material>(
          find.descendant(of: target, matching: find.byType(Material)).first,
        );
        expect(surface.color?.a, greaterThan(0));
        final paints = tester.widgetList<CustomPaint>(
          find.descendant(
            of: find.byKey(const ValueKey('summary')),
            matching: find.byType(CustomPaint),
          ),
        );
        expect(
          paints
              .where((paint) => paint.painter is AppIconPainter)
              .map((paint) => (paint.painter as AppIconPainter).glyph),
          containsAll([AppGlyph.location, AppGlyph.add]),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(action);
        await settle(tester);
        expect(find.text('事件：remove'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'action disabled state is independent, while tile disabled state protects both interactions',
    (tester) async {
      await mount(tester, context: {'actionDisabled': true});
      expect(
        tester
            .widget<IconButton>(
              find
                  .ancestor(
                    of: find.byTooltip('移除地点'),
                    matching: find.byType(IconButton),
                  )
                  .first,
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('地点'));
      await settle(tester);
      expect(find.text('事件：edit'), findsOneWidget);
      await mount(tester, context: {'disabled': true});
      expect(
        tester
            .widget<IconButton>(
              find
                  .ancestor(
                    of: find.byTooltip('移除地点'),
                    matching: find.byType(IconButton),
                  )
                  .first,
            )
            .onPressed,
        isNull,
      );
      final tile = tester.widget<ListTile>(
        find.descendant(
          of: find.byKey(const ValueKey('summary')),
          matching: find.byType(ListTile),
        ),
      );
      expect(tile.onTap, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending page work disables the secondary action and re-enables it after completion',
    (tester) async {
      final response = Completer<Object?>();
      host.interaction = (_, method, _) async {
        expect(method, 'ui.dialog');
        return response.future;
      };
      await mount(tester);
      await tester.tap(find.text('等待操作'));
      await settle(tester);
      expect(
        tester
            .widget<IconButton>(
              find
                  .ancestor(
                    of: find.byTooltip('移除地点'),
                    matching: find.byType(IconButton),
                  )
                  .first,
            )
            .onPressed,
        isNull,
      );
      response.complete(null);
      await settle(tester);
      expect(
        tester
            .widget<IconButton>(
              find
                  .ancestor(
                    of: find.byTooltip('移除地点'),
                    matching: find.byType(IconButton),
                  )
                  .first,
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
