import {services, ui, clock, ids} from '@xudian/sdk';
import {add, day} from './engine.js';

const ref = id => ({moduleId: 'app.planner', serviceId: 'planner.' + id, majorVersion: 1});
const query = (id, input = {}) => services.query(ref(id), input);
const task = id => services.query({moduleId: 'app.tasks', serviceId: 'task.get', majorVersion: 1}, {id});
async function execute(id, input) {
  const prepared = await services.prepare(ref(id), input);
  if (await ui.review(prepared.planId)) return services.commit(prepared.planId);
}
const text = value => ({type: 'text', text: value});
const button = (label, event) => ({type: 'button', text: label, event});
const row = (title, subtitle, event) => ({type: 'listTile', title, subtitle, event});
const input = (key, label, value, options = {}) => ({
  type: 'input', key, text: label, value: value ?? '', onChangeEvent: {type: 'field', key}, ...options,
});
const temporal = (key, label, value, type = 'dateInput') => ({
  type, key, text: label, value: value || null, clearable: true, event: {type: 'field', key},
});
const checkbox = (key, label, value, event) => ({type: 'checkbox', key, text: label, value, event});
const panel = async (page, context = {}) => ui.panel('app.planner.' + page, {...context, editorSession: await ids.new()}, {adaptive: true, wide: 'center'});
const stamp = (date, time) => `${date}T${time}:00`;
const summary = t => t?.dueDate ? `截${t.dueDate.slice(5).replace('-', '/')}` : '';
const deadlineLabel = t => t?.dueAt ? `${t.dueAt}（UTC）` : t?.dueDate ? `${t.dueDate}${t.dueTimezone ? '（' + t.dueTimezone + '）' : ''}` : '未设置';
async function localDeadlineLabels(values, defaultZone) {
  const exact = values.filter(t => t?.dueAt), labels = new Map();
  for (let i = 0; i < exact.length; i += 256) {
    const items = exact.slice(i, i + 256);
    const times = await clock.toLocalMany(items.map(t => ({utc: t.dueAt, zone: t.dueTimezone || defaultZone})));
    items.forEach((t, index) => labels.set(t, `${times[index].date} ${times[index].time}（${t.dueTimezone || defaultZone}）`));
  }
  return t => labels.get(t) || deadlineLabel(t);
}
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

export async function renderPlanner({state = {}, event, context = {}, formValues = {}} = {}) {
  state = {...state};
  const a = await query('availability.get');
  const today = await clock.today(a.timezone);
  if (context.pageId === 'app.planner.quickAdd') return quickAdd(state, event, formValues, a);
  if (context.pageId === 'app.planner.taskDetail') return detail(state, event, context, formValues, a);
  state.startDate ||= today;
  state.days ||= 5;
  state.selected ||= [];
  state.candidateOffset = Number.isSafeInteger(state.candidateOffset) && state.candidateOffset >= 0 ? state.candidateOffset : 0;
  const candidateLimit = 100;
  try {
    if (event?.type === 'add') await panel('quickAdd');
    if (event?.type === 'detail') await panel('taskDetail', {taskId: event.id});
    if (event?.type === 'occurrence') await panel('editor', {candidate: event.candidate});
    if (event?.type === 'onlyDeadline') { state.onlyDeadline = event.value; state.candidateOffset = 0; }
    if (event?.type === 'select') {
      const selected = event.value ? [...new Set([...state.selected, event.id])] : state.selected.filter(id => id !== event.id);
      if (selected.length > 200) throw Error('每次最多选择200项，请先安排或清空选择');
      state.selected = selected;
    }
    if (event?.type === 'clearSelection') state.selected = [];
    if (event?.type === 'candidatePage') {
      const offset = Number(event.offset);
      if (Number.isSafeInteger(offset) && offset >= 0) state.candidateOffset = offset;
    }
    if (event?.type === 'period') {
      const v = await ui.dialog({title: '图形显示范围', fields: [
        {key: 'startDate', label: '开始日期', type: 'date', value: state.startDate},
        {key: 'days', label: '天数（1–28）', type: 'number', value: state.days},
      ]});
      if (v) {
        if (!Number.isInteger(Number(v.days)) || Number(v.days) < 1 || Number(v.days) > 28) throw Error('请选择1至28天');
        day(v.startDate);
        state.startDate = v.startDate; state.days = Number(v.days); state.candidateOffset = 0;
      }
    }
    if (event?.type === 'browse') { state.startDate = add(state.startDate, event.offset * state.days); state.candidateOffset = 0; }
    if (event?.type === 'history') state.history = !state.history;
    if (event?.type === 'undo') await execute('batch.undo', {id: event.id});
    if (event?.type === 'auto') {
      state.autoPreview = await query('plan.preview', {startDate: state.startDate, days: state.days, ...(state.selected.length ? {selectedIds: state.selected} : {})});
      state.autoKey = await ids.new();
    }
    if (event?.type === 'confirmAuto' && state.autoPreview) {
      const saved = await execute('batch.apply', {batchKey: state.autoKey, preview: state.autoPreview});
      if (saved) { delete state.autoPreview; state.selected = []; }
    }
    if (event?.type === 'dismissAuto') delete state.autoPreview;
    if (event?.type === 'move') {
      // Keep the requested position after a validation failure so it can be retried.
      state.moveIntent = {...event, expectedTasks: {...event.expectedTasks,
        ...(event.targetId && state.boardVersions?.[event.targetId] ? {[event.targetId]: state.boardVersions[event.targetId]} : {})}};
      if (await applyMove(state.moveIntent, a)) delete state.moveIntent;
    }
    if (event?.type === 'retryMove' && state.moveIntent) { if (await applyMove(state.moveIntent, a)) delete state.moveIntent; }
    if (event?.type === 'dismissMove') delete state.moveIntent;
    delete state.error;
  } catch (e) { state.error = String(e); }
  const boardInput = () => ({startDate: state.startDate, days: state.days, candidateOffset: state.candidateOffset, candidateLimit, onlyDeadline: !!state.onlyDeadline});
  let data = await query('board.get', boardInput());
  if (state.candidateOffset > 0 && state.candidateOffset >= data.candidateTotal) {
    state.candidateOffset = Math.max(0, Math.floor((data.candidateTotal - 1) / candidateLimit) * candidateLimit);
    data = await query('board.get', boardInput());
  }
  const now = await clock.now(), daysByZone = {[a.timezone]: today};
  for (const t of data.tasks) if (t.dueTimezone && !daysByZone[t.dueTimezone]) daysByZone[t.dueTimezone] = await clock.today(t.dueTimezone);
  const overdue = t => !!t?.dueDate && (t.dueAt ? Date.parse(t.dueAt) < Date.parse(now) : t.dueDate < daysByZone[t.dueTimezone || a.timezone]);
  const labelDeadline = await localDeadlineLabels([...data.candidates.map(c => c.task), ...data.scheduled], a.timezone);
  const expectedTasks = Object.fromEntries(data.tasks.filter(t => t.revisionToken).map(t => [t.id, {revisionToken: t.revisionToken}]));
  state.boardVersions = expectedTasks;
  const pending = data.candidates.filter(c => !c.task?.plannedStartAt && ['pending', 'overdue'].includes(c.status));
  // Selections intentionally survive page and filter changes. Final planning
  // validates every selected ID, including items outside this visible page.
  if (event?.type === 'move' && !state.moveIntent) state.selected = state.selected.filter(id => id !== event.candidateId);
  const candidates = pending.filter(c => !state.onlyDeadline || c.task?.dueDate).map(c => ({
    id: c.taskId || c.id, title: c.title, durationMinutes: c.estimatedMinutes || a.defaultMinutes,
    deadlineSummary: summary(c.task), deadlineText: c.task?.dueDate ? '截止 ' + labelDeadline(c.task) : '', overdue: overdue(c.task),
    selected: state.selected.includes(c.id),
    selectEvent: {type: 'select', id: c.id},
    event: c.taskId ? {type: 'detail', id: c.taskId} : {type: 'occurrence', candidate: c},
    ...(c.taskId ? {moveEvent: {type: 'move', taskId: c.taskId, candidateId: c.id, expectedTasks: expectedTasks[c.taskId] ? {[c.taskId]: expectedTasks[c.taskId]} : {}}} : {}),
  }));
  const blocks = [...data.scheduled, ...data.busy].map(t => ({
    id: t.taskId || t.id, title: t.title, start: stamp(t.startDate, t.start), end: stamp(t.endDate, t.end),
    durationMinutes: (Date.parse(t.plannedEndAt || t.endAt || stamp(t.endDate, t.end) + 'Z') - Date.parse(t.plannedStartAt || t.startAt || stamp(t.startDate, t.start) + 'Z')) / 60000,
    deadlineSummary: summary(t), deadlineText: t.dueDate ? '截止 ' + labelDeadline(t) : '', overdue: overdue(t),
    fixed: !!t.locked, readOnly: !!t.readOnly, sourceLabel: t.sourceLabel,
    event: t.readOnly ? {type: 'source', title: t.title, source: t.sourceLabel} : {type: 'detail', id: t.taskId || t.id},
    ...(!t.readOnly && !t.locked ? {moveEvent: {type: 'move', taskId: t.taskId || t.id, expectedTasks: {[t.taskId || t.id]: {revisionToken: t.revisionToken}}}} : {}),
  }));
  if (event?.type === 'source') await ui.notify({message: `${event.title} · ${event.source}，请到来源修改`});
  const children = [
    {type: 'row', children: [button('上一段', {type: 'browse', offset: -1}), button(`${state.startDate} · ${state.days}天`, {type: 'period'}), button('下一段', {type: 'browse', offset: 1})]},
    checkbox('onlyDeadline', '仅有截止', !!state.onlyDeadline, {type: 'onlyDeadline'}),
  ];
  if (data.candidateTotal > candidateLimit) children.push({type: 'row', children: [
    {...button('上一页候选', {type: 'candidatePage', offset: state.candidateOffset - candidateLimit}), disabled: state.candidateOffset === 0},
    text(`候选 ${state.candidateOffset + 1}–${state.candidateOffset + pending.length} / ${data.candidateTotal}`),
    {...button('下一页候选', {type: 'candidatePage', offset: state.candidateOffset + candidateLimit}), disabled: !data.hasMoreCandidates},
  ]});
  if (state.selected.length) children.push({type: 'row', children: [
    text(`已选 ${state.selected.length} 项${state.selected.some(id => !pending.some(c => c.id === id)) ? '（含其他页或筛选外任务）' : ''}`),
    button('清空选择', {type: 'clearSelection'}),
  ]});
  if (state.error) children.push(text(state.error));
  if (state.moveIntent) children.push({type: 'row', children: [button('重试上次调整', {type: 'retryMove'}), button('放弃这次调整', {type: 'dismissMove'})]});
  const notices = [...data.warnings, ...data.conflicts];
  if (notices.length) children.push(text(notices.join('；')));
  if (state.history) {
    const history = await query('operation.list');
    children.push({type: 'keyedList', key: 'planner:history', children: [
      text('最近50次操作 · 后续修改或完成将阻止整体撤销'),
      ...history.map(b => ({...row(`${b.createdAt} · ${b.changeCount}项`, b.undone ? '已撤销' : '点击撤销整次操作', b.undone ? undefined : {type: 'undo', id: b.id}), key: b.id})),
      ...(!history.length ? [text('暂无操作记录')] : []),
    ]});
  } else if (state.autoPreview) {
    const p = state.autoPreview;
    children.push({type: 'keyedList', key: 'planner:auto', children: [
      text(`建议预览 · ${p.assigned.length}项安排 · ${p.unassigned.length}项待安排`),
      ...[...p.warnings, ...p.conflicts].map(text),
      ...p.assigned.map(c => ({...row(c.title, `${c.date} ${c.start}—${c.end}`), key: c.id})),
      ...p.unassigned.map(c => ({...row(c.title, c.reason), key: c.id})),
      button('确认安排', {type: 'confirmAuto'}), button('返回图形规划', {type: 'dismissAuto'}),
    ]});
  } else children.push({
    type: 'plannerBoard', key: 'planner:board', candidates, blocks,
    previewQuery: {ref: ref('operation.inspect'), input: {timezone: a.timezone, expectedTasks}},
    previewIdentity: JSON.stringify([a.timezone, state.startDate, state.days, state.candidateOffset, state.onlyDeadline, expectedTasks, data.busy]),
    days: Array.from({length: state.days}, (_, i) => { const date = add(state.startDate, i); return {date, label: date.slice(5).replace('-', '/')}; }),
    options: {minColumnWidth: 112, candidateLabel: '待安排'},
  });
  return {state, header: {title: '任务规划', actions: [
    {label: '操作历史', event: {type: 'history'}},
    {label: '规划设置与持续规则', event: {type: 'legacy'}},
  ]}, tree: {type: 'column', key: 'planner', fillHeight: true, spacing: 4, children,
    footer: {type: 'row', children: [button('添加任务', {type: 'add'}), button(state.selected.length ? `统一安排（${state.selected.length}）` : '统一安排', {type: 'auto'})]},
  }};
}

async function applyMove(event, a) {
  if (event.intent === 'insert') throw Error('插入顺延的可安排时段与搜索上限尚待确认；可通过详情精确调整时间');
  const proposal = event.intent === 'swap' && event.targetId
    ? {kind: 'swap', taskId: event.taskId || event.id, targetTaskId: event.targetId, timezone: a.timezone}
    : {kind: event.intent === 'resize' ? 'resize' : 'move', taskId: event.taskId || event.id, date: event.start.slice(0, 10), start: event.start.slice(11, 16), endDate: event.end.slice(0, 10), end: event.end.slice(11, 16), timezone: a.timezone,
      ...(event.intent === 'resize' ? {} : {preserveDuration: event.preserveDuration !== false})};
  if (event.expectedTasks) {
    proposal.expectedTasks = Object.fromEntries([proposal.taskId, proposal.targetTaskId].filter(id => id && event.expectedTasks[id]).map(id => [id, event.expectedTasks[id]]));
  }
  const preview = await query('operation.preview', proposal);
  if (!preview.confirmable) throw Error(preview.conflicts.join('；'));
  let allowOverdue = false;
  if (preview.overdue?.length) {
    const answer = await ui.dialog({title: '安排超出截止时间', fields: [{key: 'allow', label: `${preview.overdue.map(x => x.title || x).join('、')}：仍按此安排，并保留原截止`, type: 'boolean', value: false}]});
    if (!answer?.allow) return;
    allowOverdue = true;
  }
  return execute('operation.apply', {operationKey: await ids.new(), preview, allowOverdue});
}

async function quickAdd(state, event, forms, a) {
  state.draft ||= {title: '', notes: '', dueDate: null, dueTime: null, estimatedMinutes: a.defaultMinutes};
  const d = draft(state, forms, event);
  try {
    if (event?.type === 'description') state.description = true;
    if (event?.type === 'time') state.time = true;
    if (event?.type === 'rules') state.step = 'rules';
    if (event?.type === 'back') state.step = null;
    if (event?.type === 'save') {
      const saved = await execute('task.create', {title: d.title, notes: d.notes || '', ...(await deadline(d, a.timezone)), estimatedMinutes: Number(d.estimatedMinutes)});
      if (saved) { await ui.navigate('app.planner.home'); return savedPanel(state, '任务已保存'); }
    }
    delete state.error;
  } catch (e) { state.error = String(e); }
  const children = state.step === 'rules' ? [
    button('返回任务', {type: 'back'}), text('耗时'),
    input('estimatedMinutes', '预计分钟', d.estimatedMinutes),
    text('保存任务后，再从图形规划发起安排。'),
  ] : [
    input('title', '任务简称', d.title),
    ...(state.description ? [input('notes', '详细描述（可留空）', d.notes, {multiline: true})] : [button('添加描述', {type: 'description'})]),
    temporal('dueDate', '截止日期（可留空）', d.dueDate),
    ...(state.time ? [temporal('dueTime', '截止时间（可留空）', d.dueTime, 'timeInput')] : [button('＋ 添加具体时间', {type: 'time'})]),
    button(`添加规则 · ${d.estimatedMinutes}分钟`, {type: 'rules'}),
  ];
  if (state.error) children.push(text(state.error));
  return {state, tree: {type: 'column', key: 'planner:quickAdd', children, footer: button('保存任务', {type: 'save'})}};
}

async function detail(state, event, context, forms, a) {
  const current = await task(context.taskId);
  if (!current || current.deletedAt) return {state, tree: text('任务已不可用，请关闭后刷新')};
  if (!state.original) {
    state.original = current;
    const due = current.dueAt ? await clock.toLocal({utc: current.dueAt, zone: current.dueTimezone}) : null;
    const start = current.plannedStartAt ? await clock.toLocal({utc: current.plannedStartAt, zone: a.timezone}) : null;
    const end = current.plannedEndAt ? await clock.toLocal({utc: current.plannedEndAt, zone: a.timezone}) : null;
    state.draft = {title: current.title, notes: current.notes || '', dueDate: current.dueDate, dueTime: due?.time || null,
      estimatedMinutes: current.estimatedMinutes || a.defaultMinutes, locked: !!current.locked,
      startDate: start?.date || await clock.today(a.timezone), start: start?.time || '', endDate: end?.date || start?.date || await clock.today(a.timezone), end: end?.time || ''};
    state.originalDeadlineDraft = {dueDate: state.draft.dueDate, dueTime: state.draft.dueTime};
  }
  const d = draft(state, forms, event);
  try {
    if (event?.type === 'saveDetail') {
      const zone = state.original.dueTimezone || a.timezone;
      const originalDeadline = state.originalDeadlineDraft;
      const deadlineChanged = !originalDeadline || (d.dueDate || null) !== (originalDeadline.dueDate || null) || (d.dueTime || null) !== (originalDeadline.dueTime || null);
      const changes = {};
      for (const key of ['title', 'notes', 'locked']) if ((d[key] ?? (key === 'locked' ? false : '')) !== (state.original[key] ?? (key === 'locked' ? false : ''))) changes[key] = d[key];
      if (!state.original.plannedStartAt && Number(d.estimatedMinutes) !== Number(state.original.estimatedMinutes || a.defaultMinutes)) changes.estimatedMinutes = Number(d.estimatedMinutes);
      if (deadlineChanged) Object.assign(changes, await deadline(d, zone));
      const saved = await execute('task.update', {id: current.id, expectedUpdatedAt: state.original.updatedAt, expectedValues: state.original,
        changes});
      if (saved) { await ui.navigate('app.planner.home'); return savedPanel(state, '任务已更新'); }
    }
    if (event?.type === 'restoreDeadline') {
      const saved = await execute('task.update', {id: current.id, expectedUpdatedAt: state.original.updatedAt, expectedValues: state.original, changes: state.original.initialDeadline});
      if (saved) { await ui.navigate('app.planner.home'); return savedPanel(state, '已恢复初始截止'); }
    }
    if (event?.type === 'schedule') {
      const saved = await applyMove({taskId: current.id, start: stamp(d.startDate, d.start), end: stamp(d.endDate, d.end), intent: 'move', preserveDuration: false, expectedTasks: {[current.id]: state.original}}, a);
      if (saved) { await ui.navigate('app.planner.home'); return savedPanel(state, '安排已更新'); }
    }
    delete state.error;
  } catch (e) { state.error = String(e); }
  const adjusted = (current.deadlineHistory || []).length > 0;
  const labelDeadline = await localDeadlineLabels([current.initialDeadline, ...(current.deadlineHistory || []).flatMap(h => [h.before, h.after])], a.timezone);
  const children = [
    input('title', '任务简称', d.title), input('notes', '详细描述', d.notes, {multiline: true}),
    temporal('dueDate', '截止日期', d.dueDate), temporal('dueTime', '截止时间（可留空）', d.dueTime, 'timeInput'),
    text(`截止时区：${state.original.dueTimezone || a.timezone}`),
    ...(adjusted ? [text(`已调整 · 初始截止 ${labelDeadline(current.initialDeadline)}`), button('恢复初始截止', {type: 'restoreDeadline'}),
      {type: 'disclosure', text: '截止修改记录', children: current.deadlineHistory.map(h => text(`${h.changedAt}：${labelDeadline(h.before)} → ${labelDeadline(h.after)}`))}] : []),
    ...(current.plannedStartAt ? [text(`已安排 ${(Date.parse(current.plannedEndAt) - Date.parse(current.plannedStartAt)) / 60000}分钟 · 调整结束时间可修改时长`)] : [input('estimatedMinutes', '预计分钟', d.estimatedMinutes)]),
    checkbox('locked', '固定时间', !!d.locked, {type: 'field', key: 'locked'}),
    button('保存修改', {type: 'saveDetail'}),
    {type: 'sectionHeader', title: '安排起止时间'},
    ...(current.locked ? [text('请先解除固定并保存，再调整起止或时长。')] : [
      temporal('startDate', '开始日期', d.startDate), temporal('start', '开始时间', d.start, 'timeInput'),
      temporal('endDate', '结束日期', d.endDate), temporal('end', '结束时间', d.end, 'timeInput'),
      button('应用安排', {type: 'schedule'}),
    ]),
    ...(state.error ? [text(state.error)] : []),
  ];
  return {state, tree: {type: 'column', key: 'planner:detail:' + current.id, children}};
}
