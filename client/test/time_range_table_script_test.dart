import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/script_page.dart';
import 'package:task_app/core/ui/time_range_table.dart';
import 'package:task_app/data/app_database.dart';

class _CountingModuleHost extends ModuleHost {
  _CountingModuleHost({required super.store, required super.directory});

  int pageInvocations = 0;
  Object? submittedDraft;

  @override
  Future<Object?> invokePage(
    String moduleId,
    String handler,
    Object? input, {
    void Function(Set<String>)? onReads,
    void Function(bool)? onReplayable,
    bool readOnly = false,
    bool Function()? shouldRun,
    PagePlanReview? onReview,
    InlinePagePlanReview? onInlineReview,
    bool Function()? commandIsCurrent,
    void Function(ChangePlan)? onCommit,
  }) {
    pageInvocations++;
    if (input is Map &&
        input['event'] is Map &&
        (input['event'] as Map)['type'] == 'save') {
      submittedDraft = object(input['formValues'])['periods.table.test'];
    }
    return super.invokePage(
      moduleId,
      handler,
      input,
      onReads: onReads,
      onReplayable: onReplayable,
      readOnly: readOnly,
      shouldRun: shouldRun,
      onReview: onReview,
      onInlineReview: onInlineReview,
      commandIsCurrent: commandIsCurrent,
      onCommit: onCommit,
    );
  }
}

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late _CountingModuleHost host;
  late Directory directory;
  const moduleId = 'test.time_ranges';
  const formKey = 'periods.table.test';
  const pageContext = {'pageId': 'test.time_ranges.home'};

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    directory = await Directory.systemTemp.createTemp('time-range-script-');
    host = _CountingModuleHost(store: store, directory: directory);
    await host.initialize();
    await host.install(
      await ScriptPackage.verify(
        await ScriptPackage.build(
          {
            'formatVersion': 3,
            'manifest': {
              'id': moduleId,
              'version': '1.0.0',
              'hostApi': '^1.34.0',
              'dataVersion': 1,
              'permissions': ['ui'],
            },
            'entryPoint': 'main.js',
            'collections': [],
            'pages': [],
            'services': [],
          },
          {
            'main.js': r'''
const key='periods.table.test';
const baseline={durationMinutes:'45',rows:Array.from({length:12},(_,i)=>({
  id:String(i+1),label:`第 ${i+1} 节`,
  start:`${String(8+i).padStart(2,'0')}:00`,
  end:`${String(8+i).padStart(2,'0')}:45`,manualEnd:false,
}))};
export function render({state={},formValues={},event}={}) {
  const value=formValues[key]||{...baseline,dirty:false,resetDisabled:true,saveDisabled:true,error:null};
  return {state,replaceForms:{[key]:value},tree:{type:'column',children:[
    ...Array.from({length:5},(_,i)=>({type:'text',text:`本地编辑说明 ${i+1}`})),
    {type:'timeRangeTable',key,value,baseline},
  ],footer:{type:'row',children:[
    {type:'button',text:'保存作息设置',event:{type:'save'},disabled:{bind:['formValues',key,'saveDisabled']}},
  ]}}};
}
''',
          },
        ),
        allowUnsignedLocal: true,
      ),
    );
  });

  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump(const Duration(milliseconds: 25));
    }
  }

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScriptPage(
            host: host,
            moduleId: moduleId,
            handler: 'render',
            pageContext: pageContext,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Finder getDuration() => find.byKey(const ValueKey('time-range-duration'));
  Finder getSave() => find.widgetWithText(FilledButton, '保存作息设置');
  Finder getPageScroll() => find
      .descendant(
        of: find.byType(ScriptPage),
        matching: find.byType(SingleChildScrollView),
      )
      .first;

  void expectInteractive(WidgetTester tester) {
    expect(
      tester.widget<TimeRangeTable>(find.byType(TimeRangeTable)).enabled,
      true,
    );
    expect(tester.widget<TextField>(getDuration()).enabled, true);
    expect(
      find.descendant(
        of: find.byType(ScriptPage),
        matching: find.byType(LinearProgressIndicator),
      ),
      findsNothing,
    );
  }

  testWidgets(
    'duration edits stay local, preserve focus and scroll, and update save binding',
    (tester) async {
      await show(tester);
      expect(host.pageInvocations, 1);
      expect(tester.widget<FilledButton>(getSave()).onPressed, isNull);
      final tableState = tester.state(find.byType(TimeRangeTable));
      final durationController = tester
          .widget<TextField>(getDuration())
          .controller;
      await tester.showKeyboard(getDuration());
      await tester.pumpAndSettle();
      final editable = find.descendant(
        of: getDuration(),
        matching: find.byType(EditableText),
      );
      final focus = tester.widget<EditableText>(editable).focusNode;
      final scroll = tester
          .widget<SingleChildScrollView>(getPageScroll())
          .controller!;
      scroll.jumpTo(70);
      await tester.pump();
      final offset = scroll.offset;

      for (final value in ['6', '60', '', '45', '55']) {
        await tester.enterText(getDuration(), value);
        await tester.pump();
        expectInteractive(tester);
        expect(focus.hasFocus, true);
        expect(
          tester.widget<TextField>(getDuration()).controller,
          same(durationController),
        );
        expect(tester.state(find.byType(TimeRangeTable)), same(tableState));
        expect(scroll.offset, closeTo(offset, .1));
        expect(
          tester.widget<FilledButton>(getSave()).onPressed != null,
          value.isNotEmpty && value != '45',
        );
      }
      await tester.pump(const Duration(milliseconds: 500));
      expectInteractive(tester);
      expect(
        host.pageInvocations,
        1,
        reason: 'Neither native keystrokes nor their debounce window invoke the module renderer',
      );
      await tester.tap(getSave());
      await settle(tester);
      final result = {
        'renders': host.pageInvocations,
        'saved': host.submittedDraft,
      };
      expect(result['renders'], 2);
      expect(object(result['saved'])['durationMinutes'], '55');
      expect(object(result['saved'])['dirty'], true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'wheel edits stay local and the full draft survives page disposal and reopening',
    (tester) async {
      await show(tester);
      final tableState = tester.state(find.byType(TimeRangeTable));
      final cell = find.byKey(const ValueKey('time-range-1-start'));
      await tester.ensureVisible(cell);
      final scroll = tester
          .widget<SingleChildScrollView>(getPageScroll())
          .controller!;
      final offset = scroll.offset;
      await tester.tap(cell);
      await tester.pumpAndSettle();
      final wheels = find.byType(CupertinoPicker);
      expect(wheels, findsNWidgets(2));
      tester
          .widget<CupertinoPicker>(wheels.at(0))
          .scrollController!
          .jumpToItem(8);
      tester
          .widget<CupertinoPicker>(wheels.at(1))
          .scrollController!
          .jumpToItem(10);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expectInteractive(tester);
      expect(tester.state(find.byType(TimeRangeTable)), same(tableState));
      expect(scroll.offset, closeTo(offset, .1));
      expect(find.text('08:10'), findsOneWidget);
      expect(find.text('08:55'), findsOneWidget);
      expect(tester.widget<FilledButton>(getSave()).onPressed, isNotNull);
      expect(host.pageInvocations, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      final session = object(host.pageSessions.values.single);
      final draft = object(object(session['formValues'])[formKey]);
      expect(draft['dirty'], true);
      expect(object((draft['rows'] as List).first)['start'], '08:10');
      await show(tester);
      expect(
        host.pageInvocations,
        2,
        reason: 'Reopening invokes one renderer with the saved form draft',
      );
      expect(find.text('08:10'), findsOneWidget);
      expect(find.text('08:55'), findsOneWidget);
      expect(tester.widget<FilledButton>(getSave()).onPressed, isNotNull);
      expectInteractive(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
