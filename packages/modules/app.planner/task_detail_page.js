import {ui, clock} from '@xudian/sdk';
import {text, button, row, checkbox, stamp, localDeadlineLabels} from './page_helpers.js';
import {query, task, execute, completionCommand, setCompletion, applyMove} from './task_actions.js';

const fullWidthFooter = child => ({type: 'column', spacing: 0, children: [child]});
const input = (key, label, value, options = {}) => ({
  type: 'input', key, text: label, value: value ?? '', onChangeEvent: {type: 'field', key}, ...options,
});
const temporal = (key, label, value, type = 'dateInput') => ({
  type, key, text: label, value: value || null, clearable: true, event: {type: 'field', key},
});
function savedPanel(state, message) {
  return {state: {}, clearForms: Object.keys(state.draft || {}), tree: text(message)};
}
async function utc(date, time, zone) {
  const value = await clock.toUtc({date, time, zone});
  if (value.status !== 'unique') throw Error('所选时间在当前时区不存在或有歧义，请重新选择');
  return value.instants[0];
}
async function deadline(d, zone) {
  if (d.dueTime && !d.dueDate) throw Error('请先选择截止日期');
  return {dueDate: d.dueDate || null, dueAt: d.dueDate && d.dueTime ? await utc(d.dueDate, d.dueTime, zone) : null, dueTimezone: d.dueDate ? zone : null};
}
function draft(state, forms, event) {
  state.draft = {...state.draft, ...forms};
  if (event?.type === 'field') state.draft[event.key] = event.value;
  return state.draft;
}

export async function renderTaskDetail(state, event, context, forms, a, options = {}) {
  const finish = async message => {
    if (!options.embedded) await ui.navigate('app.planner.home');
    return {...savedPanel(state, message), ...(options.embedded ? {completed: true} : {})};
  };
  const current = await task(context.taskId);
  if (!current || current.deletedAt) return {state, tree: text('任务已不可用，请关闭后刷新')};
  const status = await query('task.state', {id: current.id});
  const content = await query('task.content', {id: current.id});
  if (!state.original) {
    state.original = current;
    state.originalLocation = content.location || '';
    state.step = context.step || null;
    state.description = !!current.notes;
    state.time = !!current.dueAt;
    const due = current.dueAt ? await clock.toLocal({utc: current.dueAt, zone: current.dueTimezone}) : null;
    const start = current.plannedStartAt ? await clock.toLocal({utc: current.plannedStartAt, zone: a.timezone}) : null;
    const end = current.plannedEndAt ? await clock.toLocal({utc: current.plannedEndAt, zone: a.timezone}) : null;
    state.draft = {title: current.title, notes: current.notes || '', location: content.location || '', dueDate: current.dueDate, dueTime: due?.time || null,
      estimatedMinutes: current.estimatedMinutes ?? '', locked: !!current.locked, scheduleScope: 'only',
      startDate: start?.date || await clock.today(a.timezone), start: start?.time || '', endDate: end?.date || start?.date || await clock.today(a.timezone), end: end?.time || ''};
    state.originalDeadlineDraft = {dueDate: state.draft.dueDate, dueTime: state.draft.dueTime};
  }
  const d = draft(state, forms, event);
  try {
    if (status.cancelled && ['saveDetail', 'restoreDeadline', 'schedule'].includes(event?.type)) throw Error('任务已取消，请先恢复任务');
    if (event?.type === 'cancelTask' || event?.type === 'restoreTask') {
      const cancelled = event.type === 'cancelTask';
      if (await execute('task.setCancelled', {id: current.id, cancelled, expectedUpdatedAt: state.original.updatedAt}, {
        title: cancelled ? '取消任务' : '恢复任务',
        message: cancelled ? `取消“${current.title}”？\n任务和原安排会保留，取消后释放占用，可随时恢复。` : `恢复“${current.title}”？\n恢复后将按原来的安排继续执行。`,
        confirmLabel: cancelled ? '确认取消任务' : '恢复任务',
      })) { return finish(cancelled ? '任务已取消，记录已保留' : '任务已恢复'); }
    }
    if (event?.type === 'description') state.description = true;
    if (event?.type === 'time') state.time = true;
    if (event?.type === 'editTime') state.step = 'time';
    if (event?.type === 'back') state.step = null;
    if (event?.type === 'complete') {
      if (await setCompletion(current, !current.completedAt, a.timezone, state.original.updatedAt)) {
        return finish(current.completedAt ? '任务已重新打开' : '任务已完成，已记录完成时间');
      }
    }
    if (event?.type === 'completionDate' && current.completedAt) {
      const answer = await ui.dialog({title: '补记完成日期', fields: [{key: 'actualCompletedOn', label: '实际完成日期', type: 'date', value: current.actualCompletedOn || await clock.today(a.timezone)}]});
      if (answer && await setCompletion(current, true, current.completedTimezone || a.timezone, state.original.updatedAt, answer.actualCompletedOn)) {
        return finish('完成日期已更新');
      }
    }
    if (event?.type === 'saveDetail') {
      const zone = state.original.dueTimezone || a.timezone;
      const originalDeadline = state.originalDeadlineDraft;
      const deadlineChanged = !originalDeadline || (d.dueDate || null) !== (originalDeadline.dueDate || null) || (d.dueTime || null) !== (originalDeadline.dueTime || null);
      const changes = {};
      if ((d.location || '').trim() !== state.originalLocation) changes.location = (d.location || '').trim() || null;
      for (const key of ['title', 'notes', 'locked']) if ((d[key] ?? (key === 'locked' ? false : '')) !== (state.original[key] ?? (key === 'locked' ? false : ''))) changes[key] = d[key];
      const minutes = d.estimatedMinutes == null || d.estimatedMinutes === '' ? null : Number(d.estimatedMinutes);
      if (!state.original.plannedStartAt && minutes !== (state.original.estimatedMinutes ?? null)) changes.estimatedMinutes = minutes;
      if (deadlineChanged) Object.assign(changes, await deadline(d, zone));
      const saved = await execute('task.update', {id: current.id, expectedUpdatedAt: state.original.updatedAt, expectedValues: state.original,
        changes});
      if (saved) { return finish('任务已更新'); }
    }
    if (event?.type === 'restoreDeadline') {
      const saved = await execute('task.update', {id: current.id, expectedUpdatedAt: state.original.updatedAt, expectedValues: state.original, changes: state.original.initialDeadline});
      if (saved) { return finish('已恢复初始截止'); }
    }
    if (event?.type === 'schedule') {
      const saved = await applyMove({taskId: current.id, start: stamp(d.startDate, d.start), end: stamp(d.endDate, d.end), intent: 'move', preserveDuration: false, scope: d.scheduleScope || 'only', expectedTasks: {[current.id]: state.original}}, a);
      if (saved) { return finish('安排已更新'); }
    }
    delete state.error;
  } catch (e) { state.error = String(e); }
  const seriesContext = state.step === 'time' ? await query('series.taskContext', {taskId: current.id}) : null;
  const adjusted = (current.deadlineHistory || []).length > 0;
  const labelDeadline = await localDeadlineLabels([current.initialDeadline, ...(current.deadlineHistory || []).flatMap(h => [h.before, h.after])], a.timezone);
  const command = completionCommand(current, !current.completedAt, a.timezone, await clock.today(a.timezone), state.original.updatedAt);
  const completion = current.completedAt ? await clock.toLocal({utc: current.completedAt, zone: current.completedTimezone || a.timezone}) : null;
  const cancelledAt = status.cancelledAt ? await clock.toLocal({utc: status.cancelledAt, zone: a.timezone}) : null;
  const children = status.cancelled ? [
    {type: 'sectionHeader', title: current.title},
    {type: 'notice', text: `已取消 · ${cancelledAt.date} ${cancelledAt.time}`},
    text('任务和原安排已保留，原时段可重新安排。'),
    ...(current.notes ? [text(current.notes)] : []),
    ...(content.location ? [text('地点：' + content.location)] : []),
    ...(current.dueDate ? [text('截止：' + (await localDeadlineLabels([current], a.timezone))(current))] : []),
    ...(current.plannedStartAt ? [text(`原安排：${d.startDate} ${d.start}—${d.endDate !== d.startDate ? d.endDate + ' ' : ''}${d.end}`)] : [text('尚未安排时间')]),
  ] : current.completedAt ? [
    {type: 'sectionHeader', title: current.title},
    {type: 'notice', tone: 'success', text: `已完成 · ${completion.date} ${completion.time}`},
    ...(current.actualCompletedOn && current.actualCompletedOn !== completion.date ? [text('实际完成日期：' + current.actualCompletedOn)] : []),
    ...(current.notes ? [text(current.notes)] : []),
    ...(content.location ? [text('地点：' + content.location)] : []),
    ...(current.dueDate ? [text('截止：' + (await localDeadlineLabels([current], a.timezone))(current))] : []),
    ...(current.plannedStartAt ? [text(`原安排：${d.startDate} ${d.start}—${d.endDate !== d.startDate ? d.endDate + ' ' : ''}${d.end}`)] : []),
    button('补记完成日期', {type: 'completionDate'}, 'text'),
  ] : state.step === 'time' ? [
    {type: 'sectionHeader', title: current.title},
    text('安排时间 · 截止保持不变'),
    ...(current.locked ? [text('请先返回详情解除固定并保存，再调整起止或时长。')] : [
      temporal('startDate', '开始日期', d.startDate), temporal('start', '开始时间', d.start, 'timeInput'),
      temporal('endDate', '结束日期', d.endDate), temporal('end', '结束时间', d.end, 'timeInput'),
      ...(seriesContext?.seriesId ? seriesTimeControls(d, seriesContext) : []),
    ]),
  ] : [
    input('title', '任务简称', d.title),
    ...(state.description ? [input('notes', '详细描述（可留空）', d.notes, {multiline: true})] : [{type: 'row', children: [button('添加描述', {type: 'description'}, 'text')]}]),
    input('location', '地点（可留空）', d.location),
    temporal('dueDate', '截止日期（可留空）', d.dueDate),
    ...(state.time ? [temporal('dueTime', '截止时间（可留空）', d.dueTime, 'timeInput')] : [button('＋ 添加具体时间', {type: 'time'})]),
    ...(adjusted ? [text(`已调整 · 初始截止 ${labelDeadline(current.initialDeadline)}`), button('恢复初始截止', {type: 'restoreDeadline'}),
      {type: 'disclosure', text: '截止修改记录', children: current.deadlineHistory.map(h => text(`${h.changedAt}：${labelDeadline(h.before)} → ${labelDeadline(h.after)}`))}] : []),
    ...(current.plannedStartAt ? [row('安排起止时间', `${d.startDate} ${d.start}—${d.endDate !== d.startDate ? d.endDate + ' ' : ''}${d.end} · ${(Date.parse(current.plannedEndAt) - Date.parse(current.plannedStartAt)) / 60000}分钟`, {type: 'editTime'})] : [
      input('estimatedMinutes', '预计分钟', d.estimatedMinutes), row('精确安排', '设置开始与结束时间', {type: 'editTime'}),
    ]),
    ...(current.plannedStartAt ? [checkbox('locked', '固定时间', !!d.locked, {type: 'field', key: 'locked'})] : []),
    button('取消任务', {type: 'cancelTask'}, 'text'),
  ];
  if (state.error) children.push(text(state.error));
  return {state, header: {title: state.step === 'time' ? '编辑时间' : '任务详情', ...(state.step === 'time' ? {backEvent: {type: 'back'}} : {})}, tree: {type: 'column', key: 'planner:detail:' + current.id, children,
    ...(status.cancelled ? {footer: fullWidthFooter(button('恢复任务', {type: 'restoreTask'}, 'filled'))} : current.completedAt ? {footer: fullWidthFooter({...button('重新打开任务', {type: 'complete'}), command})} : state.step === 'time' ? (!current.locked ? {footer: fullWidthFooter(button('应用安排', {type: 'schedule'}, 'filled'))} : {}) : {footer: fullWidthFooter({type: 'column', children: [{...button('标记已完成', {type: 'complete'}, 'filled'), command}, button('保存修改', {type: 'saveDetail'})]})}),
  }};
}

function seriesTimeControls(d, context) {
  const interval = context.rules.interval, scope = d.scheduleScope || 'only';
  const delta = (a, b) => Math.round((Date.parse(a + 'T00:00:00Z') - Date.parse(b + 'T00:00:00Z')) / 86400000);
  const short = date => `${Number(date.slice(5, 7))}月${Number(date.slice(8))}日`;
  const before = context.previous ? delta(d.startDate, context.previous.date) : null;
  const after = context.next ? delta(context.next.date, scope === 'following' ? context.current.date : d.startDate) : null;
  const valid = [before, after].filter(value => value !== null).every(value => value >= interval.minDays && value <= interval.maxDays);
  const affected = context.following || [];
  return [
    {type: 'formSection', title: '调整范围', children: [
      {type: 'choiceCard', title: '仅本次', subtitle: '其他任务日期保持不变', selected: scope === 'only', event: {type: 'field', key: 'scheduleScope', value: 'only'}},
      {type: 'choiceCard', title: '本次及以后', subtitle: `联动后续${affected.length}次安排`, selected: scope === 'following', event: {type: 'field', key: 'scheduleScope', value: 'following'}},
      ...(scope === 'following' && affected.length ? [text('受影响：' + affected.map(item => short(item.date) + (item.manual ? '（已手动调整）' : '')).join('、'))] : []),
      ...(scope === 'following' && affected.some(item => item.manual) ? [{type: 'notice', tone: 'warning', text: '后续存在手动调整，请选择仅本次或逐项修改。'}] : []),
    ]},
    {type: 'formSection', title: '间隔检查', children: [
      ...(context.previous ? [row('距上一次（' + short(context.previous.date) + '）', before + '天')] : [text('这是首次安排')]),
      ...(context.next ? [row('距下一次（' + short(context.next.date) + '）', after + '天')] : [text('这是当前最后一次安排')]),
      {type: 'notice', tone: valid ? 'success' : 'warning', text: valid ? `符合${interval.minDays}～${interval.maxDays}天间隔` : '超出间隔规则，请调整日期或选择联动后续安排。'},
    ]},
  ];
}
