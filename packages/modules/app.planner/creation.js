import {services, ui, clock, ids} from '@xudian/sdk';
import {add, day, minute, time} from './engine.js';

const reference = id => ({moduleId: 'app.planner', serviceId: 'planner.' + id, majorVersion: 1});
const query = (id, input) => services.query(reference(id), input);
const t = (text, style) => ({type: 'text', text, ...(style ? {style} : {})});
const b = (text, event, variant = 'text', extra = {}) => ({type: 'button', text, event, variant, ...extra});
const tile = (title, subtitle, event, extra = {}) => ({type: 'listTile', title, subtitle, event, ...extra});
const section = (title, children, action) => ({type: 'formSection', title, children, ...(action ? {action} : {})});
const notice = (text, tone = 'info') => ({type: 'notice', text, tone});
const field = (key, text, value, extra = {}) => ({type: 'input', key, text, value: value ?? '', onChangeEvent: {type: 'field', key}, ...extra});
const dateField = (key, text, value, type = 'dateInput') => ({type, key, text, value: value || null, clearable: key === 'dueDate' || key === 'dueTime', event: {type: 'field', key}});
const numberField = (key, text, value, min = 1, max = 365) => field(key, text, value, {inputMode: 'number', integer: true, min, max});
const segmented = (key, labels, value, eventType) => ({type: 'segmented', key, selectedIndex: value, items: labels.map((label, index) => ({label, event: {type: eventType, index}}))});
const footer = (text, event, disabled = false) => ({type: 'column', spacing: 0, children: [b(text, event, 'filled', {disabled})]});
const copy = value => JSON.parse(JSON.stringify(value));
const templateKey = 'creation.templates.v1';
const draftKey = 'creation.draft.v1';
const inputCacheKey = 'creation.input.v1';
const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const knownFields = ['mode', 'title', 'notes', 'dueDate', 'dueTime', 'estimatedMinutes', 'firstDate', 'days', 'autoRenew', 'intervalEnabled', 'minDays', 'maxDays', 'weekdaysEnabled', 'weekdays', 'windowEnabled', 'windowStart', 'windowEnd', 'priorityEnabled', 'priority', 'repeatKind', 'scheduleEnabled', 'durationEnabled', 'deadlineEnabled', 'notesEnabled', 'locationEnabled', 'startDate', 'start', 'endDate', 'end', 'locked', 'location'];
const contentFields = {schedule: ['startDate', 'start', 'endDate', 'end', 'locked'], duration: ['estimatedMinutes'], deadline: ['dueDate', 'dueTime'], notes: ['notes'], location: ['location'], priority: ['priority']};
const multipleFields = ['estimatedMinutes', 'firstDate', 'intervalEnabled', 'repeatKind', 'minDays', 'maxDays', 'weekdaysEnabled', 'weekdays', 'windowEnabled', 'windowStart', 'windowEnd', 'priorityEnabled', 'priority'];
const singleTimeFields = ['scheduleEnabled', 'durationEnabled', 'deadlineEnabled', 'startDate', 'start', 'endDate', 'end', 'locked', 'estimatedMinutes', 'dueDate', 'dueTime'];
const adjustFields = ['adjustDate', 'adjustStart', 'adjustEnd', 'adjustScope'];
const dateLabel = date => `${Number(date.slice(5, 7))}月${Number(date.slice(8))}日`;
const diffDays = (a, z) => Math.round((Date.parse(a + 'T00:00:00Z') - Date.parse(z + 'T00:00:00Z')) / 86400000);
const allDays = [1, 2, 3, 4, 5, 6, 7];
function defaults(a, today) {
  return {mode: 'once', title: '', notes: '', dueDate: null, dueTime: null, estimatedMinutes: a.defaultMinutes || 30,
    scheduleEnabled: false, durationEnabled: false, deadlineEnabled: false, notesEnabled: false, locationEnabled: false,
    startDate: null, start: null, endDate: null, end: null, locked: false, location: '',
    firstDate: today, days: 30, autoRenew: true, intervalEnabled: true, minDays: 4, maxDays: 6,
    repeatKind: 'interval', weekdaysEnabled: true, weekdays: [...allDays], windowEnabled: true, windowStart: '18:00', windowEnd: '22:00', priorityEnabled: false, priority: 0};
}
function hasDraftContent(d) {
  return !!(String(d.title || '').trim() || contentItems(d).length || d.dueTime);
}
function validateRepeat(d) {
  if (!d.intervalEnabled || !['daily', 'interval'].includes(d.repeatKind)) throw Error('多次任务需要一种重复方式，请选择每天一次或自定义间隔');
  if (d.repeatKind === 'interval' && (!Number.isInteger(Number(d.minDays)) || !Number.isInteger(Number(d.maxDays)) || Number(d.minDays) < 1 || Number(d.maxDays) < Number(d.minDays) || Number(d.maxDays) > 366)) throw Error('最大间隔必须大于或等于最小间隔，且至少1天，最多366天');
}
function dailyWeekdayNotice(d) {
  return d.repeatKind === 'daily' && d.weekdaysEnabled && (d.weekdays || []).length < 7
    ? [notice('每天一次需要相邻两次间隔1天。当前限制了允许星期，遇到未允许的日期将无法确认；可将允许星期改为每天，或改用自定义间隔。', 'warning')]
    : [];
}
function templateSummary(d) {
  const duration = d.mode === 'batch' || d.durationEnabled || d.scheduleEnabled;
  return `${duration ? d.estimatedMinutes + '分钟' : '未设置时间'} · ${d.mode === 'once' ? '无重复规则' : ruleItems(d).map(x => x.subtitle).join(' · ')}`;
}
function ruleItems(d) {
  return [
    ...(d.mode === 'batch' && d.intervalEnabled ? [{id: 'interval', title: d.repeatKind === 'daily' ? '每日安排' : '间隔安排', subtitle: d.repeatKind === 'daily' ? '每天一次' : `${d.minDays}～${d.maxDays}天`}] : []),
    ...(d.weekdaysEnabled ? [{id: 'weekdays', title: '允许星期', subtitle: weekLabel(d.weekdays)}] : []),
    ...(d.windowEnabled ? [{id: 'window', title: '允许时段', subtitle: `${d.windowStart}～${d.windowEnd}`}] : []),
    ...(d.priorityEnabled ? [{id: 'priority', title: '优先级', subtitle: ['普通', '较高', '高', '最高'][Number(d.priority)] || '普通'}] : []),
  ];
}
function weekLabel(values) {
  const days = (values || []).map(Number).sort();
  return days.join(',') === '1,2,3,4,5' ? '周一至周五' : days.length === 7 ? '每天' : days.map(d => weekdays[d - 1]).join('、') || '未选择星期';
}
function creationInput(d, zone, adjustments) {
  if (!String(d.title || '').trim()) throw Error('请填写任务名称');
  const estimatedMinutes = Number(d.estimatedMinutes);
  if (!Number.isInteger(estimatedMinutes) || estimatedMinutes < 1 || estimatedMinutes > 1439) throw Error('每次耗时需为1至1439分钟');
  validateRepeat(d);
  return {title: d.title.trim(), notes: d.notes || '', location: d.location || null, estimatedMinutes, priority: d.priorityEnabled ? Number(d.priority) : 0, timezone: zone, firstDate: d.firstDate, days: 30,
    rules: {interval: {minDays: d.repeatKind === 'daily' ? 1 : Number(d.minDays), maxDays: d.repeatKind === 'daily' ? 1 : Number(d.maxDays)},
      weekdays: d.weekdaysEnabled ? (d.weekdays || []).map(Number) : allDays,
      timeWindow: d.windowEnabled ? {start: d.windowStart, end: d.windowEnd} : {start: '00:00', end: '23:59'}}, adjustments: adjustments || []};
}
function builtins(a, today) {
  const base = defaults(a, today);
  return [
    {id: 'daily-plan', name: '每日规划', draft: {...base, title: '每日规划', mode: 'batch', estimatedMinutes: 15, repeatKind: 'daily', minDays: 1, maxDays: 1, weekdays: allDays, windowStart: '08:00', windowEnd: '10:00'}},
    {id: 'daily-review', name: '每日复盘', draft: {...base, title: '每日复盘', mode: 'batch', estimatedMinutes: 15, repeatKind: 'daily', minDays: 1, maxDays: 1, weekdays: allDays, windowStart: '20:00', windowEnd: '23:00'}},
    {id: 'read-paper', name: '阅读论文', draft: {...base, title: '阅读论文', mode: 'batch', estimatedMinutes: 30}},
    {id: 'notes', name: '整理笔记', draft: {...base, title: '整理笔记', mode: 'once', durationEnabled: true, estimatedMinutes: 30}},
  ];
}
async function command(id, input, confirmation) {
  const prepared = await services.prepare(reference(id), input);
  if (await ui.review(prepared.planId, confirmation)) return services.commit(prepared.planId);
}
async function saveOnce(d, zone) {
  if (!String(d.title || '').trim()) throw Error('请填写任务名称');
  if (d.dueTime && !d.dueDate) throw Error('请先选择截止日期');
  let dueAt = null;
  if (d.dueDate && d.dueTime) {
    const result = await clock.toUtc({date: d.dueDate, time: d.dueTime, zone});
    if (result.status !== 'unique') throw Error('所选时间在当前时区不存在或有歧义，请重新选择');
    dueAt = result.instants[0];
  }
  const scheduled = d.scheduleEnabled ? await scheduleBounds(d, zone) : null;
  const estimatedMinutes = scheduled ? scheduled.minutes : d.durationEnabled ? validDuration(d.estimatedMinutes) : null;
  return command('task.create', {title: d.title.trim(), notes: d.notes || '', location: d.location || null,
    estimatedMinutes, priority: d.priorityEnabled ? Number(d.priority) : 0,
    ...(scheduled ? {plannedStartAt: scheduled.startAt, plannedEndAt: scheduled.endAt, plannedTimezone: zone, locked: !!d.locked} : {}),
    dueDate: d.dueDate || null, dueAt, dueTimezone: d.dueDate ? zone : null});
}

function validDuration(value) {
  const minutes = Number(value);
  if (!Number.isInteger(minutes) || minutes < 1 || minutes > 1439) throw Error('预计耗时需为1至1439分钟');
  return minutes;
}
async function scheduleBounds(d, zone) {
  day(d.startDate); day(d.endDate); minute(d.start); minute(d.end);
  const values = [];
  for (const [date, time] of [[d.startDate, d.start], [d.endDate, d.end]]) {
    const converted = await clock.toUtc({date, time, zone});
    if (converted.status !== 'unique') throw Error('所选时间在当前时区不存在或有歧义，请重新选择');
    values.push(converted.instants[0]);
  }
  const minutes = (Date.parse(values[1]) - Date.parse(values[0])) / 60000;
  if (!Number.isSafeInteger(minutes) || minutes < 1) throw Error('结束时间必须晚于开始时间');
  return {startAt: values[0], endAt: values[1], minutes};
}
function contentItems(d) {
  return [
    ...(d.mode === 'batch' ? [{key: 'multiple', title: '多次任务', icon: 'repeat', value: `${d.repeatKind === 'daily' ? '每天一次' : `间隔${d.minDays}～${d.maxDays}天`} · 从${dateLabel(d.firstDate)}开始`}] : []),
    ...(d.mode !== 'batch' && d.scheduleEnabled ? [{key: 'schedule', title: '起止时间', icon: 'clock', value: `${d.startDate} ${d.start}—${d.startDate === d.endDate ? '' : d.endDate + ' '}${d.end}${d.locked ? ' · 已固定，无法拖动' : ''}`} ] : []),
    ...(!d.scheduleEnabled && (d.durationEnabled || d.mode === 'batch') ? [{key: 'duration', title: '预计耗时', icon: 'hourglass', value: `${d.estimatedMinutes}分钟`, removable: d.mode !== 'batch'}] : []),
    ...(d.mode !== 'batch' && d.dueDate ? [{key: 'deadline', title: '截止时间', icon: 'calendar', value: d.dueDate + (d.dueTime ? ' ' + d.dueTime : '')}] : []),
    ...(d.notes ? [{key: 'notes', title: '描述', icon: 'description', value: d.notes.length > 120 ? d.notes.slice(0, 120) + '…' : d.notes}] : []),
    ...(d.location ? [{key: 'location', title: '地点', icon: 'location', value: d.location}] : []),
    ...(d.priorityEnabled ? [{key: 'priority', title: '优先级', icon: 'priority', value: ['普通', '较高', '高', '最高'][Number(d.priority)] || '普通'}] : []),
    ...(d.mode === 'batch' ? ruleItems(d).filter(x => x.id === 'weekdays' || x.id === 'window').map(x => ({key: x.id, title: x.title, value: x.subtitle, icon: 'calendar'})) : []),
  ];
}
function removeContent(d, key, state) {
  if (key === 'schedule') Object.assign(d, {scheduleEnabled: false, startDate: null, start: null, endDate: null, end: null, locked: false, estimatedMinutes: null});
  if (key === 'duration') Object.assign(d, {durationEnabled: false, estimatedMinutes: null});
  if (key === 'deadline') Object.assign(d, {deadlineEnabled: false, dueDate: null, dueTime: null});
  if (key === 'notes') Object.assign(d, {notesEnabled: false, notes: ''});
  if (key === 'location') Object.assign(d, {locationEnabled: false, location: ''});
  if (key === 'priority') Object.assign(d, {priorityEnabled: false, priority: 0});
  if (key === 'weekdays') d.weekdaysEnabled = false;
  if (key === 'window') d.windowEnabled = false;
  if (key === 'multiple') Object.assign(d, {mode: 'once'}, state.singleTime || {durationEnabled: true});
}

export async function renderCreation(state, event, forms, a) {
  state = {...state};
  const today = await clock.today(a.timezone);
  const previousPage = (state.step || 'create') + (state.contentKey || '');
  if (!state.draft) {
    const saved = await ui.preferences.get(draftKey);
    state.savedDraftJson = JSON.stringify(saved);
    if (saved?.draft && typeof saved.draft === 'object' && !Array.isArray(saved.draft)) {
      state.draft = {...saved.draft};
      if (state.draft.mode === 'batch' && saved.singleTime && typeof saved.singleTime === 'object' && !Array.isArray(saved.singleTime)) state.singleTime = copy(saved.singleTime);
      try { day(state.draft.firstDate); } catch (_) { state.draft.firstDate = today; }
      if (state.draft.firstDate < today) state.draft.firstDate = today;
      state.restoredDraft = hasDraftContent({...defaults(a, today), ...state.draft});
    }
    const cachedInput = await ui.preferences.get(inputCacheKey);
    if (cachedInput && typeof cachedInput === 'object' && Object.prototype.hasOwnProperty.call(cachedInput, 'title')) {
      state.draft = {...defaults(a, today), ...state.draft, title: cachedInput.title};
      state.restoredDraft = hasDraftContent(state.draft);
    }
  }
  state.draft = {...defaults(a, today), ...state.draft};
  const d = state.draft;
  state.step ||= 'create';
  state.adjustments ||= [];
  state.templates = (await ui.preferences.get(templateKey)) || [];
  if (!Array.isArray(state.templates)) state.templates = [];
  const applyFields = (keys, target) => {
    for (const key of keys) if (Object.prototype.hasOwnProperty.call(forms || {}, key)) target[key] = forms[key];
    if (event?.type === 'field' && keys.includes(event.key)) target[event.key] = event.value;
  };
  if (state.step === 'contentEditor') applyFields(contentFields[state.contentKey] || [], state.contentDraft);
  else if (state.step === 'multiple') applyFields(multipleFields, state.multiDraft);
  else if (state.step !== 'rules') applyFields(knownFields, d);
  if (state.step === 'rules') {
    state.ruleDraft ||= copy(d);
    applyFields(knownFields.filter(k => !['title', 'notes', 'dueDate', 'dueTime'].includes(k)), state.ruleDraft);
  }
  if (state.step === 'adjust') applyFields(adjustFields, state);
  if (state.step === 'multiple' && event?.type === 'field' && event.key === 'repeatKind') state.multiDraft.intervalEnabled = true;
  if (event?.type === 'field' && event.key === 'templateSearch') state.templateSearch = event.value;
  if (event?.type === 'field' && event.key === 'ruleSearch') state.ruleSearch = event.value;
  let clearForms = [];
  const clear = keys => { clearForms = [...new Set([...clearForms, ...keys])]; };
  const invalidate = () => { delete state.preview; delete state.creationPlanId; state.adjustments = []; };
  const freezePreview = async () => {
    delete state.creationPlanId;
    if (state.preview?.confirmable && !state.preview.unassigned.length) {
      const prepared = await services.prepare(reference('creation.apply'), {creationKey: state.creationKey, preview: state.preview});
      state.creationPlanId = prepared.planId;
    }
  };
  try {
    delete state.message;
    if (event?.type === 'openAdd') { state.step = 'addContent'; state.ruleSearch = ''; clear(['ruleSearch']); }
    if (event?.type === 'editContent') {
      if (!contentFields[event.key]) throw Error('内容项不可用');
      state.contentReturn = state.step === 'addContent' ? 'addContent' : 'create';
      state.contentKey = event.key; state.contentDraft = copy(d); state.step = 'contentEditor';
      const cd = state.contentDraft;
      if (event.key === 'duration') cd.estimatedMinutes ||= a.defaultMinutes || 30;
      if (event.key === 'deadline') cd.dueDate ||= today;
      if (event.key === 'schedule' && !cd.scheduleEnabled) {
        const local = await clock.local(a.timezone), startMinute = Math.ceil((minute(local.time) + 5) / 5) * 5;
        const endMinute = startMinute + (Number(d.estimatedMinutes) || a.defaultMinutes || 30);
        Object.assign(cd, {startDate: add(local.date, Math.floor(startMinute / 1440)), start: time(startMinute % 1440),
          endDate: add(local.date, Math.floor(endMinute / 1440)), end: time(endMinute % 1440), locked: false});
      }
      clear(contentFields[event.key]);
    }
    if (event?.type === 'scheduleDate') {
      const cd = state.contentDraft, previous = cd.startDate;
      cd.startDate = add(today, event.offset === 1 ? 1 : 0);
      cd.endDate = add(cd.startDate, Math.max(0, diffDays(cd.endDate || previous, previous)));
      clear(['startDate', 'endDate']);
    }
    if (event?.type === 'applyContent') {
      const cd = state.contentDraft, key = state.contentKey;
      if (key === 'schedule') {
        const range = await scheduleBounds(cd, a.timezone);
        for (const field of contentFields.schedule) d[field] = cd[field];
        Object.assign(d, {scheduleEnabled: true, durationEnabled: false, estimatedMinutes: range.minutes});
      } else if (key === 'duration') {
        Object.assign(d, {estimatedMinutes: validDuration(cd.estimatedMinutes), durationEnabled: true, scheduleEnabled: false,
          startDate: null, start: null, endDate: null, end: null, locked: false});
      } else if (key === 'deadline') {
        if (!cd.dueDate) throw Error('请选择截止日期');
        day(cd.dueDate);
        if (cd.dueTime) {
          const converted = await clock.toUtc({date: cd.dueDate, time: cd.dueTime, zone: a.timezone});
          if (converted.status !== 'unique') throw Error('所选截止时间在当前时区不存在或有歧义，请重新选择');
        }
        Object.assign(d, {deadlineEnabled: true, dueDate: cd.dueDate, dueTime: cd.dueTime || null});
      } else if (key === 'location') {
        const location = String(cd.location || '').trim();
        if (!location || location.length > 300) throw Error('请填写地点（最多300字）');
        Object.assign(d, {locationEnabled: true, location});
      } else if (key === 'notes') {
        if (!String(cd.notes || '').trim() || String(cd.notes).length > 10000) throw Error('请填写描述（最多10000字）');
        Object.assign(d, {notesEnabled: true, notes: cd.notes});
      } else if (key === 'priority') {
        const priority = Number(cd.priority);
        if (!Number.isInteger(priority) || priority < 0 || priority > 3) throw Error('请选择有效优先级');
        Object.assign(d, {priorityEnabled: true, priority});
      }
      state.step = 'create'; delete state.contentDraft; delete state.contentKey; invalidate(); clear(knownFields);
    }
    if (event?.type === 'removeContent') { removeContent(d, event.key, state); invalidate(); clear(knownFields); }
    if (event?.type === 'openMultiple') {
      state.multiDraft = {...copy(d), mode: 'batch', estimatedMinutes: Number(d.estimatedMinutes) || a.defaultMinutes || 30};
      state.multiReturn = state.step === 'addContent' ? 'addContent' : 'create'; state.step = 'multiple';
      clear(multipleFields);
    }
    if (event?.type === 'applyMultiple') {
      const md = state.multiDraft;
      validDuration(md.estimatedMinutes); day(md.firstDate);
      if (md.firstDate < today) throw Error('首次日期不能早于今天');
      validateRepeat(md);
      if (d.mode !== 'batch') state.singleTime = Object.fromEntries(singleTimeFields.map(k => [k, d[k]]));
      for (const key of multipleFields) d[key] = md[key];
      Object.assign(d, {mode: 'batch', scheduleEnabled: false, durationEnabled: true, deadlineEnabled: false, locked: false, dueDate: null, dueTime: null});
      state.step = 'create'; delete state.multiDraft; invalidate(); clear(knownFields);
    }
    if (event?.type === 'description') state.description = true;
    if (event?.type === 'time') state.time = true;
    if (event?.type === 'mode') {
      d.mode = event.index === 1 ? 'batch' : 'once'; invalidate();
      state.message = d.mode === 'once' ? '已保留批量规则，切回批量后可继续使用。' : null;
    }
    if (event?.type === 'duration') {
      const result = await ui.dialog({title: '每次耗时', fields: [{key: 'estimatedMinutes', type: 'number', label: '预计分钟', value: Number(d.estimatedMinutes)}]});
      if (result) { d.estimatedMinutes = result.estimatedMinutes; invalidate(); clear(['estimatedMinutes']); }
    }
    if (event?.type === 'durationQuick') { d.estimatedMinutes = event.minutes; d.durationEnabled = true; invalidate(); clear(['estimatedMinutes']); }
    if (event?.type === 'templates') { state.step = 'templates'; state.templateTab = 0; state.templateSearch = ''; clear(['templateSearch']); }
    if (event?.type === 'templateTab') { state.templateTab = event.index; state.managingTemplates = false; }
    if (event?.type === 'manageTemplates') { state.managingTemplates = !state.managingTemplates; state.templateTab = 1; }
    if (event?.type === 'deleteTemplate') {
      const answer = await ui.dialog({title: '删除模板', fields: [{key: 'confirm', label: '删除此模板（已创建的任务不受影响）', type: 'boolean', value: false}]});
      if (answer?.confirm) { state.templates = state.templates.filter(x => x.id !== event.id); await ui.preferences.set(templateKey, state.templates); }
    }
    if (event?.type === 'useTemplate') {
      const template = [...builtins(a, today), ...state.templates].find(x => x.id === event.id);
      if (!template) throw Error('模板已不存在，请重新选择');
      let replace = true;
      if (hasDraftContent(d)) {
        const answer = await ui.dialog({title: '套用模板', fields: [{key: 'replace', label: '用模板替换当前名称、描述、地点、耗时、优先级和规则，并清除起止时间与截止时间。套用后仍可修改。', type: 'boolean', value: false}]});
        replace = !!answer?.replace;
      }
      if (replace) {
        await ui.preferences.set(inputCacheKey, null);
        state.draft = {...defaults(a, today), ...copy(template.draft), firstDate: today, dueDate: null, dueTime: null};
        Object.assign(state.draft, {scheduleEnabled: false, startDate: null, start: null, endDate: null, end: null, locked: false, deadlineEnabled: false});
        delete state.singleTime;
        delete state.restoredDraft;
        state.step = 'create'; state.description = !!state.draft.notes; state.time = false; state.templateName = template.name;
        invalidate(); clear(knownFields);
      }
    }
    if (event?.type === 'saveTemplate') {
      if (!String(d.title || '').trim()) throw Error('先填写任务名称，再存为模板');
      const answer = await ui.dialog({title: '存为模板', fields: [{key: 'name', label: '模板名称', type: 'text', value: d.title}]});
      if (answer) {
        if (!String(answer.name || '').trim()) throw Error('模板名称不能为空');
        const template = {id: await ids.new(), name: answer.name.trim(), draft: copy(d)};
        if (d.scheduleEnabled) template.draft.durationEnabled = true;
        for (const key of ['firstDate', 'dueDate', 'dueTime', 'startDate', 'start', 'endDate', 'end']) delete template.draft[key];
        Object.assign(template.draft, {scheduleEnabled: false, deadlineEnabled: false, locked: false});
        state.templates = [...state.templates, template]; await ui.preferences.set(templateKey, state.templates);
        state.message = '已保存到我的模板';
      }
    }
    if (event?.type === 'clearDraft') {
      const answer = await ui.dialog({title: '清空草稿', fields: [{key: 'clear', label: '清空当前任务名称、内容和规则，已创建的任务不受影响。', type: 'boolean', value: false}]});
      if (answer?.clear) {
        await ui.preferences.set(inputCacheKey, null);
        state.draft = defaults(a, today); state.step = 'create'; invalidate();
        for (const key of ['singleTime', 'creationKey', 'templateName', 'restoredDraft', 'contentDraft', 'contentKey', 'multiDraft', 'ruleDraft']) delete state[key];
        clear([...knownFields, ...adjustFields]);
      }
    }
    if (event?.type === 'rules') { state.ruleReturn = state.step === 'multiple' ? 'multiple' : state.step === 'preview' ? 'preview' : 'create'; state.ruleDraft = copy(state.step === 'multiple' ? state.multiDraft : d); state.step = 'rules'; state.ruleCategory = 0; state.ruleSearch = ''; clear(knownFields.filter(k => !['title', 'notes', 'estimatedMinutes', 'dueDate', 'dueTime'].includes(k))); }
    if (event?.type === 'ruleCategory') state.ruleCategory = event.index;
    if (event?.type === 'configureRule') state.ruleEditing = state.ruleEditing === event.id ? null : event.id;
    if (event?.type === 'removeRule') {
      if (event.id === 'interval') throw Error('多次任务必须保留一种重复方式；可在添加其他规则中更换每天一次或自定义间隔。');
      const key = {interval: 'intervalEnabled', weekdays: 'weekdaysEnabled', window: 'windowEnabled', priority: 'priorityEnabled'}[event.id];
      if (key) state.ruleDraft[key] = false;
    }
    if (event?.type === 'addRule') {
      const rd = state.ruleDraft;
      if (event.id === 'daily' || event.id === 'interval') {
        if (rd.intervalEnabled && rd.repeatKind !== event.id) {
          const answer = await ui.dialog({title: '更换重复方式', fields: [{key: 'replace', label: `改用${event.id === 'daily' ? '每日安排' : '间隔安排'}，替换当前重复规则`, type: 'boolean', value: false}]});
          if (!answer?.replace) return build(state, a, today, clearForms);
        }
        rd.intervalEnabled = true; rd.repeatKind = event.id;
        if (event.id === 'interval' && Number(rd.maxDays) === 1) { rd.minDays = 4; rd.maxDays = 6; }
        state.ruleEditing = 'interval'; clear(['minDays', 'maxDays']);
      } else {
        rd[{weekdays: 'weekdaysEnabled', window: 'windowEnabled', priority: 'priorityEnabled'}[event.id]] = true;
        state.ruleEditing = event.id;
      }
    }
    if (event?.type === 'applyRules') {
      const rd = state.ruleDraft;
      if (rd.mode === 'batch') validateRepeat(rd);
      if (rd.weekdaysEnabled && !(rd.weekdays || []).length) throw Error('至少选择一个允许星期');
      if (rd.windowEnabled && rd.windowStart >= rd.windowEnd) throw Error('允许时段的结束需晚于开始');
      if (state.ruleReturn === 'multiple') { state.multiDraft = copy(rd); state.step = 'multiple'; }
      else { state.draft = copy(rd); state.step = 'create'; invalidate(); }
      clear(knownFields); delete state.ruleDraft; delete state.ruleEditing;
    }
    if (event?.type === 'settings') state.step = 'settings';
    if (event?.type === 'applySettings') {
      day(d.firstDate); if (d.firstDate < today) throw Error('首次日期不能早于今天');
      state.step = 'create'; invalidate();
    }
    if (event?.type === 'back') {
      if (state.step === 'contentEditor') { state.step = state.contentReturn || 'create'; delete state.contentDraft; delete state.contentKey; }
      else if (state.step === 'multiple') { state.step = state.multiReturn || 'create'; delete state.multiDraft; }
      else if (state.step === 'rules') { state.step = state.ruleReturn || 'create'; delete state.ruleDraft; delete state.ruleEditing; }
      else if (state.step === 'adjust') state.step = 'preview';
      else state.step = 'create';
      clear([...knownFields, ...adjustFields]);
    }
    if (event?.type === 'preview') {
      state.preview = await query('creation.preview', creationInput(d, a.timezone, state.adjustments));
      state.creationKey ||= await ids.new(); state.step = 'preview';
      await freezePreview();
    }
    if (event?.type === 'adjust') {
      const item = state.preview.assigned.find(x => x.id === event.id);
      if (!item) throw Error('这次安排已变化，请重新预览');
      state.adjustId = item.id; state.adjustOriginal = copy(item); state.adjustDate = item.date; state.adjustStart = item.start; state.adjustEnd = item.end; state.adjustScope = 'only';
      state.step = 'adjust'; clear(adjustFields);
    }
    if (event?.type === 'adjustScope') state.adjustScope = event.index === 1 ? 'following' : 'only';
    if (event?.type === 'applyAdjustment') {
      const adjustment = {id: state.adjustId, date: state.adjustDate, start: state.adjustStart, end: state.adjustEnd, scope: state.adjustScope};
      const current = state.preview.assigned.find(x => x.id === state.adjustId);
      if (state.adjustScope === 'following') {
        const later = state.preview.assigned.filter(x => x.index > current.index && state.adjustments.some(y => y.id === x.id));
        if (later.length) throw Error('后续' + later.map(x => dateLabel(x.date)).join('、') + '已有手动调整；请选择仅本次，或逐项修改，避免覆盖。');
      }
      const adjustments = [...state.adjustments.filter(x => x.id !== state.adjustId), adjustment];
      const preview = await query('creation.preview', creationInput(d, a.timezone, adjustments));
      if (!preview.confirmable) throw Error((preview.conflicts || []).join('；') || preview.unassigned.map(x => x.reason).join('；') || '此调整无法满足规则，请修改日期或规则');
      state.adjustments = adjustments; state.preview = preview; state.step = 'preview'; clear(adjustFields);
      await freezePreview();
    }
    if (event?.type === 'save' && d.mode === 'once') {
      const saved = await saveOnce(d, a.timezone);
      if (saved) { await ui.preferences.set(draftKey, null); await ui.preferences.set(inputCacheKey, null); await ui.navigate('app.planner.home'); return {state: {}, clearForms: knownFields, tree: t('任务已保存')}; }
    }
    if (event?.type === 'confirmCreation' && state.preview) {
      if (!state.preview.confirmable || state.preview.unassigned.length) throw Error('请先处理未安排任务，再确认生成');
      if (!state.creationPlanId) await freezePreview();
      const saved = await ui.review(state.creationPlanId) ? await services.commit(state.creationPlanId) : null;
      if (saved) { await ui.preferences.set(draftKey, null); await ui.preferences.set(inputCacheKey, null); await ui.navigate('app.planner.home'); return {state: {}, clearForms: [...knownFields, ...adjustFields], tree: t('批量任务已创建，将持续补齐未来30天')}; }
    }
    delete state.error;
  } catch (e) { state.error = String(e); }
  if (state.step === 'contentEditor' && state.contentKey === 'schedule') {
    try { state.contentMinutes = (await scheduleBounds(state.contentDraft, a.timezone)).minutes; }
    catch (_) { state.contentMinutes = null; }
  }
  const currentPage = state.step + (state.contentKey || '');
  if (currentPage !== previousPage) state.pageDirection = ['back', 'applyContent', 'applyMultiple', 'applyRules', 'applySettings', 'applyAdjustment', 'useTemplate', 'clearDraft'].includes(event?.type) ? 'back' : 'forward';
  const savedDraft = hasDraftContent(state.draft) ? {draft: state.draft, ...(state.draft.mode === 'batch' && state.singleTime ? {singleTime: state.singleTime} : {})} : null;
  const savedDraftJson = JSON.stringify(savedDraft);
  if (savedDraftJson !== state.savedDraftJson) {
    try {
      await ui.preferences.set(draftKey, savedDraft);
      state.savedDraftJson = savedDraftJson;
      delete state.draftSaveFailed;
    } catch (_) { state.draftSaveFailed = true; }
  } else delete state.draftSaveFailed;
  return build(state, a, today, clearForms);
}

function build(state, a, today, clearForms) {
  const d = state.draft;
  let title = '新建任务', children = [], action, footerNode;
  if (state.step === 'addContent') {
    title = '添加内容或规则';
    const added = new Set(contentItems(d).map(x => x.key));
    const option = (key, label, subtitle, icon) => {
      const event = {type: key === 'multiple' ? 'openMultiple' : 'editContent', ...(key === 'multiple' ? {} : {key})};
      return tile(label, subtitle, event, {icon, trailing: added.has(key) ? '已添加' : '',
        trailingAction: {icon: added.has(key) ? 'check' : 'add', label: (added.has(key) ? '编辑' : '添加') + label, event, tonal: !added.has(key)}});
    };
    const matches = node => (node.title + node.subtitle).includes(state.ruleSearch || '');
    const times = d.mode === 'batch' ? [option('duration', '预计耗时', '每次任务需要的时间', 'hourglass')] : [
      option('schedule', '起止时间', '设置开始与结束，可选固定', 'clock'),
      option('duration', '预计耗时', '只记录用时，无需指定时段', 'hourglass'),
      option('deadline', '截止时间', '最晚何时完成，可单独设置', 'calendar'),
    ];
    const contents = [option('notes', '描述', d.notes ? '已填写任务说明' : '补充任务说明', 'description'), option('location', '地点', d.location || '补充执行地点', 'location'), option('priority', '优先级', '标记任务的重要程度', 'priority')];
    children = [field('ruleSearch', '搜索内容或规则', state.ruleSearch, {inputMode: 'search'}),
      ...(times.some(matches) ? [section('时间', times.filter(matches))] : []),
      ...(contents.some(matches) ? [section('内容', contents.filter(matches))] : []),
      ...(!state.ruleSearch || '多次任务每天每周自定义间隔'.includes(state.ruleSearch) ? [section('进阶', [tile('多次任务', d.mode === 'batch' ? '编辑重复规则与安排设置' : '每天或按自定义间隔安排', {type: 'openMultiple'}, {icon: 'repeat'})])] : []),
      ...(![...times, ...contents].some(matches) && state.ruleSearch && !'多次任务每天每周自定义间隔'.includes(state.ruleSearch) ? [notice('没有找到内容，请换个关键词')] : []),
    ];
  } else if (state.step === 'contentEditor') {
    const cd = state.contentDraft, key = state.contentKey;
    title = {schedule: '起止时间', duration: '预计耗时', deadline: '截止时间', notes: '描述', location: '地点', priority: '优先级'}[key];
    if (key === 'schedule') {
      children = [
        {type: 'row', children: [b('今天', {type: 'scheduleDate', offset: 0}, cd.startDate === today ? 'tonal' : 'text'), b('明天', {type: 'scheduleDate', offset: 1}, cd.startDate === add(today, 1) ? 'tonal' : 'text')]},
        section('开始', [{type: 'grid', children: [dateField('startDate', '开始日期', cd.startDate), dateField('start', '开始时间', cd.start, 'timeInput')]}]),
        section('结束', [{type: 'grid', children: [dateField('endDate', '结束日期', cd.endDate), dateField('end', '结束时间', cd.end, 'timeInput')]}]),
        {type: 'card', tone: 'soft', children: [
          {type: 'switch', key: 'locked', text: '固定时间', value: !!cd.locked, event: {type: 'field', key: 'locked'}},
          t('开启后无法在时间表中拖动；关闭后可调整。', 'muted'),
        ]},
        t(state.contentMinutes ? `时长 ${state.contentMinutes}分钟 · 自动计算` : '时长由起止时间自动计算', 'muted'),
        t('截止时间可从添加内容或规则中单独设置。', 'muted'),
      ];
    } else if (key === 'duration') children = [numberField('estimatedMinutes', '预计分钟', cd.estimatedMinutes, 1, 1439),
      {type: 'row', children: [15, 30, 60].map(minutes => b(`${minutes}分钟`, {type: 'field', key: 'estimatedMinutes', value: minutes}, Number(cd.estimatedMinutes) === minutes ? 'tonal' : 'text'))},
      ...(d.scheduleEnabled ? [notice('保存耗时后将替换起止时间，截止时间会保留。')] : [t('只记录需要多久，可在之后安排具体时间。', 'muted')])];
    else if (key === 'deadline') children = [dateField('dueDate', '截止日期', cd.dueDate), dateField('dueTime', '截止时间', cd.dueTime, 'timeInput'), t('可只设日期，也可补充具体时间；不改变执行安排。', 'muted')];
    else if (key === 'location') children = [field('location', '地点', cd.location), t('例如图书馆302、会议室或线上。', 'muted')];
    else if (key === 'notes') children = [field('notes', '详细描述', cd.notes, {multiline: true, minLines: 3, maxLines: 8})];
    else children = [{type: 'select', key: 'priority', text: '优先级', value: Number(cd.priority), items: ['普通', '较高', '高', '最高'].map((label, value) => ({label, value})), event: {type: 'field', key: 'priority'}}];
    footerNode = footer({schedule: '保存时间', duration: '保存耗时', deadline: '保存截止时间', location: '保存地点', notes: '保存描述', priority: '保存优先级'}[key], {type: 'applyContent'});
  } else if (state.step === 'multiple') {
    title = '多次任务'; const md = state.multiDraft;
    children = [
      {type: 'select', key: 'repeatKind', text: '重复方式', value: md.repeatKind, items: [{label: '每天一次', value: 'daily'}, {label: '自定义间隔', value: 'interval'}], event: {type: 'field', key: 'repeatKind'}},
      ...(md.repeatKind === 'interval' ? ruleConfiguration(md, 'interval') : [t('每天安排一次，无法安排的日期会在预览中说明。', 'muted')]),
      ...dailyWeekdayNotice(md),
      numberField('estimatedMinutes', '预计分钟', md.estimatedMinutes, 1, 1439),
      dateField('firstDate', '首次安排日期', md.firstDate),
      tile('安排规则', [md.weekdaysEnabled ? weekLabel(md.weekdays) : '不限星期', md.windowEnabled ? `${md.windowStart}—${md.windowEnd}` : '不限时段'].join(' · '), {type: 'rules'}, {icon: 'calendar'}),
      notice('保存设置后可预览未来30天的安排，再确认创建。'),
      ...(d.scheduleEnabled || d.dueDate ? [t('多次任务按规则分别安排，当前单次起止和截止会暂存；移除多次设置可恢复。', 'muted')] : []),
    ];
    footerNode = footer('保存多次设置', {type: 'applyMultiple'});
  } else if (state.step === 'templates') {
    title = '选择模板'; action = [{label: state.managingTemplates ? '完成管理' : '管理', presentation: 'inline', event: {type: 'manageTemplates'}}];
    const templates = state.templateTab === 1 ? state.templates : builtins(a, today);
    const shown = templates.filter(x => (x.name + ' ' + x.draft.title).includes(state.templateSearch || ''));
    children = [field('templateSearch', '搜索模板', state.templateSearch, {inputMode: 'search', showSearchIcon: false}), segmented('templateTabs', ['内置', '我的模板'], state.templateTab || 0, 'templateTab'),
      ...shown.flatMap(template => [tile(template.name, templateSummary(template.draft), {type: 'useTemplate', id: template.id}, {trailing: template.draft.mode === 'batch' ? '批量' : '单次', trailingAccent: true}),
        ...(state.managingTemplates ? [b('删除此模板', {type: 'deleteTemplate', id: template.id})] : []), {type: 'divider'}]),
      ...(!shown.length ? [notice(state.templateTab === 1 ? '暂无模板。填写任务后，可在更多菜单中存为模板。' : '没有找到模板，请换个关键词。')] : []),
      t('点击模板套用，之后仍可修改', 'muted')];
  } else if (state.step === 'rules') {
    title = '任务规则';
    const rd = state.ruleDraft, selected = ruleItems(rd), category = state.ruleCategory || 0;
    const matches = (item, group) => (!category || category === group) && (item.title + item.subtitle).includes(state.ruleSearch || '');
    const selectedShown = selected.filter(item => matches(item, item.id === 'interval' ? 1 : item.id === 'priority' ? 3 : 2));
    children = [field('ruleSearch', '搜索规则', state.ruleSearch, {inputMode: 'search'}), segmented('ruleCategories', ['全部', '重复', '时间', '偏好'], category, 'ruleCategory'),
      ...(rd.mode === 'once' ? [notice('单次任务可设置耗时与截止日期；重复规则在多次任务中使用。'), numberField('estimatedMinutes', '预计分钟', rd.estimatedMinutes, 1, 1439)] : [
        t('重复方式必选，可在下方更换每天一次或自定义间隔。', 'muted'),
        ...dailyWeekdayNotice(rd),
        section(`已选规则 · ${selected.length}项`, selectedShown.map(item => ({type: 'card', children: [
          {type: 'row', layout: 'flex', children: [{...tile(item.title, item.subtitle, {type: 'configureRule', id: item.id}), flex: 1}, item.id === 'interval' ? t('必选', 'muted') : b('移除', {type: 'removeRule', id: item.id})]},
          ...(state.ruleEditing === item.id || item.id === 'interval' && !state.ruleEditing ? ruleConfiguration(rd, item.id) : []),
        ]}))),
        section('添加其他规则', [
          ...(!category || category === 1 ? [
            ...(rd.repeatKind !== 'interval' || !rd.intervalEnabled ? [tile('间隔安排', rd.intervalEnabled ? '与每日安排二选一 · 点击更换' : '设置相邻两次任务的最小和最大间隔', {type: 'addRule', id: 'interval'}, {trailing: rd.intervalEnabled ? '更换' : '添加', trailingAccent: true})] : []),
            ...(rd.repeatKind !== 'daily' || !rd.intervalEnabled ? [tile('每日安排', rd.intervalEnabled ? '与间隔安排二选一 · 点击更换' : '每天安排一次', {type: 'addRule', id: 'daily'}, {trailing: rd.intervalEnabled ? '更换' : '添加', trailingAccent: true})] : []),
          ].filter(x => !state.ruleSearch || (x.title + x.subtitle).includes(state.ruleSearch)) : []),
          ...[{id: 'weekdays', title: '允许星期', subtitle: '仅在选定的星期安排', enabled: rd.weekdaysEnabled, group: 2}, {id: 'window', title: '允许时段', subtitle: '限定每日可安排时间', enabled: rd.windowEnabled, group: 2}, {id: 'priority', title: '优先级', subtitle: '安排时优先考虑', enabled: rd.priorityEnabled, group: 3}].filter(x => !x.enabled && matches(x, x.group)).map(x => tile(x.title, x.subtitle, {type: 'addRule', id: x.id}, {trailing: '添加', trailingAccent: true})),
        ]),
      ])];
    footerNode = footer(rd.mode === 'once' ? '应用设置' : `应用${selected.length}项规则`, {type: 'applyRules'});
  } else if (state.step === 'settings') {
    title = '安排设置';
    children = [dateField('firstDate', '首次安排日期', d.firstDate), {type: 'card', tone: 'soft', children: [t('未来30天', 'heading'), t(`${dateLabel(today)}—${dateLabel(add(today, 29))}`), t('每天从当天开始，持续向后规划30天；首次日期不会改变滚动窗口。', 'muted')]},
      notice('自动续排已开启。保留手动调整，已有任务不会重复生成。'), t(`安排时区：${a.timezone}`, 'muted')];
    footerNode = footer('应用安排设置', {type: 'applySettings'});
  } else if (state.step === 'preview') {
    title = '预览安排'; const p = state.preview;
    const unassigned = p.unassigned || [];
    children = [{type: 'card', tone: 'soft', children: [t(d.title, 'title'), t(`每次${d.estimatedMinutes}分钟 · ${d.repeatKind === 'daily' ? '每天一次' : '间隔' + d.minDays + '～' + d.maxDays + '天'}`), tile(`${dateLabel(p.startDate)}—${dateLabel(p.endDate)}`, null, null, {trailing: '未来30天', trailingAccent: true})]},
      {type: 'card', tone: 'soft', children: [t(`可安排 ${p.assigned.length} 次     未安排 ${unassigned.length} 次`, 'heading')]},
      ...(p.conflicts || []).map(x => notice(x, 'warning')), ...(p.warnings || []).map(x => notice(x)),
      ...(unassigned.length ? [notice(`还需处理${unassigned.length}次安排`, 'warning'), section('未安排', unassigned.map(item => ({type: 'card', children: [t(`第${item.index}次 · ${d.title}`, 'heading'), t(`可安排日期：${dateLabel(item.windowStart)}—${dateLabel(item.windowEnd)}`), notice(item.reason, 'warning'), b('调整允许时段与规则', {type: 'rules'})]})))] : []),
      section(unassigned.length ? `可安排${p.assigned.length}次` : '具体安排', p.assigned.flatMap((item, index) => [
        ...(index ? [{type: 'divider'}] : []),
        tile(dateLabel(item.date), `${item.start}—${item.end}${state.adjustments.some(x => x.id === item.id) ? ' · 手动调整' : ''}`, {type: 'adjust', id: item.id}, {trailing: '修改', trailingAccent: true, selected: state.adjustments.some(x => x.id === item.id)}),
      ])),
      t(unassigned.length ? '请先处理未安排任务' : '确认后自动续排，保留手动调整', 'muted')];
    footerNode = {type: 'row', children: [b(`确认生成${unassigned.length ? '' : p.assigned.length + '次'}`, {type: 'confirmCreation'}, 'filled', {disabled: !p.confirmable || !!unassigned.length})]};
  } else if (state.step === 'adjust') {
    title = '调整时间'; const original = state.adjustOriginal;
    const entries = state.preview.assigned, at = entries.findIndex(x => x.id === original.id), previous = entries[at - 1], next = entries[at + 1];
    const shift = state.adjustScope === 'following' ? diffDays(state.adjustDate, original.date) : 0;
    const nextDate = next ? add(next.date, shift) : null;
    const before = previous ? diffDays(state.adjustDate, previous.date) : null, after = nextDate ? diffDays(nextDate, state.adjustDate) : null;
    const min = d.repeatKind === 'daily' ? 1 : Number(d.minDays), max = d.repeatKind === 'daily' ? 1 : Number(d.maxDays);
    const valid = [before, after].filter(x => x !== null).every(x => x >= min && x <= max);
    const following = entries.slice(at + 1);
    children = [{type: 'card', tone: 'soft', children: [t(d.title, 'title'), t(`本次原定 ${dateLabel(original.date)} ${original.start}—${original.end}`, 'muted')]},
      {type: 'card', children: [dateField('adjustDate', '日期', state.adjustDate), {type: 'row', layout: 'flex', children: [{...dateField('adjustStart', '开始', state.adjustStart, 'timeInput'), flex: 1}, {...dateField('adjustEnd', '结束', state.adjustEnd, 'timeInput'), flex: 1}]}, t(`原耗时${d.estimatedMinutes}分钟`, 'muted')]},
      section('调整范围', [
        {type: 'choiceCard', title: '仅本次', subtitle: '其他任务日期保持不变', selected: state.adjustScope === 'only', event: {type: 'adjustScope', index: 0}},
        {type: 'choiceCard', title: '本次及以后', subtitle: `联动后续${following.length}次安排`, selected: state.adjustScope === 'following', event: {type: 'adjustScope', index: 1}},
        ...(state.adjustScope === 'following' && following.length ? [t(`调整后：${following.map(x => dateLabel(add(x.date, shift))).join('、')}；已有手动调整不会被静默覆盖。`, 'muted')] : []),
      ]), section('间隔检查', [
        ...(previous ? [tile(`距上一次（${dateLabel(previous.date)}）`, null, null, {trailing: `${before}天`})] : [t('这是首次安排')]),
        ...(next ? [tile(`距下一次（${dateLabel(nextDate)}）`, null, null, {trailing: `${after}天`})] : [t('这是窗口内最后一次安排')]),
        notice(valid ? `符合${min}～${max}天间隔` : '超出间隔规则。可调整日期、联动后续安排，或返回修改规则。', valid ? 'success' : 'warning'),
      ]), t('应用仅修改当前预览，确认生成后才创建任务。', 'muted')];
    footerNode = footer('应用调整', {type: 'applyAdjustment'});
  } else {
    const items = contentItems(d);
    children = [field('title', '任务名称', d.title),
      ...(state.restoredDraft && hasDraftContent(d) ? [notice('已恢复上次未完成的草稿')] : []),
      ...(d.mode === 'batch' ? dailyWeekdayNotice(d) : []),
      ...(items.length ? [section(`已添加 · ${items.length}项`, items.flatMap((item, index) => {
        const event = item.key === 'multiple' ? {type: 'openMultiple'} : ['weekdays', 'window'].includes(item.key) ? {type: 'rules'} : {type: 'editContent', key: item.key};
        return [...(index ? [{type: 'divider'}] : []), tile(item.title, item.value, event, {icon: item.icon,
          ...(item.removable === false ? {} : {trailingAction: {icon: 'close', label: '移除' + item.title, event: {type: 'removeContent', key: item.key}}}),
        })];
      }))] : []),
      {type: 'card', children: [tile('添加内容或规则', null, {type: 'openAdd'}, {icon: 'add'})]},
      t(items.length ? '点击内容可修改，× 可移除' : '只填任务名称也可以创建', 'muted'),
      t(state.draftSaveFailed ? '当前更改尚未自动保存，请保留当前页面。' : '草稿自动保留，可关闭后继续编辑。', 'muted'),
      ...(state.templateName ? [t(`已套用「${state.templateName}」，修改不会影响原模板`, 'muted')] : []),
    ];
    footerNode = footer(d.mode === 'batch' ? '预览安排' : '创建任务', {type: d.mode === 'batch' ? 'preview' : 'save'});
    action = [{label: '从模板新建', presentation: 'menu', event: {type: 'templates'}}, {label: '存为模板', presentation: 'menu', event: {type: 'saveTemplate'}}, ...(hasDraftContent(d) ? [{label: '清空草稿', presentation: 'menu', event: {type: 'clearDraft'}}] : [])];
  }

  if (state.message) children.push(notice(state.message, 'success'));
  if (state.error && !footerNode) children.push(notice(state.error, 'warning'));
  // Hidden controls keep their values in the native form cache. Synchronize
  // the current draft rather than clearing that cache when changing subpages.
  const values = {...d, ...(state.step === 'rules' ? state.ruleDraft : state.step === 'contentEditor' ? state.contentDraft : state.step === 'multiple' ? state.multiDraft : {})};
  const replaceForms = Object.fromEntries(knownFields.map(key => [key, values[key] ?? null]));
  for (const key of adjustFields) if (state[key] !== undefined) replaceForms[key] = state[key];
  replaceForms.templateSearch = state.templateSearch || '';
  replaceForms.ruleSearch = state.ruleSearch || '';
  const footerMessage = state.error ? notice(state.error, 'warning') : state.draftSaveFailed ? notice('草稿暂未自动保存。可继续编辑并创建；关闭页面可能丢失本次更改。', 'warning') : null;
  return {state, replaceForms, header: {title, ...(state.step !== 'create' ? {backEvent: {type: 'back'}} : {}), ...(action ? {actions: action} : {})}, tree: {type: 'column', key: 'planner:creation:' + state.step + (state.contentKey || ''), scrollKey: 'planner:creation:' + state.step + (state.contentKey || ''), pageTransition: {direction: state.pageDirection || 'forward', duration: 260}, ...(state.step === 'create' ? {formCache: {preferenceKey: inputCacheKey, fields: ['title']}} : {}), queueInputActions: true, compact: true, spacing: 8, children, ...(state.step === 'preview' && state.creationPlanId ? {planReview: {planId: state.creationPlanId, eventType: 'confirmCreation'}} : {}), ...(footerNode ? {footer: footerNode, ...(footerMessage ? {footerMessage} : {})} : {})}};
}

function ruleConfiguration(d, id) {
  if (id === 'interval') return d.repeatKind === 'daily' ? [t('每天安排一次；若当天无法安排，预览会明确显示。', 'muted')] : [{type: 'row', layout: 'flex', children: [{...numberField('minDays', '最少（天）', d.minDays), flex: 1}, {...numberField('maxDays', '最多（天）', d.maxDays), flex: 1}]}, t('相邻两次任务的日期间隔', 'muted')];
  if (id === 'weekdays') return [{type: 'multiSelect', key: 'weekdays', text: '选择允许星期', value: d.weekdays, items: weekdays.map((label, index) => ({label, value: index + 1})), event: {type: 'field', key: 'weekdays'}}];
  if (id === 'window') return [{type: 'row', layout: 'flex', children: [{...dateField('windowStart', '开始', d.windowStart, 'timeInput'), flex: 1}, {...dateField('windowEnd', '结束', d.windowEnd, 'timeInput'), flex: 1}]}];
  return [{type: 'select', key: 'priority', text: '优先级', value: Number(d.priority), items: ['普通', '较高', '高', '最高'].map((label, value) => ({label, value})), event: {type: 'field', key: 'priority'}}];
}
