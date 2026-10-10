import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/host_providers.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/script_app_module.dart';
import 'package:task_app/core/modules/module_registry.dart';
import 'package:task_app/core/security/capability_registry.dart';
import 'package:task_app/core/ui/module_detail_page.dart';
import 'package:task_app/core/ui/ui_page_host.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/data/providers.dart';

import 'module_host_test.dart' as fixtures;

Future<void> _settleNative(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 25));
  }
}

void main() {
  for (final systemBack in [false, true]) {
    testWidgets(
      '320px large text importer uses ${systemBack ? 'Android system' : 'AppBar'} back through internal history before exiting settings',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 720));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        late AppDatabase db;
        late CollectionStore store;
        late ModuleHost host;
        late ModuleRegistry registry;
        late Directory directory;
        late StreamSubscription<void> registrySubscription;
        late List<Map<String, Object?>> originalRecords;
        await tester.runAsync(() async {
          db = AppDatabase(NativeDatabase.memory());
          store = CollectionStore(db);
          directory = await Directory.systemTemp.createTemp(
            'shiguang-school-picker-',
          );
          host = ModuleHost(store: store, directory: directory);
          await host.initialize();
          for (final id in ['app.schedule', 'app.import.shiguang']) {
            await host.install(
              await ScriptPackage.verify(
                await File('../dist/modules/$id.xmodule').readAsBytes(),
                allowUnsignedLocal: true,
              ),
            );
          }
          final actor = host.instances['app.schedule']!.actor;
          Future<void> save(String service, Map<String, Object?> args) async {
            final plan = await host.prepare(
              actor,
              fixtures.schedule(service),
              args,
            );
            host.review(plan.id, actor);
            await host.commit(actor, plan.id);
          }

          await save('schedule.timetable.save', {
            'timetable': fixtures.timetable(),
          });
          await save('schedule.course.save', {
            'course': {
              'id': 'existing-course',
              'timetableId': 't',
              'name': '保留课程',
            },
            'meeting': {
              'id': 'existing-meeting',
              'weekday': 1,
              'startPeriod': 1,
              'endPeriod': 2,
              'weeks': [1, 3],
            },
          });
          originalRecords = await store.sql(
            'SELECT * FROM host_records ORDER BY module_id,space,collection,id',
          );
          registry = ModuleRegistry(
            [
              for (final instance in host.instances.values)
                ScriptAppModule(host, instance.package),
            ],
            capabilities: CapabilityRegistry(['ui.registry', 'ui.composition']),
          );
          registrySubscription = host.registryChanges.stream.listen((_) {
            registry.replaceExtensions([
              for (final instance in host.instances.values)
                ScriptAppModule(host, instance.package),
            ]);
          });
        });
        addTearDown(() async {
          await registrySubscription.cancel();
          registry.dispose();
          await host.close();
          await store.close();
          await db.close();
          await directory.delete(recursive: true);
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWith((_) async => db),
              moduleHostProvider.overrideWith((_) async => host),
            ],
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!,
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  appBar: AppBar(title: const Text('设置')),
                  body: FilledButton(
                    onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ModuleDetailPage(
                          registry: registry,
                          pageId: 'app.import.shiguang.home',
                          title: '临时模块名称',
                        ),
                      ),
                    ),
                    child: const Text('打开拾光导入'),
                  ),
                ),
              ),
            ),
          ),
        );
        final firstRender = Completer<void>();
        host.instances['app.import.shiguang']!.workflowTail =
            firstRender.future;
        await tester.tap(find.text('打开拾光导入'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          find.text('临时模块名称', skipOffstage: false),
          findsNothing,
          reason: 'A delegated detail header must wait for its module title',
        );
        expect(find.byType(BackButton), findsOneWidget);
        firstRender.complete();
        await _settleNative(tester);
        Finder field(String label) => find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == label,
        );
        Future<void> tap(String label) async {
          await tester.ensureVisible(find.text(label));
          await tester.tap(find.text(label));
          await _settleNative(tester);
          expect(tester.takeException(), isNull);
        }

        void expectTitle(String title) {
          expect(
            find.descendant(
              of: find.byType(AppBar),
              matching: find.text(title),
            ),
            findsOneWidget,
          );
          expect(
            find.text(title),
            findsOneWidget,
            reason: 'The current page title belongs only in the AppBar',
          );
          expect(find.byType(BackButton), findsOneWidget);
          expect(
            find.textContaining(RegExp(r'^返回(导入首页|学校列表|通用系统)$')),
            findsNothing,
          );
          expect(find.byType(ModuleDetailPage), findsOneWidget);
          expect(find.byType(UiPageHost), findsOneWidget);
          expect(tester.takeException(), isNull);
        }

        Future<void> back() async {
          if (systemBack) {
            await tester.binding.handlePopRoute();
          } else {
            await tester.tap(find.byType(BackButton));
          }
          await _settleNative(tester);
          expect(tester.takeException(), isNull);
        }

        expectTitle('拾光教务导入');
        expect(find.byType(TextField), findsNothing);
        for (final label in [
          '按学校导入',
          '通用系统导入',
          '粘贴学校脚本',
          '导入拾光 JSON 文件',
          '关于与致谢',
        ]) {
          expect(find.widgetWithText(ListTile, label), findsOneWidget);
        }
        await tap('按学校导入');
        expectTitle('选择学校');
        final search = field('搜索学校名称或缩写');
        await tester.ensureVisible(search);
        await tester.enterText(search, 'AUFE WebVPN');
        await _settleNative(tester);
        expect(find.text('找到 1 所学校 · 第 1/1 页'), findsOneWidget);
        expect(find.textContaining('进入教务系统后点击开始导入'), findsNothing);
        await tap('安徽财经大学');
        expectTitle('安徽财经大学');
        expect(
          tester.widget<TextField>(field('教务登录网址')).controller!.text,
          'http://vpn.aufe.edu.cn',
        );
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is SelectableText &&
                widget.data?.contains('resources/AUFE/aufe_01.js') == true,
          ),
          findsOneWidget,
        );
        await tap('安徽财经大学校内入口');
        expectTitle('安徽财经大学');
        expect(
          tester.widget<TextField>(field('教务登录网址')).controller!.text,
          'http://all.aufe.edu.cn',
        );
        await tap('关于与致谢');
        expectTitle('关于与致谢');
        expect(find.text('致谢'), findsOneWidget);
        for (final url in [
          'https://github.com/ShiGuangSchedule/shiguang_warehouse',
          'https://github.com/ShiGuangSchedule/shiguangschedule',
        ]) {
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is SelectableText &&
                  widget.data?.contains(url) == true,
            ),
            findsOneWidget,
          );
        }
        final license = find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              widget.data?.contains('Permission is hereby granted') == true,
        );
        expect(license, findsOneWidget);
        await tester.ensureVisible(license);
        await _settleNative(tester);
        expect(tester.takeException(), isNull);
        await back();
        expectTitle('安徽财经大学');
        expect(
          tester.widget<TextField>(field('教务登录网址')).controller!.text,
          'http://all.aufe.edu.cn',
        );
        await back();
        expectTitle('选择学校');
        expect(
          tester.widget<TextField>(search).controller!.text,
          'AUFE WebVPN',
        );
        await tester.ensureVisible(search);
        await tester.enterText(search, 'school-does-not-exist-xyz');
        await _settleNative(tester);
        expect(find.text('没有找到学校'), findsOneWidget);
        await tap('尝试通用系统导入');
        expectTitle('通用系统导入');
        expect(find.byType(ListTile), findsNWidgets(4));
        await back();
        expectTitle('选择学校');
        expect(
          tester.widget<TextField>(search).controller!.text,
          'school-does-not-exist-xyz',
        );
        expect(find.text('没有找到学校'), findsOneWidget);
        await back();
        expectTitle('拾光教务导入');
        await back();
        expect(find.byType(ModuleDetailPage), findsNothing);
        expect(find.text('设置'), findsOneWidget);
        expect(find.text('打开拾光导入'), findsOneWidget);
        expect(
          await tester.runAsync(
            () => store.sql(
              'SELECT * FROM host_records ORDER BY module_id,space,collection,id',
            ),
          ),
          originalRecords,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
