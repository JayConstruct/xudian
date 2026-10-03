import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/declarative/declarative_module_parser.dart';
import 'package:task_app/core/contracts/command_bus.dart';
import 'package:task_app/core/contracts/query_bus.dart';
import 'package:task_app/core/declarative/runtime/declarative_module_store.dart';
import 'package:task_app/core/declarative/runtime/rules/rule_engine.dart';
import 'package:task_app/core/declarative/runtime/rules/rule_execution_store.dart';
import 'package:task_app/core/declarative/runtime/templates/template_engine.dart';
import 'package:task_app/core/declarative/package/module_install_provenance.dart';
import 'package:task_app/core/events/event_bus.dart';
import 'package:task_app/core/modules/app_module.dart';
import 'package:task_app/core/modules/module_manifest.dart';
import 'package:task_app/core/modules/module_registry.dart';
import 'package:task_app/core/security/capability_registry.dart';
import 'package:task_app/core/ui/ui_registration.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/features/ai/proposal/module_proposal_service.dart';
import 'package:task_app/features/declarative_runtime/declarative_runtime_controller.dart';

class _BuiltInModule implements AppModule {
  @override
  ModuleManifest get manifest => const ModuleManifest(
    id: 'app.builtin.sample',
    version: '1.0.0',
    coreApi: '1',
  );

  @override
  List<UiRegistration> get ui => const [];
}

void main() {
  late AppDatabase database;
  late DeclarativeModuleStore store;
  late ModuleRegistry registry;
  late DeclarativeRuntimeController runtime;
  late ModuleProposalService proposals;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    store = DeclarativeModuleStore(database);
    registry = ModuleRegistry(
      const [],
      capabilities: CapabilityRegistry(const []),
    );
    runtime = DeclarativeRuntimeController(store: store, registry: registry);
    proposals = ModuleProposalService(
      store: store,
      registry: registry,
      runtime: runtime,
    );
  });

  tearDown(() => database.close());

  Map<String, Object?> source(
    String version, {
    bool extraField = false,
    bool writePermission = false,
  }) {
    return {
      'formatVersion': 1,
      'manifest': {
        'id': 'app.ai.sample',
        'version': version,
        'coreApi': '1',
        'permissions': ['tasks.read', if (writePermission) 'fields.write'],
      },
      'fields': [
        {'id': 'difficulty', 'label': '难度', 'type': 'number'},
        if (extraField) {'id': 'subject', 'label': '科目', 'type': 'text'},
      ],
    };
  }

  test('proposal for new module describes install and applies', () async {
    final proposal = await proposals.prepare(source('1.0.0'));

    expect(proposal.diff.fromVersion, isNull);
    expect(proposal.diff.toVersion, '1.0.0');
    expect(proposal.diff.permissionsAdded, ['tasks.read']);
    expect(
      proposal.diff.resources.singleWhere((item) => item.kind == 'field').added,
      ['difficulty'],
    );

    await proposals.apply(proposal);

    expect((await store.getInstalled('app.ai.sample'))?.version, '1.0.0');
    expect(
      registry.modules.any((item) => item.manifest.id == 'app.ai.sample'),
      isTrue,
    );
  });
  test('proposal update reports field and permission changes', () async {
    await runtime.install(source('1.0.0'));

    final proposal = await proposals.prepare(
      source('1.1.0', extraField: true, writePermission: true),
    );

    expect(proposal.diff.fromVersion, '1.0.0');
    expect(proposal.diff.permissionsAdded, ['fields.write']);
    final fields = proposal.diff.resources.singleWhere(
      (item) => item.kind == 'field',
    );
    expect(fields.added, ['subject']);

    await proposals.apply(proposal);
    expect((await store.getInstalled('app.ai.sample'))?.version, '1.1.0');
  });

  test('stale proposal cannot overwrite a newer module', () async {
    await runtime.install(source('1.0.0'));
    final proposal = await proposals.prepare(source('2.0.0'));

    await runtime.install(source('1.5.0'));

    await expectLater(proposals.apply(proposal), throwsStateError);
    expect((await store.getInstalled('app.ai.sample'))?.version, '1.5.0');
  });
  test('proposal downgrade is rejected in favor of rollback', () async {
    await runtime.install(source('2.0.0'));

    await expectLater(proposals.prepare(source('1.9.0')), throwsStateError);
  });

  test('proposal rejects unknown permissions', () async {
    final invalid = source('1.0.0');
    final manifest = (invalid['manifest'] as Map).cast<String, Object?>();
    manifest['permissions'] = ['shell.execute'];

    await expectLater(proposals.prepare(invalid), throwsStateError);
  });

  test('proposal cannot replace a built-in runtime module id', () async {
    registry.addOrReplace(_BuiltInModule());
    final invalid = source('1.0.0');
    final manifest = (invalid['manifest'] as Map).cast<String, Object?>();
    manifest['id'] = 'app.builtin.sample';

    await expectLater(proposals.prepare(invalid), throwsStateError);
  });

  test('proposal rejects layouts not executable by runtime v1', () async {
    final invalid = source('1.0.0');
    invalid['layouts'] = [
      {'id': 'customLayout'},
    ];

    await expectLater(proposals.prepare(invalid), throwsFormatException);
  });

  test('proposal accepts validated rule and template resources', () async {
    final events = EventBus();
    final commandBus = CommandBus();
    final ruleEngine = RuleEngine(
      events: events,
      commands: commandBus,
      queries: QueryBus(),
      executions: RuleExecutionStore(database),
    );
    final templateEngine = TemplateEngine(
      commands: commandBus,
      db: database,
      events: events,
    );
    final richRegistry = ModuleRegistry(
      const [],
      capabilities: CapabilityRegistry(const ['tasks.command', 'tasks.query']),
    );
    final richRuntime = DeclarativeRuntimeController(
      store: store,
      registry: richRegistry,
      ruleEngine: ruleEngine,
      templateEngine: templateEngine,
    );
    final service = ModuleProposalService(
      store: store,
      registry: richRegistry,
      runtime: richRuntime,
    );
    final candidate = <String, Object?>{
      'formatVersion': 1,
      'manifest': {
        'id': 'app.ai.automation',
        'version': '1.0.0',
        'coreApi': '1',
        'requiresCapabilities': ['tasks.command'],
        'permissions': ['tasks.write'],
      },
      'templates': [
        {
          'id': 'simple',
          'title': '简单模板',
          'tasks': [
            {'key': 'one', 'title': '第一项'},
          ],
        },
      ],
      'rules': [
        {
          'id': 'completeRule',
          'event': 'task.completed',
          'actions': [
            {
              'command': 'task.create',
              'payload': {'title': '复盘任务'},
            },
          ],
        },
      ],
    };

    final proposal = await service.prepare(candidate);
    expect(
      proposal.diff.resources.map((item) => item.kind),
      containsAll(['template', 'rule']),
    );

    await ruleEngine.close();
    await events.close();
  });

  test('proposal rejects select fields without options', () async {
    final invalid = source('1.0.0');
    invalid['fields'] = [
      {'id': 'level', 'label': '等级', 'type': 'select'},
    ];

    await expectLater(proposals.prepare(invalid), throwsFormatException);
  });

  test('market provenance persists through enable and rollback', () async {
    const provenance = ModuleInstallProvenance(
      origin: 'market',
      publisherId: 'xudian.official',
      packageDigest: 'abc123',
      reviewId: 'review-001',
      signatureKeyId: 'release-2026',
    );

    final proposal = await proposals.prepare(
      source('1.0.0'),
      provenance: provenance,
    );
    await proposals.apply(proposal);

    var installed = await store.getInstalled('app.ai.sample');
    expect(installed?.origin, 'market');
    expect(installed?.publisherId, 'xudian.official');
    expect(installed?.packageDigest, 'abc123');
    expect(installed?.reviewId, 'review-001');
    expect(installed?.signatureKeyId, 'release-2026');

    await runtime.setEnabled('app.ai.sample', false);
    await runtime.setEnabled('app.ai.sample', true);
    installed = await store.getInstalled('app.ai.sample');
    expect(installed?.origin, 'market');
    expect(installed?.publisherId, 'xudian.official');

    await runtime.install(
      source('1.1.0'),
      provenance: const ModuleInstallProvenance.ai(),
    );
    installed = await store.getInstalled('app.ai.sample');
    expect(installed?.version, '1.1.0');
    expect(installed?.origin, 'ai');

    await runtime.rollback('app.ai.sample', '1.0.0');
    installed = await store.getInstalled('app.ai.sample');
    expect(installed?.version, '1.0.0');
    expect(installed?.origin, 'market');
    expect(installed?.reviewId, 'review-001');

    await expectLater(
      store.install(
        const DeclarativeModuleParser().parse(source('1.0.0')),
        source('1.0.0'),
        provenance: const ModuleInstallProvenance.ai(),
      ),
      throwsStateError,
    );
  });

  test(
    'same semantic source with different key order is immutable-safe',
    () async {
      final first = source('1.0.0');
      final reordered = <String, Object?>{
        'fields': first['fields'],
        'manifest': first['manifest'],
        'formatVersion': 1,
      };

      await runtime.install(first);
      await store.install(
        const DeclarativeModuleParser().parse(reordered),
        reordered,
      );
      expect((await store.listVersions('app.ai.sample')).length, 1);
    },
  );
}
