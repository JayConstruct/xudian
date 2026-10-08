import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../contracts/json_values.dart';
import '../declarative/package/module_package.dart';
import '../module_host/module_package.dart';
import 'catalog_models.dart';

class DownloadCancelled implements Exception {
  const DownloadCancelled();
  @override
  String toString() => '下载已取消';
}

class DownloadCancellation {
  bool _cancelled = false;
  final _signal = Completer<void>();
  final _listeners = <void Function()>[];
  bool get isCancelled => _cancelled;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _signal.complete();
    for (final listener in List.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  void check() {
    if (_cancelled) throw const DownloadCancelled();
  }

  void Function() listen(void Function() listener) {
    check();
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

typedef CatalogTransport = Future<List<int>> Function(
  Uri url, {
  DownloadCancellation? cancellation,
  void Function(int received, int total)? onProgress,
  required int maximumBytes,
});

/// Redirects may retain the pinned GitHub repository or reach GitHub's release
/// asset CDN. Repository rename/transfer redirects require explicit review.
bool isAllowedCatalogRedirect(Uri source, Uri target) {
  if (target.scheme != 'https' ||
      target.userInfo.isNotEmpty ||
      target.hasPort ||
      target.hasFragment) {
    return false;
  }
  if (source.host == 'github.com' &&
      [
        'release-assets.githubusercontent.com',
        'objects.githubusercontent.com',
      ].contains(target.host)) {
    return true;
  }
  if (source.pathSegments.length < 2 || target.host != source.host) {
    return false;
  }
  final repository = source.pathSegments.take(2).join('/');
  try {
    validateRepositoryUrl(
      target,
      repository,
      release: source.host == 'github.com',
    );
    return true;
  } on FormatException {
    return false;
  }
}

class ModuleCatalogClient {
  ModuleCatalogClient({
    required this.cacheDirectory,
    String repository = 'JayConstruct/xudian-modules',
    CatalogTransport? transport,
    this.publishers,
    Map<String, String> preinstalledDigests = const {},
    this.networkRetries = 1,
  }) : repository = normalizeRepository(repository),
       preinstalledDigests = Map.unmodifiable(preinstalledDigests),
       // ignore: prefer_initializing_formals
       _transport = transport;
  final Directory cacheDirectory;
  final String repository;
  final TrustedPublisherRegistry? publishers;

  /// Immutable trust pins supplied only from the catalog bundled in the APK.
  /// Remote indexes and their SHA-256 values must never populate this map.
  final Map<String, String> preinstalledDigests;
  final int networkRetries;
  final CatalogTransport? _transport;
  bool loadedFromCache = false;
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20);
  Uri get catalogUrl => Uri.parse(
    'https://raw.githubusercontent.com/$repository/main/catalog.json',
  );

  Future<List<int>> _fetch(
    Uri url, {
    DownloadCancellation? cancellation,
    void Function(int, int)? onProgress,
    required int maximumBytes,
  }) async {
    cancellation?.check();
    if (_transport != null) {
      final pending = _transport(
        url,
        cancellation: cancellation,
        onProgress: onProgress,
        maximumBytes: maximumBytes,
      );
      final bytes = await (cancellation == null
          ? pending
          : Future.any<List<int>>([
              pending,
              cancellation._signal.future.then(
                (_) => throw const DownloadCancelled(),
              ),
            ]));
      cancellation?.check();
      if (bytes.length > maximumBytes) throw const FormatException('下载大小超出限制');
      return bytes;
    }
    return _fetchHttp(
      url,
      cancellation: cancellation,
      onProgress: onProgress,
      maximumBytes: maximumBytes,
    );
  }

  Future<HttpClientRequest> _request(
    Uri url,
    DownloadCancellation? cancellation,
  ) async {
    cancellation?.check();
    final future = _http.getUrl(url).timeout(const Duration(seconds: 30));
    if (cancellation == null) return future;
    final request = await Future.any<HttpClientRequest>([
      future.then((request) {
        if (cancellation.isCancelled) request.abort(const DownloadCancelled());
        return request;
      }),
      cancellation._signal.future.then((_) => throw const DownloadCancelled()),
    ]);
    cancellation.check();
    return request;
  }

  Future<List<int>> _fetchHttp(
    Uri url, {
    DownloadCancellation? cancellation,
    void Function(int, int)? onProgress,
    required int maximumBytes,
    int redirects = 0,
    Uri? initialUrl,
  }) async {
    final request = await _request(url, cancellation);
    request.followRedirects = false;
    final remove = cancellation?.listen(
      () => request.abort(const DownloadCancelled()),
    );
    try {
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        final target = location == null ? null : url.resolve(location);
        await response.listen(null).cancel();
        if (redirects >= 5 ||
            target == null ||
            !isAllowedCatalogRedirect(initialUrl ?? url, target)) {
          throw const FormatException('下载重定向改变发布仓库、来源不可信或超过 5 次');
        }
        return await _fetchHttp(
          target,
          cancellation: cancellation,
          onProgress: onProgress,
          maximumBytes: maximumBytes,
          redirects: redirects + 1,
          initialUrl: initialUrl ?? url,
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        await response.listen(null).cancel();
        throw HttpException('HTTP ${response.statusCode}', uri: url);
      }
      if (response.contentLength > maximumBytes) {
        await response.listen(null).cancel();
        throw const FormatException('下载大小超出限制');
      }
      final output = BytesBuilder(copy: false);
      final iterator = StreamIterator(
        response.timeout(const Duration(seconds: 30)),
      );
      try {
        while (await (cancellation == null
            ? iterator.moveNext()
            : Future.any<bool>([
                iterator.moveNext(),
                cancellation._signal.future.then(
                  (_) => throw const DownloadCancelled(),
                ),
              ]))) {
          cancellation?.check();
          final chunk = iterator.current;
          if (output.length + chunk.length > maximumBytes) {
            throw const FormatException('下载大小超出限制');
          }
          output.add(chunk);
          onProgress?.call(output.length, response.contentLength);
        }
      } finally {
        await iterator.cancel();
      }
      cancellation?.check();
      return output.takeBytes();
    } catch (_) {
      cancellation?.check();
      rethrow;
    } finally {
      remove?.call();
    }
  }

  bool _networkError(Object error) =>
      error is IOException || error is TimeoutException;
  Future<List<int>> _retry(
    Uri url, {
    DownloadCancellation? cancellation,
    void Function(int, int)? onProgress,
    required int maximumBytes,
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await _fetch(
          url,
          cancellation: cancellation,
          onProgress: onProgress,
          maximumBytes: maximumBytes,
        );
      } catch (error) {
        cancellation?.check();
        if (!_networkError(error) || attempt >= networkRetries) rethrow;
      }
    }
  }

  Future<File> _cache(String key) async =>
      File('${cacheDirectory.path}/${await digest(utf8.encode(key))}');
  Future<void> _save(File file, List<int> bytes) async {
    await cacheDirectory.create(recursive: true);
    final temp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<T> _metadata<T>(
    Uri url,
    T Function(Object?) parse, {
    bool offline = false,
  }) async {
    loadedFromCache = offline;
    final cache = await _cache(url.toString());
    List<int> bytes;
    if (offline) {
      if (!await cache.exists()) throw StateError('离线缓存中缺少目录或版本索引：$url');
      bytes = await cache.readAsBytes();
    } else {
      try {
        bytes = await _retry(url, maximumBytes: 4 * 1024 * 1024);
      } catch (error) {
        if (!_networkError(error) || !await cache.exists()) rethrow;
        loadedFromCache = true;
        bytes = await cache.readAsBytes();
      }
    }
    final result = parse(jsonDecode(utf8.decode(bytes)));
    if (!offline) await _save(cache, bytes);
    return result;
  }

  Future<ModuleCatalog> loadCatalog({bool offline = false}) =>
      _metadata(catalogUrl, ModuleCatalog.fromJson, offline: offline);
  Future<ModuleVersionIndex> loadIndex(
    CatalogModule module, {
    bool offline = false,
  }) => _metadata(
    module.indexUrl,
    (json) => ModuleVersionIndex.fromJson(json, module),
    offline: offline,
  );

  Future<ScriptPackage> _verify(List<int> bytes, CatalogVersion release) async {
    if (bytes.length != release.size || await digest(bytes) != release.sha256) {
      throw FormatException('模块下载大小或 SHA-256 不符：${release.moduleId}');
    }
    final package = await ScriptPackage.verify(
      bytes,
      allowUnsignedLocal: true,
      publishers: publishers,
      preinstalledDigest:
          preinstalledDigests[release.moduleId] == release.sha256
          ? release.sha256
          : null,
    );
    if (package.id != release.moduleId ||
        package.version != release.version ||
        canonicalJson(package.manifest) != canonicalJson(release.manifest) ||
        canonicalJson(package.definition['services'] ?? []) !=
            canonicalJson(release.services)) {
      throw FormatException('包身份、清单或服务声明与版本索引不符：${release.moduleId}');
    }
    // Directory digests never grant publisher identity. Trust comes from the
    // existing verifier's signature rules or an immutable APK-bundled pin.
    return package;
  }

  Future<ScriptPackage> download(
    CatalogVersion release, {
    DownloadCancellation? cancellation,
    void Function(int received, int total)? onProgress,
    bool offline = false,
  }) async {
    cancellation?.check();
    final cache = await _cache('package:${release.sha256}');
    if (await cache.exists()) {
      try {
        final package = await _verify(await cache.readAsBytes(), release);
        cancellation?.check();
        onProgress?.call(release.size, release.size);
        return package;
      } on FormatException {
        await cache.delete();
        if (offline) rethrow;
      }
    }
    if (offline) {
      throw StateError('离线缓存中缺少模块包：${release.moduleId} ${release.version}');
    }
    final bytes = await _retry(
      release.url,
      cancellation: cancellation,
      onProgress: (received, _) => onProgress?.call(received, release.size),
      maximumBytes: release.size,
    );
    cancellation?.check();
    final package = await _verify(bytes, release);
    cancellation?.check();
    await _save(cache, bytes);
    return package;
  }

  void dispose() => _http.close(force: true);
}
