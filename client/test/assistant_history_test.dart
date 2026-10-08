import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/modules/app_module.dart';
import 'package:task_app/core/modules/module_manifest.dart';
import 'package:task_app/core/modules/module_registry.dart';
import 'package:task_app/core/security/capability_registry.dart';
import 'package:task_app/core/ui/ui_registration.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/features/ai/assistant_runtime.dart';
import 'package:task_app/features/ai/provider/assistant_model.dart';
import 'package:task_app/features/ai/settings/ai_secret_store.dart';
import 'package:task_app/features/ai/settings/ai_settings_store.dart';
import 'package:task_app/features/tasks/application/providers.dart';

class _Module implements AppModule {
  @override
  ModuleManifest get manifest => const ModuleManifest(
    id: 'app.ai',
    version: '1.0.0',
    coreApi: '1',
    permissions: ['ui.register'],
  );

  @override
  List<UiRegistration> get ui => const [];
}

class _Secrets implements AiSecretStore {
  static const key = 'secret-from-secure-storage';

  @override
  Future<String?> readApiKey() async => key;

  @override
  Future<void> deleteApiKey() async => throw StateError('Not allowed');

  @override
  Future<void> writeApiKey(String value) async =>
      throw StateError('Not allowed');
}

class _Model implements AssistantModel {
  int calls = 0;
  bool exceedBudget = false;

  @override
  Future<AssistantModelReply> complete({
    required Uri endpoint,
    required String model,
    required String apiKey,
    required List<AssistantMessage> messages,
    required List<AssistantToolSchema> tools,
    AiRequestCancellation? cancellation,
  }) async {
    calls++;
    expect(apiKey, _Secrets.key);
    expect(
      jsonEncode(messages.map((message) => message.toJson()).toList()),
      isNot(contains(_Secrets.key)),
    );
    if (exceedBudget && calls == 1) {
      return AssistantModelReply(
        text: '',
        calls: [
          for (var index = 0; index < 25; index++)
            AssistantToolCall(
              id: 'over-limit-$index',
              name: 'ui_catalog',
              arguments: {},
            ),
        ],
      );
    }
    if (exceedBudget && calls == 2) {
      final requested = messages
          .where((message) => message.toolCalls.isNotEmpty)
          .single
          .toolCalls;
      final answered = messages
          .where((message) => message.role == 'tool')
          .map((message) => message.toolCallId)
          .toSet();
      expect(requested.every((call) => answered.contains(call.id)), isTrue);
      expect(answered, hasLength(25));
    }
    return AssistantModelReply(text: 'Do not store ${_Secrets.key}');
  }
}

Future<Map<String, Object?>> _history(AppDatabase database) async {
  final row =
      await (database.select(database.appSettings)
            ..where((row) => row.key.equals(AssistantController.historyKey)))
          .getSingle();
  return (jsonDecode(row.value) as Map).cast<String, Object?>();
}

Future<void> _eventually(Future<bool> Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('History persistence did not settle');
}

void main() {
  late AppDatabase database;
  late ModuleRegistry registry;
  late ProviderContainer container;
  late _Model model;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    registry = ModuleRegistry([
      _Module(),
    ], capabilities: CapabilityRegistry([]));
    model = _Model();
    await DriftAiSettingsStore(
      database,
    ).save(endpoint: 'https://example.com/v1/chat/completions', model: 'model');
    await database
        .into(database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: AssistantController.historyKey,
            value: jsonEncode({
              'version': 1,
              'messages': [
                {'role': 'user', 'text': 'Previous request'},
              ],
              'audit': [
                {'title': 'Previous action', 'status': '已执行'},
              ],
              'interrupted': true,
            }),
          ),
        );
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) async => database),
        aiSecretStoreProvider.overrideWithValue(_Secrets()),
        assistantModelProvider.overrideWithValue(model),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    registry.dispose();
    await database.close();
  });

  test('restart restores records without authorization, pending work or model calls', () async {
    final controller = container.read(assistantControllerProvider(registry));
    await _eventually(() async => controller.messages.isNotEmpty);
    expect(controller.messages.single.text, 'Previous request');
    expect(controller.audit.last.status, contains('不会自动恢复'));
    expect(controller.grant, isNull);
    expect(controller.pending, isEmpty);
    expect(controller.canUndo, isFalse);
    expect(model.calls, 0);
  });

  test('granting before restore does not overwrite existing history with empty records', () async {
    final controller = container.read(assistantControllerProvider(registry));
    controller.setGrant(AssistantGrant());
    await _eventually(
      () async => ((await _history(database))['audit'] as List).length == 2,
    );
    expect(((await _history(database))['messages'] as List).single, {
      'role': 'user',
      'text': 'Previous request',
    });
    expect(model.calls, 0);
  });

  test('secret echoes are redacted in visible and durable records, clear is durable', () async {
    final controller = container.read(assistantControllerProvider(registry));
    controller.setGrant(AssistantGrant());
    await controller.send('Hello');
    expect(model.calls, 1);
    expect(controller.messages.last.text, 'Do not store [密钥已隐藏]');
    await _eventually(
      () async => ((await _history(database))['messages'] as List).length == 3,
    );
    expect(jsonEncode(await _history(database)), isNot(contains(_Secrets.key)));
    await controller.clearHistory();
    final history = await _history(database);
    expect(history['messages'], isEmpty);
    expect(history['audit'], isEmpty);
    expect(history['interrupted'], isFalse);
  });

  test(
    'interrupted tool group is closed before the next conversation request',
    () async {
      model.exceedBudget = true;
      final controller = container.read(assistantControllerProvider(registry));
      controller.setGrant(AssistantGrant());
      await controller.send('Exceed the call budget');
      expect(controller.error, contains('上限'));
      expect(controller.pending, isEmpty);
      await controller.send('Continue safely');
      expect(model.calls, 2);
      expect(controller.error, isNull);
      await controller.clearHistory();
    },
  );
}
