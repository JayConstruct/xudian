class DomainEvent {
  const DomainEvent({
    required this.type,
    required this.entityType,
    required this.entityId,
    this.payload = const {},
    this.automationDepth = 0,
    this.automationTrace = const {},
  });

  final String type;
  final String entityType;
  final String entityId;
  final Map<String, Object?> payload;
  final int automationDepth;
  final Set<String> automationTrace;

  DomainEvent withAutomation({
    required int depth,
    required Set<String> trace,
  }) {
    return DomainEvent(
      type: type,
      entityType: entityType,
      entityId: entityId,
      payload: payload,
      automationDepth: depth,
      automationTrace: Set.unmodifiable(trace),
    );
  }
}
