import 'dart:io';
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/app.dart';
import 'package:task_app/app/mobile_bottom_dock.dart';
import 'package:task_app/app/workspace_page_transition.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_providers.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/modules/app_module.dart';
import 'package:task_app/core/modules/builtin_module_registration.dart';
import 'package:task_app/core/modules/module_manifest.dart';
import 'package:task_app/core/ui/ui_composition.dart';
import 'package:task_app/core/ui/ui_registration.dart';
import 'package:task_app/core/ui/page_first_frame.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';

void main() {
  Future<void> show(
    WidgetTester tester,
    int index, {
    bool reduced = false,
    TextDirection direction = TextDirection.ltr,
    int retainedPages = 1,
    Map<String, Object?>? retentionKeys,
    Widget? child,
    bool deferUntilReady = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: WorkspacePageTransition(
              destinationId: 'page-$index',
              order: index,
              maxRetainedPages: retainedPages,
              retentionKeys: retentionKeys,
              deferUntilReady: deferUntilReady,
              child: child ?? Center(child: Text('Page $index')),
            ),
          ),
        ),
      ),
    ),
  );

  for (final direction in TextDirection.values) {
    testWidgets('pages slide according to entry order in $direction', (
      tester,
    ) async {
      await show(tester, 0, direction: direction);
      final restingX = tester.getCenter(find.text('Page 0')).dx;
      await show(tester, 1, direction: direction);
      await tester.pump(const Duration(milliseconds: 90));
      final incomingX = tester.getCenter(find.text('Page 1')).dx;
      final outgoingX = tester.getCenter(find.text('Page 0')).dx;
      expect(
        incomingX,
        direction == TextDirection.ltr
            ? greaterThan(restingX)
            : lessThan(restingX),
      );
      expect(
        outgoingX,
        direction == TextDirection.ltr
            ? lessThan(restingX)
            : greaterThan(restingX),
      );
      await tester.pumpAndSettle();
      expect(find.text('Page 0'), findsNothing);
      expect(tester.getCenter(find.text('Page 1')).dx, closeTo(restingX, .01));
      await show(tester, 0, direction: direction);
      await tester.pump(const Duration(milliseconds: 90));
      expect(
        tester.getCenter(find.text('Page 0')).dx,
        direction == TextDirection.ltr
            ? lessThan(restingX)
            : greaterThan(restingX),
      );
      await tester.pumpAndSettle();
      expect(find.text('Page 1'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('rapid reversing reuses pages without a position jump', (
    tester,
  ) async {
    await show(tester, 0);
    await show(tester, 1);
    await tester.pump(const Duration(milliseconds: 70));
    final x = tester.getCenter(find.text('Page 0')).dx;
    await show(tester, 0);
    expect(find.text('Page 0'), findsOneWidget);
    expect(tester.getCenter(find.text('Page 0')).dx, closeTo(x, .01));
    await show(tester, 2);
    await tester.pump(const Duration(milliseconds: 40));
    await show(tester, 1);
    await tester.pumpAndSettle();
    expect(find.text('Page 0'), findsNothing);
    expect(find.text('Page 2'), findsNothing);
    expect(find.text('Page 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion switches immediately and removes old pages', (
    tester,
  ) async {
    await show(tester, 0, reduced: true);
    await show(tester, 1, reduced: true);
    expect(find.text('Page 0'), findsNothing);
    expect(tester.getCenter(find.text('Page 1')).dx, 400);
    await show(tester, 2);
    await tester.pump(const Duration(milliseconds: 70));
    await show(tester, 2, reduced: true);
    expect(find.text('Page 1'), findsNothing);
    expect(tester.getCenter(find.text('Page 2')).dx, 400);
    expect(tester.takeException(), isNull);
  });

  testWidgets('outgoing page cannot receive taps or accessibility focus', (
    tester,
  ) async {
    await show(tester, 0);
    await show(tester, 1);
    final outgoing = find
        .ancestor(of: find.text('Page 0'), matching: find.byType(IgnorePointer))
        .first;
    expect(tester.widget<IgnorePointer>(outgoing).ignoring, isTrue);
    final semantics = find
        .ancestor(
          of: find.text('Page 0'),
          matching: find.byType(ExcludeSemantics),
        )
        .first;
    expect(tester.widget<ExcludeSemantics>(semantics).excluding, isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('returning to a retained page preserves its real form state', (
    tester,
  ) async {
    final mounts = <int, int>{};
    Future<void> visit(int index) => show(
      tester,
      index,
      retainedPages: 3,
      child: _RetainedProbe(index: index, mounts: mounts),
    );
    await visit(0);
    await tester.enterText(find.byType(TextField), 'unfinished draft');
    FocusManager.instance.primaryFocus?.unfocus();
    await visit(1);
    await tester.pumpAndSettle();
    expect(find.text('unfinished draft'), findsNothing);
    expect(find.text('unfinished draft', skipOffstage: false), findsOneWidget);
    final hiddenField = find.byKey(
      const ValueKey('retained-field-0'),
      skipOffstage: false,
    );
    expect(TickerMode.valuesOf(tester.element(hiddenField)).enabled, isFalse);
    expect(Focus.of(tester.element(hiddenField)).canRequestFocus, isFalse);
    await visit(0);
    expect(find.text('unfinished draft'), findsOneWidget);
    expect(mounts, {0: 1, 1: 1});
    await tester.pumpAndSettle();
    expect(TickerMode.valuesOf(tester.element(hiddenField)).enabled, isTrue);
  });

  testWidgets(
    'retention is bounded and evicts the least recently visited page',
    (tester) async {
      final mounts = <int, int>{};
      Future<void> visit(int index) async {
        await show(
          tester,
          index,
          retainedPages: 2,
          child: _RetainedProbe(index: index, mounts: mounts),
        );
        await tester.pumpAndSettle();
      }

      await visit(0);
      await visit(1);
      await visit(0);
      await visit(2);
      expect(
        find.byType(_RetainedProbe, skipOffstage: false),
        findsNWidgets(2),
      );
      expect(mounts, {0: 1, 1: 1, 2: 1});
      await visit(1);
      expect(mounts[1], 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('module and layout identities invalidate retained widget state', (
    tester,
  ) async {
    final mounts = <int, int>{};
    Future<void> visit(int index, Map<String, Object?> keys) async {
      await show(
        tester,
        index,
        retainedPages: 3,
        retentionKeys: keys,
        child: _RetainedProbe(index: index, mounts: mounts),
      );
      await tester.pumpAndSettle();
    }

    await visit(0, {'page-0': 'generation-1', 'page-1': 'generation-1'});
    await visit(1, {'page-0': 'generation-1', 'page-1': 'generation-1'});
    await visit(1, {'page-0': 'generation-2', 'page-1': 'generation-1'});
    expect(find.byType(_RetainedProbe, skipOffstage: false), findsOneWidget);
    await visit(0, {'page-0': 'generation-2', 'page-1': 'generation-1'});
    expect(mounts[0], 2);
    await visit(0, {'page-0': 'generation-2'});
    expect(find.byType(_RetainedProbe, skipOffstage: false), findsOneWidget);
    await visit(0, {'page-0': 'generation-3'});
    expect(mounts[0], 3);
  });

  testWidgets(
    'different header heights do not shift the incoming body vertically',
    (tester) async {
      Future<void> page(int index) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspacePageTransition(
              destinationId: 'page-$index',
              order: index,
              child: Column(
                children: [
                  SizedBox(height: index == 0 ? 160 : 40),
                  Expanded(child: Center(child: Text('body-$index'))),
                ],
              ),
            ),
          ),
        ),
      );
      await page(0);
      await page(1);
      await tester.pump(const Duration(milliseconds: 90));
      final during = tester.getCenter(find.text('body-1')).dy;
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.text('body-1')).dy, during);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('first visit prepares content before sliding without a spinner', (
    tester,
  ) async {
    final ready = Completer<void>();
    await show(tester, 0, retainedPages: 3, deferUntilReady: true);
    await tester.pumpAndSettle();
    await show(
      tester,
      1,
      retainedPages: 3,
      deferUntilReady: true,
      child: _FirstFrameProbe(ready: ready.future),
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('Page 0'), findsOneWidget);
    expect(find.text('Prepared content'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.getCenter(find.text('Page 0')).dx, 400);
    ready.complete();
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Prepared content'), findsOneWidget);
    await show(tester, 0, retainedPages: 3, deferUntilReady: true);
    await tester.pumpAndSettle();
    await show(
      tester,
      1,
      retainedPages: 3,
      deferUntilReady: true,
      child: _FirstFrameProbe(ready: ready.future),
    );
    expect(find.text('Prepared content'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('late readiness cannot switch back after a rapid return', (
    tester,
  ) async {
    final ready = Completer<void>();
    await show(tester, 0, retainedPages: 3, deferUntilReady: true);
    await tester.pumpAndSettle();
    await show(
      tester,
      1,
      retainedPages: 3,
      deferUntilReady: true,
      child: _FirstFrameProbe(ready: ready.future),
    );
    await tester.pump(const Duration(milliseconds: 40));
    await show(tester, 0, retainedPages: 3, deferUntilReady: true);
    ready.complete();
    await tester.pumpAndSettle();
    expect(find.text('Page 0'), findsOneWidget);
    expect(find.text('Prepared content'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('real workspace', () {
    late AppDatabase db;
    late CollectionStore store;
    late Directory directory;
    late ModuleHost host;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      store = CollectionStore(db);
      directory = await Directory.systemTemp.createTemp('page-slide-');
      host = ModuleHost(store: store, directory: directory);
      await host.initialize();
    });
    tearDown(() async {
      await host.close();
      await store.close();
      await db.close();
      await directory.delete(recursive: true);
    });
    testWidgets(
      'real dock switches header and page together; page gestures stay local',
      (tester) async {
        tester.view.physicalSize = const Size(420, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var horizontalUpdates = 0;
        final app = XudianApp();
        app.registry.registerBuiltin(
          BuiltinModuleRegistration(
            module: _TransitionModule(() => horizontalUpdates++),
            title: '页面切换测试',
            description: '本地横向手势与工作区切换',
          ),
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          app.registry.dispose();
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWith((_) async => db),
              moduleHostProvider.overrideWith((_) async => host),
            ],
            child: app,
          ),
        );
        for (var i = 0; i < 20; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.pumpAndSettle();
        Finder nav(String label) => find.descendant(
          of: find.byType(MobileBottomDock),
          matching: find.text(label),
        );
        final dockX = tester.getCenter(find.byType(MobileBottomDock)).dx;
        final menuX = tester
            .getCenter(find.byKey(const ValueKey('workspace-menu')))
            .dx;
        await tester.tap(nav('第二页'));
        await tester.pump();
        // First-frame readiness starts this initial visit after paint. Let the
        // ticker establish its baseline before measuring the slide itself.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));
        Finder region(String name, String label) => find.descendant(
          of: find.byKey(ValueKey(name)),
          matching: find.text(label),
        );
        expect(tester.getCenter(find.text('正文 1')).dx, greaterThan(210));
        expect(tester.getCenter(find.text('正文 0')).dx, lessThan(210));
        expect(
          tester.getCenter(region('workspace-header-region', '第二页')).dx,
          greaterThan(210),
        );
        expect(tester.getCenter(find.byType(MobileBottomDock)).dx, dockX);
        Finder menuFor(int page) => find.descendant(
          of: find.byWidgetPredicate(
            (widget) =>
                widget is FractionalTranslation &&
                widget.key == ValueKey('test.entry.$page'),
          ),
          matching: find.byKey(const ValueKey('workspace-menu')),
        );
        for (final page in [0, 1]) {
          final bodyOffset = tester.getCenter(find.text('正文 $page')).dx - 210;
          expect(
            tester.getCenter(menuFor(page)).dx - menuX,
            closeTo(bodyOffset, .01),
            reason: 'Page $page menu and body must share the same translation',
          );
        }
        await tester.pumpAndSettle();
        expect(tester.getCenter(menuFor(1)).dx, closeTo(menuX, .01));
        await tester.drag(
          find.byKey(const ValueKey('local-horizontal-1')),
          const Offset(-170, 0),
        );
        await tester.pumpAndSettle();
        expect(horizontalUpdates, greaterThan(0));
        expect(find.text('正文 1'), findsOneWidget);
        expect(find.text('正文 0'), findsNothing);
        await tester.tap(nav('第一页'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));
        expect(tester.getCenter(find.text('正文 0')).dx, lessThan(210));
        await tester.tap(nav('第三页'));
        await tester.pump();
        await tester.tap(nav('第二页'));
        await tester.pumpAndSettle();
        expect(find.text('正文 1'), findsOneWidget);
        expect(find.text('正文 0'), findsNothing);
        expect(find.text('正文 2'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });
}

class _FirstFrameProbe extends StatefulWidget {
  const _FirstFrameProbe({required this.ready});
  final Future<void> ready;

  @override
  State<_FirstFrameProbe> createState() => _FirstFrameProbeState();
}

class _FirstFrameProbeState extends State<_FirstFrameProbe> {
  bool ready = false;

  @override
  void initState() {
    super.initState();
    widget.ready.then((_) {
      if (mounted) setState(() => ready = true);
    });
  }

  @override
  Widget build(BuildContext context) => PageFirstFrameGate(
    blocked: !ready,
    child: const Center(child: Text('Prepared content')),
  );
}

class _RetainedProbe extends StatefulWidget {
  const _RetainedProbe({required this.index, required this.mounts});
  final int index;
  final Map<int, int> mounts;

  @override
  State<_RetainedProbe> createState() => _RetainedProbeState();
}

class _RetainedProbeState extends State<_RetainedProbe> {
  final controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.mounts.update(widget.index, (value) => value + 1, ifAbsent: () => 1);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: TextField(
      key: ValueKey('retained-field-${widget.index}'),
      controller: controller,
    ),
  );
}

class _TransitionModule implements AppModule {
  _TransitionModule(this.horizontalUpdate);
  final VoidCallback horizontalUpdate;

  @override
  ModuleManifest get manifest => const ModuleManifest(
    id: 'test.pageslide',
    version: '1.0.0',
    coreApi: '1',
    requiresCapabilities: ['ui.registry', 'ui.composition'],
    permissions: ['ui.register'],
  );

  @override
  List<UiRegistration> get ui => [
    for (var i = 0; i < 3; i++) ...[
      UiPageRegistration(
        id: 'test.page.$i',
        moduleId: manifest.id,
        title: '测试页面 $i',
        builder: (_, _) => GestureDetector(
          key: ValueKey('local-horizontal-$i'),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (_) => horizontalUpdate(),
          child: Center(child: Text('正文 $i')),
        ),
      ),
      UiEntryRegistration(
        id: 'test.entry.$i',
        moduleId: manifest.id,
        pageId: 'test.page.$i',
        label: ['第一页', '第二页', '第三页'][i],
        icon: Icons.apps,
        defaultMount: UiMount(placement: UiPlacement.main, order: i),
      ),
    ],
  ];
}
