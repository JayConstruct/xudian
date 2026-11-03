import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/collection_store.dart';
import 'package:task_app/core/module_host/module_host.dart';
import 'package:task_app/core/module_host/module_package.dart';
import 'package:task_app/core/module_host/script_page.dart';
import 'package:task_app/core/ui/script_content_widgets.dart';
import 'package:task_app/core/ui/ui_design.dart';
import 'package:task_app/data/app_database.dart';

void main() {
  late AppDatabase db;
  late CollectionStore store;
  late ModuleHost host;
  late Directory folder;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    store = CollectionStore(db);
    folder = await Directory.systemTemp.createTemp('script-content-');
    host = ModuleHost(store: store, directory: folder);
    await host.initialize();
    final bytes = await ScriptPackage.build(
      {
        'formatVersion': 3,
        'manifest': {
          'id': 'test.content',
          'version': '1.0.0',
          'hostApi': '^1.45.0',
          'dataVersion': 1,
          'permissions': ['ui'],
          'dependencies': [],
        },
        'entryPoint': 'main.js',
        'pages': [],
        'services': [],
        'collections': [],
      },
      {
        'main.js': r'''
export async function render({state={},event,formValues={},context={}}) {
  state={...state};
  if(event) state.last=event.type;
  if(event?.type==='tab') state.tab=event.index;
  const text=(text,extra={})=>({type:'text',text,...extra});
  const column=children=>({type:'column',spacing:4,trailingSpacing:false,children});
  if(context.longRows) {
    const longTitle='长'.repeat(300);
    const line=(value,extra={})=>text(value,{maxLines:1,overflow:'ellipsis',...extra});
    const instance=(title,key)=>({type:'card',key,variant:'outlined',padding:12,event:{type:'open'},children:[
      {type:'row',layout:'flex',spacing:8,children:[
        {...column([line('11/03'),line('周二',{style:'caption'})]),width:65},
        {...column([line(title,{key:key+'-title',weight:'semibold'}),line('20:00–20:30',{style:'caption'})]),flex:1},
        {...column([line('第10次',{style:'caption'}),{type:'badge',text:'已调整',tone:'muted'}]),width:60},
        {type:'icon',icon:'right',size:18,tone:'muted'}
      ]}
    ]});
    return {state,tree:{type:'column',spacing:12,children:[instance('阅读','short-row'),instance(longTitle,'long-row')]}};
  }
  return {state,tree:{type:'column',spacing:12,footerStyle:'flat',children:[
    {type:'input',key:'search',text:'搜索条目',presentation:'search',inputMode:'search',clearable:true,onChangeEvent:{type:'search'}},
    {type:'tabs',variant:'pills',scrollable:true,selectedIndex:state.tab||0,items:[
      {label:'全部 4',event:{type:'tab',index:0}},
      {label:'待处理 3',event:{type:'tab',index:1}},
      {label:'已暂停 1',event:{type:'tab',index:2}},
      {label:'已结束 0',event:{type:'tab',index:3}}
    ]},
    {type:'card',key:'content-card',variant:'outlined',padding:14,event:{type:'open'},children:[
      {type:'row',layout:'flex',crossAxisAlignment:'start',children:[
        {type:'icon',icon:'book',size:22,surface:true,surfaceSize:40,tone:'success'},
        {...column([
          {type:'row',spacing:8,children:[text('阅读与整理较长的资料标题',{style:'heading',weight:'bold'}),{type:'badge',text:'进行中',tone:'success'}]},
          text('每2～3天 · 30分钟',{style:'caption'}),
          {type:'badge',text:'2次未能安排 · 查看原因',tone:'warning',icon:'warning'}
        ]),flex:1},
        {type:'icon',icon:'right',tone:'muted'}
      ]}
    ]},
    {type:'card',variant:'outlined',padding:12,children:[
      {type:'row',layout:'flex',crossAxisAlignment:'start',children:[
        {...column([text('11/03'),text('周二',{style:'caption'})]),width:70},
        {...column([text('阅读论文'),text('20:00–20:30',{style:'caption'})]),flex:1},
        {...column([text('第10次',{style:'caption'}),{type:'badge',text:'已调整',tone:'muted'}]),width:64}
      ]}
    ]},
    {type:'tabs',variant:'underline',selectedIndex:state.tab||0,items:[{label:'待执行 10',event:{type:'tab',index:0}},{label:'已完成 6',event:{type:'tab',index:1}},{label:'已取消 0',event:{type:'tab',index:2}}]},
    ...Array.from({length:20},(_,i)=>text('条目 '+i)),
    text('操作：'+(state.last||'')),text('搜索值：'+(formValues.search||''))
  ],footerMessage:text('操作说明在底部持续可见',{style:'caption',align:'center'}),footer:{type:'row',layout:'flex',children:[
    {type:'button',key:'secondary',flex:1,text:'暂停生成',variant:'outlined',event:{type:'pause'}},
    {type:'button',key:'primary',flex:1,text:'编辑规则',variant:'filled',icon:'edit',event:{type:'edit'}}
  ]}}};
}
''',
      },
    );
    await host.install(
      await ScriptPackage.verify(bytes, allowUnsignedLocal: true),
    );
  });

  tearDown(() async {
    await host.close();
    await store.close();
    await db.close();
    await folder.delete(recursive: true);
  });

  Finder bodyScroll() => find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.down,
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> mount(
    WidgetTester tester, {
    double width = 390,
    TextScaler scaler = TextScaler.noScaling,
    Brightness brightness = Brightness.light,
    Map<String, Object?> pageContext = const {},
  }) async {
    tester.view.physicalSize = Size(width, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppDesign.theme(brightness),
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 850), textScaler: scaler),
          child: Scaffold(
            body: ScriptPage(
              host: host,
              moduleId: 'test.content',
              handler: 'render',
              pageContext: pageContext,
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('script cards navigate and filters expose selected semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await mount(tester);
    expect(find.byType(ScriptGlyph), findsNWidgets(2));
    expect(tester.getSize(find.byType(ScriptGlyph).first), const Size(40, 40));
    final selected = tester.getSemantics(find.text('全部 4'));
    expect(selected.flagsCollection.isSelected, Tristate.isTrue);
    await tester.tap(find.text('待处理 3'));
    await settle(tester);
    expect(
      tester.getSemantics(find.text('待处理 3')).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    await tester.tap(find.text('阅读与整理较长的资料标题'));
    await settle(tester);
    await tester.scrollUntilVisible(
      find.text('操作：open'),
      300,
      scrollable: bodyScroll(),
    );
    expect(find.text('操作：open'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets(
    'flat footer buttons remain equal width and fixed during scroll',
    (tester) async {
      await mount(tester);
      final first = find.byType(OutlinedButton).first;
      final second = find.byType(FilledButton).first;
      final top = tester.getTopLeft(second).dy;
      expect(
        tester.getSize(first).width,
        closeTo(tester.getSize(second).width, .1),
      );
      expect(tester.getSize(second).height, greaterThanOrEqualTo(48));
      await tester.scrollUntilVisible(
        find.text('条目 19'),
        300,
        scrollable: bodyScroll(),
      );
      expect(tester.getTopLeft(second).dy, top);
      expect(find.text('操作说明在底部持续可见'), findsOneWidget);
      await tester.tap(find.text('编辑规则'));
      await settle(tester);
      expect(find.text('操作：edit'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow dark layout wraps content at twice the normal text size',
    (tester) async {
      await mount(
        tester,
        width: 320,
        scaler: const TextScaler.linear(2),
        brightness: Brightness.dark,
      );
      expect(find.text('进行中'), findsOneWidget);
      expect(find.text('2次未能安排 · 查看原因'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('11/03'),
        180,
        scrollable: bodyScroll(),
      );
      expect(find.text('11/03'), findsOneWidget);
      expect(find.text('已调整'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('search hint remains compact and clear restores the query', (
    tester,
  ) async {
    await mount(tester);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration!.labelText, isNull);
    expect(field.decoration!.hintText, '搜索条目');
    await tester.enterText(find.byType(TextField), '论文');
    await tester.pump(const Duration(milliseconds: 450));
    await settle(tester);
    expect(find.byTooltip('清除搜索条目'), findsOneWidget);
    await tester.tap(find.byTooltip('清除搜索条目'));
    await tester.pump(const Duration(milliseconds: 450));
    await settle(tester);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '300-character titles keep instance rows bounded and accessible',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final longTitle = List.filled(300, '长').join();
      for (final layout in [
        (width: 390.0, scaler: TextScaler.noScaling),
        (width: 320.0, scaler: const TextScaler.linear(2)),
      ]) {
        await mount(
          tester,
          width: layout.width,
          scaler: layout.scaler,
          pageContext: const {'longRows': true},
        );
      final shortRow = find.byKey(const ValueKey('short-row')).first;
      final longRow = find.byKey(const ValueKey('long-row')).first;
        final title = find.text(longTitle);
        expect(tester.getSize(title).width, greaterThan(50));
        expect(
          tester.getSize(longRow).height,
          closeTo(tester.getSize(shortRow).height, .1),
        );
      expect(tester.getSize(longRow).height, lessThan(200));
        expect(tester.widget<Text>(title).maxLines, 1);
        expect(tester.widget<Text>(title).overflow, TextOverflow.ellipsis);
      expect(tester.getSemantics(title).label, contains(longTitle));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
      semantics.dispose();
    },
  );
}
