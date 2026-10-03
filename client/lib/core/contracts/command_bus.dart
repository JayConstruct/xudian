import '../modules/module_context.dart';

typedef CommandPayload = Map<String, Object?>;
typedef CommandHandler = Future<Object?> Function(CommandPayload payload);
typedef ScopedCommandHandler = Future<Object?> Function(
  ModuleContext context,
  CommandPayload payload,
);

class _CommandRegistration {
  const _CommandRegistration(this.permission, this.handler, this.scopedHandler);
  final String permission;
  final CommandHandler? handler;
  final ScopedCommandHandler? scopedHandler;
}

class CommandBus {
  final Map<String, _CommandRegistration> _handlers = {};

  Iterable<String> get registeredCommands => _handlers.keys;

  void register(
    String id, {
    required String permission,
    required CommandHandler handler,
  }) {
    if (!_validId(id)) throw ArgumentError('Invalid command id: $id');
    if (_handlers.containsKey(id)) {
      throw StateError('Command already registered: $id');
    }
    _handlers[id] = _CommandRegistration(permission, handler, null);
  }

  void registerScoped(
    String id, {
    required String permission,
    required ScopedCommandHandler handler,
  }) {
    if (!_validId(id)) throw ArgumentError('Invalid command id: $id');
    if (_handlers.containsKey(id)) {
      throw StateError('Command already registered: $id');
    }
    _handlers[id] = _CommandRegistration(permission, null, handler);
  }

  Future<Object?> execute(
    ModuleContext context,
    String id, [
    CommandPayload payload = const {},
  ]) async {
    final registration = _handlers[id];
    if (registration == null) throw StateError('Unknown command: $id');
    context.require(registration.permission);
    if (registration.scopedHandler case final handler?) {
      return handler(context, payload);
    }
    return registration.handler!(payload);
  }

  bool _validId(String id) =>
      RegExp(r'^[a-z][a-zA-Z0-9]*(\.[a-zA-Z][a-zA-Z0-9]*)+$').hasMatch(id);
}
