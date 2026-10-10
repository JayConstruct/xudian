import '../../../data/providers.dart';
export '../../../data/providers.dart';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/contracts/command_bus.dart';
import '../../../core/contracts/query_bus.dart';
import '../../../core/declarative/runtime/declarative_module_store.dart';
import '../../../core/declarative/runtime/field_value_store.dart';
import '../../../core/declarative/runtime/rules/rule_engine.dart';
import '../../../core/declarative/runtime/rules/rule_execution_store.dart';
import '../../../core/declarative/runtime/templates/template_engine.dart';
import '../../../core/declarative/package/module_package.dart';
import '../../../core/declarative/package/module_package_verifier.dart';
import '../../../core/events/event_bus.dart';
import '../../../data/app_database.dart';
import '../../ai/settings/ai_secret_store.dart';
import '../../ai/settings/ai_settings_store.dart';
import '../data/change_journal.dart';
import '../data/task_store.dart';
import '../integration/field_command_bindings.dart';
import '../integration/task_command_bindings.dart';
import '../integration/task_query_bindings.dart';
import 'task_command_service.dart';
import 'task_query_service.dart';

final eventBusProvider = Provider<EventBus>((ref) {
  final bus = EventBus();
  ref.onDispose(() {
    bus.close();
  });
  return bus;
});

final taskStoreProvider = FutureProvider<TaskStore>((ref) async {
  return TaskStore(await ref.watch(databaseProvider.future));
});

final fieldValueStoreProvider = FutureProvider<FieldValueStore>((ref) async {
  return FieldValueStore(await ref.watch(databaseProvider.future));
});

final declarativeModuleStoreProvider = FutureProvider<DeclarativeModuleStore>((
  ref,
) async {
  return DeclarativeModuleStore(await ref.watch(databaseProvider.future));
});

final aiSettingsStoreProvider = FutureProvider<AiSettingsStore>((ref) async {
  return DriftAiSettingsStore(await ref.watch(databaseProvider.future));
});

final aiSecretStoreProvider = Provider<AiSecretStore>((ref) {
  return SecureAiSecretStore();
});

final trustedPublisherRegistryProvider =
    FutureProvider<TrustedPublisherRegistry>((ref) async {
      final raw = await rootBundle.loadString('assets/trusted_publishers.json');
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException(
          'trusted_publishers.json must be an object',
        );
      }
      return TrustedPublisherRegistry.fromJson(
        decoded.map((key, value) => MapEntry('$key', value)),
      );
    });

final modulePackageVerifierProvider = FutureProvider<ModulePackageVerifier>((
  ref,
) async {
  return ModulePackageVerifier(
    trustedPublishers: await ref.watch(trustedPublisherRegistryProvider.future),
  );
});

final queryClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final taskQueryServiceProvider = FutureProvider<TaskQueryService>((ref) async {
  return TaskQueryService(
    await ref.watch(taskStoreProvider.future),
    now: ref.watch(queryClockProvider),
  );
});
final taskCommandServiceProvider = FutureProvider<TaskCommandService>((
  ref,
) async {
  final db = await ref.watch(databaseProvider.future);
  final store = await ref.watch(taskStoreProvider.future);
  return TaskCommandService(
    db: db,
    store: store,
    journal: ChangeJournal(db),
    events: ref.watch(eventBusProvider),
  );
});

final projectsProvider = StreamProvider<List<Project>>((ref) async* {
  final queries = await ref.watch(taskQueryServiceProvider.future);
  yield* queries.watchProjects();
});

final tasksProvider = StreamProvider<List<Task>>((ref) async* {
  final queries = await ref.watch(taskQueryServiceProvider.future);
  yield* queries.watchTasks();
});

final projectTasksProvider = StreamProvider.autoDispose
    .family<List<Task>, String>((ref, projectId) async* {
      final queries = await ref.watch(taskQueryServiceProvider.future);
      yield* queries.watchProjectTasks(projectId);
    });

final commandBusProvider = FutureProvider<CommandBus>((ref) async {
  final bus = CommandBus();
  registerTaskCommands(bus, await ref.watch(taskCommandServiceProvider.future));
  registerFieldCommands(
    bus,
    await ref.watch(fieldValueStoreProvider.future),
    events: ref.watch(eventBusProvider),
  );
  return bus;
});

final queryBusProvider = FutureProvider<QueryBus>((ref) async {
  final bus = QueryBus();
  registerTaskQueries(bus, await ref.watch(taskQueryServiceProvider.future));
  return bus;
});

final ruleExecutionStoreProvider = FutureProvider<RuleExecutionStore>((
  ref,
) async {
  return RuleExecutionStore(await ref.watch(databaseProvider.future));
});

final ruleEngineProvider = FutureProvider<RuleEngine>((ref) async {
  final engine = RuleEngine(
    events: ref.watch(eventBusProvider),
    commands: await ref.watch(commandBusProvider.future),
    queries: await ref.watch(queryBusProvider.future),
    executions: await ref.watch(ruleExecutionStoreProvider.future),
  );
  ref.onDispose(() {
    engine.close();
  });
  return engine;
});

final templateEngineProvider = FutureProvider<TemplateEngine>((ref) async {
  return TemplateEngine(
    commands: await ref.watch(commandBusProvider.future),
    db: await ref.watch(databaseProvider.future),
    events: ref.watch(eventBusProvider),
  );
});
