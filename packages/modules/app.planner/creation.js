import {services, ui, clock, ids} from '@xudian/sdk';
import {add, day} from './engine.js';

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
const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const knownFields = ['mode', 'title', 'notes', 'dueDate', 'dueTime', 'estimatedMinutes', 'firstDate', 'days', 'autoRenew', 'intervalEnabled', 'minDays', 'maxDays', 'weekdaysEnabled', 'weekdays', 'windowEnabled', 'windowStart', 'windowEnd', 'priorityEnabled', 'priority', 'repeatKind'];
const adjustFields = ['adjustDate', 'adjustStart', 'adjustEnd', 'adjustScope'];
const dateLabel = date => `${Number(date.slice(5, 7))}月${Number(date.slice(8))}日`;
const diffDays = (a, z) => Math.round((Date.parse(a + 'T00:00:00Z') - Date.parse(z + 'T00:00:00Z')) / 86400000);
const allDays = [1, 2, 3, 4, 5, 6, 7];
function defaults(a, today) {
  return {mode: 'once', title: '', notes: '', dueDate: null, dueTime: null, estimatedMinutes: a.defaultMinutes || 30,
    firstDate: today, days: 30, autoRenew: true, intervalEnabled: true, minDays: 4, maxDays: 6,
    repeatKind: 'interval', weekdaysEnabled: true, weekdays: [1, 2, 3, 4, 5], windowEnabled: true, windowStart: '18:00', windowEnd: '22:00', priorityEnabled: false, priority: 0};
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
  if (!d.intervalEnabled) throw Error('请先在任务规则中选择一种重复方式');
  return {title: d.title.trim(), notes: d.notes || '', estimatedMinutes, priority: d.priorityEnabled ? Number(d.priority) : 0, timezone: zone, firstDate: d.firstDate, days: 30,
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
    {id: 'notes', name: '整理笔记', draft: {...base, title: '整理笔记', mode: 'once', estimatedMinutes: 30}},
  ];
}
async function command(id, input, confirmation) {
  const prepared = await services.prepare(reference(id), input);
  if (await ui.review(prepared.planId, confirmation)) return services.commit(prepared.planId);
}
async function saveOnce(d, zone) {
  if (d.dueTime && !d.dueDate) throw Error('请先选择截止日期');
  let dueAt = null;
  if (d.dueDate && d.dueTime) {
    const result = await clock.toUtc({date: d.dueDate, time: d.dueTime, zone});
    if (result.status !== 'unique') throw Error('所选时间在当前时区不存在或有歧义，请重新选择');
    dueAt = result.instants[0];
  }
  return command('task.create', {title: d.title, notes: d.notes || '', estimatedMinutes: Number(d.estimatedMinutes), dueDate: d.dueDate || null, dueAt, dueTimezone: d.dueDate ? zone : null});
}

export async function renderCreation(state, event, forms, a) {
  state = {...state};
  const today = await clock.today(a.timezone);
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
  if (state.step !== 'rules') applyFields(knownFields, d);
  else applyFields(['title', 'notes', 'estimatedMinutes', 'dueDate', 'dueTime'], d);
  if (state.step === 'rules') {
    state.ruleDraft ||= copy(d);
    applyFields(knownFields.filter(k => !['title', 'notes', 'estimatedMinutes', 'dueDate', 'dueTime'].includes(k)), state.ruleDraft);
  }
  if (state.step === 'adjust') applyFields(adjustFields, state);
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
    if (event?.type === 'durationQuick') { d.estimatedMinutes = event.minutes; invalidate(); clear(['estimatedMinutes']); }
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
      if (String(d.title || '').trim() || String(d.notes || '').trim()) {
        const answer = await ui.dialog({title: '套用模板', fields: [{key: 'replace', label: '用模板替换名称、描述、耗时和规则；清除当前截止日期。套用后仍可修改。', type: 'boolean', value: false}]});
        replace = !!answer?.replace;
      }
      if (replace) {
        state.draft = {...defaults(a, today), ...copy(template.draft), firstDate: today, dueDate: null, dueTime: null};
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
        delete template.draft.firstDate; delete template.draft.dueDate; delete template.draft.dueTime;
        state.templates = [...state.templates, template]; await ui.preferences.set(templateKey, state.templates);
        state.message = '已保存到我的模板';
      }
    }
    if (event?.type === 'rules') { state.ruleReturn = state.step === 'preview' ? 'preview' : 'create'; state.ruleDraft = copy(d); state.step = 'rules'; state.ruleCategory = 0; state.ruleSearch = ''; clear(knownFields.filter(k => !['title', 'notes', 'estimatedMinutes', 'dueDate', 'dueTime'].includes(k))); }
    if (event?.type === 'ruleCategory') state.ruleCategory = event.index;
    if (event?.type === 'configureRule') state.ruleEditing = state.ruleEditing === event.id ? null : event.id;
    if (event?.type === 'removeRule') {
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
      if (d.mode === 'once') rd.estimatedMinutes = d.estimatedMinutes;
      if (rd.intervalEnabled && (Number(rd.minDays) < 1 || Number(rd.maxDays) < Number(rd.minDays))) throw Error('最大间隔必须大于或等于最小间隔，且至少1天');
      if (rd.weekdaysEnabled && !(rd.weekdays || []).length) throw Error('至少选择一个允许星期');
      if (rd.windowEnabled && rd.windowStart >= rd.windowEnd) throw Error('允许时段的结束需晚于开始');
      state.draft = copy(rd); state.step = 'create'; invalidate(); clear(knownFields); delete state.ruleDraft; delete state.ruleEditing;
    }
    if (event?.type === 'settings') state.step = 'settings';
    if (event?.type === 'applySettings') {
      day(d.firstDate); if (d.firstDate < today) throw Error('首次日期不能早于今天');
      state.step = 'create'; invalidate();
    }
    if (event?.type === 'back') {
      if (state.step === 'adjust') state.step = 'preview';
      else { state.step = 'create'; delete state.ruleDraft; delete state.ruleEditing; }
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
      if (saved) { await ui.navigate('app.planner.home'); return {state: {}, clearForms: knownFields, tree: t('任务已保存')}; }
    }
    if (event?.type === 'confirmCreation' && state.preview) {
      if (!state.preview.confirmable || state.preview.unassigned.length) throw Error('请先处理未安排任务，再确认生成');
      if (!state.creationPlanId) await freezePreview();
      const saved = await ui.review(state.creationPlanId) ? await services.commit(state.creationPlanId) : null;
      if (saved) { await ui.navigate('app.planner.home'); return {state: {}, clearForms: [...knownFields, ...adjustFields], tree: t('批量任务已创建，将持续补齐未来30天')}; }
    }
    delete state.error;
  } catch (e) { state.error = String(e); }
  return build(state, a, today, clearForms);
}

function build(state, a, today, clearForms) {
  const d = state.draft;
  let title = '新建任务', children = [], action, footerNode;
  if (state.step === 'templates') {
    title = '选择模板'; action = [{label: state.managingTemplates ? '完成管理' : '管理', presentation: 'inline', event: {type: 'manageTemplates'}}];
    const templates = state.templateTab === 1 ? state.templates : builtins(a, today);
    const shown = templates.filter(x => (x.name + ' ' + x.draft.title).includes(state.templateSearch || ''));
    children = [field('templateSearch', '搜索模板', state.templateSearch, {inputMode: 'search', showSearchIcon: false}), segmented('templateTabs', ['内置', '我的模板'], state.templateTab || 0, 'templateTab'),
      ...shown.flatMap(template => [tile(template.name, `${template.draft.estimatedMinutes}分钟 · ${template.draft.mode === 'once' ? '无重复规则' : ruleItems(template.draft).map(x => x.subtitle).join(' · ')}`, {type: 'useTemplate', id: template.id}, {trailing: template.draft.mode === 'batch' ? '批量' : '单次', trailingAccent: true}),
        ...(state.managingTemplates ? [b('删除此模板', {type: 'deleteTemplate', id: template.id})] : []), {type: 'divider'}]),
      ...(!shown.length ? [notice(state.templateTab === 1 ? '暂无模板。填写任务后，可在更多菜单中存为模板。' : '没有找到模板，请换个关键词。')] : []),
      t('点击模板套用，之后仍可修改', 'muted')];
  } else if (state.step === 'rules') {
    title = '任务规则';
    const rd = state.ruleDraft, selected = ruleItems(rd), category = state.ruleCategory || 0;
    const matches = (item, group) => (!category || category === group) && (item.title + item.subtitle).includes(state.ruleSearch || '');
    const selectedShown = selected.filter(item => matches(item, item.id === 'interval' ? 1 : item.id === 'priority' ? 3 : 2));
    children = [field('ruleSearch', '搜索规则', state.ruleSearch, {inputMode: 'search'}), segmented('ruleCategories', ['全部', '重复', '时间', '偏好'], category, 'ruleCategory'),
      ...(d.mode === 'once' ? [notice('单次任务可设置耗时与截止日期；重复规则在批量模式中使用。'), numberField('estimatedMinutes', '预计分钟', d.estimatedMinutes, 1, 1439)] : [
        section(`已选规则 · ${selected.length}项`, selectedShown.map(item => ({type: 'card', children: [
          {type: 'row', layout: 'flex', children: [{...tile(item.title, item.subtitle, {type: 'configureRule', id: item.id}), flex: 1}, b('移除', {type: 'removeRule', id: item.id})]},
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
    footerNode = footer(d.mode === 'once' ? '应用设置' : `应用${selected.length}项规则`, {type: 'applyRules'});
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
    children = [{type: 'row', children: [b('从模板新建', {type: 'templates'})]}, segmented('creationMode', ['单次', '批量'], d.mode === 'batch' ? 1 : 0, 'mode'),
      ...(d.mode === 'batch' ? [t('同一任务按规则持续安排', 'muted')] : []),
      field('title', '任务名称', d.title), ...(state.description || d.notes ? [field('notes', '详细描述（可留空）', d.notes, {multiline: true, minLines: 2, maxLines: 6})] : [{type: 'row', children: [b('＋ 添加描述', {type: 'description'})]}]),
      tile('每次耗时', null, {type: 'duration'}, {trailing: `${d.estimatedMinutes}分钟`, trailingAccent: true}),
      {type: 'row', children: [15, 30, 60].map(minutes => b(`${minutes}分钟`, {type: 'durationQuick', minutes}, Number(d.estimatedMinutes) === minutes ? 'tonal' : 'text'))},
      ...(d.mode === 'batch' ? [section('任务规则', ruleItems(d).flatMap((item, index) => [...(index ? [{type: 'divider'}] : []), tile(item.title, null, {type: 'rules'}, {trailing: item.subtitle})]), {text: `${ruleItems(d).length}项 · 编辑`, event: {type: 'rules'}}), tile('安排设置', `首次${d.firstDate === today ? '今天' : dateLabel(d.firstDate)} · 未来30天 · 自动续排`, {type: 'settings'}), t('保留手动调整，自动补齐不重复', 'muted')] : [
        tile('添加规则', '耗时与任务设置', {type: 'rules'}),
        section('截止日期与时间', [dateField('dueDate', '截止日期（可留空）', d.dueDate), ...(state.time ? [dateField('dueTime', '截止时间（可留空）', d.dueTime, 'timeInput')] : [b('＋ 添加具体时间', {type: 'time'})])]),
      ]),
      ...(state.templateName ? [t(`已套用「${state.templateName}」，修改不会影响原模板`, 'muted')] : [])];
    footerNode = footer(d.mode === 'batch' ? '预览安排' : '保存任务', {type: d.mode === 'batch' ? 'preview' : 'save'});
    action = [{label: '存为模板', presentation: 'menu', event: {type: 'saveTemplate'}}];
  }
  if (state.message) children.push(notice(state.message, 'success'));
  if (state.error) children.push(notice(state.error, 'warning'));
  // Hidden controls keep their values in the native form cache. Synchronize
  // the current draft rather than clearing that cache when changing subpages.
  const values = {...d, ...(state.step === 'rules' ? state.ruleDraft : {})};
  const replaceForms = Object.fromEntries(knownFields.map(key => [key, values[key] ?? null]));
  for (const key of adjustFields) if (state[key] !== undefined) replaceForms[key] = state[key];
  replaceForms.templateSearch = state.templateSearch || '';
  replaceForms.ruleSearch = state.ruleSearch || '';
  return {state, replaceForms, header: {title, ...(state.step !== 'create' ? {backEvent: {type: 'back'}} : {}), ...(action ? {actions: action} : {})}, tree: {type: 'column', key: 'planner:creation:' + state.step, scrollKey: 'planner:creation:' + state.step, compact: true, spacing: 8, children, ...(state.step === 'preview' && state.creationPlanId ? {planReview: {planId: state.creationPlanId, eventType: 'confirmCreation'}} : {}), ...(footerNode ? {footer: footerNode} : {})}};
}

function ruleConfiguration(d, id) {
  if (id === 'interval') return d.repeatKind === 'daily' ? [t('每天安排一次；若当天无法安排，预览会明确显示。', 'muted')] : [{type: 'row', layout: 'flex', children: [{...numberField('minDays', '最少（天）', d.minDays), flex: 1}, {...numberField('maxDays', '最多（天）', d.maxDays), flex: 1}]}, t('相邻两次任务的日期间隔', 'muted')];
  if (id === 'weekdays') return [{type: 'multiSelect', key: 'weekdays', text: '选择允许星期', value: d.weekdays, items: weekdays.map((label, index) => ({label, value: index + 1})), event: {type: 'field', key: 'weekdays'}}];
  if (id === 'window') return [{type: 'row', layout: 'flex', children: [{...dateField('windowStart', '开始', d.windowStart, 'timeInput'), flex: 1}, {...dateField('windowEnd', '结束', d.windowEnd, 'timeInput'), flex: 1}]}];
  return [{type: 'select', key: 'priority', text: '优先级', value: Number(d.priority), items: ['普通', '较高', '高', '最高'].map((label, value) => ({label, value})), event: {type: 'field', key: 'priority'}}];
}
