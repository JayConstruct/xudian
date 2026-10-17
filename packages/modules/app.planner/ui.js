import {services, ui, clock} from '@xudian/sdk';
import {add} from './engine.js';
import {renderPlanner} from './ux.js';

const ref = id => ({moduleId: 'app.planner', serviceId: 'planner.' + id, majorVersion: 1});
const query = (id, input = {}) => services.query(ref(id), input);
async function execute(id, input) {
  const prepared = await services.prepare(ref(id), input);
  if (await ui.review(prepared.planId)) return services.commit(prepared.planId);
}
const text = value => ({type: 'text', text: value});
const button = (label, event, variant = 'tonal') => ({type: 'button', text: label, event, variant});
const fullWidthFooter = child => ({type: 'column', spacing: 0, children: [child]});
const row = (title, subtitle, event) => ({type: 'listTile', title, subtitle, event});
const field = (key, label, value, type = 'text', options) => ({key, label, value: value ?? '', type, ...(options ? {options} : {})});
const input = (key, label, value, multiline = false) => ({type: 'input', key, text: label, value: String(value ?? ''), multiline, onChangeEvent: {type: 'field', key}});
const temporal = (key, label, value, type = 'dateInput') => ({type, key, text: label, value: value || null, clearable: true, event: {type: 'field', key}});
const check = (key, label, value) => ({type: 'checkbox', key, text: label, value: !!value, event: {type: 'field', key}});
const kinds = [['once', '单次任务'], ['daily', '每日'], ['weekly', '每周多次'], ['interval', '最大间隔']].map(([value, label]) => ({value, label}));
const parseSlots = value => String(value || '').split(/[,，]/).filter(s => s.trim()).map(s => { const [start, end] = s.trim().split('-'); return {start, end}; });

export async function render(input = {}) {
  const pageId = input.context?.pageId;
  if (pageId === 'app.planner.tools') return tools(input);
  if (pageId === 'app.planner.editor') return occurrenceEditor(input);
  if (pageId === 'app.planner.summary') {
    const a = await query('availability.get'), today = await clock.today(a.timezone);
    const data = await query('candidates.list', {startDate: input.context?.selectedDate || today, days: 1});
    if (input.event?.type === 'openPlanner') await ui.navigate('app.planner.home');
    return {state: {}, tree: row('任务规划', `${data.candidates.filter(c => ['pending', 'overdue'].includes(c.status)).length}项待安排 · ${data.conflicts.length}项冲突`, {type: 'openPlanner'})};
  }
  // The graphical planner is the sole home page. Rule and instance tools use
  // their own progressive panels and never replace it with a second home UI.
  return renderPlanner(input);
}

async function tools({state = {}, event, context = {}, formValues = {}}) {
  state = {...state};
  const a = await query('availability.get'), today = await clock.today(a.timezone);
  state.screen ||= context.screen || 'rules';
  state.draft = {...state.draft, ...formValues};
  if (event?.type === 'field') state.draft[event.key] = event.value;
  try {
    if (event?.type === 'screen') state.screen = event.screen;
    if (event?.type === 'editRule') {
      const r = event.rule;
      state.originalRule = r || null;
      state.draft = ruleDraft(r, a, today);
      state.ruleStep = null;
      state.screen = 'rule';
    }
    if (event?.type === 'ruleStep') state.ruleStep = event.step;
    if (event?.type === 'ruleBack') state.ruleStep = null;
    if (event?.type === 'saveRule') {
      const d = state.draft, original = state.originalRule;
      const titles = String(d.titles || '').split('\n').map(s => s.trim()).filter(Boolean);
      if (!titles.length) throw Error('请填写任务名称');
      if (original?.id && titles.length !== 1) throw Error('编辑规则仅填写一个任务名称');
      const saved = await execute('rules.save', {rules: titles.map(title => ({
        ...(original?.id ? {id: original.id, expectedVersion: original.version} : {}),
        title, kind: d.kind, timezone: a.timezone, startDate: d.startDate, endDate: d.endDate || undefined,
        estimatedMinutes: Number(d.estimatedMinutes), times: [{start: d.start, end: d.end}],
        weekdays: String(d.weekdays).split(/[,，\s]+/).filter(Boolean).map(Number), perWeek: Number(d.perWeek),
        maxGapDays: Number(d.maxGapDays), earlyDays: Number(d.earlyDays), lastCompletedOn: d.lastCompletedOn || null,
        firstDeadline: d.firstDeadline, optional: !!d.optional, priority: Number(d.priority), status: original?.status || 'active',
      }))});
      if (saved) { state.screen = 'rules'; state.draft = {}; state.originalRule = null; }
    }
    if (event?.type === 'ruleStatus') {
      const r = {...event.rule, status: event.status, expectedVersion: event.rule.version};
      delete r.version; delete r.effectiveOn;
      await execute('rules.save', {rules: [r]});
    }
    if (event?.type === 'settings') {
      const result = await settings(a);
      if (result) await ui.notify({message: '规划设置已保存', kind: 'success'});
    }
    if (event?.type === 'exception') {
      const v = await ui.dialog({title: '当天可用时间', fields: [field('date', '日期', today, 'date'), field('slots', '可用时段；留空表示当天很忙', '18:00-22:00')]});
      if (v) await execute('availability.save', {availability: {...a, exceptions: {...a.exceptions, [v.date]: parseSlots(v.slots)}}});
    }
    if (event?.type === 'busy') {
      const v = await ui.dialog({title: '添加忙碌时段', fields: [field('date', '日期', today, 'date'), field('start', '开始', '12:00', 'time'), field('end', '结束', '13:00', 'time')]});
      if (v) await execute('availability.save', {availability: {...a, busy: [...a.busy, v]}});
    }
    if (event?.type === 'clearBusy') {
      const answer = await ui.dialog({title: '清除手动忙碌时段', fields: [field('confirm', `清除${a.busy.length}项手动占用`, false, 'boolean')]});
      if (answer?.confirm) await execute('availability.save', {availability: {...a, busy: []}});
    }
    if (event?.type === 'attach') await attachExisting(a, today);
    delete state.error;
  } catch (e) { state.error = String(e); }
  let children, title = '规划规则', footer;
  if (state.screen === 'rule') {
    title = state.originalRule?.id ? '编辑规则' : '添加规则';
    const d = state.draft;
    children = state.ruleStep === 'time' ? [
      temporal('startDate', '允许开始日期', d.startDate), temporal('endDate', '规则结束日期', d.endDate),
      temporal('start', '每日允许开始', d.start, 'timeInput'), temporal('end', '每日允许结束', d.end, 'timeInput'),
      input('estimatedMinutes', '预计分钟', d.estimatedMinutes), input('weekdays', '允许星期（1至7，以逗号分隔）', d.weekdays),
    ] : state.ruleStep === 'repeat' ? [
      {type: 'select', key: 'kind', text: '重复方式', value: d.kind, items: kinds, event: {type: 'field', key: 'kind'}},
      ...(d.kind === 'weekly' ? [input('perWeek', '每周次数', d.perWeek)] : []),
      ...(d.kind === 'interval' ? [input('maxGapDays', '最大间隔自然日', d.maxGapDays), input('earlyDays', '允许提前天数', d.earlyDays), temporal('lastCompletedOn', '上次实际完成日（从未执行可留空）', d.lastCompletedOn), temporal('firstDeadline', '首次最晚日期', d.firstDeadline)] : []),
      check('optional', '有空再做（不适用于最大间隔）', d.optional), input('priority', '优先级 0–3', d.priority),
    ] : [
      input('titles', state.originalRule?.id ? '任务名称' : '任务名称（每行一项）', d.titles, true),
      row('允许安排时段', `${d.estimatedMinutes}分钟 · ${d.start}—${d.end}`, {type: 'ruleStep', step: 'time'}),
      row('重复方式', kinds.find(k => k.value === d.kind)?.label || '', {type: 'ruleStep', step: 'repeat'}),
      text('规则生成的任务先进入规划，保存规则不会立即占用执行时段。'),
    ];
    footer = state.ruleStep ? null : button('保存规则', {type: 'saveRule'}, 'filled');
  } else if (state.screen === 'settings') {
    title = '规划设置';
    children = [
      row('每周可用时间', `${a.timezone} · 默认${a.defaultMinutes}分钟 · 缓冲${a.bufferMinutes}分钟`, {type: 'settings'}),
      row('日期例外', '单独设置某一天的可用时段', {type: 'exception'}),
      row('添加忙碌时段', '在自动安排中避开手动占用', {type: 'busy'}),
      ...(a.busy.length ? [row('清除手动忙碌时段', `共${a.busy.length}项，保留其他来源安排`, {type: 'clearBusy'})] : []),
      row('选择已有待办', '保留原任务，补充安排窗口', {type: 'attach'}),
      row('规划规则', '管理单次与持续规则', {type: 'screen', screen: 'rules'}),
    ];
  } else {
    const rules = await query('rules.list');
    children = [
      row('添加规则', '配置时段、耗时与重复方式', {type: 'editRule'}),
      {type: 'disclosure', text: '从模板开始', children: [
        row('每日规划', '15分钟 · 08:00—10:00', {type: 'editRule', rule: {title: '每日规划', kind: 'daily', estimatedMinutes: 15, times: [{start: '08:00', end: '10:00'}]}}),
        row('每日复盘', '15分钟 · 20:00—23:00', {type: 'editRule', rule: {title: '每日复盘', kind: 'daily', estimatedMinutes: 15, times: [{start: '20:00', end: '23:00'}]}}),
        row('打字练习', '有空再做 · 15分钟', {type: 'editRule', rule: {title: '打字练习', kind: 'daily', estimatedMinutes: 15, times: [{start: '09:00', end: '22:00'}], optional: true}}),
      ]},
      ...rules.map(rule => {
        const r = rule.versions[rule.versions.length - 1];
        return {type: 'card', key: rule.id, children: [
          row(r.title, `${kinds.find(k => k.value === r.kind)?.label || ''} · ${r.estimatedMinutes}分钟 · ${{active: '生效中', paused: '已暂停', ended: '已结束'}[r.status] || r.status}`, {type: 'editRule', rule: r}),
          {type: 'disclosure', text: '规则操作', children: [
            button(r.status === 'paused' ? '恢复规则' : '暂停规则', {type: 'ruleStatus', rule: r, status: r.status === 'paused' ? 'active' : 'paused'}),
            button('结束规则', {type: 'ruleStatus', rule: r, status: 'ended'}),
          ]},
        ]};
      }),
      ...(!rules.length ? [text('暂无规则。普通任务可直接从首页新建。')] : []),
    ];
  }
  if (state.error) children.push(text(state.error));
  return {state, ...(event?.type === 'editRule' || event?.type === 'saveRule' ? {clearForms: Object.keys(state.draft || {})} : {}), header: {title, ...(state.screen === 'rule' ? {backEvent: state.ruleStep ? {type: 'ruleBack'} : {type: 'screen', screen: 'rules'}} : {})}, tree: {type: 'column', key: 'planner:tools:' + state.screen, children, ...(footer ? {footer: fullWidthFooter(footer)} : {})}};
}

function ruleDraft(r, a, today) {
  return {titles: r?.title || '', kind: r?.kind || 'once', startDate: r?.startDate || today, endDate: r?.endDate || add(today, 6),
    estimatedMinutes: r?.estimatedMinutes || a.defaultMinutes, start: r?.times?.[0]?.start || '18:00', end: r?.times?.[0]?.end || '22:00',
    weekdays: (r?.weekdays || [1, 2, 3, 4, 5, 6, 7]).join(','), perWeek: r?.perWeek || 2, maxGapDays: r?.maxGapDays || 6,
    earlyDays: r?.earlyDays ?? 2, lastCompletedOn: r?.lastCompletedOn || null, firstDeadline: r?.firstDeadline || add(today, 6), optional: !!r?.optional, priority: r?.priority || 0};
}
async function settings(a) {
  const v = await ui.dialog({title: '每周可用时间', fields: [
    field('timezone', 'IANA时区', a.timezone), field('defaultMinutes', '默认耗时（分钟）', a.defaultMinutes, 'number'), field('bufferMinutes', '任务间缓冲（分钟）', a.bufferMinutes, 'number'),
    ...Array.from({length: 7}, (_, i) => field('day' + (i + 1), ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][i] + '（18:00-22:00，多段用逗号，留空无空闲）', (a.weekly[i + 1] || []).map(x => x.start + '-' + x.end).join(','))),
  ]});
  if (!v) return;
  const weekly = {};
  for (let i = 1; i <= 7; i++) weekly[i] = parseSlots(v['day' + i]);
  return execute('availability.save', {availability: {...a, timezone: v.timezone, defaultMinutes: Number(v.defaultMinutes), bufferMinutes: Number(v.bufferMinutes), weekly}});
}
async function attachExisting(a, today) {
  const data = await query('candidates.list', {startDate: today, days: 5});
  if (!data.existingTasks.length) throw Error('没有可加入的待办');
  const v = await ui.dialog({title: '选择已有待办', fields: [
    field('taskId', '待办', data.existingTasks[0].id, 'select', data.existingTasks.map(t => ({value: t.id, label: t.title}))),
    field('startDate', '允许开始日期', today, 'date'), field('endDate', '最晚日期', add(today, 4), 'date'),
    field('estimatedMinutes', '预计分钟', a.defaultMinutes, 'number'), field('start', '允许开始时间', '18:00', 'time'), field('end', '允许结束时间', '22:00', 'time'),
  ]});
  if (v) return execute('occurrence.update', {taskId: v.taskId, window: {startDate: v.startDate, endDate: v.endDate, estimatedMinutes: Number(v.estimatedMinutes), times: [{start: v.start, end: v.end}]}});
}

async function occurrenceEditor({state = {}, event, context = {}, formValues = {}}) {
  state = {...state};
  const c = context.candidate;
  if (!c) return {state, tree: text('实例不可用，请重新打开')};
  state.draft ||= {startDate: c.startDate, endDate: c.endDate, start: c.times[0].start, end: c.times[0].end, estimatedMinutes: c.estimatedMinutes, priority: c.priority, locked: !!c.locked};
  state.draft = {...state.draft, ...formValues};
  if (event?.type === 'field') state.draft[event.key] = event.value;
  try {
    if (event?.type === 'save') {
      const d = state.draft;
      const changes = c.status === 'confirmed' ? {locked: !!d.locked} : {startDate: d.startDate, endDate: d.endDate, times: [{start: d.start, end: d.end}], estimatedMinutes: Number(d.estimatedMinutes), priority: Number(d.priority), locked: !!d.locked};
      if (await execute('occurrence.update', {id: c.id, candidate: c, changes})) { await ui.navigate('app.planner.home'); return {state: {}, clearForms: Object.keys(d), tree: text('实例已更新')}; }
    }
    if (event?.type === 'status') {
      if (await execute('occurrence.update', {id: c.id, candidate: c, changes: {status: event.status}})) { await ui.navigate('app.planner.home'); return {state: {}, clearForms: Object.keys(state.draft), tree: text('实例已更新')}; }
    }
    delete state.error;
  } catch (e) { state.error = String(e); }
  const d = state.draft;
  return {state, header: {title: c.title}, tree: {type: 'column', key: 'planner:occurrence:' + c.id, children: [
    text('调整规则实例的允许安排窗口'),
    ...(c.status === 'confirmed' ? [text('已确认任务的具体起止时间请从图形任务详情调整。')] : [
      temporal('startDate', '允许开始日期', d.startDate), temporal('endDate', '最晚日期', d.endDate),
      temporal('start', '每日允许开始', d.start, 'timeInput'), temporal('end', '每日允许结束', d.end, 'timeInput'),
      input('estimatedMinutes', '预计分钟', d.estimatedMinutes), input('priority', '优先级 0–3', d.priority),
    ]),
    check('locked', '固定时间', d.locked),
    {type: 'disclosure', text: '实例操作', children: [button('跳过本次', {type: 'status', status: 'skipped'}), button('取消本次', {type: 'status', status: 'cancelled'})]},
    ...(state.error ? [text(state.error)] : []),
  ], footer: fullWidthFooter(button('保存实例', {type: 'save'}, 'filled'))}};
}
