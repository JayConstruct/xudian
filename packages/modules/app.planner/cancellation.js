import {data, services, clock} from '@xudian/sdk';

const taskRef = serviceId => ({moduleId: 'app.tasks', serviceId, majorVersion: 1});
export async function cancelledTaskIds() {
  const rows = await data.query('taskStates', {filter: {field: 'cancelledAt', op: 'notNull'}, limit: 10000});
  if (rows.length === 10000) throw Error('已取消任务过多，请先整理历史记录');
  return new Set(rows.map(row => row.id));
}
export async function taskState({id}) {
  const saved = await data.get('taskStates', id);
  return {id, cancelled: !!saved?.cancelledAt, cancelledAt: saved?.cancelledAt || null};
}
export async function requireActiveTask(id) {
  if ((await taskState({id})).cancelled) throw Error('任务已取消，请先恢复任务');
}
export async function taskSetCancelled({id, cancelled, expectedUpdatedAt}) {
  if (typeof cancelled !== 'boolean') throw Error('取消状态无效');
  const before = await services.query(taskRef('task.get'), {id});
  if (!before || before.deletedAt || before.archivedAt) throw Error('任务已不可用，请刷新');
  if (before.completedAt) throw Error('请先重新打开已完成的任务');
  if (expectedUpdatedAt !== undefined && before.updatedAt !== expectedUpdatedAt) throw Error('任务已被其他操作修改，请关闭后重新打开');
  const previous = await taskState({id});
  if (previous.cancelled === cancelled) return {writes: [], events: [], result: previous};
  const now = await clock.now();
  // Advance the task revision as well, so stale completion buttons, schedule
  // previews and undo operations cannot act on a newly cancelled task.
  const updatedAt = new Date(Math.max(Date.parse(now), Date.parse(before.updatedAt) + 1)).toISOString();
  await services.prepare(taskRef('task.restore'), {id, expected: before, value: {...before, updatedAt}});
  const value = {id, cancelledAt: cancelled ? now : null, updatedAt};
  return {writes: [{collection: 'taskStates', id, value}], events: [{type: 'planner.changed'}], result: {...value, cancelled}};
}
