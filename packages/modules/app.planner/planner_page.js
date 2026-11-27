import {data, ui, clock, ids, services} from '@xudian/sdk';
import {add, day, weekday} from './engine.js';
import {renderCreation} from './creation.js';
import {plannerEditor, quickAdjustmentContract} from './presentation.js';
import {renderTaskDetail} from './task_detail_page.js';
import {text, button, row, checkbox, stamp, localDeadlineLabels, monthDay, note, group, iconRow, hero, footer, keyValue, pageInset} from './page_helpers.js';
import {ref, query, task, execute, completionCommand, setCompletion, applyMove, undoBatch} from './task_actions.js';

const keyedList = (scope, children) => ({
  type: 'keyedList', key: scope, scope,
  children: children.map((child, index) => ({...child,
    key: `${scope}:${child.key ? 'item:' + child.key : 'static:' + index}`,
  })),
});
const panel = async (page, context = {}) => ui.panel('app.planner.' + page, {...context, editorSession: await ids.new()}, {adaptive: true, wide: 'center', heightFactor: page === 'quickAdd' ? .94 : page === 'taskDetail' ? .83 : .88});
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
  if (preference.mode === 'manual') {
    const startMinute = displayMinute(preference.start);
    return {startMinute, endMinute: displayMinute(preference.end, true), initialMinute: startMinute,
      displayHoursLabel: `手动 ${preference.start}–${preference.end}`};
  }
  if (preference.mode === 'auto') {
    // The host combines visible occupancy with the measured scroll viewport.
    let first = 1440;
    for (let i = 0; i < days; i++) {
      const date = add(startDate, i), next = add(date, 1);
      for (const block of blocks) {
        if (block.start >= next + 'T00:00:00' || block.end <= date + 'T00:00:00') continue;
        const from = block.start.slice(0, 10) < date ? 0 : displayMinute(block.start.slice(11, 16));
        first = Math.min(first, from);
      }
    }
    const initialMinute = first === 1440 ? 480 : Math.max(0, Math.floor((first - 60) / 60) * 60);
    return {startMinute: 0, endMinute: 1440, initialMinute, smartHours: true, displayHoursLabel: '自动 · 智能时段'};
  }
  return {startMinute: 0, endMinute: 1440, initialMinute: 540, displayHoursLabel: '全天 00:00–24:00'};
}

export async function renderPlanner({state = {}, event, context = {}, formValues = {}} = {}) {
  state = {...state};
  const loadRange = context.timelineRange === undefined ? null : timelineRange(context.timelineRange);
  if (loadRange && event != null) throw Error('时间轴范围加载不接受事件');
  const a = await query('availability.get');
  const today = await clock.today(a.timezone);
  if (context.pageId === 'app.planner.quickAdd') return renderCreation(state, event, formValues, a);
  if (context.pageId === 'app.planner.taskDetail') return renderTaskDetail(state, event, context, formValues, a);
  const route = {
    'app.planner.history': 'history', 'app.planner.cancelled': 'cancelledView', 'app.planner.auto': 'chooseAuto',
  }[context.pageId];
  if (route && !state.detailRoute) {
    state.detailRoute = true;
    state[route] = true;
    if (route === 'chooseAuto') {
      state.startDate ||= context.startDate;
      state.days ||= context.days;
      state.selected ||= context.selected;
    }
  }
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
      await ui.navigate('app.planner.displaySettings');
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
          {value: 'auto', label: '智能时段'}, {value: 'manual', label: '手动设置'}, {value: 'full', label: '显示全天'},
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
    if (event?.type === 'detail') {
      if (state.cancelledView) await ui.navigate('app.planner.taskDetail', {taskId: event.id});
      else await panel('taskDetail', {taskId: event.id});
    }
    if (event?.type === 'editTime') await panel('taskDetail', {taskId: event.id, step: 'time'});
    if (event?.type === 'tools') await ui.navigate('app.planner.tools', {screen: event.screen || 'rules'});
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
    if (event?.type === 'occurrence') await ui.navigate('app.planner.editor', {candidate: event.candidate});
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
    if (event?.type === 'openSummary' && ['history', 'cancelled', 'auto'].includes(event.page)) {
      await ui.navigate('app.planner.' + event.page, event.page === 'auto'
        ? {startDate: state.startDate, days: state.days, selected: state.selected} : {});
    }
    if (event?.type === 'history') state.history = !state.history;
    if (event?.type === 'undo') await undoBatch(event.id, a.timezone);
    if (event?.type === 'auto') {
      const endDate = add(state.startDate, state.days - 1);
      const startDate = state.startDate < today && today <= endDate ? today : state.startDate;
      const days = Math.round((Date.parse(endDate) - Date.parse(startDate)) / 86400000) + 1;
      state.autoPreview = await query('plan.preview', {startDate, days, ...(state.selected.length ? {selectedIds: state.selected} : {})});
      state.chooseAuto = false;
      state.autoKey = await ids.new();
      delete state.autoPlanId;
      if (state.autoPreview.confirmable && state.autoPreview.assigned.length) {
        const plan = await services.prepare(ref('batch.apply'), {batchKey: state.autoKey, preview: state.autoPreview});
        state.autoPlanId = plan.planId;
      }
    }
    if (event?.type === 'confirmAuto' && state.autoPreview) {
      const saved = state.autoPlanId && await ui.review(state.autoPlanId) && await services.commit(state.autoPlanId);
      if (saved) {
        delete state.autoPreview;
        state.selected = [];
        if (state.detailRoute) await ui.navigate('app.planner.home');
      }
    }
    if (event?.type === 'dismissAuto') {
      delete state.autoPreview;
      if (state.detailRoute) await ui.navigate('app.planner.home');
    }
    if (event?.type === 'move') {
      // Keep the requested position after a validation failure so it can be retried.
      state.moveIntent = {...event, expectedTasks: {...event.expectedTasks,
        ...(event.targetId && state.boardVersions?.[event.targetId] ? {[event.targetId]: state.boardVersions[event.targetId]} : {})}};
    }
    if ((event?.type === 'move' || event?.type === 'retryMove') && state.moveIntent) {
      await applyMove(state.moveIntent, a);
      delete state.moveIntent;
    }
    if (event?.type === 'dismissMove') delete state.moveIntent;
    delete state.error;
  } catch (e) { state.error = String(e); }
  // Summary pages do not need current board positions or candidate projection.
  // Undo and apply still validate current tasks in their command services.
  if (context.pageId === 'app.planner.displaySettings') return {state, header: {title: '详情显示', minHeight: 65, compact: true, titleStyle: 'large'}, tree: detailSettingsContent(state)};
  if (!loadRange && state.history) return plannerPage(state, await historyContent(state, a.timezone));
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
    const selectedCount = state.selected.length;
    const choices = pending.map(c => ({
      ...checkbox('select:' + c.id, c.title, state.selected.includes(c.id), {type: 'select', id: c.id}),
      minHeight: 64, subtitle: `${c.estimatedMinutes || a.defaultMinutes} 分钟 · ${c.task?.dueDate ? '截止 ' + monthDay(c.task.dueDate) : c.ruleId ? '规划规则' : '无截止日期'}`,
    }));
    content = {type: 'column', key: 'planner:chooseAuto', children: [
      ...(state.error ? [{type: 'notice', tone: 'warning', text: state.error}] : []),
      group('待安排', choices.length ? choices : [row('暂无待安排任务')], selectedCount
        ? {action: {label: '清空选择', event: {type: 'clearSelection'}}} : {count: data.candidateTotal + ' 项'}),
      ...(data.candidateTotal > candidateLimit ? [
        note(`候选 ${state.candidateOffset + 1}–${state.candidateOffset + pending.length} / ${data.candidateTotal}`),
        ...(state.candidateOffset ? [button('上一页候选', {type: 'candidatePage', offset: Math.max(0, state.candidateOffset - candidateLimit)})] : []),
        ...(data.hasMoreCandidates ? [button('下一页候选', {type: 'candidatePage', offset: state.candidateOffset + candidateLimit})] : []),
      ] : []),
      ...(selectedCount && state.selected.some(id => !pending.some(c => c.id === id)) ? [note(selectedText)] : []),
      note('有截止日期或来自规则的任务可直接预览；没有截止日期的任务需手动选中。'),
    ], ...footer(button(selectedCount ? `预览安排（${selectedCount} 项）` : '预览有截止及规则任务', {type: 'auto'}, 'filled'))};
  } else content = {
    type: 'plannerBoard', key: 'planner:board', candidates, blocks,
    quickAdjustment: true,
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
  const historyAction = {label: '操作历史', icon: 'history', presentation: 'menu', event: {type: 'openSummary', page: 'history'}};
  const cancelledAction = {label: '已取消任务', icon: 'archive', presentation: 'menu', event: {type: 'openSummary', page: 'cancelled'}};
  const batchesAction = {label: '批量任务', icon: 'layers', presentation: 'menu', event: {type: 'batches'}};
  const recordActions = state.cancelledView ? [historyAction, batchesAction] : state.history ? [cancelledAction, batchesAction] : [];
  return {state, header: {compact: true, title: state.cancelledView ? '已取消任务' : state.history ? '操作历史' : state.autoPreview ? '安排预览' : state.chooseAuto ? '自动安排' : '任务规划',
    ...(!alternate ? {layout: 'plannerTimeline'} : {}),
    ...(alternate ? {titleStyle: 'large', minHeight: 65,
      ...(state.detailRoute ? {backIcon: 'chevron', ...(state.autoPreview ? {backEvent: {type: 'chooseAuto'}} : {})} : {backEvent: {type: 'board'}})} : {}), actions: alternate ? recordActions : [
    {label: '调整', tooltip: '快速调整', icon: 'tune', presentation: 'inline', variant: 'text', overflowOnly: true, quickAdjustment: quickAdjustmentContract},
    {label: '新建', icon: 'add', presentation: 'inline', iconOnly: true, overflowOnly: true, event: {type: 'add'}},
    {label: '自动安排', icon: 'schedule', presentation: 'menu', event: {type: 'openSummary', page: 'auto'}},
    batchesAction, historyAction, cancelledAction,
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
  const option = (key, label, icon) => ({...checkbox('detail:' + key, label, state.details[key], {type: 'detailPreference', key}), minHeight: icon ? 54 : 50, icon});
  const locationTeacher = [state.details.location && '教一 302', state.details.teacher && '王老师'].filter(Boolean).join(' · ');
  const sourceGaps = [state.details.source && '课程', state.details.gaps && '09:35–10:00'].filter(Boolean).join(' · ');
  const cardDetails = ['08:00–09:35', state.details.courseLocation && '教一 302', state.details.courseTeacher && '王老师'].filter(Boolean);
  return {type: 'column', key: 'planner:details', ...pageInset([
    ...(state.error ? [{type: 'notice', tone: 'warning', text: state.error}] : []),
    group('课程卡片', [option('courseLocation', '显示地点', 'location'), option('courseTeacher', '显示老师', 'school')]),
    {...hero('高等数学', cardDetails.join(' · '), 'school'), key: 'planner:details:item:coursePreview'},
    group('选中后的详情', [option('location', '地点'), option('teacher', '老师'), option('source', '来源'), option('gaps', '空闲时段')]),
    {...group('选中详情预览', [
      iconRow('高等数学', '08:00–09:35 · 1 小时 35 分钟', undefined, 'school'),
      ...(locationTeacher ? [keyValue([state.details.location && '地点', state.details.teacher && '老师'].filter(Boolean).join('／'), locationTeacher)] : []),
      ...(sourceGaps ? [keyValue([state.details.source && '来源', state.details.gaps && '空闲'].filter(Boolean).join('／'), sourceGaps)] : []),
    ]), key: 'planner:details:item:selectionPreview'},
  ]), ...footer(button('恢复默认', {type: 'resetDetails'}, 'outlined'))};
}

async function cancelledContent(state, a) {
  const tasks = await query('task.cancelled.list');
  const planned = tasks.filter(t => t.plannedStartAt);
  const positions = [];
  for (let offset = 0; offset < planned.length; offset += 128) {
    positions.push(...await clock.toLocalMany(planned.slice(offset, offset + 128).flatMap(t => [
      {utc: t.plannedStartAt, zone: a.timezone}, {utc: t.plannedEndAt, zone: a.timezone},
    ])));
  }
  let index = 0;
  const rows = tasks.map((t, rowIndex) => {
    const start = t.plannedStartAt ? positions[index++] : null, end = start ? positions[index++] : null;
    const subtitle = start ? `原安排 · ${monthDay(start.date)} ${start.time}–${end.date === start.date ? '' : monthDay(end.date) + ' '}${end.time}` : '尚未安排时间';
    return {type: 'groupItem', key: t.id, position: tasks.length === 1 ? 'only' : rowIndex === 0 ? 'first' : rowIndex === tasks.length - 1 ? 'last' : 'middle',
      child: {type: 'inset', padding: [0, 0, 14, 0], children: [{type: 'row', layout: 'flex', children: [
        {...iconRow(t.title, subtitle, {type: 'detail', id: t.id}, 'calendarRemove', {trailing: false}), flex: 1},
        {...button('恢复任务', {type: 'restoreTask', id: t.id, expectedUpdatedAt: t.updatedAt}, 'text'), presentation: 'link'},
      ]}]}};
  });
  return {...keyedList('planner:cancelled', [
    ...(state.error ? [note(state.error)] : []),
    ...(rows.length ? [{type: 'sectionHeader', title: '已取消', compact: true, count: rows.length + ' 项', countPosition: 'end'},
      ...rows, {type: 'inset', padding: [0, 14, 0, 0], children: [note('点任务名称可查看详情。')]}] : [{type: 'emptyState', title: '暂无已取消的任务', icon: 'calendarRemove', iconSurface: true}]),
  ]), spacing: 0};
}

async function historyContent(state, timezone) {
  const [history, contract] = await Promise.all([query('operation.list'), data.contract('journal')]);
  const moments = [];
  for (let offset = 0; offset < history.length; offset += 256) {
    moments.push(...await clock.toLocalMany(history.slice(offset, offset + 256).map(op => ({utc: op.createdAt, zone: timezone}))));
  }
  const byDate = new Map();
  history.forEach((op, index) => {
    const {date, time} = moments[index];
    if (!byDate.has(date)) byDate.set(date, []);
    byDate.get(date).push({...iconRow(`${time} · ${op.changeCount} 项变更`, op.undone ? '已撤销' : '撤销整次操作',
      op.undone ? undefined : {type: 'undo', id: op.id}, 'history'), key: op.id});
  });
  return {type: 'column', key: 'planner:history', children: [
    ...(state.error ? [note(state.error)] : []),
    ...Array.from(byDate, ([date, rows]) => group(monthDay(date), rows)),
    ...(!history.length ? [{type: 'emptyState', title: '暂无操作记录', text: '调整安排后，可在这里查看最近的操作。', icon: 'history', iconSurface: true, padding: 12}] : []),
    note(`保留最近 ${contract.settings.retainedRecords} 次操作。任务在之后被修改或完成时，将无法整体撤销。`),
  ]};
}

function previewContent(state) {
  const p = state.autoPreview, date = p.assigned[0]?.date || p.input?.startDate || state.startDate;
  const multiDay = p.assigned.some(c => c.date !== date);
  return {type: 'column', key: 'planner:auto', ...(state.autoPlanId ? {planReview: {planId: state.autoPlanId, eventType: 'confirmAuto'}} : {}), children: [
    hero(multiDay ? rangeLabel(p.input.startDate, add(p.input.startDate, p.input.days - 1)) : `${monthDay(date)} · 周${'一二三四五六日'[weekday(date) - 1]}`,
      `${p.assigned.length} 项可安排 · ${p.unassigned.length} 项仍待安排`, 'schedule'),
    ...(state.error ? [{type: 'notice', tone: 'warning', text: state.error}] : []),
    ...[...p.warnings, ...p.conflicts].map(message => ({type: 'notice', tone: 'warning', text: message})),
    ...(p.assigned.length ? [group('建议安排', p.assigned.map(c => iconRow(c.title, `${multiDay ? monthDay(c.date) + ' · ' : ''}${c.start}–${c.end} · ${c.estimatedMinutes} 分钟`, undefined, 'schedule')), {count: p.assigned.length + ' 项'})] : []),
    ...(p.unassigned.length ? [group('仍待安排', p.unassigned.map(c => iconRow(c.title, c.reason, {type: 'occurrence', candidate: c}, 'warning')), {count: p.unassigned.length + ' 项'})] : []),
  ], ...footer(button('返回图形规划', {type: 'dismissAuto'}, 'outlined'), {...button('确认安排', {type: 'confirmAuto'}, 'filled'), disabled: !state.autoPlanId || !p.confirmable || !p.assigned.length})};
}
