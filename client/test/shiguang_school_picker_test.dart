import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/script_page.dart';
import 'package:task_app/data/app_database.dart';

Future<void> _settleNative(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 25));
  }
}

void main() {
  testWidgets(
    '320px large-text import categories, school details, generic fallback and selectable attribution fit without overflow',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      late AppDatabase db;
      late CollectionStore store;
      late ModuleHost host;
      late Directory directory;
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
      });
      addTearDown(() async {
        await host.close();
        await store.close();
        await db.close();
        await directory.delete(recursive: true);
      });
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: ScriptPage(
              host: host,
              moduleId: 'app.import.shiguang',
              handler: 'render',
            ),
          ),
        ),
      );
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
      expect(tester.takeException(), isNull);
      final search = field('搜索学校名称或缩写');
      await tester.ensureVisible(search);
      await tester.enterText(search, 'AUFE WebVPN');
      await _settleNative(tester);
      expect(find.text('找到 1 所学校 · 第 1/1 页'), findsOneWidget);
      expect(find.textContaining('进入教务系统后点击开始导入'), findsNothing);
      final choice = find.text('安徽财经大学');
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await _settleNative(tester);
      final url = tester.widget<TextField>(field('教务登录网址'));
      expect(url.controller!.text, 'http://vpn.aufe.edu.cn');
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              widget.data?.contains('resources/AUFE/aufe_01.js') == true,
        ),
        findsOneWidget,
      );
      await tap('安徽财经大学校内入口');
      expect(
        tester.widget<TextField>(field('教务登录网址')).controller!.text,
        'http://all.aufe.edu.cn',
      );
      await tap('返回导入首页');
      await tap('按学校导入');
      await tester.ensureVisible(search);
      await tester.enterText(search, 'school-does-not-exist-xyz');
      await _settleNative(tester);
      expect(find.text('没有找到学校'), findsOneWidget);
      await tap('尝试通用系统导入');
      expect(find.byType(ListTile), findsNWidgets(4));
      await tap('返回导入首页');
      await tap('关于与致谢');
      expect(find.text('致谢'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              widget.data?.contains(
                    'https://github.com/ShiGuangSchedule/shiguang_warehouse',
                  ) ==
                  true,
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              widget.data?.contains(
                    'https://github.com/ShiGuangSchedule/shiguangschedule',
                  ) ==
                  true,
        ),
        findsOneWidget,
      );
      final license = find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            widget.data?.contains('Permission is hereby granted') == true,
      );
      expect(license, findsOneWidget);
      await tester.ensureVisible(license);
      await _settleNative(tester);
      expect(tester.takeException(), isNull);
      final actor = host.instances['app.schedule']!.actor;
      expect(
        await tester.runAsync(() => store.query(actor, 'courses', {})),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
