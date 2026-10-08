import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/legacy_app.dart';
import 'package:task_app/core/declarative/runtime/declarative_module_store.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/features/ai/assistant_runtime.dart';
import 'package:task_app/features/ai/settings/ai_secret_store.dart';
import 'package:task_app/features/ai/settings/ai_settings_store.dart';
import 'package:task_app/features/module_manager/builtin_module_controller.dart';
import 'package:task_app/features/tasks/application/providers.dart';

class _HttpOverrides extends HttpOverrides {
  final clients = <_PendingClient>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = _PendingClient();
    clients.add(client);
    return client;
  }
}

class _PendingClient extends Fake implements HttpClient {
  final request = _PendingRequest();
  bool forceClosed = false;

  @override
  Future<HttpClientRequest> postUrl(Uri url) async => request;

  @override
  void close({bool force = false}) => forceClosed = force;
}

class _PendingRequest extends Fake implements HttpClientRequest {
  final response = Completer<HttpClientResponse>();
  final body = StringBuffer();
  bool started = false;
  int aborts = 0;

  @override
  final HttpHeaders headers = _Headers();

  @override
  void write(Object? object) => body.write(object);

  @override
  Future<HttpClientResponse> close() {
    started = true;
    return response.future;
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) => aborts++;

  void reply() {
    response.complete(
      _Response(
        utf8.encode(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'formatVersion': 1,
                    'manifest': {
                      'id': 'app.cancelled.advanced',
                      'version': '1.0.0',
                      'coreApi': '1',
                    },
                  }),
                },
              },
            ],
          }),
        ),
      ),
    );
  }
}

class _Headers extends Fake implements HttpHeaders {
  @override
  set contentType(ContentType? value) {}

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.bytes);

  final List<int> bytes;

  @override
  int get statusCode => 200;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Secrets implements AiSecretStore {
  @override
  Future<String?> readApiKey() async => null;

  @override
  Future<void> writeApiKey(String value) async {}

  @override
  Future<void> deleteApiKey() async {}
}

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 30 && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue);
}

void main() {
  for (final action in ['stop', 'revoke', 'disable']) {
    testWidgets(
      'advanced generation cancels on $action without applying a late reply',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final database = AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final app = XudianApp();
        addTearDown(app.registry.dispose);
        final overrides = _HttpOverrides();
        final previousOverrides = HttpOverrides.current;
        HttpOverrides.global = overrides;
        addTearDown(() => HttpOverrides.global = previousOverrides);
        await DriftAiSettingsStore(database).save(
          endpoint: 'https://model.example/v1/chat/completions',
          model: 'cancellation-test',
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWith((ref) async => database),
              aiSecretStoreProvider.overrideWithValue(_Secrets()),
            ],
            child: app,
          ),
        );
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(XudianApp)),
        );
        final assistant = container.read(
          assistantControllerProvider(app.registry),
        );
        assistant.setGrant(AssistantGrant());
        await tester.tap(find.byKey(const ValueKey('assistant-bubble')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('高级开发'));
        await tester.pumpAndSettle();
        final requestField = find.widgetWithText(TextField, '你想添加什么功能？');
        await tester.enterText(requestField, '建立一个考试管理模块');
        await tester.ensureVisible(find.text('生成并查看变更'));
        await tester.tap(find.text('生成并查看变更'));
        await _until(
          tester,
          () =>
              overrides.clients.isNotEmpty &&
              overrides.clients.single.request.started,
        );
        final client = overrides.clients.single;
        expect(client.request.body.toString(), contains('建立一个考试管理模块'));
        expect(assistant.busy, isFalse);
        expect(assistant.awaitingApproval, isFalse);
        final version = assistant.cancellationVersion;
        await tester.tap(find.byKey(const ValueKey('assistant-minimize')));
        await tester.pumpAndSettle();
        expect(client.forceClosed, isFalse);
        expect(client.request.aborts, 0);
        expect(assistant.cancellationVersion, version);
        expect(tester.binding.hasScheduledFrame, isFalse);
        await tester.tap(find.byKey(const ValueKey('assistant-bubble')));
        await tester.pump();
        expect(
          tester.widget<TextField>(requestField).controller!.text,
          '建立一个考试管理模块',
        );
        if (action == 'disable') {
          final modules = await container.read(
            builtinModuleControllerProvider(app.registry).future,
          );
          await modules.setEnabled('app.ai', false);
        } else {
          await tester.tap(find.byKey(ValueKey('assistant-$action')));
        }
        await _until(tester, () => client.forceClosed);
        await tester.pumpAndSettle();
        expect(client.request.aborts, 1);
        expect(assistant.cancellationVersion, greaterThan(version));
        if (action != 'stop') expect(assistant.grant, isNull);
        client.request.reply();
        await tester.pumpAndSettle();
        expect(find.text('确认应用'), findsNothing);
        expect(find.textContaining('AI 提案失败'), findsNothing);
        expect(app.registry.isEnabled('app.cancelled.advanced'), isFalse);
        expect(
          await DeclarativeModuleStore(database)
              .getInstalled('app.cancelled.advanced'),
          isNull,
        );
        if (action != 'disable') {
          expect(
            tester.widget<TextField>(requestField).controller!.text,
            '建立一个考试管理模块',
          );
          final generate = find.ancestor(
            of: find.text('生成并查看变更'),
            matching: find.byType(FilledButton),
          );
          expect(tester.widget<FilledButton>(generate).onPressed, isNotNull);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
