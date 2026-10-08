import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/declarative/declarative_module_parser.dart';
import 'package:task_app/features/ai/proposal/module_proposal.dart';
import 'package:task_app/core/declarative/package/module_install_provenance.dart';
import 'package:task_app/core/ui/module_ui_labels.dart';
import 'package:task_app/features/ai/proposal/module_proposal_review.dart';
import 'package:drift/native.dart';
import 'package:task_app/core/declarative/runtime/declarative_module_store.dart';
import 'package:task_app/core/modules/module_registry.dart';
import 'package:task_app/core/security/capability_registry.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/features/ai/proposal/module_proposal_coordinator.dart';
import 'package:task_app/features/ai/proposal/module_proposal_service.dart';
import 'package:task_app/features/declarative_runtime/declarative_runtime_controller.dart';

void main() {
  test(
    'module labels explain supported identifiers and preserve unknown ones',
    () {
      const permissions = {
        'tasks.read': '读取任务与项目（tasks.read）',
        'tasks.write': '创建或修改任务与项目（tasks.write）',
        'fields.write': '修改自定义字段（fields.write）',
        'ui.register': '添加界面入口（ui.register）',
        'custom.permission': 'custom.permission',
      };
      for (final entry in permissions.entries) {
        expect(modulePermissionLabel(entry.key), entry.value);
      }
      const resources = {
        'page': '页面（page）',
        'view': '任务视图（view）',
        'field': '自定义字段（field）',
        'template': '任务模板（template）',
        'rule': '自动化规则（rule）',
        'layout': '布局（layout）',
        'custom-resource': 'custom-resource',
      };
      for (final entry in resources.entries) {
        expect(moduleResourceLabel(entry.key), entry.value);
      }
    },
  );
  testWidgets('a pending review cannot apply after its module was disabled', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    final registry = ModuleRegistry([], capabilities: CapabilityRegistry([]));
    addTearDown(registry.dispose);
    final store = DeclarativeModuleStore(db);
    final coordinator = ModuleProposalCoordinator(
      ModuleProposalService(
        store: store,
        registry: registry,
        runtime: DeclarativeRuntimeController(store: store, registry: registry),
      ),
    );
    bool active = true;
    bool? applied;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                applied = await coordinator.reviewAndApply(context, {
                  'formatVersion': 1,
                  'manifest': {
                    'id': 'app.cancelled.review',
                    'version': '1.0.0',
                    'coreApi': '1',
                  },
                }, canApply: () => active);
              },
              child: const Text('审核'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('审核'));
    await tester.pumpAndSettle();
    active = false;
    await tester.tap(find.text('确认应用'));
    await tester.pumpAndSettle();
    expect(applied, isFalse);
    expect(await store.getInstalled('app.cancelled.review'), isNull);
    expect(registry.modules, isEmpty);
  });
  testWidgets('proposal review requires explicit confirmation', (tester) async {
    final module = const DeclarativeModuleParser().parse({
      'formatVersion': 1,
      'manifest': {
        'id': 'app.review.sample',
        'version': '1.0.0',
        'coreApi': '1',
        'permissions': ['tasks.read'],
      },
    });
    final proposal = ModuleProposal(
      source: const {},
      module: module,
      expectedCurrentVersion: null,
      provenance: const ModuleInstallProvenance.ai(),
      diff: const ModuleProposalDiff(
        moduleId: 'app.review.sample',
        fromVersion: null,
        toVersion: '1.0.0',
        permissionsAdded: ['tasks.read'],
        permissionsRemoved: ['tasks.write'],
        resources: [
          ModuleResourceChange(
            kind: 'field',
            added: ['difficulty'],
            removed: [],
            changed: [],
          ),
        ],
      ),
    );

    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showModuleProposalReview(
                  context: context,
                  proposal: proposal,
                );
              },
              child: const Text('打开审核'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开审核'));
    await tester.pumpAndSettle();
    expect(find.text('新增权限'), findsOneWidget);
    expect(find.text('• 读取任务与项目（tasks.read）'), findsOneWidget);
    expect(find.text('• 创建或修改任务与项目（tasks.write）'), findsOneWidget);
    expect(find.text('自定义字段（field）'), findsOneWidget);
    expect(find.text('新增：difficulty'), findsOneWidget);
    expect(
      find.text(
        '确认后会立即安装或更新模块。可在版本历史中恢复旧配置；'
        '恢复配置不会撤销已创建的任务或已执行的自动化操作。',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isFalse);

    await tester.tap(find.text('打开审核'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认应用'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
