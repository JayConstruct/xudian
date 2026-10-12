import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/more_workspace_page.dart';
import 'package:task_app/core/ui/ui_composition.dart';

void main() {
  testWidgets(
    'More is a scrolling workspace with tools and persistent settings',
    (tester) async {
      final entries = List.generate(
        30,
        (i) => UiEntryRegistration(
          id: 'entry-$i',
          moduleId: 'test',
          pageId: 'page-$i',
          label: '工具 $i',
          icon: Icons.apps,
        ),
      );
      UiEntryRegistration? opened;
      var settingsCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MoreWorkspacePage(
              entries: entries,
              onOpen: (entry) => opened = entry,
              onSettings: () => settingsCalls++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('工具 0'));
      expect(opened, entries.first);
      final settings = find.byKey(const ValueKey('more-workspace-settings'));
      await tester.scrollUntilVisible(settings, 300);
      // Lazy lists can build the tile in their cache before it enters view.
      await tester.ensureVisible(settings);
      await tester.pumpAndSettle();
      final viewport = tester.getRect(find.byType(ListView));
      final settingsRect = tester.getRect(settings);
      expect(settingsRect.top, greaterThanOrEqualTo(viewport.top));
      expect(settingsRect.bottom, lessThanOrEqualTo(viewport.bottom));
      await tester.tap(settings);
      expect(settingsCalls, 1);
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty More keeps settings reachable', (tester) async {
    var settingsCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MoreWorkspacePage(
            entries: const [],
            onOpen: (_) {},
            onSettings: () => settingsCalls++,
          ),
        ),
      ),
    );
    expect(find.text('可在设置中添加更多常用入口。'), findsOneWidget);
    await tester.tap(find.text('设置'));
    expect(settingsCalls, 1);
    expect(tester.takeException(), isNull);
  });
}
