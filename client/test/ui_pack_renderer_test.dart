import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/module_host/host_dialogs.dart';
import 'package:task_app/core/ui/ui_component.dart';
import 'package:task_app/core/ui/ui_pack.dart';

UiPackDefinition pack(
  String id,
  Map<String, Object?> components, {
  Map<String, Object?> tokens = const {},
}) => UiPackDefinition.parse(
  moduleId: id,
  version: '1.0.0',
  digest: id,
  source: {'contractVersion': 1, 'components': components, 'tokens': tokens},
);

Map<String, Object?> text(String value) => {
  'tree': {
    'type': 'primitive',
    'name': 'text',
    'props': {'text': value},
  },
};

Widget preview(
  Map<String, UiPackDefinition> packs,
  UiSelection selection,
  Widget child, {
  String? moduleId,
  MediaQueryData media = const MediaQueryData(size: Size(800, 600)),
}) => ProviderScope(
  child: MaterialApp(
    home: MediaQuery(
      data: media,
      child: UiPackScope(
        previewPacks: packs,
        previewSelection: selection,
        moduleId: moduleId,
        child: Scaffold(body: child),
      ),
    ),
  ),
);

void main() {
  testWidgets('standalone scopes retain the default UI without providers', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: UiPackScope(
          child: UiComponent(ref: 'ui.text@1', fallback: Text('native')),
        ),
      ),
    );
    expect(find.text('native'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('conditional wrapped list slots retain a lazy bounded viewport', (
    tester,
  ) async {
    final ui = pack('test.viewport', {
      'ui.page.list@1': {
        'tree': {
          'type': 'primitive',
          'name': 'column',
          'children': [
            {
              'type': 'primitive',
              'name': 'text',
              'props': {'text': 'list header'},
            },
            {
              'type': 'responsive',
              for (final branch in ['narrow', 'wide'])
                branch: {
                  'type': 'primitive',
                  'name': 'padding',
                  'props': {'padding': 8},
                  'children': [
                    {'type': 'slot', 'name': 'items'},
                  ],
                },
            },
          ],
        },
      },
    });
    await tester.pumpWidget(
      preview(
        {'test.viewport': ui},
        UiSelection(globalPackId: 'test.viewport'),
        UiComponent(
          ref: 'ui.page.list@1',
          slots: {
            'items': ListView.builder(
              itemCount: 1000,
              itemBuilder: (_, i) =>
                  SizedBox(height: 48, child: Text('bounded record $i')),
            ),
          },
          fallback: const Text('native'),
        ),
      ),
    );
    expect(find.text('list header'), findsOneWidget);
    expect(find.text('bounded record 0'), findsOneWidget);
    expect(find.text('bounded record 999'), findsNothing);
    expect(find.byType(Text).evaluate().length, lessThan(35));
    expect(tester.takeException(), isNull);
  });

  testWidgets('form template decoration preserves host validation and fields', (
    tester,
  ) async {
    final ui = pack('test.form', {
      for (final ref in ['ui.page.form@1', 'ui.dialog@1', 'ui.input@1'])
        ref: {
          'tree': {
            'type': 'primitive',
            'name': 'card',
            'props': {'padding': 8},
            'children': [
              {'type': 'base'},
            ],
          },
        },
    });
    await tester.pumpWidget(
      preview(
        {'test.form': ui},
        UiSelection(globalPackId: 'test.form'),
        const HostFormDialog(
          title: '输入数值',
          fields: [
            {'key': 'amount', 'label': '数量', 'type': 'number'},
            {'key': 'name', 'label': '名称', 'required': true},
          ],
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'invalid');
    await tester.tap(find.text('继续'));
    await tester.pump();
    expect(find.text('请输入有效数字'), findsOneWidget);
    expect(find.text('请填写此项'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'module component overrides global while missing components use global and native',
    (tester) async {
      final global = pack('test.global', {
        'ui.text@1': text('global text'),
        'ui.tag@1': text('global tag'),
      });
      final local = pack('test.local', {'ui.text@1': text('local text')});
      await tester.pumpWidget(
        preview(
          {'test.global': global, 'test.local': local},
          UiSelection(
            globalPackId: 'test.global',
            modulePackIds: {'business': 'test.local'},
          ),
          const Column(
            children: [
              UiComponent(ref: 'ui.text@1', fallback: Text('native text')),
              UiComponent(ref: 'ui.tag@1', fallback: Text('native tag')),
              UiComponent(
                ref: 'ui.divider@1',
                fallback: Text('native divider'),
              ),
            ],
          ),
          moduleId: 'business',
        ),
      );
      expect(find.text('local text'), findsOneWidget);
      expect(find.text('global tag'), findsOneWidget);
      expect(find.text('native divider'), findsOneWidget);
      expect(find.text('global text'), findsNothing);
    },
  );

  testWidgets('custom button preserves caller event and disabled behavior', (
    tester,
  ) async {
    final ui = pack('test.buttons', {
      'ui.button@1': {
        'tree': {
          'type': 'primitive',
          'name': 'button',
          'event': 'press',
          'props': {
            'label': {
              'bind': ['props', 'label'],
            },
          },
        },
      },
    });
    final payload = Object();
    final received = <Object>[];
    for (final disabled in [false, true]) {
      await tester.pumpWidget(
        preview(
          {'test.buttons': ui},
          UiSelection(globalPackId: 'test.buttons'),
          UiComponent(
            ref: 'ui.button@1',
            props: {'label': '操作', 'disabled': disabled},
            events: {'press': (_) => received.add(payload)},
            fallback: const Text('native'),
          ),
        ),
      );
      await tester.tap(find.text('操作'));
      await tester.pump();
      expect(received, [same(payload)]);
    }
  });

  test(
    'required controls and button actions cannot be omitted from recipes',
    () {
      expect(
        () => pack('test.invalid', {'ui.input@1': text('hidden input')}),
        throwsFormatException,
      );
      expect(
        () => pack('test.invalid', {'ui.button@1': text('hidden button')}),
        throwsFormatException,
      );
      expect(
        () => pack('test.invalid', {
          'ui.chrome.bottomNav@1': {
            'tree': {'type': 'slot', 'name': 'navigation'},
          },
        }),
        throwsFormatException,
      );
    },
  );

  testWidgets('repeat with 1000 records only builds the visible viewport', (
    tester,
  ) async {
    final ui = pack('test.list', {
      'test.list.rows@1': {
        'tree': {
          'type': 'repeat',
          'items': {
            'bind': ['props', 'items'],
          },
          'child': {
            'type': 'primitive',
            'name': 'text',
            'props': {
              'text': {
                'bind': ['item', 'label'],
              },
              'height': 48,
            },
          },
        },
      },
    });
    await tester.pumpWidget(
      preview(
        {'test.list': ui},
        UiSelection(globalPackId: 'test.list'),
        SizedBox(
          height: 300,
          child: UiComponent(
            ref: 'test.list.rows@1',
            props: {
              'items': [
                for (var i = 0; i < 1000; i++) {'label': 'record $i'},
              ],
            },
            fallback: const Text('native'),
          ),
        ),
      ),
    );
    expect(find.text('record 0'), findsOneWidget);
    expect(find.byType(Text).evaluate().length, lessThan(25));
    expect(find.text('record 999'), findsNothing);
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('record 999'), findsOneWidget);
    expect(find.byType(Text).evaluate().length, lessThan(25));
  });

  testWidgets('presentation switch keeps owned input text cursor and focus', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'draft text');
    final focus = FocusNode();
    final selected = ValueNotifier(UiSelection());
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    addTearDown(selected.dispose);
    final ui = pack('test.input', {
      'ui.input@1': {
        'tree': {
          'type': 'primitive',
          'name': 'padding',
          'props': {'padding': 24},
          'children': [
            {'type': 'slot', 'name': 'control'},
          ],
        },
      },
    });
    final input = TextField(
      key: GlobalKey(),
      controller: controller,
      focusNode: focus,
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ValueListenableBuilder<UiSelection>(
            valueListenable: selected,
            builder: (_, selection, _) => UiPackScope(
              previewPacks: {'test.input': ui},
              previewSelection: selection,
              child: Scaffold(
                body: UiComponent(
                  ref: 'ui.input@1',
                  slots: {'control': input},
                  fallback: input,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    controller.selection = const TextSelection(baseOffset: 2, extentOffset: 6);
    selected.value = UiSelection(globalPackId: 'test.input');
    await tester.pump();
    expect(controller.text, 'draft text');
    expect(
      controller.selection,
      const TextSelection(baseOffset: 2, extentOffset: 6),
    );
    expect(focus.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'high contrast retains native palette and environment reflects reduced motion',
    (tester) async {
      final ui = pack(
        'test.accessible',
        {
          'ui.text@1': {
            'tree': {
              'type': 'if',
              'condition': {
                'bind': ['environment', 'reduceMotion'],
              },
              'then': {
                'type': 'primitive',
                'name': 'text',
                'props': {'text': 'motion off'},
              },
              'else': {
                'type': 'primitive',
                'name': 'text',
                'props': {'text': 'motion on'},
              },
            },
          },
        },
        tokens: {
          'light': {'primary': '#FF0000', 'canvas': '#CC0000'},
        },
      );
      late ThemeData theme;
      await tester.pumpWidget(
        preview(
          {'test.accessible': ui},
          UiSelection(globalPackId: 'test.accessible'),
          Builder(
            builder: (context) {
              theme = Theme.of(context);
              return const UiComponent(
                ref: 'ui.text@1',
                fallback: Text('native'),
              );
            },
          ),
          media: const MediaQueryData(
            size: Size(800, 600),
            highContrast: true,
            disableAnimations: true,
          ),
        ),
      );
      expect(find.text('motion off'), findsOneWidget);
      expect(
        theme.scaffoldBackgroundColor,
        ThemeData().scaffoldBackgroundColor,
      );
      expect(theme.colorScheme.primary, ThemeData().colorScheme.primary);
    },
  );
}
