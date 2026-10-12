import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

import '../core/module_host/collection_store.dart';
import '../core/module_host/host_browser.dart';
import '../core/module_host/host_network.dart';
import '../core/module_host/module_host.dart';

/// Adapts host capabilities to platform services without retaining UI context.
/// Permission checks remain in ModuleHost, before dispatch to this bridge.
class HostPlatformBridge {
  HostPlatformBridge(
    this.store, {
    HostBrowser? browser,
    MethodChannel? filesChannel,
    bool? android,
  }) : _network = HostNetwork(store),
       _browser = browser ?? HostBrowser(),
       _filesChannel = filesChannel ?? const MethodChannel('xudian.host/files'),
       _android = android ?? Platform.isAndroid;

  final CollectionStore store;
  final HostNetwork _network;
  final HostBrowser _browser;
  final MethodChannel _filesChannel;
  final bool _android;
  ModuleHost? _host;
  bool _closed = false;

  void attach(ModuleHost host) {
    _requireOpen();
    _detach();
    _host = host;
    host.onDeactivate = _revoke;
    host.onDeleteData = _network.deleteModuleCredentials;
  }

  void _detach() {
    final host = _host;
    if (host?.onDeactivate == _revoke) host?.onDeactivate = null;
    if (host?.onDeleteData == _network.deleteModuleCredentials) {
      host?.onDeleteData = null;
    }
    _host = null;
  }

  void _revoke(ModuleActor caller) {
    _network.revoke(caller);
    unawaited(_browser.revoke(caller));
  }

  void revokeInactive() => _network.revokeInactive();

  Future<String?> configureSecret(
    ModuleActor caller,
    Object? endpoint,
    Future<String?> Function(Uri endpoint) prompt,
  ) async {
    _requireOpen();
    final validated = _network.validateEndpoint(endpoint);
    final secret = await prompt(validated);
    // A dialog can outlive the module that opened it, including cancellation.
    store.requireActive(caller);
    _requireOpen();
    if (secret == null) return null;
    return _network.configure(caller, validated.toString(), secret);
  }

  Future<Object?> invoke(
    ModuleActor caller,
    String method,
    Map<String, Object?> args,
  ) async {
    _requireOpen();
    switch (method) {
      case 'secrets.delete':
        await _network.delete(caller, args['handle'] as String);
        return null;
      case 'http.request':
        return _network.request(caller, args);
      case 'http.cancel':
        _network.cancel(caller, args['id'] as String);
        return null;
      case 'browser.capture':
        return _browser.capture(caller, args);
      case 'files.readText':
        final file = await openFile(
          acceptedTypeGroups: [
            const XTypeGroup(label: 'JSON 文件', extensions: ['json']),
          ],
        );
        if (file == null) return null;
        final bytes = await file.readAsBytes();
        if (bytes.length > 2 * 1024 * 1024) throw StateError('文件超过2 MiB');
        return utf8.decode(bytes);
      case 'files.saveText':
        final text = args['text'] as String;
        final bytes = utf8.encode(text);
        if (bytes.length > 2 * 1024 * 1024) throw StateError('文件超过2 MiB');
        if (_android) {
          return await _filesChannel.invokeMethod<bool>('saveText', {
                'name': args['name'],
                'text': text,
              }) ??
              false;
        }
        final location = await getSaveLocation(
          suggestedName: args['name'] as String,
        );
        if (location == null) return false;
        await XFile.fromData(
          Uint8List.fromList(bytes),
          mimeType: 'application/json',
        ).saveTo(location.path);
        return true;
      default:
        throw StateError('Unsupported host capability: $method');
    }
  }

  void _requireOpen() {
    if (_closed) throw StateError('Host interaction unavailable');
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _detach();
    _network.close();
    unawaited(_browser.close());
  }
}
