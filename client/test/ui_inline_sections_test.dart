import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/design_system.dart';
import 'package:task_app/core/modules/app_module.dart';
import 'package:task_app/core/modules/module_manifest.dart';
import 'package:task_app/core/modules/module_registry.dart';
import 'package:task_app/core/security/capability_registry.dart';
import 'package:task_app/core/ui/ui_composition.dart';
import 'package:task_app/core/ui/ui_page_host.dart';
import 'package:task_app/core/ui/ui_registration.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';

class _Module implements AppModule {
  _Module(this.ui);

  @override
  final List<UiRegistration> ui;

  @override
  ModuleManifest get manifest => const ModuleManifest(
    id: 'test.inline',
    version: '1.0.0',
    coreApi: '1',
    requiresCapabilities: ['ui.registry', 'ui.composition'],
    permissions: ['ui.register'],
  );
}

UiEntryRegistration _entry(String id, String target, {int order = 0}) =>
    UiEntryRegistration(
      id: 'test.inline.$id.entry',
      moduleId: 'test.inline',
      pageId: 'test.inline.$id',
      label: id,
      icon: Icons.pages,
      content: true,
      defaultMount: UiMount(
        placement: UiPlacement.page,
        pageId: 'test.inline.$target',
        slotId: 'body',
        order: order,
      ),
    );

UiPageRegistration _container(String id, {required bool inline}) =>
    UiPageRegistration(
      id: 'test.inline.$id',
      moduleId: 'test.inline',
      title: id,
      container: true,
      builder: (_, _) => const SizedBox.shrink(),
      slots: [
        PageSlotDefinition(
          id: 'body',
          label: '内容区',
          kind: PageSlotKind.sections,
          inline: inline,
        ),
      ],
    );

UiPageRegistration _content(String id, double height) => UiPageRegistration(
  id: 'test.inline.$id',
  moduleId: 'test.inline',
  title: id,
  builder: (context, _) {
    final content = SizedBox(
      key: ValueKey('$id-content'),
      height: height,
      child: Text('$id inline=${UiPageContentScope.inlineOf(context)}'),
    );
    return UiPageContentScope.inlineOf(context)
        ? content
        : SingleChildScrollView(child: content);
  },
);

Future<void> _pump(WidgetTester tester, List<UiRegistration> ui) async {
  final database = AppDatabase(NativeDatabase.memory());
  final registry = ModuleRegistry([
    _Module(ui),
  ], capabilities: CapabilityRegistry(['ui.registry', 'ui.composition']));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    registry.dispose();
    await database.close();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWith((_) async => database)],
      child: MaterialApp(
        home: Scaffold(
          body: WorkspaceContentInsets(
            bottom: 64,
            child: UiPageHost(registry: registry, pageId: 'test.inline.home'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('inline sections share scrolling and preserve natural heights', (
    tester,
  ) async {
    await _pump(tester, [
      _container('home', inline: true),
      _content('first', 120),
      _content('second', 800),
      _entry('second', 'home', order: 100),
      _entry('first', 'home'),
    ]);
    expect(find.text('first inline=true'), findsOneWidget);
    expect(find.text('second inline=true'), findsOneWidget);
    expect(find.byType(Scrollable), findsOneWidget);
    final first = find.byKey(const ValueKey('first-content'));
    final second = find.byKey(const ValueKey('second-content'));
    expect(tester.getSize(first).height, 120);
    expect(tester.getSize(second).height, 800);
    expect(tester.getTopLeft(second).dy - tester.getTopLeft(first).dy, 120);
    final firstStart = tester.getTopLeft(first).dy;
    final secondStart = tester.getTopLeft(second).dy;
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(first).dy, lessThan(firstStart));
    expect(
      firstStart - tester.getTopLeft(first).dy,
      closeTo(secondStart - tester.getTopLeft(second).dy, .1),
    );
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.maxScrollExtent, closeTo(920 + 64 - 600, .1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('nested inline sections reuse the outer scrollable', (
    tester,
  ) async {
    await _pump(tester, [
      _container('home', inline: true),
      _container('nested', inline: true),
      _content('leaf', 800),
      _entry('nested', 'home'),
      _entry('leaf', 'nested'),
    ]);
    expect(find.text('leaf inline=true'), findsOneWidget);
    expect(find.byType(Scrollable), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('leaf-content'))).height,
      800,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty inline sections do not show an empty content panel', (
    tester,
  ) async {
    await _pump(tester, [_container('home', inline: true)]);
    expect(find.textContaining('暂无内容'), findsNothing);
    expect(find.byType(Scrollable), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('default sections retain separate full page scrollables', (
    tester,
  ) async {
    await _pump(tester, [
      _container('home', inline: false),
      _content('first', 120),
      _content('second', 800),
      _entry('first', 'home'),
      _entry('second', 'home', order: 100),
    ]);
    expect(find.text('first inline=false'), findsOneWidget);
    expect(find.text('second inline=false'), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(Scrollable), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
}
