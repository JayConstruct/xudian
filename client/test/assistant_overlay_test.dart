import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/modules/module_registry.dart';
import 'package:task_app/core/security/capability_registry.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/features/ai/assistant_overlay.dart';
import 'package:task_app/features/ai/assistant_panel.dart';
import 'package:task_app/features/ai/assistant_runtime.dart';
import 'package:task_app/features/ai/settings/ai_secret_store.dart';
import 'package:task_app/features/settings/ui_layout.dart';
import 'package:task_app/features/settings/ui_layout_page.dart';
import 'package:task_app/features/settings/ui_layout_preview.dart';
import 'package:task_app/features/tasks/application/providers.dart';

class _Controller extends ChangeNotifier implements AssistantController {
  @override
  bool enabled = true;
  @override
  bool expanded = false;
  @override
  bool advanced = false;
  @override
  bool busy = false;
  @override
  bool awaitingApproval = false;
  @override
  bool canUndo = false;
  @override
  String? error;
  @override
  AssistantGrant? grant;
  @override
  List<AssistantChatItem> messages = [];
  @override
  List<AssistantActionPreview> pending = [];
  @override
  List<AssistantAuditItem> audit = [];

  final sent = <String>[];
  int approvals = 0;
  int rejections = 0;
  int stops = 0;
  int undos = 0;
  int clears = 0;
  Completer<void>? approvalCompletion;

  void change(VoidCallback operation) {
    operation();
    notifyListeners();
  }

  @override
  void open() => change(() => expanded = true);

  @override
  void minimize() => change(() => expanded = false);

  @override
  void setAdvanced(bool value) => change(() => advanced = value);

  @override
  void setGrant(AssistantGrant? value) => change(() => grant = value);

  @override
  Future<void> send(String text) async {
    change(() {
      sent.add(text);
      messages.add(_ChatItem('user', text));
    });
  }

  @override
  Future<void> approvePending() async {
    approvals++;
    if (approvalCompletion != null) await approvalCompletion!.future;
    change(() {
      pending = [];
      awaitingApproval = false;
      canUndo = true;
    });
  }

  @override
  void rejectPending() {
    change(() {
      rejections++;
      awaitingApproval = false;
      pending = [];
    });
  }

  @override
  void stop() {
    change(() {
      stops++;
      busy = false;
    });
  }

  @override
  Future<void> undoLast() async {
    change(() {
      undos++;
      canUndo = false;
    });
  }

  @override
  Future<void> clearHistory() async {
    change(() {
      clears++;
      messages = [];
      audit = [];
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ChatItem extends Fake implements AssistantChatItem {
  _ChatItem(this.role, this.text);

  @override
  final String role;
  @override
  final String text;
}

class _Preview extends Fake implements AssistantActionPreview {
  _Preview({this.layout, this.changes = const ['新增任务：准备评审']});

  @override
  String get title => '创建任务提案';
  @override
  final List<String> changes;
  @override
  final UiLayout? layout;
}

class _AuditItem extends Fake implements AssistantAuditItem {
  @override
  String get title => '任务读取';
  @override
  String get status => '已完成';
}

class _Secrets implements AiSecretStore {
  @override
  Future<String?> readApiKey() async => 'not-an-exposed-secret';
  @override
  Future<void> writeApiKey(String value) async {}
  @override
  Future<void> deleteApiKey() async {}
}

class _DeveloperDraft extends StatefulWidget {
  const _DeveloperDraft();

  @override
  State<_DeveloperDraft> createState() => _DeveloperDraftState();
}

class _DeveloperDraftState extends State<_DeveloperDraft> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      TextField(
        key: const ValueKey('developer-draft'),
        controller: controller,
        decoration: const InputDecoration(labelText: '开发草稿'),
      ),
    ],
  );
}

class _Harness {
  final registry = ModuleRegistry([], capabilities: CapabilityRegistry([]));
  final controller = _Controller();
  final database = AppDatabase(NativeDatabase.memory());
  final rootNavigator = GlobalKey<NavigatorState>();

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1200, 800),
    double scale = 1,
    bool standalone = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(database.close);
    addTearDown(registry.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assistantControllerProvider(registry).overrideWithValue(controller),
          databaseProvider.overrideWith((ref) async => database),
          aiSecretStoreProvider.overrideWithValue(_Secrets()),
        ],
        child: MaterialApp(
          navigatorKey: rootNavigator,
          theme: ThemeData(useMaterial3: true),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: standalone
                ? child!
                : Stack(
                    children: [
                      Positioned.fill(child: child!),
                      Positioned.fill(
                        child: AssistantOverlay(
                          registry: registry,
                          developerBuilder: (_) => const _DeveloperDraft(),
                        ),
                      ),
                    ],
                  ),
          ),
          home: standalone
              ? AssistantPanel(
                  registry: registry,
                  developerBuilder: (_) => const _DeveloperDraft(),
                )
              : Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: TextButton(
                      key: const ValueKey('root-route-button'),
                      onPressed: () => rootNavigator.currentState!.push<void>(
                        MaterialPageRoute(
                          builder: (_) => const Scaffold(body: Text('其他全局页面')),
                        ),
                      ),
                      child: const Text('打开其他页面'),
                    ),
                  ),
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _reveal(WidgetTester tester, String value) async {
  final list = find.byKey(const PageStorageKey('assistant-conversation'));
  final scrollable = find
      .descendant(of: list, matching: find.byType(Scrollable))
      .first;
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(_key(value), 180, scrollable: scrollable);
  await tester.pumpAndSettle();
}

Future<void> _dialogReveal(WidgetTester tester, String value) async {
  await tester.scrollUntilVisible(
    _key(value),
    160,
    scrollable: find
        .descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    '320px large text pending cards scroll to preview, approval and rejection above keyboard',
    (tester) async {
      final harness = _Harness();
      harness.controller.expanded = true;
      harness.controller.grant = AssistantGrant(layout: true);
      harness.controller.awaitingApproval = true;
      harness.controller.pending = [
        _Preview(
          layout: UiLayout(),
          changes: [
            for (var index = 1; index <= 18; index++)
              '布局变更 $index：将对应入口移动到公开槽位，保留其他项目和未授权数据。',
          ],
        ),
      ];
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 20);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetViewInsets);
      await harness.pump(tester, size: const Size(320, 640), scale: 2);
      final scrollable = find
          .descendant(
            of: find.byKey(const PageStorageKey('assistant-conversation')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.dragUntilVisible(
        find.text('预览窄屏').hitTestable(),
        scrollable,
        const Offset(0, -100),
        maxIteration: 100,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('预览窄屏'));
      await tester.pumpAndSettle();
      expect(find.byType(UiLayoutPreview), findsOneWidget);
      await tester.ensureVisible(find.text('返回编辑'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('返回编辑'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        _key('assistant-approve'),
        100,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      expect(_key('assistant-approve').hitTestable(), findsOneWidget);
      final approveRect = tester.getRect(_key('assistant-approve'));
      expect(approveRect.bottom, lessThanOrEqualTo(360));
      expect(harness.controller.approvals, 0);
      expect(
        await harness.database.select(harness.database.tasks).get(),
        isEmpty,
      );
      expect(
        tester.widget<IconButton>(_key('assistant-stop')).onPressed,
        isNotNull,
      );
      expect(
        tester.widget<IconButton>(_key('assistant-revoke')).onPressed,
        isNotNull,
      );
      await tester.scrollUntilVisible(
        _key('assistant-reject'),
        80,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      await tester.tap(_key('assistant-reject'));
      await tester.pumpAndSettle();
      expect(harness.controller.rejections, 1);
      expect(harness.controller.pending, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disabled sidecar leaves the root route interactive', (
    tester,
  ) async {
    final harness = _Harness();
    harness.controller.enabled = false;
    await harness.pump(tester);
    expect(_key('assistant-bubble'), findsNothing);
    expect(find.byType(AssistantPanel), findsNothing);
    await tester.tap(_key('root-route-button'));
    await tester.pumpAndSettle();
    expect(find.text('其他全局页面'), findsOneWidget);
  });

  testWidgets('bubble drags and clamps to viewport, safe area and keyboard', (
    tester,
  ) async {
    final harness = _Harness();
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 20);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetViewInsets);
    await harness.pump(tester, size: const Size(320, 740));
    await tester.drag(_key('assistant-bubble'), const Offset(-1000, -1000));
    await tester.pumpAndSettle();
    var bubble = tester.getRect(_key('assistant-bubble'));
    expect(bubble.left, greaterThanOrEqualTo(0));
    expect(bubble.top, greaterThanOrEqualTo(24));
    await tester.drag(_key('assistant-bubble'), const Offset(1000, 1000));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    bubble = tester.getRect(_key('assistant-bubble'));
    expect(bubble.right, lessThanOrEqualTo(320));
    expect(bubble.bottom, lessThanOrEqualTo(440));
    await tester.tap(_key('assistant-bubble'));
    await tester.pumpAndSettle();
    expect(harness.controller.expanded, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px, large text and keyboard keep panel and consent usable', (
    tester,
  ) async {
    final harness = _Harness();
    harness.controller.expanded = true;
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 20);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetViewInsets);
    await harness.pump(tester, size: const Size(320, 740), scale: 2);
    final panel = tester.getRect(_key('assistant-floating-panel'));
    expect(panel.width, lessThanOrEqualTo(320 * .9));
    expect(panel.height, lessThanOrEqualTo((740 - 24 - 300) * .9));
    expect(panel.top, greaterThanOrEqualTo(24));
    expect(panel.bottom, lessThanOrEqualTo(440));
    await _reveal(tester, 'assistant-input');
    await tester.enterText(_key('assistant-input'), '窄屏草稿');
    await _reveal(tester, 'assistant-grant');
    await tester.tap(_key('assistant-grant'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(_key('assistant-confirm-grant'));
    await tester.pumpAndSettle();
    expect(harness.controller.grant, isNotNull);
    expect(harness.controller.sent, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'outside clicks navigate globally without losing the open draft',
    (tester) async {
      final harness = _Harness();
      harness.controller.expanded = true;
      await harness.pump(tester);
      await _reveal(tester, 'assistant-input');
      await tester.enterText(_key('assistant-input'), '跨页面草稿');
      await tester.tap(_key('root-route-button'));
      await tester.pumpAndSettle();
      expect(find.text('其他全局页面'), findsOneWidget);
      expect(harness.rootNavigator.currentState!.canPop(), isTrue);
      expect(harness.controller.expanded, isTrue);
      expect(
        tester.widget<TextField>(_key('assistant-input')).controller!.text,
        '跨页面草稿',
      );
      expect(harness.controller.stops, 0);
    },
  );

  testWidgets(
    'minimize preserves both mode drafts and does not stop execution',
    (tester) async {
      final harness = _Harness();
      harness.controller.expanded = true;
      await harness.pump(tester);
      expect(_key('developer-draft'), findsNothing);
      await _reveal(tester, 'assistant-input');
      await tester.enterText(_key('assistant-input'), '对话草稿');
      await tester.tap(find.text('高级开发'));
      await tester.pumpAndSettle();
      await tester.enterText(_key('developer-draft'), '开发草稿');
      harness.controller.change(() => harness.controller.busy = true);
      await tester.pumpAndSettle();
      await tester.tap(_key('assistant-minimize'));
      await tester.pumpAndSettle();
      expect(harness.controller.busy, isTrue);
      expect(harness.controller.stops, 0);
      expect(_key('assistant-bubble'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.tap(_key('assistant-bubble'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(_key('developer-draft')).controller!.text,
        '开发草稿',
      );
      await tester.tap(find.text('对话'));
      await tester.pumpAndSettle();
      await _reveal(tester, 'assistant-input');
      expect(
        tester.widget<TextField>(_key('assistant-input')).controller!.text,
        '对话草稿',
      );
      harness.controller.change(() => harness.controller.enabled = false);
      await tester.pumpAndSettle();
      expect(find.byType(AssistantPanel), findsNothing);
    },
  );

  testWidgets(
    'connection uses its nested navigator with stop and revocation accessible',
    (tester) async {
      final harness = _Harness();
      harness.controller.expanded = true;
      harness.controller.grant = AssistantGrant();
      await harness.pump(tester);
      await tester.tap(_key('assistant-connection'));
      await tester.pumpAndSettle();
      expect(find.text('AI 连接'), findsOneWidget);
      expect(harness.rootNavigator.currentState!.canPop(), isFalse);
      harness.controller.change(() => harness.controller.busy = true);
      await tester.pump();
      await tester.tap(_key('assistant-stop'));
      await tester.tap(_key('assistant-revoke'));
      await tester.pumpAndSettle();
      expect(harness.controller.stops, 1);
      expect(harness.controller.grant, isNull);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(_key('assistant-mode'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('standalone panel provides proper navigation for routes too', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.pump(tester, standalone: true);
    await tester.tap(_key('assistant-connection'));
    await tester.pumpAndSettle();
    expect(find.text('AI 连接'), findsOneWidget);
    expect(harness.rootNavigator.currentState!.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'draft is never sent before explicit permission; grants default to least privilege',
    (tester) async {
      final harness = _Harness();
      harness.controller.expanded = true;
      await harness.pump(tester);
      await _reveal(tester, 'assistant-input');
      await tester.enterText(_key('assistant-input'), '整理今天的任务');
      await _reveal(tester, 'assistant-send');
      expect(
        tester.widget<FilledButton>(_key('assistant-send')).onPressed,
        isNull,
      );
      expect(harness.controller.sent, isEmpty);
      await _reveal(tester, 'assistant-grant');
      await tester.tap(_key('assistant-grant'));
      await tester.pumpAndSettle();
      expect(find.textContaining('你的描述和界面元数据'), findsOneWidget);
      expect(harness.controller.sent, isEmpty);
      await tester.tap(_key('assistant-confirm-grant'));
      await tester.pumpAndSettle();
      final grant = harness.controller.grant!;
      expect(grant.shareTasks, isFalse);
      expect(grant.writeTasks, isFalse);
      expect(grant.navigate, isTrue);
      expect(grant.settings, isFalse);
      expect(grant.layout, isFalse);
      expect(grant.delegated, isFalse);
      await _reveal(tester, 'assistant-send');
      await tester.tap(_key('assistant-send'));
      await tester.pumpAndSettle();
      expect(harness.controller.sent, ['整理今天的任务']);
      expect(find.text('not-an-exposed-secret'), findsNothing);
    },
  );

  testWidgets(
    'project scoped sharing stays independent from writes and delegation is bounded',
    (tester) async {
      final harness = _Harness();
      harness.controller.expanded = true;
      final now = DateTime.now();
      await harness.database
          .into(harness.database.projects)
          .insert(
            ProjectsCompanion.insert(
              id: 'scoped-project',
              name: '专属项目',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await harness.pump(tester);
      await tester.tap(_key('assistant-grant'));
      await tester.pumpAndSettle();
      await _dialogReveal(tester, 'assistant-share-tasks');
      await tester.tap(_key('assistant-share-tasks'));
      await _dialogReveal(tester, 'assistant-project-scope');
      await tester.tap(_key('assistant-project-scope'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('专属项目').last);
      await tester.pumpAndSettle();
      await _dialogReveal(tester, 'assistant-delegated');
      expect(find.textContaining('最多 20 次操作'), findsOneWidget);
      await tester.tap(_key('assistant-delegated'));
      await tester.tap(_key('assistant-confirm-grant'));
      await tester.pumpAndSettle();
      final grant = harness.controller.grant!;
      expect(grant.projectId, 'scoped-project');
      expect(grant.shareTasks, isTrue);
      expect(grant.writeTasks, isFalse);
      expect(grant.delegated, isTrue);
      expect(
        grant.expiresAt.difference(DateTime.now()).inMinutes,
        inInclusiveRange(29, 30),
      );
      expect(
        await harness.database.select(harness.database.tasks).get(),
        isEmpty,
      );
      expect(harness.controller.sent, isEmpty);
    },
  );

  testWidgets(
    'pending changes require a single explicit approval and can be rejected',
    (tester) async {
      final harness = _Harness();
      harness.controller.expanded = true;
      harness.controller.grant = AssistantGrant(writeTasks: true);
      harness.controller.awaitingApproval = true;
      harness.controller.pending = [_Preview()];
      harness.controller.approvalCompletion = Completer<void>();
      await harness.pump(tester);
      expect(harness.controller.approvals, 0);
      expect(
        await harness.database.select(harness.database.tasks).get(),
        isEmpty,
      );
      await _reveal(tester, 'assistant-approve');
      expect(find.text('新增任务：准备评审'), findsNothing);
      expect(find.text('• 新增任务：准备评审'), findsOneWidget);
      await tester.tap(_key('assistant-approve'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(_key('assistant-approve')).onPressed,
        isNull,
      );
      expect(harness.controller.approvals, 1);
      harness.controller.approvalCompletion!.complete();
      await tester.pumpAndSettle();
      harness.controller.change(() {
        harness.controller.awaitingApproval = true;
        harness.controller.pending = [_Preview()];
      });
      await tester.pumpAndSettle();
      await _reveal(tester, 'assistant-reject');
      await tester.tap(_key('assistant-reject'));
      await tester.pumpAndSettle();
      expect(harness.controller.rejections, 1);
      expect(harness.controller.approvals, 1);
      expect(harness.controller.pending, isEmpty);
    },
  );

  testWidgets(
    'layout preview and manual draft editing are isolated from root navigation',
    (tester) async {
      final harness = _Harness();
      final draft = UiLayout();
      harness.controller.expanded = true;
      harness.controller.pending = [_Preview(layout: draft)];
      harness.controller.awaitingApproval = true;
      await harness.pump(tester);
      await tester.tap(find.text('预览窄屏'));
      await tester.pumpAndSettle();
      expect(find.byType(UiLayoutPreview), findsOneWidget);
      expect(harness.controller.approvals, 0);
      expect(harness.rootNavigator.currentState!.canPop(), isFalse);
      await tester.ensureVisible(find.text('返回编辑'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('返回编辑'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('手动编辑草稿'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<UiLayoutPage>(find.byType(UiLayoutPage)).initialDraft,
        same(draft),
      );
      expect(harness.rootNavigator.currentState!.canPop(), isFalse);
      expect(harness.controller.approvals, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tool results, errors, audit, undo and confirmed clearing are visible',
    (tester) async {
      final harness = _Harness();
      harness.controller.expanded = true;
      harness.controller.messages = [_ChatItem('tool', '读取到 2 个任务')];
      harness.controller.error = '模型连接暂时不可用';
      harness.controller.audit = [_AuditItem()];
      harness.controller.canUndo = true;
      await harness.pump(tester);
      expect(find.text('工具结果'), findsOneWidget);
      expect(find.text('读取到 2 个任务'), findsOneWidget);
      expect(find.text('模型连接暂时不可用'), findsOneWidget);
      expect(find.text('任务读取 · 已完成'), findsOneWidget);
      expect(find.text('not-an-exposed-secret'), findsNothing);
      await tester.tap(_key('assistant-undo'));
      await tester.pumpAndSettle();
      expect(harness.controller.undos, 1);
      await tester.tap(_key('assistant-clear'));
      await tester.pumpAndSettle();
      expect(harness.controller.clears, 0);
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      expect(harness.controller.clears, 1);
      expect(harness.controller.messages, isEmpty);
      expect(harness.controller.audit, isEmpty);
    },
  );

  testWidgets(
    'busy, revoked and expired grants disable sending but not stop or revocation',
    (tester) async {
      final harness = _Harness();
      harness.controller.expanded = true;
      harness.controller.grant = AssistantGrant();
      await harness.pump(tester);
      await _reveal(tester, 'assistant-input');
      await tester.enterText(_key('assistant-input'), '仍然是草稿');
      harness.controller.change(() => harness.controller.busy = true);
      await tester.pumpAndSettle();
      await _reveal(tester, 'assistant-send');
      expect(
        tester.widget<FilledButton>(_key('assistant-send')).onPressed,
        isNull,
      );
      expect(
        tester.widget<IconButton>(_key('assistant-stop')).onPressed,
        isNotNull,
      );
      expect(
        tester.widget<IconButton>(_key('assistant-revoke')).onPressed,
        isNotNull,
      );
      await tester.tap(_key('assistant-stop'));
      await tester.tap(_key('assistant-revoke'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(_key('assistant-send')).onPressed,
        isNull,
      );
      harness.controller.setGrant(
        AssistantGrant(
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(_key('assistant-send')).onPressed,
        isNull,
      );
      expect(harness.controller.sent, isEmpty);
    },
  );
}
