import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/modules/app_module.dart';
import 'package:task_app/core/modules/module_manifest.dart';
import 'package:task_app/core/modules/module_registry.dart';
import 'package:task_app/core/security/capability_registry.dart';
import 'package:task_app/core/ui/module_detail_page.dart';
import 'package:task_app/core/ui/ui_composition.dart';
import 'package:task_app/core/ui/ui_design.dart';
import 'package:task_app/core/ui/ui_icon.dart';
import 'package:task_app/core/ui/ui_registration.dart';
import 'package:task_app/core/ui/workspace_header.dart';

class _DetailModule implements AppModule {
  @override
  ModuleManifest get manifest => const ModuleManifest(
    id: 'test.detail',
    version: '1.0.0',
    coreApi: '1',
    permissions: ['ui.register'],
    requiresCapabilities: ['ui.registry', 'ui.composition'],
  );

  @override
  List<UiRegistration> get ui => [
    UiPageRegistration(
      id: 'test.detail.page',
      moduleId: 'test.detail',
      title: '批量任务',
      headerMode: 'contributed',
      builder: (_, _) => const SizedBox.shrink(),
    ),
  ];
}

class _HeaderContent extends StatefulWidget {
  const _HeaderContent({this.compact = true});
  final bool compact;

  @override
  State<_HeaderContent> createState() => _HeaderContentState();
}

class _HeaderContentState extends State<_HeaderContent> {
  bool detail = false;
  final owner = Object();

  void publish() {
    final scope = WorkspaceHeaderScope.read(context)!;
    scope.controller.publish(
      scope.lease!,
      owner,
      {
        'title': detail ? '批次详情' : '批量任务',
        if (widget.compact) 'compact': true,
        if (widget.compact) 'backIcon': 'chevron',
        if (detail) 'backEvent': {'type': 'back'},
      },
      (_) async {
        setState(() => detail = false);
        publish();
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) publish();
    });
  }

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () {
        setState(() => detail = true);
        publish();
      },
      child: Text(detail ? '详情正文' : '打开详情'),
    ),
  );
}

void main() {
  late ModuleRegistry registry;
  setUp(() {
    registry = ModuleRegistry([
      _DetailModule(),
    ], capabilities: CapabilityRegistry(['ui.registry', 'ui.composition']));
  });
  tearDown(() => registry.dispose());

  Future<void> open(WidgetTester tester, {bool compact = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppDesign.theme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ModuleDetailPage(
                    registry: registry,
                    pageId: 'test.detail.page',
                    child: _HeaderContent(compact: compact),
                  ),
                ),
              ),
              child: const Text('原页面'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('原页面'));
    await tester.pumpAndSettle();
  }

  testWidgets('compact child header matches typography and chevron spacing', (
    tester,
  ) async {
    await open(tester);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    final title = tester.widget<Text>(find.text('批量任务'));
    expect(appBar.leadingWidth, 48);
    expect(appBar.titleSpacing, 8);
    expect(title.style!.fontSize, 20);
    expect(title.style!.fontWeight, FontWeight.w700);
    expect(tester.getTopLeft(find.text('批量任务')).dx, 56);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is UiIcon && widget.icon == Icons.chevron_left,
      ),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(ModuleDetailPage), findsNothing);
    expect(find.text('原页面'), findsOneWidget);
  });

  testWidgets('chevron and system back keep internal navigation before exit', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();
    expect(find.text('批次详情'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('批量任务'), findsOneWidget);
    expect(find.byType(ModuleDetailPage), findsOneWidget);
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('批量任务'), findsOneWidget);
    expect(find.byType(ModuleDetailPage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ModuleDetailPage), findsNothing);
  });

  testWidgets('ordinary detail header retains existing defaults', (
    tester,
  ) async {
    await open(tester, compact: false);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.leadingWidth, isNull);
    expect(appBar.titleSpacing, isNull);
    expect(tester.widget<Text>(find.text('批量任务')).style, isNull);
    expect(find.byType(BackButton), findsOneWidget);
  });
}
