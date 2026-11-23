import {services, ui, clock} from '@xudian/sdk';
import {add} from './engine.js';
import {text, button, row, pair, section, group, footer, note, iconRow, keyValue, pageInset} from './page_helpers.js';
import {renderPlanner} from './planner_page.js';
import {renderBatches} from './batch_ui.js';

const ref = id => ({moduleId: 'app.planner', serviceId: 'planner.' + id, majorVersion: 1});
const query = (id, input = {}) => services.query(ref(id), input);
async function execute(id, input) {
  const prepared = await services.prepare(ref(id), input);
  if (await ui.review(prepared.planId)) return services.commit(prepared.planId);
}
const field = (key, label, value, type = 'text', options) => ({key, label, value: value ?? '', type, ...(options ? {options} : {})});
const input = (key, label, value, multiline = false) => ({type: 'input', presentation: 'labeled', key, text: label, value: String(value ?? ''), multiline, minLines: 1, onChangeEvent: {type: 'field', key}});
const temporal = (key, label, value, type = 'dateInput') => ({type, key, presentation: 'labeled', text: label, value: value || null, clearable: ['endDate', 'lastCompletedOn'].includes(key), event: {type: 'field', key}});
const check = (key, label, value) => ({type: 'checkbox', key, text: label, value: !!value, event: {type: 'field', key}});
const weekdays = ['周一','周二','周三','周四','周五','周六','周日'];
const kinds = [['once', '单次任务'], ['daily', '每日'], ['weekly', '每周多次'], ['interval', '最大间隔']].map(([value, label]) => ({value, label}));
const parseSlots = value => String(value || '').split(/[,，]/).filter(s => s.trim()).map(s => { const [start, end] = s.trim().split('-'); return {start, end}; });

export async function render(input = {}) {
  const pageId = input.context?.pageId;
  if (pageId === 'app.planner.batches') return renderBatches(input);
  if (pageId === 'app.planner.tools') return tools(input);
  if (pageId === 'app.planner.editor') return occurrenceEditor(input);
  if (pageId === 'app.planner.summary') {
    const a = await query('availability.get'), today = await clock.today(a.timezone);
    const data = await query('candidates.list', {startDate: input.context?.selectedDate || today, days: 1});
    if (input.event?.type === 'openPlanner') await ui.navigate('app.planner.home');
    return {state: {}, tree: row('任务规划', `${data.candidates.filter(c => ['pending', 'overdue'].includes(c.status)).length}项待安排 · ${data.conflicts.length}项冲突`, {type: 'openPlanner'})};
  }
  // Rule and instance routes share this handler with the graphical planner.
  return renderPlanner(input);
}

async function tools({state = {}, event, context = {}, formValues = {}}) {
  state = {...state};
  let a = await query('availability.get');
  const today = await clock.today(a.timezone);
  state.screen ||= context.screen || 'rules';
  state.draft = {...state.draft, ...formValues};
  if (event?.type === 'field') state.draft[event.key] = event.value;
  let replaceForms;
  try {
    if (event?.type === 'screen') {
      if (state.screen === 'settings' && event.screen === 'rules') state.rulesFromSettings = true;
      state.screen = event.screen;
    }
    if (event?.type === 'templates') state.templates = !state.templates;
    if (event?.type === 'ruleActions') state.ruleActions = state.ruleActions === event.id ? null : event.id;
    if (event?.type === 'editRule') {
      const r = event.rule;
      state.originalRule = r || null;
      state.draft = ruleDraft(r, a, today);
      replaceForms = {...state.draft};
      state.ruleStep = null;
      state.screen = 'rule';
    }
    if (event?.type === 'ruleStep') state.ruleStep = event.step;
    if (event?.type === 'field' && event.key === 'kind' && event.value === 'interval') state.draft.optional = false;
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
        firstDeadline: d.firstDeadline, optional: d.kind !== 'interval' && !!d.optional, priority: Number(d.priority), status: original?.status || 'active',
      }))});
      if (saved) { state.screen = 'rules'; state.draft = {}; state.originalRule = null; }
    }
    if (event?.type === 'ruleStatus') {
      const r = {...event.rule, status: event.status, expectedVersion: event.rule.version};
      delete r.version; delete r.effectiveOn;
      await execute('rules.save', {rules: [r]});
    }
    if (event?.type === 'settings') {
      state.screen = 'weekly';
      state.weekly = Object.fromEntries(weekdays.map((_, i) => [i + 1, (a.weekly[i + 1] || []).map(slot => slot.start + '-' + slot.end).join(',')]));
      state.draft = {timezone: a.timezone, defaultMinutes: String(a.defaultMinutes), bufferMinutes: String(a.bufferMinutes)};
      replaceForms = {...state.draft};
    }
    if (event?.type === 'weekDay') {
      const result = await ui.dialog({title: weekdays[event.day - 1], presentation: 'sheet', fullWidthActions: true, fields: [
        {...field('slots', '可用时段', state.weekly[event.day]), presentation: 'labeled', helperText: '多段用逗号分隔，留空表示当天无空闲。'},
      ]});
      if (result) state.weekly[event.day] = result.slots;
    }
    if (event?.type === 'saveWeekly') {
      const weekly = Object.fromEntries(Object.entries(state.weekly).map(([day, value]) => [day, parseSlots(value)]));
      if (await execute('availability.save', {availability: {...a, weekly, timezone: state.draft.timezone, defaultMinutes: Number(state.draft.defaultMinutes), bufferMinutes: Number(state.draft.bufferMinutes)}})) {
        a = await query('availability.get');
        state.screen = 'settings';
        await ui.notify({message: '规划设置已保存', kind: 'success'});
      }
    }
    if (event?.type === 'exception') {
      const v = await ui.dialog({title: '当天可用时间', presentation: 'sheet', fullWidthActions: true, fields: [
        {...field('date', '日期', today, 'date'), clearable: false, presentation: 'labeled'},
        {...field('slots', '可用时段', '18:00-22:00'), presentation: 'labeled', helperText: '留空表示当天没有可用时间。'},
      ]});
      if (v) await execute('availability.save', {availability: {...a, exceptions: {...a.exceptions, [v.date]: parseSlots(v.slots)}}});
    }
    if (event?.type === 'busy') {
      const v = await ui.dialog({title: '添加忙碌时段', presentation: 'sheet', fullWidthActions: true, fields: [
        {...field('date', '日期', today, 'date'), clearable: false, presentation: 'labeled'},
        {...field('start', '开始', '12:00', 'time'), row: 'range', clearable: false, presentation: 'labeled'},
        {...field('end', '结束', '13:00', 'time'), row: 'range', clearable: false, presentation: 'labeled'},
      ]});
      if (v && await execute('availability.save', {availability: {...a, busy: [...a.busy, v]}})) a = await query('availability.get');
    }
    if (event?.type === 'clearBusy') {
      const answer = await ui.dialog({title: '清除手动忙碌时段', fields: [field('confirm', `清除${a.busy.length}项手动占用`, false, 'boolean')]});
      if (answer?.confirm && await execute('availability.save', {availability: {...a, busy: []}})) a = await query('availability.get');
    }
    if (event?.type === 'attach') await attachExisting(a, today);
    delete state.error;
  } catch (e) { state.error = String(e); }
  let children, title = '规划规则', actions = [], backEvent;
  if (state.screen === 'rule') {
    const d = state.draft;
    backEvent = state.ruleStep ? {type: 'ruleBack'} : {type: 'screen', screen: 'rules'};
    if (state.ruleStep === 'time') {
      title = '允许安排时段';
      children = [
        section('日期', [temporal('startDate', '允许开始日期', d.startDate), temporal('endDate', '规则结束日期', d.endDate)]),
        section('每日时段', [
          pair(temporal('start', '允许开始', d.start, 'timeInput'), temporal('end', '允许结束', d.end, 'timeInput')),
          input('estimatedMinutes', '预计分钟', d.estimatedMinutes), input('weekdays', '允许星期', d.weekdays),
        ]),
      ];
    } else if (state.ruleStep === 'repeat') {
      title = '重复方式';
      children = [
        section('规则', [
          {type: 'select', key: 'kind', text: '重复方式', presentation: 'labeled', value: d.kind, items: kinds, event: {type: 'field', key: 'kind'}},
          ...(d.kind === 'weekly' ? [input('perWeek', '每周次数', d.perWeek)] : []),
          ...(d.kind === 'interval' ? [
            pair(input('maxGapDays', '最大间隔天数', d.maxGapDays), input('earlyDays', '允许提前天数', d.earlyDays)),
            temporal('lastCompletedOn', '上次实际完成日', d.lastCompletedOn), temporal('firstDeadline', '首次最晚日期', d.firstDeadline),
          ] : [check('optional', '有空再做', d.optional)]),
          input('priority', '优先级', d.priority),
        ]),
        ...(d.kind === 'interval' ? [note('最大间隔规则按自然日计算。')] : []),
      ];
    } else {
      title = state.originalRule?.id ? '编辑规则' : '添加规则';
      children = [
        section('任务信息', [input('titles', state.originalRule?.id ? '任务名称' : '任务名称（每行一项）', d.titles, !state.originalRule?.id)]),
        group('安排条件', [
          iconRow('允许安排时段', `${d.estimatedMinutes} 分钟 · ${d.start}–${d.end}`, {type: 'ruleStep', step: 'time'}, 'schedule'),
          iconRow('重复方式', kinds.find(k => k.value === d.kind)?.label, {type: 'ruleStep', step: 'repeat'}, 'repeat'),
        ]),
        note('规则生成的任务先进入规划，保存规则后可继续安排具体时段。'),
      ];
      actions.push(button('保存规则', {type: 'saveRule'}, 'filled'));
    }
  } else if (state.screen === 'weekly') {
    title = '每周可用时间';
    backEvent = {type: 'screen', screen: 'settings'};
    children = [
      section('时段设置', [
        input('timezone', 'IANA 时区', state.draft.timezone),
        pair(input('defaultMinutes', '默认耗时（分钟）', state.draft.defaultMinutes), input('bufferMinutes', '任务间缓冲（分钟）', state.draft.bufferMinutes)),
      ]),
      group('每周时段', weekdays.map((label, i) => ({
        ...keyValue(label, state.weekly[i + 1] || '无空闲'), event: {type: 'weekDay', day: i + 1},
      }))),
      note('点时段可编辑，多段用逗号分隔，留空表示当天无空闲。'),
    ];
    actions = [button('取消', backEvent, 'outlined'), button('继续', {type: 'saveWeekly'}, 'filled')];
  } else if (state.screen === 'settings') {
    title = '规划设置';
    children = [
      group('可用时间', [
        iconRow('每周可用时间', `${a.timezone} · 默认 ${a.defaultMinutes} 分钟 · 缓冲 ${a.bufferMinutes} 分钟`, {type: 'settings'}, 'schedule'),
        iconRow('日期例外', '单独设置某一天的可用时段', {type: 'exception'}, 'calendar'),
        iconRow('添加忙碌时段', '记录需要避开的手动占用', {type: 'busy'}, 'calendarRemove'),
        iconRow('清除手动忙碌时段', `共 ${a.busy.length} 项`, {type: 'clearBusy'}, 'delete', {disabled: !a.busy.length}),
      ]),
      group('任务与规则', [
        iconRow('选择已有待办', '为已有任务增加安排窗口', {type: 'attach'}, 'clipboard'),
        iconRow('规划规则', '管理单次与持续规则', {type: 'screen', screen: 'rules'}, 'repeat'),
      ]),
    ];
  } else {
    if (state.rulesFromSettings) backEvent = {type: 'screen', screen: 'settings'};
    const rules = await query('rules.list');
    const templates = [
      {title: '每日规划', start: '08:00', end: '10:00'},
      {title: '每日复盘', start: '20:00', end: '23:00'},
      {title: '打字练习', start: '09:00', end: '22:00', optional: true},
    ];
    children = [
      group('新规则', [
        iconRow('添加规则', '配置时段、耗时与重复方式', {type: 'editRule'}, 'add'),
        iconRow('从模板开始', null, {type: 'templates'}, 'layers', {expanded: !!state.templates, trailingIcon: state.templates ? 'expandLess' : 'expandMore'}),
        ...(state.templates ? templates.map(({title, start, end, optional}) => row(title, optional ? '有空再做 · 15 分钟' : `15 分钟 · ${start}–${end}`, {
          type: 'editRule', rule: {title, kind: 'daily', estimatedMinutes: 15, times: [{start, end}], optional: !!optional},
        })) : []),
      ]),
      group('已有规则', rules.length ? rules.flatMap(rule => {
        const r = rule.versions[rule.versions.length - 1], open = state.ruleActions === rule.id;
        return [
          iconRow(r.title, `${kinds.find(k => k.value === r.kind)?.label || ''} · ${r.estimatedMinutes} 分钟 · ${{active: '生效中', paused: '已暂停', ended: '已结束'}[r.status] || r.status}`, {type: 'editRule', rule: r}, 'repeat'),
          {...row('规则操作', null, {type: 'ruleActions', id: rule.id}), expanded: open, trailingIcon: open ? 'expandLess' : 'expandMore'},
          ...(open ? [{type: 'row', children: [
            button(r.status === 'paused' ? '恢复规则' : '暂停规则', {type: 'ruleStatus', rule: r, status: r.status === 'paused' ? 'active' : 'paused'}, 'text'),
            {...button('结束规则', {type: 'ruleStatus', rule: r, status: 'ended'}, 'text'), tone: 'danger'},
          ]}] : []),
        ];
      }) : [{type: 'emptyState', title: '暂无规则', text: '普通任务可直接从首页新建。', icon: 'repeat'}]),
    ];
  }
  if (state.error) children.push({type: 'notice', tone: 'warning', text: state.error});
  return {state, ...(replaceForms ? {replaceForms} : {}), header: {title, minHeight: 65, compact: true, titleStyle: 'large', backIcon: state.screen === 'weekly' ? 'close' : 'chevron', ...(backEvent ? {backEvent} : {})},
    tree: {type: 'column', key: 'planner:tools:' + state.screen, scrollKey: state.screen + (state.ruleStep || ''), queueInputActions: true, ...pageInset(children), ...(actions.length ? footer(...actions) : {})}};
}

function ruleDraft(r, a, today) {
  return {titles: r?.title || '', kind: r?.kind || 'once', startDate: r?.startDate || today, endDate: r?.endDate || add(today, 6),
    estimatedMinutes: r?.estimatedMinutes || a.defaultMinutes, start: r?.times?.[0]?.start || '18:00', end: r?.times?.[0]?.end || '22:00',
    weekdays: (r?.weekdays || [1, 2, 3, 4, 5, 6, 7]).join(','), perWeek: r?.perWeek || 2, maxGapDays: r?.maxGapDays || 6,
    earlyDays: r?.earlyDays ?? 2, lastCompletedOn: r?.lastCompletedOn || null, firstDeadline: r?.firstDeadline || add(today, 6), optional: !!r?.optional, priority: r?.priority || 0};
}
async function attachExisting(a, today) {
  const data = await query('candidates.list', {startDate: today, days: 5});
  if (!data.existingTasks.length) throw Error('没有可加入的待办');
  const v = await ui.dialog({title: '选择已有待办', presentation: 'sheet', fullWidthActions: true, fields: [
    field('taskId', '待办', data.existingTasks[0].id, 'select', data.existingTasks.map(t => ({value: t.id, label: t.title}))),
    field('startDate', '允许开始日期', today, 'date'), field('endDate', '最晚日期', add(today, 4), 'date'),
    field('estimatedMinutes', '预计分钟', a.defaultMinutes, 'number'), field('start', '允许开始时间', '18:00', 'time'), field('end', '允许结束时间', '22:00', 'time'),
  ].map(f => ({...f, presentation: 'labeled', clearable: false, ...(f.type === 'time' ? {row: 'range'} : {})}))});
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
  return {state, header: {title: c.title, minHeight: 65, compact: true, titleStyle: 'large'}, tree: {type: 'column', key: 'planner:occurrence:' + c.id, queueInputActions: true, ...pageInset([
    c.status === 'confirmed' ? note('已确认任务的具体起止时间请从图形任务详情调整。') : section('允许安排窗口', [
      pair(temporal('startDate', '允许开始日期', d.startDate), {...temporal('endDate', '最晚日期', d.endDate), clearable: false}),
      pair(temporal('start', '每日允许开始', d.start, 'timeInput'), temporal('end', '每日允许结束', d.end, 'timeInput')),
      pair(input('estimatedMinutes', '预计分钟', d.estimatedMinutes), input('priority', '优先级', d.priority)),
    ]),
    group('实例操作', [
      {...check('locked', '固定时间', d.locked), icon: 'lock', minHeight: 52},
      iconRow('跳过本次', null, {type: 'status', status: 'skipped'}, 'skipNext'),
      iconRow('取消本次', null, {type: 'status', status: 'cancelled'}, 'calendarRemove'),
    ]),
    ...(state.error ? [{type: 'notice', tone: 'warning', text: state.error}] : []),
  ]), ...footer(button('保存实例', {type: 'save'}, 'filled'))}};
}
