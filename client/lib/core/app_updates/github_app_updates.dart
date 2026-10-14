import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';

const appRepository = 'JayConstruct/xudian';
final appReleasesUrl = Uri.https('github.com', '/$appRepository/releases');

class InstalledAppVersion {
  const InstalledAppVersion(this.version, this.buildNumber);
  final String version, buildNumber;
  String get label => '$version（构建 $buildNumber）';
}

final installedAppVersionProvider = FutureProvider<InstalledAppVersion>((
  _,
) async {
  final info = await PackageInfo.fromPlatform();
  return InstalledAppVersion(info.version, info.buildNumber);
});

enum AppUpdatePlatform { android, windows, unsupported }

enum AppUpdateChannel { stable, testing }

final appUpdatePlatformProvider = Provider<AppUpdatePlatform>(
  (_) => Platform.isAndroid
      ? AppUpdatePlatform.android
      : Platform.isWindows
      ? AppUpdatePlatform.windows
      : AppUpdatePlatform.unsupported,
);

class AppRelease {
  const AppRelease({
    required this.version,
    required this.url,
    required this.notes,
    required this.publishedAt,
    this.isPrerelease = false,
  });
  final Version version;
  final Uri url;
  final String notes;
  final DateTime? publishedAt;
  final bool isPrerelease;
}

class AppUpdateResult {
  const AppUpdateResult(this.installed, this.release);
  final InstalledAppVersion installed;
  final AppRelease? release;
  bool get updateAvailable =>
      release != null &&
      release!.version > _semanticVersion(Version.parse(installed.version));
}

Version _semanticVersion(Version version) => Version(
  version.major,
  version.minor,
  version.patch,
  pre: version.preRelease.isEmpty ? null : version.preRelease.join('.'),
);

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

class GitHubResponse {
  const GitHubResponse(this.status, this.body);
  final int status;
  final String body;
}

typedef GitHubReleaseTransport = Future<GitHubResponse> Function(Uri url);

final githubAppUpdatesProvider = Provider<GitHubAppUpdates>(
  (_) => GitHubAppUpdates(),
);

/// App releases share a repository with module releases. Only supported app
/// tags with uploaded installers for this platform can become app updates.
class GitHubAppUpdates {
  GitHubAppUpdates({GitHubReleaseTransport? transport})
    : _transport = transport ?? _request;
  final GitHubReleaseTransport _transport;

  Future<AppUpdateResult> check(
    InstalledAppVersion installed,
    AppUpdatePlatform platform, {
    AppUpdateChannel channel = AppUpdateChannel.stable,
  }) async {
    if (platform == AppUpdatePlatform.unsupported) {
      throw const AppUpdateException('当前平台暂不支持应用更新，请查看 GitHub 发布页');
    }
    try {
      Version.parse(installed.version);
      // Search past recent module releases, but bound traffic and response size.
      AppRelease? newest;
      for (var page = 1; page <= 5; page++) {
        final url = Uri.https(
          'api.github.com',
          '/repos/$appRepository/releases',
          {'per_page': '100', 'page': '$page'},
        );
        final response = await _transport(url)
            .timeout(const Duration(seconds: 15));
        if (response.status == 403 || response.status == 429) {
          throw const AppUpdateException('GitHub 暂时限制了请求，请稍后重试');
        }
        if (response.status != 200) {
          throw AppUpdateException('GitHub 暂时不可用（${response.status}），请稍后重试');
        }
        final data = jsonDecode(response.body);
        if (data is! List) throw const FormatException('Invalid releases');
        final releases =
            data
                .map((value) => _release(value, platform, channel))
                .whereType<AppRelease>()
                .toList()
              ..sort((a, b) => b.version.compareTo(a.version));
        if (releases.isNotEmpty &&
            (newest == null || releases.first.version > newest.version)) {
          newest = releases.first;
        }
        if (data.length < 100) return AppUpdateResult(installed, newest);
      }
      throw const AppUpdateException('发布记录较多，请打开 GitHub 发布页查看');
    } on AppUpdateException {
      rethrow;
    } on TimeoutException {
      throw const AppUpdateException('检查更新超时，请检查网络后重试');
    } on SocketException {
      throw const AppUpdateException('无法连接 GitHub，请检查网络后重试');
    } on HandshakeException {
      throw const AppUpdateException('无法安全连接 GitHub，请稍后重试');
    } on FormatException {
      throw const AppUpdateException('版本信息格式异常，请稍后重试');
    } on HttpException {
      throw const AppUpdateException('网络连接中断，请重试');
    }
  }

  static AppRelease? _release(
    Object? value,
    AppUpdatePlatform platform,
    AppUpdateChannel channel,
  ) {
    if (value is! Map ||
        value['draft'] != false ||
        value['prerelease'] is! bool) {
      return null;
    }
    final tag = value['tag_name'];
    if (tag is! String ||
        !RegExp(
          r'^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-(?:alpha|beta|rc)\.(0|[1-9]\d*))?$',
        ).hasMatch(tag)) {
      return null;
    }
    final Version version;
    try {
      version = Version.parse(tag.startsWith('v') ? tag.substring(1) : tag);
    } on FormatException {
      return null;
    }
    final isPrerelease = value['prerelease'] == true || version.isPreRelease;
    if (channel == AppUpdateChannel.stable && isPrerelease) return null;
    final url = Uri.tryParse(
      value['html_url'] is String ? value['html_url'] as String : '',
    );
    if (url == null || !_repositoryUrl(url, '/releases/tag/$tag')) return null;
    final assets = value['assets'];
    if (assets is! List ||
        !assets.any((asset) {
          if (asset is! Map ||
              asset['state'] != 'uploaded' ||
              asset['size'] is! num ||
              (asset['size'] as num) <= 0) {
            return false;
          }
          final name = asset['name'];
          final address = asset['browser_download_url'];
          if (name is! String || address is! String) return false;
          final uri = Uri.tryParse(address);
          if (uri == null ||
              !_repositoryUrl(uri, '/releases/download/$tag/$name')) {
            return false;
          }
          final lower = name.toLowerCase();
          return platform == AppUpdatePlatform.android
              ? lower.endsWith('.apk')
              : lower.contains('windows') &&
                    ['.zip', '.exe', '.msix'].any(lower.endsWith);
        })) {
      return null;
    }
    return AppRelease(
      version: version,
      isPrerelease: isPrerelease,
      url: url,
      notes: value['body'] is String ? value['body'] as String : '',
      publishedAt: value['published_at'] is String
          ? DateTime.tryParse(value['published_at'] as String)
          : null,
    );
  }

  static bool _repositoryUrl(Uri url, String suffix) =>
      url.scheme == 'https' &&
      url.host == 'github.com' &&
      !url.hasPort &&
      url.userInfo.isEmpty &&
      !url.hasQuery &&
      !url.hasFragment &&
      url.path == '/$appRepository$suffix';

  static Future<GitHubResponse> _request(Uri url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      return await (() async {
        final request = await client.getUrl(url);
        request.followRedirects = false;
        request.headers.set(
          HttpHeaders.acceptHeader,
          'application/vnd.github+json',
        );
        request.headers.set(HttpHeaders.userAgentHeader, 'Xudian-App-Update');
        request.headers.set('X-GitHub-Api-Version', '2022-11-28');
        final response = await request.close();
        if (response.statusCode != 200) {
          return GitHubResponse(response.statusCode, '');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 2 * 1024 * 1024) {
            throw const AppUpdateException('发布信息过大，请打开 GitHub 发布页查看');
          }
          bytes.addAll(chunk);
        }
        return GitHubResponse(response.statusCode, utf8.decode(bytes));
      })().timeout(const Duration(seconds: 15));
    } finally {
      client.close(force: true);
    }
  }
}
