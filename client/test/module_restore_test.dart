import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/declarative/declarative_module_parser.dart';
import 'package:task_app/core/declarative/runtime/declarative_module_store.dart';
import 'package:task_app/core/modules/module_registry.dart';
import 'package:task_app/core/security/capability_registry.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/features/declarative_runtime/declarative_app_module.dart';
import 'package:task_app/features/declarative_runtime/declarative_runtime_controller.dart';

Map<String, Object?> source(
  String id, [
  List<String> dependencies = const [],
]) => {
  'formatVersion': 1,
  'manifest': {
    'id': id,
    'version': '1.0.0',
    'coreApi': '1',
    'dependencies': dependencies,
  },
  'fields': [
    {'id': 'note', 'type': 'text', 'label': '备注'},
  ],
};

void main() {
  late AppDatabase db;
  late DeclarativeModuleStore store;
  late ModuleRegistry registry;
  late DeclarativeRuntimeController runtime;
  const parser = DeclarativeModuleParser();
  Future<void> persist(
    String id, [
    List<String> dependencies = const [],
  ]) async {
    final json = source(id, dependencies);
    await store.install(parser.parse(json), json);
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = DeclarativeModuleStore(db);
    registry = ModuleRegistry([], capabilities: CapabilityRegistry([]));
    runtime = DeclarativeRuntimeController(store: store, registry: registry);
  });
  tearDown(() async {
    registry.dispose();
    await db.close();
  });

  test(
    'restores dependencies before dependents regardless of persisted order',
    () async {
      await persist('app.child.module', ['app.middle.module']);
      await persist('app.middle.module', ['app.base.module']);
      await persist('app.base.module');
      expect(await runtime.restoreEnabled(), isEmpty);
      expect(registry.modules.map((module) => module.manifest.id), [
        'app.base.module',
        'app.middle.module',
        'app.child.module',
      ]);
      expect(
        (await store.listInstalled()).every((item) => item.enabled),
        isTrue,
      );
      expect(
        (await db.select(db.fieldDefinitions).get()).every(
          (item) => item.active,
        ),
        isTrue,
      );
    },
  );

  test('cycles and missing dependencies are isolated with reasons and data retained', () async {
    await persist('app.cycle.a', ['app.cycle.b']);
    await persist('app.cycle.b', ['app.cycle.a']);
    await persist('app.missing.module', ['app.absent.module']);
    await persist('app.dependent.module', ['app.missing.module']);
    await persist('app.healthy.module');
    final failures = await runtime.restoreEnabled();
    expect(
      failures.map((failure) => failure.moduleId),
      unorderedEquals([
        'app.cycle.a',
        'app.cycle.b',
        'app.missing.module',
        'app.dependent.module',
      ]),
    );
    expect(failures.any((failure) => failure.reason.contains('循环')), isTrue);
    expect(
      failures.any((failure) => failure.reason.contains('app.absent.module')),
      isTrue,
    );
    expect(registry.modules.single.manifest.id, 'app.healthy.module');
    final installed = await store.listInstalled();
    expect(installed, hasLength(5));
    expect(
      installed.where((row) => row.enabled).single.id,
      'app.healthy.module',
    );
    expect(await store.listVersions('app.cycle.a'), hasLength(1));
    expect(
      (await db.select(db.fieldDefinitions).get())
          .where((row) => row.active)
          .single
          .moduleId,
      'app.healthy.module',
    );
  });

  test(
    'update creating a cycle is rejected before changing persistent state',
    () async {
      await runtime.install(source('app.base.module'));
      await runtime.install(source('app.child.module', ['app.base.module']));
      final update = source('app.base.module', ['app.child.module']);
      (update['manifest'] as Map)['version'] = '2.0.0';
      await expectLater(runtime.install(update), throwsStateError);
      expect((await store.getInstalled('app.base.module'))!.version, '1.0.0');
      expect(registry.modules.first.manifest.dependencies, isEmpty);
      expect(await store.listVersions('app.base.module'), hasLength(1));
    },
  );

  test('registry rejects a self dependency', () {
    expect(
      () => registry.addOrReplace(
        DeclarativeAppModule(
          parser.parse(source('app.self.module', ['app.self.module'])),
        ),
      ),
      throwsStateError,
    );
    expect(registry.modules, isEmpty);
  });
}
