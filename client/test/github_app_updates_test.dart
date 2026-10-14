import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/app_updates/github_app_updates.dart';

Map<String, Object?> release(
  String tag, {
  String? name,
  bool draft = false,
  bool prerelease = false,
  String? url,
  String? download,
  int size = 100,
  String state = 'uploaded',
}) => {
  'tag_name': tag,
  'draft': draft,
  'prerelease': prerelease,
  'html_url': url ?? 'https://github.com/$appRepository/releases/tag/$tag',
  'body': '修复并优化界面',
  'published_at': '2026-10-11T03:00:00Z',
  'assets': [
    {
      'name': name ?? 'app-arm64-v8a-release.apk',
      'size': size,
      'state': state,
      'browser_download_url':
          download ??
          'https://github.com/$appRepository/releases/download/$tag/${name ?? 'app-arm64-v8a-release.apk'}',
    },
  ],
};

GitHubAppUpdates withReleases(List<Object?> values) => GitHubAppUpdates(
  transport: (_) async => GitHubResponse(200, jsonEncode(values)),
);

void main() {
  const installed = InstalledAppVersion('0.1.9', '4066');

  test(
    'uses semantic order and excludes modules, draft and prerelease',
    () async {
      final result = await withReleases([
        release('modules-20261011', name: 'app.schedule-9.0.0.xmodule'),
        release('v8.0.0', draft: true),
        release('v7.0.0', prerelease: true),
        release('v6.0.0-beta.1'),
        release('v5.0.0', name: 'app.schedule.xmodule'),
        release('v0.1.9'),
        release('v0.1.10'),
        release('v0.1.2'),
      ]).check(installed, AppUpdatePlatform.android);
      expect(result.updateAvailable, isTrue);
      expect(result.release!.version.toString(), '0.1.10');
      expect(result.release!.notes, '修复并优化界面');
      expect(result.release!.publishedAt!.year, 2026);
    },
  );

  test(
    'same semantic version and older releases never request a downgrade',
    () async {
      for (final version in ['0.1.10', '0.1.10+999', '0.2.0']) {
        final result = await withReleases([release('v0.1.10')]).check(
          InstalledAppVersion(version, '4001'),
          AppUpdatePlatform.android,
        );
        expect(result.updateAvailable, isFalse);
      }
      final result = await withReleases([release('v1.0.0')]).check(
        const InstalledAppVersion('1.0.0-beta.1', '99'),
        AppUpdatePlatform.android,
      );
      expect(result.updateAvailable, isTrue);
    },
  );

  test('module-only and empty repositories have no app release', () async {
    for (final values in [
      <Object?>[],
      [release('modules-2026')],
    ]) {
      final result = await withReleases(values)
          .check(installed, AppUpdatePlatform.android);
      expect(result.release, isNull);
      expect(result.updateAvailable, isFalse);
    }
  });

  test(
    'testing channel orders numeric prereleases and retains release checks',
    () async {
      final result =
          await withReleases([
            release('v0.2.0-alpha.12', prerelease: true),
            release('v0.2.0-beta.2', prerelease: true),
            release('v0.2.0-beta.10', prerelease: true),
            release('v0.1.9'),
            release('v9.0.0-beta.1', draft: true, prerelease: true),
            release('modules-2026', prerelease: true),
            release(
              'v8.0.0-beta.1',
              name: 'app.schedule.xmodule',
              prerelease: true,
            ),
            release(
              'v7.0.0-beta.1',
              name: 'xudian-windows.zip',
              prerelease: true,
            ),
            release('v6.0.0-beta.1', size: 0, prerelease: true),
            release(
              'v5.0.0-beta.1',
              url: 'https://example.com/release',
              prerelease: true,
            ),
            release(
              'v4.0.0-beta.1',
              download: 'https://example.com/app.apk',
              prerelease: true,
            ),
            release('v3.0.0-nightly.1', prerelease: true),
            release('v3.0.0-beta.01', prerelease: true),
          ]).check(
            installed,
            AppUpdatePlatform.android,
            channel: AppUpdateChannel.testing,
          );
      expect(result.updateAvailable, isTrue);
      expect(result.release!.version.toString(), '0.2.0-beta.10');
      expect(result.release!.isPrerelease, isTrue);
    },
  );

  test('testing channel recognizes prerelease tags and GitHub flags', () async {
    for (final candidate in [
      release('v0.2.0-beta.3'),
      release('v0.2.0', prerelease: true),
    ]) {
      final service = withReleases([candidate]);
      expect(
        (await service.check(installed, AppUpdatePlatform.android)).release,
        isNull,
      );
      final result = await service.check(
        installed,
        AppUpdatePlatform.android,
        channel: AppUpdateChannel.testing,
      );
      expect(result.updateAvailable, isTrue);
      expect(result.release!.isPrerelease, isTrue);
    }
  });

  test(
    'testing channel advances beta to rc to stable without downgrades',
    () async {
      for (final scenario in [
        ('0.2.0-beta.3', 'v0.2.0-rc.1', true),
        ('0.2.0-rc.1', 'v0.2.0', true),
        ('0.2.0', 'v0.2.0-rc.9', false),
        ('0.2.0-beta.3+999', 'v0.2.0-beta.3', false),
        ('0.2.0-beta.10', 'v0.2.0-beta.3', false),
      ]) {
        final result = await withReleases([release(scenario.$2)]).check(
          InstalledAppVersion(scenario.$1, '999'),
          AppUpdatePlatform.android,
          channel: AppUpdateChannel.testing,
        );
        expect(
          result.updateAvailable,
          scenario.$3,
          reason: '${scenario.$1} -> ${scenario.$2}',
        );
      }
      final result =
          await withReleases([
            release('v0.2.0-beta.10', prerelease: true),
            release('v0.2.0'),
            release('v0.2.0-rc.1', prerelease: true),
          ]).check(
            installed,
            AppUpdatePlatform.android,
            channel: AppUpdateChannel.testing,
          );
      expect(result.release!.version.toString(), '0.2.0');
      expect(result.release!.isPrerelease, isFalse);
    },
  );

  test('selects uploaded installers for the current platform', () async {
    final service = withReleases([
      release('v2.0.0', name: 'xudian-windows-x64.zip'),
      release('v1.0.0'),
      release('v9.0.0', size: 0),
      release('v8.0.0', state: 'new'),
    ]);
    expect(
      (await service.check(
        installed,
        AppUpdatePlatform.android,
      )).release!.version.toString(),
      '1.0.0',
    );
    expect(
      (await service.check(
        installed,
        AppUpdatePlatform.windows,
      )).release!.version.toString(),
      '2.0.0',
    );
  });

  test('rejects foreign repository, non-https and deceptive asset URLs', () async {
    final result = await withReleases([
      release('v9.0.0', url: 'https://example.com/releases/tag/v9.0.0'),
      release(
        'v8.0.0',
        url: 'https://github.com/another/repo/releases/tag/v8.0.0',
      ),
      release(
        'v7.0.0',
        download:
            'http://github.com/$appRepository/releases/download/v7.0.0/app-arm64-v8a-release.apk',
      ),
      release(
        'v6.0.0',
        download:
            'https://evil@github.com/$appRepository/releases/download/v6.0.0/app-arm64-v8a-release.apk',
      ),
      release(
        'v5.0.0',
        download:
            'https://github.com/$appRepository/releases/download/v4.0.0/app-arm64-v8a-release.apk',
      ),
      release(
        'v4.0.0',
        url:
            'https://github.com/$appRepository/releases/tag/v4.0.0?redirect=evil',
      ),
      release('v1.0.0'),
    ]).check(installed, AppUpdatePlatform.android);
    expect(result.release!.version.toString(), '1.0.0');
  });

  test(
    'paginates past module releases and compares all fetched app versions',
    () async {
      final requests = <Uri>[];
      final service = GitHubAppUpdates(
        transport: (url) async {
          requests.add(url);
          final page = url.queryParameters['page'];
          return GitHubResponse(
            200,
            jsonEncode(
              page == '1'
                  ? [
                      release('v1.0.0'),
                      ...List.generate(99, (_) => release('modules-1')),
                    ]
                  : [release('v2.0.0')],
            ),
          );
        },
      );
      final result = await service.check(installed, AppUpdatePlatform.android);
      expect(requests.length, 2);
      expect(
        requests.first.toString(),
        'https://api.github.com/repos/JayConstruct/xudian/releases?per_page=100&page=1',
      );
      expect(result.release!.version.toString(), '2.0.0');
    },
  );

  test(
    'limits history and does not claim a partial response is latest',
    () async {
      var calls = 0;
      final service = GitHubAppUpdates(
        transport: (_) async {
          calls++;
          return GitHubResponse(
            200,
            jsonEncode(List.generate(100, (_) => release('modules-1'))),
          );
        },
      );
      await expectLater(
        service.check(installed, AppUpdatePlatform.android),
        throwsA(
          isA<AppUpdateException>().having(
            (e) => e.message,
            'message',
            contains('发布记录较多'),
          ),
        ),
      );
      expect(calls, 5);
    },
  );

  test(
    'network, malformed responses and rate limits remain retryable errors',
    () async {
      for (final status in [403, 404, 429, 500]) {
        final service = GitHubAppUpdates(
          transport: (_) async => GitHubResponse(status, ''),
        );
        await expectLater(
          service.check(installed, AppUpdatePlatform.android),
          throwsA(isA<AppUpdateException>()),
        );
      }
      for (final body in ['not json', '{}']) {
        await expectLater(
          GitHubAppUpdates(transport: (_) async => GitHubResponse(200, body))
              .check(installed, AppUpdatePlatform.android),
          throwsA(isA<AppUpdateException>()),
        );
      }
      for (final failure in [
        const SocketException('offline'),
        TimeoutException('timeout'),
      ]) {
        await expectLater(
          GitHubAppUpdates(transport: (_) async => throw failure)
              .check(installed, AppUpdatePlatform.android),
          throwsA(isA<AppUpdateException>()),
        );
      }
    },
  );
}
