import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/app.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_providers.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/time_grid.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';

Future<ScriptPackage> _scheduleSource() async {
  final directory = Directory('../packages/modules/app.schedule');
  final files = <String, String>{};
  await for (final entity in directory.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.js')) {
      files[entity.path.substring(directory.path.length + 1)] = await entity
          .readAsString();
    }
  }
  return ScriptPackage.verify(
    await ScriptPackage.build(
      object(
        jsonDecode(await File('${directory.path}/module.json').readAsString()),
      ),
      files,
    ),
    allowUnsignedLocal: true,
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 24; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory directory;
  late ModuleActor actor;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('schedule-chrome-');
    host = ModuleHost(store: store, directory: directory);
    host.clockNow = () => DateTime.utc(2026, 9, 7, 0, 30);
    await host.initialize();
    await host.install(await _scheduleSource());
    actor = host.instances['app.schedule']!.actor;
    final plan = await host.prepare(
      actor,
      const ServiceRef('app.schedule', 'schedule.timetable.save', 1),
      {
        'timetable': {
          'id': 'table',
          'name': '滚动课表',
          'firstMonday': '2026-09-07',
          'totalWeeks': 20,
          'timezone': 'Asia/Shanghai',
          'displayWeekStart': 1,
          'periods': [
            for (var i = 0; i < 12; i++)
              {
                'number': i + 1,
                'start': '${(8 + i).toString().padLeft(2, '0')}:00',
                'end': '${(8 + i).toString().padLeft(2, '0')}:45',
              },
          ],
        },
      },
    );
    host.review(plan.id, actor);
    await host.commit(actor, plan.id);
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });
  Future<void> pumpApp(
    WidgetTester tester, {
    double width = 420,
    bool largeText = false,
  }) async {
    tester.view.physicalSize = Size(width, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (largeText) {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((_) async => db),
          moduleHostProvider.overrideWith((_) async => host),
        ],
        child: XudianApp(),
      ),
    );
    await _settle(tester);
  }

  Finder verticalGrid() =>
      find.byKey(const PageStorageKey('time-grid-vertical'));
  Finder dock() => find.byKey(const ValueKey('mobile-bottom-dock'));
  bool dockVisible(WidgetTester tester) {
    final opacity = find.ancestor(
      of: dock(),
      matching: find.byType(AnimatedOpacity),
    );
    return opacity.evaluate().isEmpty ||
        tester.widget<AnimatedOpacity>(opacity.first).opacity > 0;
  }

  Future<void> scrollDown(WidgetTester tester) async {
    await tester.drag(verticalGrid(), const Offset(0, -260));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'vertical reading hides both phone bars and reveal or upward scrolling restores them',
    (tester) async {
      await pumpApp(tester, largeText: true);
      final semantics = tester.ensureSemantics();
      expect(find.byTooltip('打开设置'), findsOneWidget);
      expect(dockVisible(tester), isTrue);
      final viewport = tester.getSize(find.byType(TimeGrid));
      await scrollDown(tester);
      expect(find.byTooltip('打开设置'), findsNothing);
      expect(dockVisible(tester), isFalse);
      expect(
        find.byKey(const ValueKey('workspace-chrome-reveal')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('展开工具栏'), findsOneWidget);
      expect(
        tester.getSize(find.byType(TimeGrid)).height,
        greaterThan(viewport.height),
      );
      final ignore = find.ancestor(
        of: dock(),
        matching: find.byType(IgnorePointer),
      );
      expect(
        ignore.evaluate().map(
          (element) => (element.widget as IgnorePointer).ignoring,
        ),
        contains(true),
      );
      await tester.tap(find.byKey(const ValueKey('workspace-chrome-reveal')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('打开设置'), findsOneWidget);
      expect(dockVisible(tester), isTrue);
      await scrollDown(tester);
      expect(dockVisible(tester), isFalse);
      await tester.drag(verticalGrid(), const Offset(0, 120));
      await tester.pumpAndSettle();
      expect(find.byTooltip('打开设置'), findsOneWidget);
      expect(dockVisible(tester), isTrue);
      expect(tester.takeException(), isNull);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'accessible navigation keeps collapse and reveal usable with motion disabled',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(
            accessibleNavigation: true,
            disableAnimations: true,
            reduceMotion: true,
          );
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpApp(tester);
      final semantics = tester.ensureSemantics();
      try {
        expect(
          MediaQuery.of(tester.element(find.byType(TimeGrid)))
              .accessibleNavigation,
          isTrue,
        );
        expect(
          MediaQuery.of(tester.element(find.byType(TimeGrid)))
              .disableAnimations,
          isTrue,
        );
        await scrollDown(tester);
        expect(find.byTooltip('打开设置'), findsNothing);
        expect(dockVisible(tester), isFalse);
        final header = find.byKey(const ValueKey('workspace-header-region'));
        expect(tester.widget(header), isNot(isA<AnimatedSize>()));
        expect(
          find.descendant(of: header, matching: find.byType(AnimatedSize)),
          findsNothing,
        );
        final opacity = find.ancestor(
          of: dock(),
          matching: find.byType(AnimatedOpacity),
        );
        expect(
          tester.widget<AnimatedOpacity>(opacity.first).duration,
          Duration.zero,
        );
        expect(find.bySemanticsLabel('展开工具栏'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('workspace-chrome-reveal')));
        await tester.pumpAndSettle();
        expect(find.byTooltip('打开设置'), findsOneWidget);
        expect(dockVisible(tester), isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'horizontal swipes and programmatic vertical jumps preserve visible controls',
    (tester) async {
      await pumpApp(tester);
      await tester.drag(
        find.byKey(const PageStorageKey('time-grid-horizontal')),
        const Offset(-180, 0),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('打开设置'), findsOneWidget);
      expect(dockVisible(tester), isTrue);
      final scrollable = find
          .descendant(of: verticalGrid(), matching: find.byType(Scrollable))
          .evaluate()
          .whereType<StatefulElement>()
          .map((element) => element.state)
          .whereType<ScrollableState>()
          .singleWhere(
            (state) => state.widget.axisDirection == AxisDirection.down,
          );
      scrollable.position.jumpTo(160);
      await tester.pumpAndSettle();
      expect(find.byTooltip('打开设置'), findsOneWidget);
      expect(dockVisible(tester), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'disabling a collapsed schedule preserves the host recovery entry',
    (tester) async {
      await pumpApp(tester);
      await scrollDown(tester);
      expect(find.byTooltip('打开设置'), findsNothing);
      await tester.runAsync(() => host.disable('app.schedule'));
      await _settle(tester);
      expect(find.text('没有可用工作区'), findsOneWidget);
      expect(find.text('打开设置并恢复模块'), findsOneWidget);
      await tester.tap(find.text('打开设置并恢复模块'));
      await _settle(tester);
      expect(find.text('外观主题'), findsOneWidget);
      expect(find.text('模块管理与恢复'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a render failure while collapsed restores protected controls and fallback title',
    (tester) async {
      await tester.runAsync(() async {
        await host.uninstall('app.schedule');
        await host.install(
          await ScriptPackage.verify(
            await ScriptPackage.build(
              {
                'formatVersion': 3,
                'manifest': {
                  'id': 'private.chrome',
                  'version': '1.0.0',
                  'hostApi': '^1.3.0',
                  'dataVersion': 1,
                  'permissions': ['ui'],
                  'dependencies': [],
                },
                'entryPoint': 'main.js',
                'collections': [
                  {
                    'id': 'flags',
                    'schema': {'type': 'object'},
                    'indexes': [],
                  },
                ],
                'pages': [
                  {
                    'id': 'private.chrome.home',
                    'title': '安全后备标题',
                    'handler': 'render',
                    'headerMode': 'contributed',
                    'entry': {
                      'id': 'private.chrome.entry',
                      'placement': 'main',
                      'opening': 'workspace',
                    },
                  },
                ],
                'services': [
                  {
                    'id': 'fail',
                    'kind': 'command',
                    'handler': 'fail',
                    'major': 1,
                    'input': {'type': 'object'},
                    'output': {'type': 'object'},
                    'confirmation': 'host',
                  },
                ],
              },
              {
                'main.js': """
import {data} from '@xudian/sdk';
export function fail(){return {writes:[{collection:'flags',id:'fail',value:{id:'fail'}}],result:{}};}
export async function render(){
  if(await data.get('flags','fail'))throw new Error('安全故障测试');
  return {state:{},header:{title:'折叠测试标题',autoHideChrome:true},tree:{type:'column',fillHeight:true,children:[
    {type:'timeGrid',columns:[{id:'mon',label:'周一'}],rows:Array.from({length:12},(_,i)=>({id:String(i),label:String(i+1)})),blocks:[]}
  ]}};
}
""",
              },
            ),
            allowUnsignedLocal: true,
          ),
        );
      });
      await pumpApp(tester);
      expect(find.text('折叠测试标题'), findsOneWidget);
      await scrollDown(tester);
      expect(find.byTooltip('打开设置'), findsNothing);
      await tester.runAsync(() async {
        final caller = host.instances['private.chrome']!.actor;
        final plan = await host.prepare(
          caller,
          const ServiceRef('private.chrome', 'fail', 1),
          {},
        );
        host.review(plan.id, caller);
        await host.commit(caller, plan.id);
      });
      await _settle(tester);
      expect(find.text('折叠测试标题'), findsNothing);
      expect(find.text('安全后备标题'), findsWidgets);
      expect(find.byTooltip('打开设置'), findsOneWidget);
      expect(dockVisible(tester), isTrue);
      expect(
        find.byKey(const ValueKey('workspace-chrome-reveal')),
        findsNothing,
      );
      expect(find.textContaining('安全故障测试'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'wide schedule collapses its header while the permanent sidebar stays available',
    (tester) async {
      await pumpApp(tester, width: 1200);
      expect(find.byTooltip('打开设置'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
      await scrollDown(tester);
      expect(find.byTooltip('打开设置'), findsNothing);
      expect(find.text('设置'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('workspace-chrome-reveal')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
