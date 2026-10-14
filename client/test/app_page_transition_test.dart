import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/ui/ui_design.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets('global route motion respects reduced=$reduced', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppDesign.theme(Brightness.light)
              .copyWith(platform: TargetPlatform.android),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      key: const ValueKey('destination'),
                      appBar: AppBar(title: const Text('新页面')),
                      body: const Text('页面内容'),
                    ),
                  ),
                ),
                child: const Text('切换'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('切换'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final position = tester.getTopLeft(
        find.byKey(const ValueKey('destination')),
      );
      expect(position.dx, reduced ? equals(0) : greaterThan(0));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('destination'))).dx,
        0,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('切换'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
