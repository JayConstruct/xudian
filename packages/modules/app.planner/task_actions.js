import {services, ui, clock, ids} from '@xudian/sdk';

export const ref = id => ({moduleId: 'app.planner', serviceId: 'planner.' + id, majorVersion: 1});
export const query = (id, input = {}) => services.query(ref(id), input);
export const task = id => services.query({moduleId: 'app.tasks', serviceId: 'task.get', majorVersion: 1}, {id});
export async function execute(id, input, confirmation) {
  const prepared = await services.prepare(ref(id), input);
  if (await ui.review(prepared.planId, confirmation)) return services.commit(prepared.planId);
}
export const completionCommand = (current, completed, zone, date, expectedUpdatedAt = current.updatedAt) => ({
  ref: {moduleId: 'app.tasks', serviceId: 'task.setCompleted', majorVersion: 1},
  input: {id: current.id, completed, expectedUpdatedAt, ...(completed ? {actualCompletedOn: date, completedTimezone: zone} : {})},
});
export async function setCompletion(current, completed, zone, expectedUpdatedAt = current.updatedAt, actualCompletedOn) {
  if ((await query('task.state', {id: current.id})).cancelled) throw Error('任务已取消，请先恢复任务');
  const prepared = await services.prepare({moduleId: 'app.tasks', serviceId: 'task.setCompleted', majorVersion: 1}, {
    id: current.id, completed, expectedUpdatedAt,
    ...(completed ? {actualCompletedOn: actualCompletedOn || await clock.today(zone), completedTimezone: zone} : {}),
  });
  if (await ui.review(prepared.planId)) return services.commit(prepared.planId);
}

export async function applyMove(event, a) {
  if (event.intent === 'insert') throw Error('插入顺延的可安排时段与搜索上限尚待确认；可通过详情精确调整时间');
  const proposal = event.intent === 'swap' && event.targetId
    ? {kind: 'swap', taskId: event.taskId || event.id, targetTaskId: event.targetId, timezone: a.timezone}
    : {kind: event.intent === 'resize' ? 'resize' : 'move', taskId: event.taskId || event.id, date: event.start.slice(0, 10), start: event.start.slice(11, 16), endDate: event.end.slice(0, 10), end: event.end.slice(11, 16), timezone: a.timezone,
      ...(event.intent === 'resize' ? {} : {preserveDuration: event.preserveDuration !== false}),
      ...(event.scope ? {scope: event.scope} : {})};
  if (event.expectedTasks) {
    proposal.expectedTasks = Object.fromEntries([proposal.taskId, proposal.targetTaskId].filter(id => id && event.expectedTasks[id]).map(id => [id, event.expectedTasks[id]]));
  }
  const preview = await query('operation.preview', proposal);
  if (!preview.confirmable) throw Error(preview.conflicts.join('；'));
  const allowOverdue = !!preview.overdue?.length;
  const confirmation = await moveConfirmation(preview, a.timezone, event.preserveDuration === false);
  return execute('operation.apply', {operationKey: await ids.new(), preview, allowOverdue}, confirmation);
}

// These labels describe the same validated preview used to prepare the frozen
// plan. The host owns confirmation, optional acknowledgement and final review;
// canceling the dialog never commits the prepared operation.
async function moveConfirmation(preview, zone, precise) {
  const instants = preview.changes.flatMap(c => [c.before.plannedStartAt, c.before.plannedEndAt,
    c.fields.plannedStartAt, c.fields.plannedEndAt]).filter(Boolean);
  const local = await clock.toLocalMany(instants.map(utc => ({utc, zone})));
  const times = new Map(instants.map((utc, i) => [utc, local[i]]));
  const label = (start, end) => {
    if (!start || !end) return '待安排';
    const a = times.get(start), b = times.get(end);
    return `${a.date} ${a.time} — ${a.date === b.date ? '' : b.date + ' '}${b.time}`;
  };
  const newTask = !preview.changes[0].before.plannedStartAt;
  const action = preview.kind === 'swap' ? '交换时间' : preview.kind === 'resize' ? '调整时长'
    : precise ? '调整时间' : newTask ? '安排任务' : '移动任务';
  const confirmLabel = preview.kind === 'swap' ? '确认交换' : preview.kind === 'resize' || precise ? '确认调整'
    : newTask ? '确认安排' : '确认移动';
  return {
    title: '确认' + action,
    message: preview.changes.map(c => `${c.before.title}\n原安排：${label(c.before.plannedStartAt, c.before.plannedEndAt)}\n调整为：${label(c.fields.plannedStartAt, c.fields.plannedEndAt)}\n时长${c.fields.estimatedMinutes}分钟`).join('\n\n')
      + '\n\n截止时间保持不变。',
    confirmLabel,
    ...(preview.overdue?.length ? {acknowledgement: `${preview.overdue.map(c => c.title).join('、')}的安排超出截止时间，我仍按此安排，保留原截止。`} : {}),
  };
}
