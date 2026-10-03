import '../modules/module_context.dart';

typedef QueryPayload = Map<String, Object?>;
typedef QueryHandler = Future<Object?> Function(QueryPayload payload);
typedef QueryWatchHandler = Stream<Object?> Function(QueryPayload payload);

class _QueryRegistration {
  const _QueryRegistration(this.permission, this.handler, this.watchHandler);
  final String permission;
  final QueryHandler handler;
  final QueryWatchHandler? watchHandler;
}

class QueryBus {
  final Map<String, _QueryRegistration> _handlers = {};

  Iterable<String> get registeredQueries => _handlers.keys;

  void register(
    String id, {
    required String permission,
    required QueryHandler handler,
    QueryWatchHandler? watchHandler,
  }) {
    if (_handlers.containsKey(id)) {
      throw StateError('Query already registered: $id');
    }
    _handlers[id] = _QueryRegistration(permission, handler, watchHandler);
  }

  Stream<Object?> watch(
    ModuleContext context,
    String id, [
    QueryPayload payload = const {},
  ]) async* {
    final registration = _handlers[id];
    if (registration == null) throw StateError('Unknown query: $id');
    context.require(registration.permission);
    final watch = registration.watchHandler;
    if (watch == null) throw StateError('Query cannot be watched: $id');
    yield* watch(payload);
  }

  Future<Object?> execute(
    ModuleContext context,
    String id, [
    QueryPayload payload = const {},
  ]) async {
    final registration = _handlers[id];
    if (registration == null) throw StateError('Unknown query: $id');
    context.require(registration.permission);
    return registration.handler(payload);
  }
}
