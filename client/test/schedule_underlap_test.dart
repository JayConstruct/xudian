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
  final root = Directory('../packages/modules/app.schedule');
  final sources = <String, String>{};
  await for (final entity in root.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.js')) {
      sources[entity.path.substring(root.path.length + 1)] = await entity
          .readAsString();
    }
  }
  return ScriptPackage.verify(
    await ScriptPackage.build(
      object(jsonDecode(await File('${root.path}/module.json').readAsString())),
      sources,
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
    directory = await Directory.systemTemp.createTemp('schedule-underlap-');
    host = ModuleHost(store: store, directory: directory);
    host.clockNow = () => DateTime.utc(2026, 9, 7, 0, 30);
    await host.initialize();
    await host.install(await _scheduleSource());
    actor = host.instances['app.schedule']!.actor;
    Future<void> save(String service, Object? args) async {
      final plan = await host.prepare(
        actor,
        ServiceRef('app.schedule', service, 1),
        args,
      );
      host.review(plan.id, actor);
      await host.commit(actor, plan.id);
    }

    await save('schedule.timetable.save', {
      'timetable': {
        'id': 'table',
        'name': '悬浮课表',
        'firstMonday': '2026-09-07',
        'totalWeeks': 20,
        'timezone': 'Asia/Shanghai',
        'displayWeekStart': 1,
        'periods': [
          for (var i = 0; i < 12; i++)
            {
              'number': i + 1,
              'start': '${8 + i}:00'.padLeft(5, '0'),
              'end': '${8 + i}:45'.padLeft(5, '0'),
            },
        ],
      },
    });
    await save('schedule.course.save', {
      'course': {
        'id': 'last',
        'timetableId': 'table',
        'name': '末节课',
        'color': '#486DA4',
      },
      'meeting': {
        'id': 'last-meeting',
        'weekday': 1,
        'startPeriod': 12,
        'endPeriod': 12,
        'weeks': [1],
        'location': '夜间教室',
      },
    });
  });
  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });
  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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

  Finder dock() => find.byKey(const ValueKey('mobile-bottom-dock'));
  Finder reveal() => find.byKey(const ValueKey('workspace-chrome-reveal'));
  Finder lastCourseBlock() =>
      find.ancestor(of: find.text('末节课'), matching: find.byType(InkWell));
  List<Color> revealSurfaceColors(WidgetTester tester) => find
      .ancestor(of: reveal(), matching: find.byType(DecoratedBox))
      .evaluate()
      .map((element) => (element.widget as DecoratedBox).decoration)
      .whereType<ShapeDecoration>()
      .map((decoration) => decoration.gradient)
      .whereType<LinearGradient>()
      .single
      .colors;
  Finder verticalGrid() =>
      find.byKey(const PageStorageKey('time-grid-vertical'));
  Future<void> collapse(WidgetTester tester) async {
    await tester.drag(verticalGrid(), const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(reveal(), findsOneWidget);
  }

  ScrollPosition verticalPosition() =>
      verticalGrid()
          .evaluate()
          .single
          .findAncestorStateOfType<ScrollableState>()
          ?.position ??
      find
          .descendant(of: verticalGrid(), matching: find.byType(Scrollable))
          .evaluate()
          .whereType<StatefulElement>()
          .map((element) => element.state)
          .whereType<ScrollableState>()
          .singleWhere(
            (state) => state.widget.axisDirection == AxisDirection.down,
          )
          .position;

  testWidgets(
    'grid continues behind floating navigation and its last lesson can scroll fully above it',
    (tester) async {
      await pumpApp(tester);
      final gridRect = tester.getRect(find.byType(TimeGrid));
      final dockRect = tester.getRect(dock());
      expect(gridRect.bottom, greaterThan(dockRect.bottom));
      expect(
        tester.widget<TimeGrid>(find.byType(TimeGrid)).bottomInset,
        greaterThan(0),
      );
      final position = verticalPosition();
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.byTooltip('打开设置'), findsOneWidget);
      final lessonRect = tester.getRect(lastCourseBlock());
      expect(lessonRect.bottom, lessThanOrEqualTo(tester.getRect(dock()).top));
      expect(lessonRect.top, greaterThanOrEqualTo(gridRect.top));
      await tester.tap(find.text('末节课'));
      await _settle(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('夜间教室'),
        ),
        findsOneWidget,
      );
      expect(find.text('第 12–12 节 · 19:00–19:45'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'revealing navigation after a real scroll to the end keeps the entire last block above it',
    (tester) async {
      await pumpApp(tester);
      for (var i = 0; i < 4; i++) {
        await tester.drag(verticalGrid(), const Offset(0, -400));
        await tester.pumpAndSettle();
        if (verticalPosition().extentAfter < 1) break;
      }
      expect(verticalPosition().extentAfter, lessThan(1));
      expect(reveal(), findsOneWidget);
      expect(find.byTooltip('打开设置'), findsNothing);
      await tester.tap(reveal());
      await tester.pumpAndSettle();
      expect(find.byTooltip('打开设置'), findsOneWidget);
      final block = tester.getRect(lastCourseBlock());
      final navigation = tester.getRect(dock());
      expect(
        block.bottom,
        lessThanOrEqualTo(navigation.top),
        reason: 'The whole twelfth-period block must stay above the expanded floating navigation.',
      );
      expect(
        block.top,
        greaterThanOrEqualTo(tester.getRect(find.byType(TimeGrid)).top),
      );
      await tester.tap(find.text('末节课'));
      await _settle(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('第 12–12 节 · 19:00–19:45'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'collapsed reveal remains a blurred floating capsule with a full-size tap target',
    (tester) async {
      await pumpApp(tester);
      await collapse(tester);
      final filters = find.ancestor(
        of: reveal(),
        matching: find.byType(BackdropFilter),
      );
      expect(filters, findsOneWidget);
      expect(tester.widget<BackdropFilter>(filters).enabled, isTrue);
      expect(revealSurfaceColors(tester).every((color) => color.a < 1), isTrue);
      final capsule = tester.getRect(reveal());
      expect(capsule.height, greaterThanOrEqualTo(48));
      expect(capsule.width, lessThan(420));
      expect(
        tester.getRect(find.byType(TimeGrid)).bottom,
        greaterThan(capsule.bottom),
      );
      await tester.tap(reveal());
      await tester.pumpAndSettle();
      expect(find.byTooltip('打开设置'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'high contrast and reduced motion preserve a readable reveal and last-period access',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(
            highContrast: true,
            accessibleNavigation: true,
            disableAnimations: true,
            reduceMotion: true,
          );
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(tester);
      final dockFilters = find.descendant(
        of: dock(),
        matching: find.byType(BackdropFilter),
      );
      expect(dockFilters, findsOneWidget);
      expect(tester.widget<BackdropFilter>(dockFilters).enabled, isFalse);
      await collapse(tester);
      final filters = find.ancestor(
        of: reveal(),
        matching: find.byType(BackdropFilter),
      );
      expect(filters, findsOneWidget);
      expect(tester.widget<BackdropFilter>(filters).enabled, isFalse);
      expect(
        revealSurfaceColors(tester).every((color) => color.a == 1),
        isTrue,
      );
      final capsule = tester.getRect(reveal());
      expect(capsule.height, greaterThanOrEqualTo(48));
      await tester.tap(reveal());
      await tester.pumpAndSettle();
      final position = verticalPosition();
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(lastCourseBlock()).bottom,
        lessThanOrEqualTo(tester.getRect(dock()).top),
      );
      expect(find.byTooltip('打开设置'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
