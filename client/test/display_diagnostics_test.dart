import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/ui/ui_design.dart';
import 'package:task_app/features/settings/display_diagnostics_page.dart';
import 'package:task_app/features/settings/settings_tools_page.dart';

class _NonlinearTextScaler extends TextScaler {
  const _NonlinearTextScaler();
  @override
  double scale(double fontSize) =>
      fontSize <= 14 ? fontSize * 2.5 : fontSize * 1.5;
  @override
  double get textScaleFactor => 2.5;
}

class _SecondaryView extends TestFlutterView {
  _SecondaryView(TestFlutterView original, this.viewId)
    : super(
        view: original,
        platformDispatcher: original.platformDispatcher,
        display: TestDisplay(original.platformDispatcher, original.display),
      );
  @override
  final int viewId;
  @override
  void render(ui.Scene scene, {Size? size}) {}
  @override
  void updateSemantics(ui.SemanticsUpdate update) {}
}

Widget _app({
  Widget home = const DisplayDiagnosticsPage(),
  MediaQueryData? media,
}) => MaterialApp(
  theme: AppDesign.theme(Brightness.light),
  builder: media == null
      ? null
      : (_, child) => MediaQuery(data: media, child: child!),
  home: home,
);

void _size(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

class _ClipboardCapture {
  _ClipboardCapture() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copies.add(
              jsonDecode((call.arguments as Map)['text'] as String)
                  as Map<String, dynamic>,
            );
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
  }
  final copies = <Map<String, dynamic>>[];
  Future<Map<String, dynamic>> copy(WidgetTester tester) async {
    final notice = find.byTooltip('关闭提示');
    if (notice.evaluate().isNotEmpty) {
      await tester.tap(notice);
      await tester.pumpAndSettle();
    }
    final button = find.widgetWithText(FilledButton, '复制诊断 JSON');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    return copies.last;
  }
}

void main() {
  testWidgets(
    'diagnostic JSON contains only explicit measurements and privacy values',
    (tester) async {
      _size(tester, const Size(320, 700));
      final media = const MediaQueryData(
        size: Size(320, 700),
        textScaler: _NonlinearTextScaler(),
        padding: EdgeInsets.fromLTRB(10, 24, 20, 8),
        viewPadding: EdgeInsets.fromLTRB(10, 24, 20, 16),
        viewInsets: EdgeInsets.only(bottom: 180),
      );
      final snapshot = DisplayDiagnostics.capture(
        view: tester.view,
        media: media,
        availableWidth: 290,
        contentWidth: 258,
      );
      final data = jsonDecode(snapshot.json) as Map<String, dynamic>;
      expect(data.keys.toSet(), {
        'schemaVersion',
        'source',
        'platformView',
        'mediaQuery',
        'layout',
        'privacy',
      });
      expect(data['schemaVersion'], 1);
      expect(data['source'], 'currentFlutterViewAndMediaQuery');
      expect(data['platformView'], {
        'physicalSizePx': {'width': 320.0, 'height': 700.0},
        'devicePixelRatio': 1.0,
        'logicalSizeFromView': {'width': 320.0, 'height': 700.0},
        'hardwarePanelResolution': 'notMeasured',
      });
      expect(data['mediaQuery'], {
        'logicalViewportSize': {'width': 320.0, 'height': 700.0},
        'padding': {'left': 10.0, 'top': 24.0, 'right': 20.0, 'bottom': 8.0},
        'viewPadding': {
          'left': 10.0,
          'top': 24.0,
          'right': 20.0,
          'bottom': 16.0,
        },
        'keyboardAndOtherViewInsets': {
          'left': 0.0,
          'top': 0.0,
          'right': 0.0,
          'bottom': 180.0,
        },
        'textScalerSamples': {'12': 30.0, '14': 35.0, '24': 36.0},
      });
      expect(data['layout'], {
        'availableWidthLogicalPx': 290.0,
        'contentWidthLogicalPx': 258.0,
      });
      expect(data['privacy'], {
        'dataScope': 'displayMetricsOnly',
        'transfer': 'manualClipboardOnly',
      });
    },
  );

  testWidgets(
    'narrow large-text tools entry opens a read-only scrollable page',
    (tester) async {
      _size(tester, const Size(320, 700));
      await tester.pumpWidget(
        ProviderScope(
          child: _app(
            media: const MediaQueryData(
              size: Size(320, 700),
              textScaler: TextScaler.linear(2),
            ),
            home: const SettingsToolsPage(),
          ),
        ),
      );
      await tester.tap(find.text('显示与布局信息'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, '复制诊断 JSON').hitTestable(),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.textContaining('不假设缩放比例恒定'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, '界面标注模式'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'nonlinear scaler remains intact and samples stay reachable on narrow screens',
    (tester) async {
      _size(tester, const Size(320, 700));
      await tester.pumpWidget(
        _app(
          media: const MediaQueryData(
            size: Size(320, 700),
            textScaler: _NonlinearTextScaler(),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('24 → 36.00'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('24 → 36.00').hitTestable(), findsOneWidget);
      final context = tester.element(find.text('24 → 36.00'));
      expect(MediaQuery.textScalerOf(context).scale(12), 30);
      expect(MediaQuery.textScalerOf(context).scale(24), 36);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'copy is user initiated and platform metrics refresh with fixed MediaQuery',
    (tester) async {
      _size(tester, const Size(320, 700));
      final clipboard = _ClipboardCapture();
      await tester.pumpWidget(
        _app(media: const MediaQueryData(size: Size(320, 700))),
      );
      expect(clipboard.copies, isEmpty);
      final initial = await clipboard.copy(tester);
      expect(initial['platformView']['physicalSizePx']['width'], 320.0);
      expect(find.text('显示诊断信息已复制'), findsOneWidget);
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 2;
      await tester.pumpAndSettle();
      expect(clipboard.copies.length, 1);
      final updated = await clipboard.copy(tester);
      expect(updated['platformView']['physicalSizePx'], {
        'width': 800.0,
        'height': 1200.0,
      });
      expect(updated['platformView']['devicePixelRatio'], 2.0);
      expect(updated['mediaQuery']['logicalViewportSize'], {
        'width': 320.0,
        'height': 700.0,
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('diagnostics follow their own FlutterView in a multi-view tree', (
    tester,
  ) async {
    _size(tester, const Size(900, 1000));
    final secondary = _SecondaryView(tester.view, 101)
      ..devicePixelRatio = 2
      ..physicalSize = const Size(640, 1400);
    final clipboard = _ClipboardCapture();
    await tester.pumpWidget(
      ViewCollection(
        views: [
          View(view: tester.view, child: const SizedBox.shrink()),
          View(view: secondary, child: _app()),
        ],
      ),
      wrapWithView: false,
    );
    final initial = await clipboard.copy(tester);
    expect(initial['platformView']['physicalSizePx'], {
      'width': 640.0,
      'height': 1400.0,
    });
    expect(initial['platformView']['devicePixelRatio'], 2.0);
    expect(initial['mediaQuery']['logicalViewportSize'], {
      'width': 320.0,
      'height': 700.0,
    });
    secondary.physicalSize = const Size(760, 1500);
    await tester.pumpAndSettle();
    final updated = await clipboard.copy(tester);
    expect(updated['platformView']['physicalSizePx']['width'], 760.0);
    expect(updated['mediaQuery']['logicalViewportSize']['width'], 380.0);
    expect(tester.view.physicalSize.width, 900.0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'safe-area and keyboard changes retain original MediaQuery metrics',
    (tester) async {
      _size(tester, const Size(400, 900));
      final clipboard = _ClipboardCapture();
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetViewInsets);
      tester.view.padding = const FakeViewPadding(
        left: 10,
        top: 24,
        right: 20,
        bottom: 16,
      );
      tester.view.viewPadding = const FakeViewPadding(
        left: 10,
        top: 24,
        right: 20,
        bottom: 16,
      );
      await tester.pumpWidget(_app());
      final initial = await clipboard.copy(tester);
      expect(initial['mediaQuery']['padding']['top'], 24.0);
      expect(initial['layout']['availableWidthLogicalPx'], 370.0);
      expect(initial['layout']['contentWidthLogicalPx'], 338.0);
      tester.view.padding = const FakeViewPadding(left: 10, top: 24, right: 20);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      final updated = await clipboard.copy(tester);
      expect(updated['mediaQuery']['padding']['bottom'], 0.0);
      expect(updated['mediaQuery']['viewPadding']['bottom'], 16.0);
      expect(
        updated['mediaQuery']['keyboardAndOtherViewInsets']['bottom'],
        300.0,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
