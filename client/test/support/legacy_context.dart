import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_app/data/providers.dart';
import 'package:task_app/core/ui/ui_composition.dart';

// v2 context contracts retained solely as a migration baseline.
Stream<bool> legacyPageContextValidity(Ref ref,PageContext context) async* {
  if(context.taskId==null&&context.projectId==null) {yield true;return;}
  final database=await ref.watch(databaseProvider.future);
  final taskId=context.taskId??'',projectId=context.projectId??'';
  yield* database.customSelect(
    "SELECT (? = '' OR EXISTS(SELECT 1 FROM tasks WHERE id = ?)) "
    "AND (? = '' OR EXISTS(SELECT 1 FROM projects WHERE id = ?)) "
    "AND (? = '' OR ? = '' OR EXISTS(SELECT 1 FROM tasks WHERE id = ? AND project_id = ?)) AS valid",
    variables:[for(final value in [taskId,taskId,projectId,projectId,taskId,projectId,taskId,projectId]) Variable<String>(value)],
    readsFrom:{database.tasks,database.projects}).watchSingle().map((row)=>row.read<int>('valid')==1);
}
