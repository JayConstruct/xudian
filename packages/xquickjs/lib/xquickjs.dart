import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

@Native<Pointer<Void> Function(Int64)>(symbol: 'xm_create')
external Pointer<Void> _create(int memoryLimit);
@Native<Int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>(
  symbol: 'xm_add_file',
)
external int _add(
  Pointer<Void> handle,
  Pointer<Utf8> path,
  Pointer<Utf8> source,
);
@Native<Int Function(Pointer<Void>)>(symbol: 'xm_start')
external int _start(Pointer<Void> handle);
@Native<Void Function(Pointer<Void>, Pointer<Utf8>)>(symbol: 'xm_send')
external void _send(Pointer<Void> handle, Pointer<Utf8> source);
@Native<Pointer<Utf8> Function(Pointer<Void>)>(symbol: 'xm_poll')
external Pointer<Utf8> _poll(Pointer<Void> handle);
@Native<Void Function(Pointer<Void>)>(symbol: 'xm_free_message')
external void _free(Pointer<Void> message);
@Native<Void Function(Pointer<Void>)>(symbol: 'xm_cancel')
external void _cancel(Pointer<Void> handle);
@Native<Void Function(Pointer<Void>)>(symbol: 'xm_destroy')
external void _destroy(Pointer<Void> handle);

typedef HostHandler = Future<Object?> Function(
  String method,
  Object? arguments,
);

/// Each instance owns a native worker. Only registered source ESM and JSON
/// messages are available. This is capability isolation inside the app process.
class JavaScriptWorker {
  JavaScriptWorker(
    Map<String, String> files, {
    required this.host,
    int memoryLimit = 64 * 1024 * 1024,
  }) {
    _handle = _create(memoryLimit);
    if (_handle == nullptr) throw StateError('Cannot create JavaScript worker');
    try {
      for (final entry in {...files, '@xudian/sdk': sdkSource}.entries) {
        final path = entry.key.toNativeUtf8();
        final source = entry.value.toNativeUtf8();
        try {
          if (_add(_handle, path, source) == 0)
            throw StateError('Cannot register ESM');
        } finally {
          calloc.free(path);
          calloc.free(source);
        }
      }
      if (_start(_handle) == 0)
        throw StateError('Cannot start JavaScript worker');
    } catch (_) {
      _destroy(_handle);
      rethrow;
    }
    _timer = Timer.periodic(const Duration(milliseconds: 8), (_) => _drain());
    _post(bootstrap);
  }

  final HostHandler host;
  late Pointer<Void> _handle;
  late Timer _timer;
  final _pending = <int, Completer<Object?>>{};
  int _sequence = 0;
  bool _closed = false;
  bool get closed => _closed;

  Future<Object?> load(String entryPoint) => _request('load', entryPoint);
  Future<Object?> invoke(
    String handler,
    Object? arguments, {
    Duration? timeout = const Duration(seconds: 10),
  }) => _request('invoke', {
    'handler': handler,
    'arguments': arguments,
  }, timeout: timeout);

  Future<Object?> _request(
    String type,
    Object? payload, {
    Duration? timeout = const Duration(seconds: 10),
  }) async {
    if (_closed) throw StateError('JavaScript worker is closed');
    final id = ++_sequence;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _post(
      '__dispatch(${jsonEncode({'id': id, 'type': type, 'payload': payload})})',
    );
    try {
      return await (timeout == null
          ? completer.future
          : completer.future.timeout(timeout));
    } on TimeoutException {
      close();
      rethrow;
    } finally {
      _pending.remove(id);
    }
  }

  void emit(String id, Object? value) =>
      _post('__notify(${jsonEncode(id)},${jsonEncode(value)})');

  void _post(String source) {
    if (_closed) return;
    final value = source.toNativeUtf8();
    try {
      _send(_handle, value);
    } finally {
      calloc.free(value);
    }
  }

  void _drain() {
    if (_closed) return;
    while (!_closed) {
      final raw = _poll(_handle);
      if (raw == nullptr) break;
      Map<String, dynamic> message;
      try {
        message = jsonDecode(raw.toDartString()) as Map<String, dynamic>;
      } finally {
        _free(raw.cast());
      }
      if (message.containsKey('fatal') || message['closed'] == true) {
        close(StateError('${message['fatal'] ?? 'JavaScript worker stopped'}'));
        break;
      }
      if (message['type'] == 'host') {
        unawaited(_host(message));
      } else if (message['type'] == 'result') {
        final completer = _pending[message['id']];
        if (completer == null || completer.isCompleted) continue;
        if (message.containsKey('error')) {
          completer.completeError(StateError('${message['error']}'));
        } else {
          completer.complete(message['value']);
        }
      }
    }
  }

  Future<void> _host(Map<String, dynamic> message) async {
    try {
      final value = await host(
        message['method'] as String,
        message['arguments'],
      );
      _post('__deliver(${jsonEncode({'id': message['id'], 'value': value})})');
    } catch (error) {
      _post(
        '__deliver(${jsonEncode({'id': message['id'], 'error': '$error'})})',
      );
    }
  }

  void close([Object? error]) {
    if (_closed) return;
    _closed = true;
    _timer.cancel();
    _cancel(_handle);
    for (final completer in _pending.values) {
      if (!completer.isCompleted)
        completer.completeError(error ?? StateError('Module stopped'));
    }
    _pending.clear();
    _destroy(_handle);
  }
}

const bootstrap = r'''
(() => {
  let module, sequence = 0;
  const pending = new Map(), listeners = new Map();
  globalThis.__watch = async (method,args,listener) => { const id=await globalThis.__host(method,args); listeners.set(id,listener); return {id,close:async()=>{listeners.delete(id);await globalThis.__host('subscriptions.close',{id});}}; };
  globalThis.__notify = (id,value) => { const listener=listeners.get(id); if(listener) listener(value); };
  const send = globalThis.__send;
  globalThis.__host = (method, args) => new Promise((resolve, reject) => {
    const id = ++sequence;
    pending.set(id, {resolve, reject});
    send(JSON.stringify({type: 'host', id, method, arguments: args}));
  });
  globalThis.__deliver = message => {
    const p = pending.get(message.id); if (!p) return;
    pending.delete(message.id);
    if ('error' in message) p.reject(new Error(message.error)); else p.resolve(message.value);
  };
  globalThis.__dispatch = async message => {
    try {
      let value;
      if (message.type === 'load') {
        module = await import(message.payload); value = true;
      } else {
        const fn = module[message.payload.handler];
        if (typeof fn !== 'function') throw new Error('Unknown handler: ' + message.payload.handler);
        value = await fn(message.payload.arguments);
      }
      send(JSON.stringify({type: 'result', id: message.id, value: value ?? null}));
    } catch (error) {
      send(JSON.stringify({type: 'result', id: message.id, error: String(error) + '\n' + String(error.stack || '')}));
    }
  };
})();
''';

const sdkSource = r'''
const call = (name, args) => globalThis.__host(name, args);
export const data = Object.freeze({
  get: (collection, id) => call('data.get', {collection, id}),
  query: (collection, options = {}) => call('data.query', {collection, ...options}),
  watch: (collection, options, listener) => globalThis.__watch('data.watch', {collection,...options},listener),
});
export const services = Object.freeze({
  directory: () => call('services.directory', {}),
  query: (ref, input) => call('services.query', {ref, input}),
  watch: (ref,input,listener) => globalThis.__watch('services.watch',{ref,input},listener),
  prepare: (ref, input) => call('services.prepare', {ref, input}),
  commit: planId => call('services.commit', {planId}),
  adopt: planId => call('services.adopt', {planId}),
});
export const extensions = Object.freeze({query: entity => call('extensions.query', {entity}),queryMany: entities => call('extensions.queryMany',{entities})});
export const events = Object.freeze({subscribe: (source,listener) => globalThis.__watch('events.subscribe',source,listener)});
export const ui = Object.freeze({
  component: (ref, {key, props = {}, slots = {}, events = {}} = {}) => ({type: 'component', ref, ...(key === undefined ? {} : {key}), props, slots, events}),
  catalog: () => call('ui.catalog', {}),
  navigate: (page, context = {}) => call('ui.navigate', {page, context}),
  panel: (page, context = {}, presentation = {}) => call('ui.panel', {page, context, presentation}),
  dialog: spec => call('ui.dialog', spec),
  review: planId => call('ui.review', {planId}),
});
export const http = Object.freeze({request: options => call('http.request', options), cancel: id => call('http.cancel', {id})});
export const secrets = Object.freeze({configure: options => call('secrets.configure', options), delete: handle => call('secrets.delete', {handle})});
export const grants = Object.freeze({request: spec => call('grants.request', spec), revoke: id => call('grants.revoke', {id})});
export const packages = Object.freeze({prepare: spec => call('packages.prepare', spec), review: id => call('packages.review', {id})});
export const files = Object.freeze({readText: () => call('files.readText', {}), saveText: (name, text) => call('files.saveText', {name, text})});
export const browser = Object.freeze({capture: options => call('browser.capture', options)});
export const clock = Object.freeze({today: zone => call('clock.today', {zone}), local: zone => call('clock.local', {zone}), now: () => call('clock.now', {})});
export const ids = Object.freeze({new: () => call('ids.new', {})});
export default Object.freeze({data, services, extensions, events, ui, http, secrets, grants, packages, files, browser, clock, ids});
''';
