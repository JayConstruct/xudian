import {data, ui, clock, ids} from '@xudian/sdk';
import {add, day} from './engine.js';
import {renderCreation} from './creation.js';
import {plannerEditor, quickAdjustmentContract} from './presentation.js';
import {renderTaskDetail} from './task_detail_page.js';
import {text, button, row, checkbox, stamp, localDeadlineLabels} from './page_helpers.js';
import {ref, query, task, execute, completionCommand, setCompletion, applyMove} from './task_actions.js';

const keyedList = (scope, children) => ({
  type: 'keyedList', key: scope, scope,
  children: children.map((child, index) => ({...child,
    key: `${scope}:${child.key ? 'item:' + child.key : 'static:' + index}`,
  })),
});
const panel = async (page, context = {}) => ui.panel('app.planner.' + page, {...context, editorSession: await ids.new()}, {adaptive: true, wide: 'center', heightFactor: page === 'quickAdd' ? .94 : page === 'taskDetail' ? .78 : .88});
const summary = t => t?.dueDate ? `${t.dueDate.slice(5).replace('-', '/')}截止` : '';
const duration = minutes => minutes >= 60 ? `耗时${Math.round(minutes / 6) / 10}h` : `耗时${minutes}min`;
const rangeLabel = (start, end) => start.slice(0, 7) === end.slice(0, 7)
  ? `${Number(start.slice(5, 7))}月${Number(start.slice(8))}日—${Number(end.slice(8))}日`
  : `${Number(start.slice(5, 7))}月${Number(start.slice(8))}日—${Number(end.slice(5, 7))}月${Number(end.slice(8))}日`;

const displayKey = 'board.displayHours';
const displayDefaults = {mode: 'auto', start: '08:00', end: '22:00'};
const zoomKey = 'board.zoom';
const pinchKey = 'board.pinchZoom';
const detailsKey = 'board.details';
const detailsDefaults = {courseLocation: true, courseTeacher: true, location: true, teacher: true, source: true, gaps: true};
const detailsPreference = value => Object.fromEntries(Object.entries(detailsDefaults).map(([key, fallback]) => [key, typeof value?.[key] === 'boolean' ? value[key] : fallback]));
const viewportKey = 'board.viewport';
const visibleDayCounts = [1, 3, 5, 7];
function timelineRange(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw Error('时间轴加载范围无效');
  const startDate = day(value.startDate);
  if (!Number.isInteger(value.days) || value.days < 1 || value.days > 28) throw Error('时间轴加载天数需在1至28之间');
  day(add(startDate, value.days - 1));
  return {startDate, days: value.days};
}
function viewportPreference(value) {
  try {
    day(value.startDate);
    if (!visibleDayCounts.includes(value.days)) return {};
    if (value.selectedDate) day(value.selectedDate);
    return value;
  } catch (_) { return {}; }
}
const saveViewport = state => ui.preferences.set(viewportKey, {startDate: state.startDate, days: state.days, selectedDate: state.selectedDate});
async function jumpDate(state, date) {
  day(date);
  state.startDate = add(date, -Math.floor(state.days / 2));
  state.selectedDate = date;
  state.scrollRequest++;
  state.candidateOffset = 0;
  await saveViewport(state);
}
const zoomLevels = [
  {pixelsPerMinute: .75, label: '紧凑'},
  {pixelsPerMinute: 1.1, label: '标准'},
  {pixelsPerMinute: 1.5, label: '舒展'},
  {pixelsPerMinute: 2, label: '宽松'},
  {pixelsPerMinute: 3, label: '最大'},
];
const zoomIndex = value => Number.isInteger(value) && value >= 0 && value < zoomLevels.length ? value : 1;
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
  const loadRange = context.timelineRange === undefined ? null : timelineRange(context.timelineRange);
  if (loadRange && event != null) throw Error('时间轴范围加载不接受事件');
  const a = await query('availability.get');
  const today = await clock.today(a.timezone);
  if (context.pageId === 'app.planner.quickAdd') return renderCreation(state, event, formValues, a);
  if (context.pageId === 'app.planner.taskDetail') return renderTaskDetail(state, event, context, formValues, a);
  state.displayHours = displayPreference(await ui.preferences.get(displayKey));
  state.zoom = zoomIndex(await ui.preferences.get(zoomKey));
  const savedScale = await ui.preferences.get(pinchKey);
  state.zoomScale = typeof savedScale === 'number' && savedScale >= .75 && savedScale <= 3 ? savedScale : zoomLevels[state.zoom].pixelsPerMinute;
  state.details = detailsPreference(await ui.preferences.get(detailsKey));
  const viewport = viewportPreference(await ui.preferences.get(viewportKey));
  state.days = visibleDayCounts.includes(state.days) ? state.days : viewport.days || 3;
  state.startDate ||= viewport.startDate || add(today, -Math.floor(state.days / 2));
  state.selectedDate ||= viewport.selectedDate || today;
  state.scrollRequest = Number.isSafeInteger(state.scrollRequest) && state.scrollRequest >= 0 ? state.scrollRequest : 0;
  state.selected ||= [];
  state.candidateOffset = Number.isSafeInteger(state.candidateOffset) && state.candidateOffset >= 0 ? state.candidateOffset : 0;
  const candidateLimit = 100;
  try {
    if (event?.type === 'detailSettings') {
      await panel('displaySettings');
      state.details = detailsPreference(await ui.preferences.get(detailsKey));
    }
    if (event?.type === 'detailPreference') {
      if (!(event.key in detailsDefaults) || typeof event.value !== 'boolean') throw Error('详情显示选项无效');
      state.details = await ui.preferences.set(detailsKey, {...state.details, [event.key]: event.value});
    }
    if (event?.type === 'resetDetails') state.details = await ui.preferences.set(detailsKey, {...detailsDefaults});
    if (event?.type === 'pinchZoom') {
      if (typeof event.pixelsPerMinute !== 'number' || !Number.isFinite(event.pixelsPerMinute) || event.pixelsPerMinute < .75 || event.pixelsPerMinute > 3) throw Error('时间轴缩放范围无效');
      state.zoomScale = await ui.preferences.set(pinchKey, event.pixelsPerMinute);
      state.zoom = zoomLevels.reduce((best, item, index) => Math.abs(item.pixelsPerMinute - state.zoomScale) < Math.abs(zoomLevels[best].pixelsPerMinute - state.zoomScale) ? index : best, 0);
      await ui.preferences.set(zoomKey, state.zoom);
    }
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
    if (event?.type === 'batches') await ui.navigate('app.planner.batches');
    if (event?.type === 'completeTask') {
      const current = await task(event.id);
      if (!current || current.deletedAt || current.archivedAt) throw Error('任务已不可用，请刷新');
      const saved = await setCompletion(current, !current.completedAt, a.timezone, event.expectedUpdatedAt);
      if (saved) await ui.notify({message: current.completedAt ? '任务已重新打开' : '任务已完成，已记录完成时间', kind: 'success'});
    }
    if (event?.type === 'openProject') await ui.navigate('app.tasks.directory', {projectId:event.projectId,folderId:event.folderId,focusTaskId:event.taskId});
    if (event?.type === 'detail') await panel('taskDetail', {taskId: event.id});
    if (event?.type === 'editTime') await panel('taskDetail', {taskId: event.id, step: 'time'});
    if (event?.type === 'tools') await panel('tools', {screen: event.screen || 'rules'});
    if (event?.type === 'today') await jumpDate(state, today);
    if (event?.type === 'timelineViewport') {
      day(event.startDate);
      if (!visibleDayCounts.includes(event.visibleDays)) throw Error('请选择1、3、5或7列');
      state.startDate = event.startDate; state.days = event.visibleDays;
      await saveViewport(state);
    }
    if (event?.type === 'board') { state.history = false; state.cancelledView = false; state.chooseAuto = false; delete state.autoPreview; }
    if (event?.type === 'cancelledTasks') state.cancelledView = true;
    if (event?.type === 'restoreTask') {
      if (await execute('task.setCancelled', {id: event.id, cancelled: false, expectedUpdatedAt: event.expectedUpdatedAt}, {
        title: '恢复任务', message: '恢复后将按原来的安排继续执行。', confirmLabel: '恢复任务',
      })) await ui.notify({message: '任务已恢复', kind: 'success'});
    }
    if (event?.type === 'chooseAuto') { state.chooseAuto = true; delete state.autoPreview; }
    if (event?.type === 'occurrence') await panel('editor', {candidate: event.candidate});
    if (event?.type === 'onlyDeadline') { state.onlyDeadline = event.value ?? !state.onlyDeadline; state.candidateOffset = 0; }
    if (event?.type === 'zoom') {
      if (event.delta !== -1 && event.delta !== 1) throw Error('请选择放大或缩小时间轴');
      const next = event.delta > 0 ? zoomLevels.findIndex(level => level.pixelsPerMinute > state.zoomScale + .001) : zoomLevels.reduce((last, level, index) => level.pixelsPerMinute < state.zoomScale - .001 ? index : last, -1);
      state.zoom = await ui.preferences.set(zoomKey, next < 0 ? (event.delta > 0 ? zoomLevels.length - 1 : 0) : next);
      state.zoomScale = await ui.preferences.set(pinchKey, zoomLevels[state.zoom].pixelsPerMinute);
    }
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
      const v = await ui.dialog({title: '跳转日期', fields: [
        {key: 'startDate', label: '日期', type: 'date', value: state.selectedDate},
      ]});
      if (v) await jumpDate(state, v.startDate);
    }
    if (event?.type === 'periodShortcut') {
      if (!visibleDayCounts.includes(event.days)) throw Error('请选择1、3、5或7列');
      state.days = event.days; state.candidateOffset = 0;
      await saveViewport(state);
    }
    if (event?.type === 'history') state.history = !state.history;
    if (event?.type === 'undo') await execute('batch.undo', {id: event.id});
    if (event?.type === 'auto') {
      const elapsedDays = Math.max(0, Math.round((Date.parse(today + 'T00:00:00Z') - Date.parse(state.startDate + 'T00:00:00Z')) / 86400000));
      if (elapsedDays >= state.days) throw Error('当前可见日期均已过去，请回到今天后自动安排');
      state.chooseAuto = false;
      state.autoPreview = await query('plan.preview', {startDate: add(state.startDate, elapsedDays), days: state.days - elapsedDays, ...(state.selected.length ? {selectedIds: state.selected} : {})});
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
  if (context.pageId === 'app.planner.displaySettings') return {state, header: {title: '详情显示'}, tree: detailSettingsContent(state)};
  if (!loadRange && state.history) return plannerPage(state, await historyContent(state));
  if (!loadRange && state.cancelledView) return plannerPage(state, await cancelledContent(state, a));
  if (!loadRange && state.autoPreview) return plannerPage(state, previewContent(state));
  const boardInput = () => ({...(loadRange || {startDate: add(state.startDate, -7), days: 21}), candidateOffset: state.candidateOffset, candidateLimit, onlyDeadline: !!state.onlyDeadline});
  let data = await query('board.get', boardInput());
  if (state.candidateOffset > 0 && state.candidateOffset >= data.candidateTotal) {
    state.candidateOffset = Math.max(0, Math.floor((data.candidateTotal - 1) / candidateLimit) * candidateLimit);
    data = await query('board.get', boardInput());
  }
  const now = await clock.now(), daysByZone = {[a.timezone]: today};
  const localNow = await clock.toLocal({utc: now, zone: a.timezone});
  for (const t of data.tasks) if (t.dueDate && !t.dueAt && t.dueTimezone && !daysByZone[t.dueTimezone]) daysByZone[t.dueTimezone] = await clock.today(t.dueTimezone);
  const overdue = t => !t?.completedAt && !!t?.dueDate && (t.dueAt ? Date.parse(t.dueAt) < Date.parse(now) : t.dueDate < daysByZone[t.dueTimezone || a.timezone]);
  const labelDeadline = await localDeadlineLabels([...data.candidates.map(c => c.task), ...data.scheduled], a.timezone);
  const expectedTasks = Object.fromEntries(data.tasks.filter(t => t.revisionToken).map(t => [t.id, {revisionToken: t.revisionToken}]));
  state.boardVersions = expectedTasks;
  const pending = data.candidates.filter(c => !c.task?.plannedStartAt && ['pending', 'overdue'].includes(c.status));
  // Selections intentionally survive page and filter changes. Final planning
  // validates every selected ID, including items outside this visible page.
  if (event?.type === 'move' && !state.moveIntent) state.selected = state.selected.filter(id => id !== event.candidateId);
  const candidates = pending.filter(c => !state.onlyDeadline || c.task?.dueDate).map(c => ({
    id: c.taskId || c.id, colorKey: c.taskId || c.id, title: c.title, durationMinutes: c.estimatedMinutes || a.defaultMinutes,
    preferredSummary: overdue(c.task) ? '已逾期' : summary(c.task) || (c.task && c.task.estimatedMinutes == null ? '未设置耗时' : duration(c.estimatedMinutes || a.defaultMinutes)),
    deadlineSummary: summary(c.task), deadlineText: c.task?.dueDate ? '截止 ' + labelDeadline(c.task) : '', overdue: overdue(c.task),
    selected: state.selected.includes(c.id),
    selectEvent: {type: 'select', id: c.id},
    event: c.taskId ? {type: 'detail', id: c.taskId} : {type: 'occurrence', candidate: c},
    ...(c.taskId ? {editTimeEvent: {type: 'editTime', id: c.taskId}} : {}),
    ...(c.taskId ? {moveEvent: {type: 'move', taskId: c.taskId, candidateId: c.id, expectedTasks: expectedTasks[c.taskId] ? {[c.taskId]: expectedTasks[c.taskId]} : {}}} : {}),
  }));
  const blocks = [...data.scheduled, ...data.busy].map(t => ({
    id: t.taskId || t.id, colorKey: t.courseId || t.taskId || t.id,
    ...(t.courseId ? {courseId: t.courseId} : {}),
    ...(t.cancelled ? {color: '#858B95'} : typeof t.color === 'string' ? {color: t.color} : {}),
    title: t.title, start: stamp(t.startDate, t.start), end: stamp(t.endDate, t.end),
    durationMinutes: (Date.parse(t.plannedEndAt || t.endAt || stamp(t.endDate, t.end) + 'Z') - Date.parse(t.plannedStartAt || t.startAt || stamp(t.startDate, t.start) + 'Z')) / 60000,
    deadlineSummary: summary(t), deadlineText: t.dueDate ? '截止 ' + labelDeadline(t) : '', overdue: !t.cancelled && overdue(t),
    completed: !!t.completedAt, fixed: !t.cancelled && !!t.locked, readOnly: !!t.readOnly, sourceLabel: t.cancelled ? '已取消' : t.completedAt ? '已完成' : t.sourceLabel,
    ...(!t.readOnly ? {actions: [
      t.cancelled
        ? {label:'恢复任务', icon:'undo', event:{type:'restoreTask', id:t.id, expectedUpdatedAt:t.updatedAt}}
        : {label:t.completedAt?'重新打开':'已完成', icon:t.completedAt?'undo':'check', event:{type:'completeTask',id:t.id,expectedUpdatedAt:t.updatedAt}, command:completionCommand(t,!t.completedAt,a.timezone,today)},
      ...(t.projectName ? [{label:'所属项目 · '+t.projectName, icon:'folder', event:{type:'openProject',projectId:t.projectId,folderId:t.folderId,taskId:t.id}}] : []),
    ]} : {}),
    ...(!t.readOnly && !t.cancelled ? {statusIndicator:'edgeToCorner'} : {}),
    ...(t.cancelled ? {
      appearance: {borderStyle: 'dashed', titleDecoration: 'lineThrough', cornerIcon: 'slash', badgeText: '已取消'},
      selectionNote: '原安排已保留，此时段可重新安排', ...(!t.projectName ? {selectionLayout:'inlineActions'} : {}),
      occupiesTime: false,
    } : {}),
    showLocation: !t.courseId || state.details.courseLocation, showTeacher: !t.courseId || state.details.courseTeacher,
    selectionDetails: [
      ...(state.details.location && t.location?.trim() ? [{label: '地点', value: t.location.trim()}] : []),
      ...(state.details.teacher && t.teacher?.trim() ? [{label: '老师', value: t.teacher.trim()}] : []),
    ],
    showSelectionSource: state.details.source, showSelectionGaps: state.details.gaps,
    ...(typeof t.location === 'string' && t.location.trim() ? {location: t.location.trim()} : {}),
    ...(typeof t.teacher === 'string' && t.teacher.trim() ? {teacher: t.teacher.trim()} : {}),
    event: t.readOnly ? {type: 'source', title: t.title, source: t.sourceLabel} : {type: 'detail', id: t.taskId || t.id},
    ...(!t.readOnly && !t.completedAt && !t.cancelled ? {editTimeEvent: {type: 'editTime', id: t.taskId || t.id}} : {}),
    ...(!t.readOnly && !t.locked && !t.completedAt && !t.cancelled ? {moveEvent: {type: 'move', taskId: t.taskId || t.id, expectedTasks: {[t.taskId || t.id]: {revisionToken: t.revisionToken}}}} : {}),
  }));
  if (event?.type === 'source') await ui.notify({message: `${event.title} · ${event.source}，请到来源修改`});
  const notices = [...data.warnings, ...data.conflicts];
  const selectedText = state.selected.length ? `已选 ${state.selected.length} 项${state.selected.some(id => !pending.some(c => c.id === id)) ? '（含其他页或筛选外任务）' : ''}` : '';
  const visibleHours = displayHours(state.displayHours, blocks, loadRange?.startDate || state.startDate, loadRange?.days || state.days);
  let content;
  if (!loadRange && state.chooseAuto) {
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
    quickAdjustment: quickAdjustmentContract,
    previewQuery: {ref: ref('operation.inspect'), input: {timezone: a.timezone, expectedTasks}},
    previewIdentity: JSON.stringify([a.timezone, state.startDate, state.days, state.candidateOffset, state.onlyDeadline, expectedTasks, data.busy]),
    days: Array.from({length: data.range.days}, (_, index) => { const date = add(data.range.startDate, index); return {date, label: date.slice(5).replace('-', '/')}; }),
    options: {
      editor: plannerEditor,
      continuousDates: true, visibleDays: state.days, initialDate: state.startDate, scrollRequest: state.scrollRequest,
      timeline: {rangeContextKey: 'timelineRange', preferenceKey: viewportKey, stateKeys: {startDate: 'startDate', visibleDays: 'days'}},
      viewportEvent: {type: 'timelineViewport'}, selectedDate: state.selectedDate, now: stamp(localNow.date, localNow.time),
      allowedIntents: ['move', 'swap', 'resize'],
      dashboard: true, minColumnWidth: 112, pixelsPerMinute: state.zoomScale, pinchZoom: {event: {type: 'pinchZoom'}, min: .75, max: 3}, candidateLabel: '待安排', candidateCount: data.candidateTotal,
      ...visibleHours, displayHours: state.displayHours, displayHoursEvent: {type: 'displayHours'},
      rangeLabel: rangeLabel(state.startDate, add(state.startDate, state.days - 1)), today,
      onlyDeadline: !!state.onlyDeadline, filterEvent: {type: 'onlyDeadline'},
      rangeEvent: {type: 'period'}, todayEvent: {type: 'today'},
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
  return plannerPage(state, content, visibleHours.displayHoursLabel);
}

function plannerPage(state, content, displayHoursLabel = '') {
  const alternate = state.history || state.cancelledView || state.autoPreview || state.chooseAuto;
  return {state, header: {compact: true, title: state.cancelledView ? '已取消任务' : state.history ? '操作历史' : state.autoPreview ? '安排预览' : state.chooseAuto ? '自动安排' : '任务规划',
    ...(!alternate ? {layout: 'plannerTimeline'} : {}),
    ...(alternate ? {backEvent: {type: 'board'}} : {}), actions: alternate ? [] : [
    {label: '新建', icon: 'add', presentation: 'inline', iconOnly: true, overflowOnly: true, event: {type: 'add'}},
    {label: '批量任务', icon: 'layers', presentation: 'menu', event: {type: 'batches'}},
    {label: '操作历史', icon: 'history', presentation: 'menu', event: {type: 'history'}},
    {label: '已取消任务', icon: 'archive', presentation: 'menu', event: {type: 'cancelledTasks'}},
    {label: '视图与显示', icon: 'calendar', presentation: 'menu', separatorBefore: true, children: [
      {kind: 'choiceGrid', label: '显示列数', children: visibleDayCounts.map(days => ({label: `${days}列`, selected: state.days === days, event: {type: 'periodShortcut', days}}))},
      {label: '跳转日期…', icon: 'dateRange', event: {type: 'period'}},
      {label: '每日显示时段', icon: 'schedule', subtitle: displayHoursLabel, separatorBefore: true, event: {type: 'displayHours'}},
      {label: '详情显示', icon: 'tune', event: {type: 'detailSettings'}},
      {kind: 'stepper', label: '时间轴缩放', valueLabel: zoomLevels[state.zoom].label,
        decreaseEvent: {type: 'zoom', delta: -1}, increaseEvent: {type: 'zoom', delta: 1},
        decreaseEnabled: state.zoomScale > zoomLevels[0].pixelsPerMinute, increaseEnabled: state.zoomScale < zoomLevels[zoomLevels.length - 1].pixelsPerMinute},
    ]},
    {label: '待安排筛选', icon: 'tune', presentation: 'menu', valueLabel: state.onlyDeadline ? '仅有截止' : '全部', children: [
      {label: '全部任务', selected: !state.onlyDeadline, event: {type: 'onlyDeadline', value: false}},
      {label: '仅有截止', selected: !!state.onlyDeadline, event: {type: 'onlyDeadline', value: true}},
    ]},
    {label: '规划规则', icon: 'list', presentation: 'menu', separatorBefore: true, event: {type: 'tools', screen: 'rules'}},
    {label: '规划设置', icon: 'settings', presentation: 'menu', event: {type: 'tools', screen: 'settings'}},
  ]}, tree: alternate ? content : {type: 'column', key: 'planner', underlapChrome: true, fillHeight: true, spacing: 0, children: [content]}};

}

function detailSettingsContent(state) {
  const option = (key, label) => checkbox('detail:' + key, label, state.details[key], {type: 'detailPreference', key});
  return keyedList('planner:details', [
    text('所有课程共用，设置自动保存。标题与时间始终显示。'),
    ...(state.error ? [{type: 'notice', text: state.error}] : []),
    {type: 'card', children: [text('课程卡片'), option('courseLocation', '显示地点'), option('courseTeacher', '显示老师'), text('空间不足时省略，可选中查看完整内容。')]},
    {type: 'card', key: 'coursePreview', tone: 'soft', children: [
      {...text('课程卡片预览'), style: 'caption', color: 'muted'},
      {...text('高等数学'), weight: 'semibold'},
      ...(state.details.courseLocation ? [text('教一 302')] : []),
      ...(state.details.courseTeacher ? [text('王老师')] : []),
      {...text('08:00—09:35'), style: 'caption', color: 'muted'},
    ]},
    {type: 'card', children: [text('选中后的详情'), option('location', '地点'), option('teacher', '老师'), option('source', '来源'), option('gaps', '空闲时段')]},
    {type: 'card', key: 'selectionPreview', variant: 'outlined', children: [
      {...text('选中详情预览'), style: 'caption', color: 'muted'},
      {...text('高等数学'), weight: 'semibold'}, text('08:00—09:35 · 1小时35分钟'),
      ...(state.details.location ? [text('地点 教一 302')] : []),
      ...(state.details.teacher ? [text('老师 王老师')] : []),
      ...(state.details.source ? [text('来源 课程')] : []),
      ...(state.details.gaps ? [text('空闲 09:35—10:00')] : []),
    ]},
    text('双指张开或合拢可缩放时间轴。拖动按5分钟调整，精确时间请手动编辑。'),
    button('恢复默认', {type: 'resetDetails'}, 'text'),
  ]);
}

async function cancelledContent(state, a) {
  const tasks = await query('task.cancelled.list');
  const positions = await clock.toLocalMany(tasks.filter(t => t.plannedStartAt).flatMap(t => [
    {utc: t.plannedStartAt, zone: a.timezone}, {utc: t.plannedEndAt, zone: a.timezone},
  ]));
  let index = 0;
  return keyedList('planner:cancelled', [
    {type: 'notice', text: tasks.length ? `${tasks.length} 项已取消 · 任务和原安排均已保留` : '暂无已取消的任务'},
    ...(state.error ? [text(state.error)] : []),
    ...tasks.map(t => {
      const start = t.plannedStartAt ? positions[index++] : null, end = start ? positions[index++] : null;
      return {type: 'card', key: t.id, children: [
        row(t.title, start ? `已取消 · 原安排 ${start.date} ${start.time}—${end.date === start.date ? '' : end.date + ' '}${end.time}` : '已取消 · 尚未安排时间', {type: 'detail', id: t.id}),
        button('恢复任务', {type: 'restoreTask', id: t.id, expectedUpdatedAt: t.updatedAt}, 'text'),
      ]};
    }),
  ]);
}

async function historyContent(state) {
  const [history, contract] = await Promise.all([query('operation.list'), data.contract('journal')]);
  return keyedList('planner:history', [
    text(`最近${contract.settings.retainedRecords}次操作 · 后续修改或完成将阻止整体撤销`),
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
