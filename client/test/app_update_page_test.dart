import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/app/design_system.dart';
import 'package:task_app/core/app_updates/github_app_updates.dart';
import 'package:task_app/core/module_host/host_settings_page.dart';
import 'package:task_app/core/ui/app_repository_links.dart';
import 'package:task_app/features/settings/app_update_page.dart';

import 'github_app_updates_test.dart' show release;

Widget app(
  Widget home,
  GitHubAppUpdates service, {
  Future<bool> Function(Uri)? launcher,
}) => ProviderScope(
  overrides: [
    installedAppVersionProvider.overrideWith(
      (_) async => const InstalledAppVersion('0.1.0', '4067'),
    ),
    appUpdatePlatformProvider.overrideWithValue(AppUpdatePlatform.android),
    githubAppUpdatesProvider.overrideWithValue(service),
    if (launcher != null)
      externalUrlLauncherProvider.overrideWithValue(launcher),
  ],
  child: MaterialApp(theme: AppDesign.theme(Brightness.light), home: home),
);

void main() {
  testWidgets(
    'about entry shows installed version and opens the real checker',
    (tester) async {
      var calls = 0;
      final service = GitHubAppUpdates(
        transport: (_) async {
          calls++;
          return const GitHubResponse(200, '[]');
        },
      );
      await tester.pumpWidget(app(const AboutSettingsPage(), service));
      await tester.pumpAndSettle();
      expect(find.text('0.1.0（构建 4067）'), findsOneWidget);
      expect(calls, 0);
      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();
      expect(find.byType(AppUpdatePage), findsOneWidget);
      expect(find.text('暂未发布 App 正式版本'), findsOneWidget);
      expect(calls, 1);
    },
  );

  testWidgets(
    'busy check is disabled, new version exposes notes and trusted browser link',
    (tester) async {
      final pending = Completer<GitHubResponse>();
      var calls = 0;
      Uri? opened;
      await tester.pumpWidget(
        app(
          const AppUpdatePage(),
          GitHubAppUpdates(
            transport: (_) {
              calls++;
              return pending.future;
            },
          ),
          launcher: (url) async {
            opened = url;
            return true;
          },
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('正在检查更新…'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(calls, 1);
      pending.complete(GitHubResponse(200, jsonEncode([release('v0.2.0')])));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本 0.2.0'), findsOneWidget);
      expect(find.text('修复并优化界面'), findsOneWidget);
      await tester.tap(find.text('查看更新并下载'));
      await tester.pumpAndSettle();
      expect(
        opened.toString(),
        'https://github.com/JayConstruct/xudian/releases/tag/v0.2.0',
      );
    },
  );

  testWidgets('rate limit offers retry and does not display stale success', (
    tester,
  ) async {
    var calls = 0;
    final service = GitHubAppUpdates(
      transport: (_) async => ++calls == 1
          ? const GitHubResponse(403, '')
          : const GitHubResponse(200, '[]'),
    );
    await tester.pumpWidget(app(const AppUpdatePage(), service));
    await tester.pumpAndSettle();
    expect(find.text('GitHub 暂时限制了请求，请稍后重试'), findsOneWidget);
    expect(find.text('当前已是最新版本'), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('暂未发布 App 正式版本'), findsOneWidget);
    expect(find.text('检查未完成'), findsNothing);
  });

  testWidgets(
    'late network completion after closing does not update disposed page',
    (tester) async {
      final pending = Completer<GitHubResponse>();
      await tester.pumpWidget(
        app(
          const AppUpdatePage(),
          GitHubAppUpdates(transport: (_) => pending.future),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(const GitHubResponse(200, '[]'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new release and notes remain usable on narrow large-text screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        app(
          const AppUpdatePage(),
          GitHubAppUpdates(
            transport: (_) async =>
                GitHubResponse(200, jsonEncode([release('v0.2.0')])),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('查看更新并下载'));
      expect(find.text('发现新版本 0.2.0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
