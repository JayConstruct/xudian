import 'dart:async';

import 'automation_execution.dart';
import 'domain_event.dart';

class EventBus {
  static final Object _deferredEventsKey = Object();
  final _controller = StreamController<DomainEvent>.broadcast();

  Stream<DomainEvent> get events => _controller.stream;

  void publish(DomainEvent event) {
    final prepared = event.withAutomation(
      depth: currentAutomationDepth,
      trace: currentAutomationTrace,
    );
    final deferred = Zone.current[_deferredEventsKey] as List<DomainEvent>?;
    if (deferred != null) {
      deferred.add(prepared);
    } else {
      _controller.add(prepared);
    }
  }

  Future<T> afterCommit<T>(Future<T> Function() action) async {
    final deferred = <DomainEvent>[];
    final result = await runZoned(
      action,
      zoneValues: {_deferredEventsKey: deferred},
    );
    for (final event in deferred) {
      _controller.add(event);
    }
    return result;
  }

  Future<void> close() => _controller.close();
}
