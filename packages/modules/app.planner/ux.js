import {services, ui, clock, ids} from '@xudian/sdk';
import {add, day} from './engine.js';

const ref = id => ({moduleId: 'app.planner', serviceId: 'planner.' + id, majorVersion: 1});
const query = (id, input = {}) => services.query(ref(id), input);
const task = id => services.query({moduleId: 'app.tasks', serviceId: 'task.get', majorVersion: 1}, {id});
async function execute(id, input, confirmation) {
  const prepared = await services.prepare(ref(id), input);
  if (await ui.review(prepared.planId, confirmation)) return services.commit(prepared.planId);
}
const text = value => ({type: 'text', text: value});
const button = (label, event, variant = 'tonal') => ({type: 'button', text: label, event, variant});
const fullWidthFooter = child => ({type: 'column', spacing: 0, children: [child]});
const row = (title, subtitle, event) => ({type: 'listTile', title, subtitle, event});
const keyedList = (scope, children) => ({
  type: 'keyedList', key: scope, scope,
  children: children.map((child, index) => ({...child,
    key: `${scope}:${child.key ? 'item:' + child.key : 'static:' + index}`,
  })),
});
const input = (key, label, value, options = {}) => ({
  type: 'input', key, text: label, value: value ?? '', onChangeEvent: {type: 'field', key}, ...options,
});
const temporal = (key, label, value, type = 'dateInput') => ({
  type, key, text: label, value: value || null, clearable: true, event: {type: 'field', key},
});
const checkbox = (key, label, value, event) => ({type: 'checkbox', key, text: label, value, event});
const panel = async (page, context = {}) => ui.panel('app.planner.' + page, {...context, editorSession: await ids.new()}, {adaptive: true, wide: 'center', heightFactor: page === 'quickAdd' ? .66 : page === 'taskDetail' ? .78 : .88});
const stamp = (date, time) => `${date}T${time}:00`;
const summary = t => t?.dueDate ? `${t.dueDate.slice(5).replace('-', '/')}截止` : '';
const duration = minutes => minutes >= 60 ? `耗时${Math.round(minutes / 6) / 10}h` : `耗时${minutes}min`;
const rangeLabel = (start, end) => start.slice(0, 7) === end.slice(0, 7)
  ? `${Number(start.slice(5, 7))}月${Number(start.slice(8))}日—${Number(end.slice(8))}日`
  : `${Number(start.slice(5, 7))}月${Number(start.slice(8))}日—${Number(end.slice(5, 7))}月${Number(end.slice(8))}日`;
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

const displayKey = 'board.displayHours';
const displayDefaults = {mode: 'auto', start: '08:00', end: '22:00'};
function displayMinute(value, allowMidnight = false) {
  if (allowMidnight && value === '24:00') return 1440;
  if (typeof value !== 'string' || !/^([01]\d|2[0-3]):[0-5]\d$/.test(value)) throw Error('时间请填写 HH:mm，结束时间可填 24:00');
  return Number(value.slice(0, 2)) * 60 + Number(value.slice(3));
}
function displayPreference(value) {
  try {
    if (!['auto', 'manual', 'full'].includes(value?.mode)) return {...displayDefaults};
    if (displayMinute(value.start) >= displayMinute(value.end, true)) return {...displayDefaults};
    return {mode: value.mode, start: value.start, end: value.end};
  } catch (_) { return {...displayDefaults}; }
}
function displayHours(preference, blocks, startDate, days) {
  let startMinute = 480, endMinute = 1320;
  if (preference.mode === 'full') { startMinute = 0; endMinute = 1440; }
  else if (preference.mode === 'manual') {
    startMinute = displayMinute(preference.start); endMinute = displayMinute(preference.end, true);
  } else {
    let first = 1440, last = 0;
    // Intersect each occupation with each displayed calendar day. Overnight
    // tasks include the late and early portions, including midnight boundaries.
    for (let i = 0; i < days; i++) {
      const date = add(startDate, i), next = add(date, 1);
      for (const block of blocks) {
        if (block.start >= next + 'T00:00:00' || block.end <= date + 'T00:00:00') continue;
        const from = block.start.slice(0, 10) < date ? 0 : displayMinute(block.start.slice(11, 16));
        const to = block.end.slice(0, 10) > date ? 1440 : displayMinute(block.end.slice(11, 16));
        first = Math.min(first, from); last = Math.max(last, to);
      }
    }
    if (last > first) {
      startMinute = Math.max(0, Math.floor((first - 60) / 60) * 60);
      endMinute = Math.min(1440, Math.ceil((last + 60) / 60) * 60);
    }
  }
  const label = minute => `${String(Math.floor(minute / 60)).padStart(2, '0')}:${String(minute % 60).padStart(2, '0')}`;
  return {startMinute, endMinute, initialMinute: preference.mode === 'full' ? 540 : startMinute,
    displayHoursLabel: `${{auto: '自动', manual: '手动', full: '全天'}[preference.mode]} ${label(startMinute)}–${label(endMinute)}`};
}

export async function renderPlanner({state = {}, event, context = {}, formValues = {}} = {}) {
  state = {...state};
  const a = await query('availability.get');
  const today = await clock.today(a.timezone);
  if (context.pageId === 'app.planner.quickAdd') return quickAdd(state, event, formValues, a);
  if (context.pageId === 'app.planner.taskDetail') return detail(state, event, context, formValues, a);
  state.displayHours = displayPreference(await ui.preferences.get(displayKey));
  state.startDate ||= today;
  state.days ||= 5;
  state.selected ||= [];
  state.candidateOffset = Number.isSafeInteger(state.candidateOffset) && state.candidateOffset >= 0 ? state.candidateOffset : 0;
  const candidateLimit = 100;
  try {
    if (event?.type === 'displayHours') {
      const previous = state.displayHours;
      const mode = await ui.dialog({title: '表格显示时段', fields: [{key: 'mode', type: 'select', label: '显示方式', value: previous.mode,
        presentation: 'grid', submitOnSelect: true, options: [
          {value: 'auto', label: '自动按任务'}, {value: 'manual', label: '手动设置'}, {value: 'full', label: '显示全天'},
        ]}]});
      if (mode && ['auto', 'manual', 'full'].includes(mode.mode)) {
        let next = {...previous, mode: mode.mode};
        if (mode.mode === 'manual') {
          const bounds = await ui.dialog({title: '手动显示时段', fields: [
            {key: 'start', type: 'time', label: '显示开始', value: previous.start},
            {key: 'end', type: 'text', label: '显示结束（HH:mm，可填 24:00）', value: previous.end},
          ]});
          if (!bounds) next = null;
          else {
            if (displayMinute(bounds.start) >= displayMinute(bounds.end, true)) throw Error('显示结束必须晚于开始；请设置同一天内的时段');
            next = {...next, start: bounds.start, end: bounds.end};
          }
        }
        if (next) state.displayHours = await ui.preferences.set(displayKey, next);
      }
    }
    if (event?.type === 'add') await panel('quickAdd');
    if (event?.type === 'detail') await panel('taskDetail', {taskId: event.id});
    if (event?.type === 'editTime') await panel('taskDetail', {taskId: event.id, step: 'time'});
    if (event?.type === 'tools') await panel('tools', {screen: event.screen || 'rules'});
    if (event?.type === 'today') { state.startDate = today; state.candidateOffset = 0; }
    if (event?.type === 'board') { state.history = false; state.chooseAuto = false; delete state.autoPreview; }
    if (event?.type === 'chooseAuto') { state.chooseAuto = true; delete state.autoPreview; }
    if (event?.type === 'occurrence') await panel('editor', {candidate: event.candidate});
    if (event?.type === 'onlyDeadline') { state.onlyDeadline = event.value ?? !state.onlyDeadline; state.candidateOffset = 0; }
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
      state.chooseAuto = false;
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
  // Summary pages do not need current board positions or candidate projection.
  // Undo and apply still validate current tasks in their command services.
  if (state.history) return plannerPage(state, await historyContent(state));
  if (state.autoPreview) return plannerPage(state, previewContent(state));
  const boardInput = () => ({startDate: state.startDate, days: state.days, candidateOffset: state.candidateOffset, candidateLimit, onlyDeadline: !!state.onlyDeadline});
  let data = await query('board.get', boardInput());
  if (state.candidateOffset > 0 && state.candidateOffset >= data.candidateTotal) {
    state.candidateOffset = Math.max(0, Math.floor((data.candidateTotal - 1) / candidateLimit) * candidateLimit);
    data = await query('board.get', boardInput());
  }
  const now = await clock.now(), daysByZone = {[a.timezone]: today};
  for (const t of data.tasks) if (t.dueDate && !t.dueAt && t.dueTimezone && !daysByZone[t.dueTimezone]) daysByZone[t.dueTimezone] = await clock.today(t.dueTimezone);
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
    preferredSummary: overdue(c.task) ? '已逾期' : summary(c.task) || duration(c.estimatedMinutes || a.defaultMinutes),
    deadlineSummary: summary(c.task), deadlineText: c.task?.dueDate ? '截止 ' + labelDeadline(c.task) : '', overdue: overdue(c.task),
    selected: state.selected.includes(c.id),
    selectEvent: {type: 'select', id: c.id},
    event: c.taskId ? {type: 'detail', id: c.taskId} : {type: 'occurrence', candidate: c},
    ...(c.taskId ? {editTimeEvent: {type: 'editTime', id: c.taskId}} : {}),
    ...(c.taskId ? {moveEvent: {type: 'move', taskId: c.taskId, candidateId: c.id, expectedTasks: expectedTasks[c.taskId] ? {[c.taskId]: expectedTasks[c.taskId]} : {}}} : {}),
  }));
  const blocks = [...data.scheduled, ...data.busy].map(t => ({
    id: t.taskId || t.id, title: t.title, start: stamp(t.startDate, t.start), end: stamp(t.endDate, t.end),
    durationMinutes: (Date.parse(t.plannedEndAt || t.endAt || stamp(t.endDate, t.end) + 'Z') - Date.parse(t.plannedStartAt || t.startAt || stamp(t.startDate, t.start) + 'Z')) / 60000,
    deadlineSummary: summary(t), deadlineText: t.dueDate ? '截止 ' + labelDeadline(t) : '', overdue: overdue(t),
    fixed: !!t.locked, readOnly: !!t.readOnly, sourceLabel: t.sourceLabel,
    ...(typeof t.location === 'string' && t.location.trim() ? {location: t.location.trim()} : {}),
    ...(typeof t.teacher === 'string' && t.teacher.trim() ? {teacher: t.teacher.trim()} : {}),
    event: t.readOnly ? {type: 'source', title: t.title, source: t.sourceLabel} : {type: 'detail', id: t.taskId || t.id},
    ...(!t.readOnly ? {editTimeEvent: {type: 'editTime', id: t.taskId || t.id}} : {}),
    ...(!t.readOnly && !t.locked ? {moveEvent: {type: 'move', taskId: t.taskId || t.id, expectedTasks: {[t.taskId || t.id]: {revisionToken: t.revisionToken}}}} : {}),
  }));
  if (event?.type === 'source') await ui.notify({message: `${event.title} · ${event.source}，请到来源修改`});
  const notices = [...data.warnings, ...data.conflicts];
  const selectedText = state.selected.length ? `已选 ${state.selected.length} 项${state.selected.some(id => !pending.some(c => c.id === id)) ? '（含其他页或筛选外任务）' : ''}` : '';
  let content;
  if (state.chooseAuto) {
    content = keyedList('planner:chooseAuto', [
      text('选择参与自动安排的任务；无截止任务仅在明确选中后参与。'),
      ...(state.error ? [text(state.error)] : []),
      ...pending.map(c => ({...checkbox(c.id, `${c.title} · ${summary(c.task) || duration(c.estimatedMinutes || a.defaultMinutes)}`, state.selected.includes(c.id), {type: 'select', id: c.id}), key: 'select:' + c.id})),
      ...(data.candidateTotal > candidateLimit ? [
        text(`候选 ${state.candidateOffset + 1}–${state.candidateOffset + pending.length} / ${data.candidateTotal}`),
        ...(state.candidateOffset ? [button('上一页候选', {type: 'candidatePage', offset: Math.max(0, state.candidateOffset - candidateLimit)})] : []),
        ...(data.hasMoreCandidates ? [button('下一页候选', {type: 'candidatePage', offset: state.candidateOffset + candidateLimit})] : []),
      ] : []),
      ...(selectedText ? [text(selectedText), button('清空选择', {type: 'clearSelection'})] : []),
      button(state.selected.length ? `预览安排（${state.selected.length}项）` : '预览有截止及规则任务', {type: 'auto'}, 'filled'),
    ]);
  } else content = {
    type: 'plannerBoard', key: 'planner:board', candidates, blocks,
    quickAdjustment: {taskModuleId: 'app.tasks', applyServiceId: 'planner.operation.apply', undoServiceId: 'planner.batch.undo'},
    previewQuery: {ref: ref('operation.inspect'), input: {timezone: a.timezone, expectedTasks}},
    previewIdentity: JSON.stringify([a.timezone, state.startDate, state.days, state.candidateOffset, state.onlyDeadline, expectedTasks, data.busy]),
    days: Array.from({length: state.days}, (_, i) => { const date = add(state.startDate, i); return {date, label: date.slice(5).replace('-', '/')}; }),
    options: {
      dashboard: true, minColumnWidth: 112, pixelsPerMinute: 1.1, candidateLabel: '待安排', candidateCount: data.candidateTotal,
      ...displayHours(state.displayHours, blocks, state.startDate, state.days), displayHoursEvent: {type: 'displayHours'},
      rangeLabel: rangeLabel(state.startDate, add(state.startDate, state.days - 1)), periodLabel: `${state.days}天`, today,
      onlyDeadline: !!state.onlyDeadline, filterEvent: {type: 'onlyDeadline'},
      rangeEvent: {type: 'period'}, periodEvent: {type: 'period'}, todayEvent: {type: 'today'},
      previousEvent: {type: 'browse', offset: -1}, nextEvent: {type: 'browse', offset: 1},
      editTimeEvent: {type: 'editTime'},
      ...(state.error ? {errorText: state.error} : {}),
      ...([...notices, selectedText].filter(Boolean).length ? {noticeText: [...notices, selectedText].filter(Boolean).join('；')} : {}),
      ...(state.moveIntent ? {retryEvent: {type: 'retryMove'}, dismissErrorEvent: {type: 'dismissMove'}, noticeText: state.error || '本次调整尚未应用，可重试或放弃'} : {}),
      ...(data.candidateTotal > candidateLimit ? {
        candidatePageLabel: `${state.candidateOffset + 1}–${state.candidateOffset + pending.length} / ${data.candidateTotal}`,
        ...(state.candidateOffset ? {candidatePreviousEvent: {type: 'candidatePage', offset: Math.max(0, state.candidateOffset - candidateLimit)}} : {}),
        ...(data.hasMoreCandidates ? {candidateNextEvent: {type: 'candidatePage', offset: state.candidateOffset + candidateLimit}} : {}),
      } : {}),
    },
  };
  return plannerPage(state, content);
}

function plannerPage(state, content) {
  const alternate = state.history || state.autoPreview || state.chooseAuto;
  return {state, header: {compact: true, title: state.history ? '操作历史' : state.autoPreview ? '安排预览' : state.chooseAuto ? '自动安排' : '任务规划',
    ...(alternate ? {backEvent: {type: 'board'}} : {}), actions: alternate ? [] : [
    {label: '操作历史', icon: 'history', presentation: 'inline', event: {type: 'history'}},
    {label: '新建', icon: 'add', variant: 'filled', presentation: 'inline', event: {type: 'add'}},
    {label: '自动安排', presentation: 'menu', event: {type: 'chooseAuto'}},
    {label: '表格显示时段', presentation: 'menu', event: {type: 'displayHours'}},
    {label: '规划规则', presentation: 'menu', event: {type: 'tools', screen: 'rules'}},
    {label: '规划设置', presentation: 'menu', event: {type: 'tools', screen: 'settings'}},
  ]}, tree: alternate ? content : {type: 'column', key: 'planner', underlapChrome: true, fillHeight: true, spacing: 0, children: [content]}};

}

async function historyContent(state) {
  const history = await query('operation.list');
  return keyedList('planner:history', [
    text('最近50次操作 · 后续修改或完成将阻止整体撤销'),
    ...(state.error ? [text(state.error)] : []),
    ...history.map(b => ({...row(`${b.createdAt} · ${b.changeCount}项`, b.undone ? '已撤销' : '点击撤销整次操作', b.undone ? undefined : {type: 'undo', id: b.id}), key: b.id})),
    ...(!history.length ? [text('暂无操作记录')] : []),
  ]);
}

function previewContent(state) {
  const p = state.autoPreview;
  return keyedList('planner:auto', [
    text(`建议预览 · ${p.assigned.length}项安排 · ${p.unassigned.length}项待安排`),
    ...(state.error ? [text(state.error)] : []),
    ...[...p.warnings, ...p.conflicts].map(text),
    ...p.assigned.map(c => ({...row(c.title, `${c.date} ${c.start}—${c.end}`), key: c.id})),
    ...p.unassigned.map(c => ({...row(c.title, c.reason, {type: 'occurrence', candidate: c}), key: c.id})),
    button('确认安排', {type: 'confirmAuto'}, 'filled'), button('返回图形规划', {type: 'dismissAuto'}),
  ]);
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
      + `\n\n时区：${zone}\n截止时间保持不变。`,
    confirmLabel,
    ...(preview.overdue?.length ? {acknowledgement: `${preview.overdue.map(c => c.title).join('、')}的安排超出截止时间，我仍按此安排，保留原截止。`} : {}),
  };
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
    text('耗时'),
    input('estimatedMinutes', '预计分钟', d.estimatedMinutes),
    text('保存任务后，再从图形规划发起安排。'),
  ] : [
    input('title', '任务简称', d.title),
    ...(state.description ? [input('notes', '详细描述（可留空）', d.notes, {multiline: true})] : [{type: 'row', children: [button('添加描述', {type: 'description'}, 'text')]}]),
    {type: 'row', layout: 'flex', children: [
      {...temporal('dueDate', '截止日期（可留空）', d.dueDate), flex: 1},
      ...(!state.time ? [button('＋ 时间', {type: 'time'}, 'text')] : []),
    ]},
    ...(state.time ? [temporal('dueTime', '截止时间（可留空）', d.dueTime, 'timeInput')] : []),
    row('添加规则', `${d.estimatedMinutes}分钟`, {type: 'rules'}),
  ];
  if (state.error) children.push(text(state.error));
  return {state, header: {title: state.step === 'rules' ? '任务规则' : '新建任务', ...(state.step === 'rules' ? {backEvent: {type: 'back'}} : {})}, tree: {type: 'column', key: 'planner:quickAdd', children, footer: fullWidthFooter(button('保存任务', {type: 'save'}, 'filled'))}};
}

async function detail(state, event, context, forms, a) {
  const current = await task(context.taskId);
  if (!current || current.deletedAt) return {state, tree: text('任务已不可用，请关闭后刷新')};
  if (!state.original) {
    state.original = current;
    state.step = context.step || null;
    state.description = !!current.notes;
    state.time = !!current.dueAt;
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
    if (event?.type === 'description') state.description = true;
    if (event?.type === 'time') state.time = true;
    if (event?.type === 'editTime') state.step = 'time';
    if (event?.type === 'back') state.step = null;
    if (event?.type === 'complete') {
      const answer = await ui.dialog({title: current.completedAt ? '撤销完成' : '完成任务', fields: [{key: 'completed', label: '已完成', type: 'boolean', value: !current.completedAt}, {key: 'actualCompletedOn', label: '实际完成日期', type: 'date', value: current.actualCompletedOn || await clock.today(a.timezone)}]});
      if (answer) {
        const prepared = await services.prepare({moduleId: 'app.tasks', serviceId: 'task.setCompleted', majorVersion: 1}, {id: current.id, completed: answer.completed,
          ...(answer.completed ? {actualCompletedOn: answer.actualCompletedOn, completedTimezone: a.timezone} : {}),
          expectedUpdatedAt: state.original.updatedAt});
        if (await ui.review(prepared.planId)) { await services.commit(prepared.planId); await ui.navigate('app.planner.home'); return savedPanel(state, '完成状态已更新'); }
      }
    }
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
  const children = state.step === 'time' ? [
    {type: 'sectionHeader', title: current.title},
    text(`安排时间 · ${a.timezone} · 截止保持不变`),
    ...(current.locked ? [text('请先返回详情解除固定并保存，再调整起止或时长。')] : [
      temporal('startDate', '开始日期', d.startDate), temporal('start', '开始时间', d.start, 'timeInput'),
      temporal('endDate', '结束日期', d.endDate), temporal('end', '结束时间', d.end, 'timeInput'),
    ]),
  ] : [
    input('title', '任务简称', d.title),
    ...(state.description ? [input('notes', '详细描述（可留空）', d.notes, {multiline: true})] : [{type: 'row', children: [button('添加描述', {type: 'description'}, 'text')]}]),
    temporal('dueDate', '截止日期（可留空）', d.dueDate),
    ...(state.time ? [temporal('dueTime', '截止时间（可留空）', d.dueTime, 'timeInput'), text(`截止时区：${state.original.dueTimezone || a.timezone}`)] : [button('＋ 添加具体时间', {type: 'time'})]),
    ...(adjusted ? [text(`已调整 · 初始截止 ${labelDeadline(current.initialDeadline)}`), button('恢复初始截止', {type: 'restoreDeadline'}),
      {type: 'disclosure', text: '截止修改记录', children: current.deadlineHistory.map(h => text(`${h.changedAt}：${labelDeadline(h.before)} → ${labelDeadline(h.after)}`))}] : []),
    ...(current.plannedStartAt ? [row('安排起止时间', `${d.startDate} ${d.start}—${d.endDate !== d.startDate ? d.endDate + ' ' : ''}${d.end} · ${(Date.parse(current.plannedEndAt) - Date.parse(current.plannedStartAt)) / 60000}分钟`, {type: 'editTime'})] : [
      input('estimatedMinutes', '预计分钟', d.estimatedMinutes), row('精确安排', '设置开始与结束时间', {type: 'editTime'}),
    ]),
    checkbox('locked', '固定时间', !!d.locked, {type: 'field', key: 'locked'}),
    row(current.completedAt ? '撤销完成／补记日期' : '完成任务', '完成状态单独记录，不改变截止和安排', {type: 'complete'}),
  ];
  if (state.error) children.push(text(state.error));
  return {state, header: {title: state.step === 'time' ? '编辑时间' : '任务详情', ...(state.step === 'time' ? {backEvent: {type: 'back'}} : {})}, tree: {type: 'column', key: 'planner:detail:' + current.id, children,
    ...(state.step === 'time' ? (!current.locked ? {footer: fullWidthFooter(button('应用安排', {type: 'schedule'}, 'filled'))} : {}) : {footer: fullWidthFooter(button('保存修改', {type: 'saveDetail'}, 'filled'))}),
  }};
}
