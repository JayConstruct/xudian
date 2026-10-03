import 'package:drift/drift.dart';

import '../../../../data/app_database.dart';

class RuleExecutionStore {
  RuleExecutionStore(this.db);

  final AppDatabase db;

  Future<void> append({
    required String moduleId,
    required String ruleId,
    required String eventType,
    required String entityType,
    required String entityId,
    required String eventPayloadJson,
    int? sourceExecutionId,
    required String status,
    String? message,
    required int automationDepth,
    required int actionCount,
  }) async {
    await db.into(db.ruleExecutions).insert(
      RuleExecutionsCompanion.insert(
        moduleId: moduleId,
        ruleId: ruleId,
        eventType: eventType,
        entityType: entityType,
        entityId: entityId,
        eventPayloadJson: Value(eventPayloadJson),
        sourceExecutionId: Value(sourceExecutionId),
        status: status,
        message: Value(message),
        automationDepth: Value(automationDepth),
        actionCount: Value(actionCount),
        createdAt: DateTime.now(),
      ),
    );
  }
  Future<List<RuleExecution>> listForModule(
    String moduleId, {
    String? status,
    String? ruleId,
    int limit = 100,
  }) {
    final query = db.select(db.ruleExecutions)
      ..where((row) => row.moduleId.equals(moduleId));
    if (status != null) {
      query.where((row) => row.status.equals(status));
    }
    if (ruleId != null && ruleId.trim().isNotEmpty) {
      query.where((row) => row.ruleId.equals(ruleId.trim()));
    }
    query
      ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
      ..limit(limit);
    return query.get();
  }

  Future<void> clearForModule(String moduleId) async {
    await (db.delete(db.ruleExecutions)
          ..where((row) => row.moduleId.equals(moduleId)))
        .go();
  }
}
