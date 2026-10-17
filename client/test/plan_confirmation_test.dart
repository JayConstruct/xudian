import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/data_change_review.dart';
import 'package:task_app/core/module_host/host_dialogs.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/plan_confirmation.dart';
import 'package:task_app/data/app_database.dart';

const _options = {
  'title': '确认移动任务',
  'message': '阅读论文\n原安排：10月17日 11:00—11:30\n新安排：10月17日 13:00—13:30',
  'confirmLabel': '应用调整',
};
Map<String, Object?> _details({bool deletion = false}) => {
  'planId': 'frozen-plan',
  'writes': [
    {
      'moduleId': 'test.confirmation',
      'space': 'test-data',
      'collection': 'notes',
      'id': 'a',
      'before': {'id': 'a', 'title': '真实任务', 'start': 'original-time'},
      'value': deletion
          ? null
          : {'id': 'a', 'title': '真实任务', 'start': 'frozen-new-time'},
    },
  ],
  'result': {'frozen': true},
};
Future<void> _show(
  WidgetTester tester,
  Object? details, {
  Map<String, Object?> options = _options,
  ValueChanged<bool>? onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final accepted = await reviewDialog(
                context,
                '确认实际数据变更',
                details,
                confirmation: PlanConfirmation.parse(options),
              );
              onResult?.call(accepted);
            },
            child: const Text('打开确认'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开确认'));
  await tester.pumpAndSettle();
}

void main() {
  test('confirmation validates every plain text field and freezes only allowed presentation keys', () {
    final input = <String, Object?>{
      ..._options,
      'acknowledgement': '确认接受超截止安排',
    };
    final parsed = PlanConfirmation.parse(input);
    input['message'] = '之后修改';
    expect(parsed.message, _options['message']);
    expect(parsed.acknowledgement, '确认接受超截止安排');
    expect(() => parsed.toJson()['title'] = '修改', throwsUnsupportedError);
    for (final key in PlanConfirmation.limits.keys) {
      for (final value in [
        null,
        '',
        '  ',
        false,
        5,
        [],
        List.filled(PlanConfirmation.limits[key]! + 1, '字').join(),
      ]) {
        expect(
          () => PlanConfirmation.parse({..._options, key: value}),
          throwsFormatException,
          reason: '$key=$value',
        );
      }
    }
    for (final value in [
      null,
      [],
      '确认',
      {..._options, 'writes': []},
      {..._options}..remove('title'),
    ]) {
      expect(() => PlanConfirmation.parse(value), throwsFormatException);
    }
    expect(
      PlanConfirmation.parse({
        ..._options,
        'acknowledgement': List.filled(1000, '字').join(),
      }).acknowledgement!.length,
      1000,
    );
  });

  testWidgets(
    'compact confirmation shows plain action text, cancels, and keeps real writes expandable',
    (tester) async {
      bool? accepted;
      await _show(tester, _details(), onResult: (value) => accepted = value);
      expect(find.text('确认移动任务'), findsOneWidget);
      expect(find.text(_options['message']!), findsOneWidget);
      expect(find.byType(DataChangeReview), findsNothing);
      expect(find.text('start'), findsNothing);
      await tester.tap(find.text('查看变更详情'));
      await tester.pumpAndSettle();
      expect(find.byType(DataChangeReview), findsOneWidget);
      expect(find.text('修改 · 真实任务'), findsOneWidget);
      expect(find.text('之前："original-time"'), findsOneWidget);
      expect(find.text('之后："frozen-new-time"'), findsOneWidget);
      final raw = find.text('全量原始详情');
      await tester.ensureVisible(raw);
      await tester.tap(raw);
      await tester.pumpAndSettle();
      expect(find.textContaining('frozen-plan'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(accepted, isFalse);
    },
  );

  testWidgets(
    'overdue acknowledgement starts unchecked and gates the same confirmation button',
    (tester) async {
      bool? accepted;
      await _show(
        tester,
        _details(),
        options: {..._options, 'acknowledgement': '我确认接受超过截止时间的安排'},
        onResult: (value) => accepted = value,
      );
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      final confirm = find.widgetWithText(FilledButton, '应用调整');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.tap(find.text('应用调整'));
      await tester.pump();
      expect(accepted, isNull);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      await tester.tap(find.text('应用调整'));
      await tester.pumpAndSettle();
      expect(accepted, isTrue);
    },
  );

  testWidgets(
    'real deletions are announced before optional details are expanded',
    (tester) async {
      await _show(tester, _details(deletion: true));
      expect(find.text('将删除 1 条记录，请核对后确认。'), findsOneWidget);
      expect(find.byType(DataChangeReview), findsNothing);
      await tester.tap(find.text('查看变更详情'));
      await tester.pumpAndSettle();
      expect(find.text('删除 · 真实任务'), findsOneWidget);
      expect(find.text('此记录将被删除'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unrecognizable plans retain the original host review instead of compact text',
    (tester) async {
      await _show(
        tester,
        {
          'planId': 'invalid',
          'writes': [
            {'value': null},
          ],
        },
        options: {..._options, 'acknowledgement': '不能替代原始审核'},
      );
      expect(find.text('确认实际数据变更'), findsOneWidget);
      expect(find.text('确认移动任务'), findsNothing);
      expect(find.text('无法生成可靠的数据摘要，请核对以下原始详情。'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('确认'), findsOneWidget);
    },
  );

  testWidgets(
    'compact review remains scrollable on a narrow screen with large text and a long acknowledgement',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      bool? accepted;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  accepted = await reviewDialog(
                    context,
                    '原始审核',
                    _details(),
                    confirmation: PlanConfirmation.parse({
                      ..._options,
                      'message': List.filled(50, '完整安排的原始时间与新时间').join('\n'),
                      'acknowledgement': List.filled(
                        30,
                        '我确认接受超截止安排',
                      ).join('，'),
                    }),
                  );
                },
                child: const Text('打开确认'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开确认'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '应用调整'))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(find.text('应用调整').hitTestable(), findsOneWidget);
      await tester.tap(find.text('应用调整'));
      await tester.pumpAndSettle();
      expect(accepted, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  group('SDK and host frozen review', () {
    late AppDatabase db;
    late CollectionStore store;
    late ModuleHost host;
    late Directory directory;
    late ModuleActor actor;
    var serial = 0;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      store = CollectionStore(db);
      directory = await Directory.systemTemp.createTemp('confirmation-host-');
      host = ModuleHost(store: store, directory: directory);
      await host.initialize();
      final package = await ScriptPackage.verify(
        await ScriptPackage.build(
          {
            'formatVersion': 3,
            'manifest': {
              'id': 'test.confirmation',
              'version': '1.0.0',
              'hostApi': '^1.27.0',
              'dataVersion': 1,
              'permissions': [],
            },
            'entryPoint': 'main.js',
            'pages': [],
            'services': [],
            'collections': [
              {
                'id': 'notes',
                'schema': {
                  'type': 'object',
                  'properties': {
                    'id': {'type': 'string'},
                    'title': {'type': 'string'},
                  },
                  'required': ['id', 'title'],
                },
                'indexes': [],
              },
            ],
          },
          {
            'main.js': r'''
import {ui} from '@xudian/sdk';
export async function review(input) {
  return input.legacy ? ui.review(input.planId) : ui.review(input.planId, input.confirmation);
}
''',
          },
        ),
        allowUnsignedLocal: true,
      );
      await host.install(package);
      actor = host.instances['test.confirmation']!.actor;
    });
    tearDown(() async {
      await host.close();
      await store.close();
      await db.close();
      await directory.delete(recursive: true);
    });
    Future<ChangePlan> plan(String title) async {
      final snapshot = SnapshotSession(actor, 'review-${serial++}')
        ..result = {'title': title};
      await store.stage(snapshot, actor, {
        'writes': [
          {
            'collection': 'notes',
            'id': 'a',
            'value': {'id': 'a', 'title': title},
          },
        ],
      });
      return store.seal(snapshot);
    }

    test(
      'canceling compact review never authorizes or commits its frozen plan',
      () async {
        final frozen = await plan('取消保持原样');
        Map<String, Object?>? shown;
        host.interaction = (_, method, args) async {
          expect(method, 'ui.review');
          shown = args;
          return false;
        };
        expect(
          await host.invokePage(actor.moduleId, 'review', {
            'planId': frozen.id,
            'confirmation': _options,
          }),
          isFalse,
        );
        expect(shown!['writes'], frozen.writes);
        expect(shown!['result'], frozen.result);
        expect(shown!['confirmation'], _options);
        expect(frozen.content.containsKey('confirmation'), isFalse);
        await expectLater(
          host.commit(actor, frozen.id),
          throwsA(
            predicate(
              (error) => error.toString().contains('Host review required'),
            ),
          ),
        );
        expect(await store.get(actor, 'notes', 'a'), isNull);
      },
    );

    test('acceptance reviews exactly the frozen write set and retains stale-plan rejection', () async {
      final frozen = await plan('冻结原安排');
      final originalContent = frozen.content;
      host.interaction = (_, method, args) async {
        expect(args['writes'], same(frozen.writes));
        expect(args['result'], same(frozen.result));
        expect(() => (args['writes'] as List).clear(), throwsUnsupportedError);
        return true;
      };
      expect(
        await host.invokePage(actor.moduleId, 'review', {
          'planId': frozen.id,
          'confirmation': _options,
        }),
        isTrue,
      );
      expect(frozen.content, same(originalContent));
      final newer = await plan('另一操作写入');
      host.review(newer.id, actor);
      await host.commit(actor, newer.id);
      await expectLater(host.commit(actor, frozen.id), throwsStateError);
      expect(object(await store.get(actor, 'notes', 'a'))['title'], '另一操作写入');
    });

    test('legacy SDK call has unchanged payload while malformed confirmation never reaches interaction', () async {
      final frozen = await plan('兼容旧调用');
      var interactions = 0;
      host.interaction = (_, method, args) async {
        interactions++;
        expect(args.keys.toSet(), {'planId', 'writes', 'result'});
        return true;
      };
      for (final invalid in [
        null,
        {..._options, 'writes': []},
        {..._options, 'confirmLabel': ''},
      ]) {
        await expectLater(
          host.invokePage(actor.moduleId, 'review', {
            'planId': frozen.id,
            'confirmation': invalid,
          }),
          throwsA(
            predicate(
              (error) => error.toString().contains('Invalid plan confirmation'),
            ),
          ),
        );
      }
      expect(interactions, 0);
      expect(
        await host.invokePage(actor.moduleId, 'review', {
          'planId': frozen.id,
          'legacy': true,
        }),
        isTrue,
      );
      expect(interactions, 1);
      expect(await host.commit(actor, frozen.id), frozen.result);
      expect(object(await store.get(actor, 'notes', 'a'))['title'], '兼容旧调用');
    });
  });
}
