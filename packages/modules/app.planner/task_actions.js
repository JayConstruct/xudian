import {services, ui, clock, ids, data} from '@xudian/sdk';

import {monthDay} from './page_helpers.js';
import {weekday} from './engine.js';

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

const dayLabel = date => monthDay(date) + ' 周' + '一二三四五六日'[weekday(date) - 1];
const timeRange = (a, b) => a.time + '–' + (a.date === b.date ? '' : monthDay(b.date) + ' ') + b.time;
const placement = (a, b) => a && b ? monthDay(a.date) + ' ' + timeRange(a, b) : '待安排';

async function localTimes(instants, zone) {
  const keys = [...new Set(instants.filter(Boolean))];
  const local = keys.length ? await clock.toLocalMany(keys.map(utc => ({utc, zone}))) : [];
  return new Map(keys.map((utc, i) => [utc, local[i]]));
}

async function moveConfirmation(preview, zone, precise) {
  const first = preview.changes[0], swap = preview.kind === 'swap';
  const times = await localTimes(preview.changes.flatMap(c => [c.before.plannedStartAt,
    c.before.plannedEndAt, c.fields.plannedStartAt, c.fields.plannedEndAt, c.before.dueAt]), zone);
  const newTask = !first.before.plannedStartAt;
  const action = swap ? '交换时间' : preview.kind === 'resize' ? '调整时长'
    : precise ? '调整时间' : newTask ? '安排任务' : '移动任务';
  const items = [], notices = preview.warnings.map(warning =>
    warning === '所选开始时间已过去，仍可保存安排。' ? '这个时段已过去，仍可保存安排。' : warning);
  for (const c of preview.changes) {
    const a = times.get(c.fields.plannedStartAt), b = times.get(c.fields.plannedEndAt);
    const old = placement(times.get(c.before.plannedStartAt), times.get(c.before.plannedEndAt));
    if (swap) {
      items.push({title: c.before.title.slice(0, 300), subtitle: old + ' → ' + placement(a, b)});
    } else {
      if (!newTask) items.push({title: '原安排', subtitle: old});
      items.push({title: '日期', subtitle: dayLabel(a.date)}, {title: '时间', subtitle: timeRange(a, b)});
    }
    if (preview.overdue?.some(task => task.taskId === c.taskId)) {
      const due = times.get(c.before.dueAt);
      items.push({title: '任务截止', subtitle: due ? monthDay(due.date) + ' ' + due.time : monthDay(c.before.dueDate)});
      const minutes = due ? Math.ceil((Date.parse(c.fields.plannedEndAt) - Date.parse(c.before.dueAt)) / 60000) : 0;
      const delay = minutes % 60 === 0 ? (minutes / 60) + ' 小时' : minutes + ' 分钟';
      notices.push((swap ? c.before.title + '的安排' : '安排') + (due ? '比任务截止时间晚 ' + delay + '。' : '超过任务截止日期。'));
    }
  }
  return {title: '确认' + action, section: '本次安排', summaryOnly: true, items,
    subject: swap ? '交换两项任务' : first.before.title.slice(0, 120),
    message: swap ? '2 项任务' : (newTask ? '待安排' : '已安排') + ' · ' + first.fields.estimatedMinutes + ' 分钟',
    icon: 'clipboard', ...(notices.length ? {notice: notices.join('\n').slice(0, 2000)} : {}),
    confirmLabel: preview.overdue?.length ? '仍然安排' : swap ? '确认交换' : precise || preview.kind === 'resize' ? '确认调整' : newTask ? '确认安排' : '确认移动'};
}

export async function undoBatch(id, zone) {
  const batch = await data.get('batches', id);
  const changes = batch?.changes || [];
  if (!changes.length || !['move', 'resize', 'swap', 'plan'].includes(batch.kind || 'plan')) {
    return execute('batch.undo', {id});
  }
  const single = changes.length === 1, shown = changes.slice(0, 39);
  const times = await localTimes(shown.flatMap(c => [c.before?.plannedStartAt, c.before?.plannedEndAt,
    c.after?.plannedStartAt, c.after?.plannedEndAt]), zone);
  const label = task => task ? placement(times.get(task.plannedStartAt), times.get(task.plannedEndAt)) : '移除本次创建的任务';
  const first = changes[0].after || changes[0].before;
  const items = single ? [{title: '当前安排', subtitle: label(changes[0].after)}, {title: '撤销后', subtitle: label(changes[0].before)}]
    : shown.map(c => ({title: (c.after || c.before).title.slice(0, 300), subtitle: label(c.after) + ' → ' + label(c.before)}));
  if (changes.length > shown.length) items.push({title: '其他任务', subtitle: (changes.length - shown.length) + ' 项'});
  return execute('batch.undo', {id}, {title: '撤销这次安排？', section: '安排变化', icon: 'history',
    summaryOnly: true, items, subject: single ? first.title.slice(0, 120) : '批量安排',
    message: single && first.estimatedMinutes ? first.estimatedMinutes + ' 分钟' : changes.length + ' 项任务', confirmLabel: '确认撤销'});
}
