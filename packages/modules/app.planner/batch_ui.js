import {services, ui, ids} from '@xudian/sdk';
import {renderCreation} from './creation.js';
import {renderTaskDetail} from './ux.js';

const ref = id => ({moduleId: 'app.planner', serviceId: 'planner.' + id, majorVersion: 1});
const query = (id, input = {}) => services.query(ref(id), input);
const text = (value, style = 'body', extra = {}) => ({type: 'text', text: String(value), style, ...extra});
const column = (children, spacing = 4, extra = {}) => ({type: 'column', spacing, trailingSpacing: false, children, ...extra});
const row = (children, extra = {}) => ({type: 'row', layout: 'flex', spacing: 10, children, ...extra});
const icon = (name, extra = {}) => ({type: 'icon', icon: name, size: 20, tone: 'muted', ...extra});
const badge = (label, tone = 'muted') => ({type: 'badge', text: label, tone});
const button = (label, event, variant = 'text', extra = {}) => ({type: 'button', text: label, event, variant, ...extra});
const card = (children, extra = {}) => ({type: 'card', variant: 'outlined', padding: 14, children, ...extra});
const field = (key, label, value, extra = {}) => ({type: 'input', key, text: label, value: value ?? '', onChangeEvent: {type: 'editField', key}, ...extra});
const temporal = (key, label, value) => ({type: 'timeInput', key, text: label, value, event: {type: 'editField', key}});
const statusLabels = {active: '进行中', paused: '已暂停', ended: '已结束'};
const statusTones = {active: 'success', paused: 'muted', ended: 'muted'};
const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const editKeys = ['editTitle', 'editDuration', 'editMin', 'editMax', 'editStart', 'editEnd', 'editPreferredTime', 'editWeekdays'];
const cleanError = error => String(error).replace(/^Error:\s*/, '');
const dateLabel = value => value ? value.slice(5).replace('-', '/') : '';
const weekdayLabel = value => value ? weekdays[(new Date(value + 'T00:00:00Z').getUTCDay() + 6) % 7] : '';
const intervalLabel = draft => {
  const interval = draft.rules.interval;
  return interval.minDays === 1 && interval.maxDays === 1 ? '每天一次' :
    interval.minDays === interval.maxDays ? '每' + interval.minDays + '天' :
      '每' + interval.minDays + '～' + interval.maxDays + '天';
};
const weekLabel = values => values.length === 7 ? '周一至周日' :
  values.join(',') === '1,2,3,4,5' ? '周一至周五' : values.map(day => weekdays[day - 1]).join('、');
const menuAction = (label, type, name = 'refresh') => ({label, icon: name, presentation: 'menu', event: {type}});
const issueLabels = batch => (batch.blocked || []).map(item => typeof item === 'string' ? item : item.reason || String(item));
function appearance(title) {
  if (/健身|训练|运动|跑步/.test(title)) return {name: 'fitness', tone: 'warning'};
  if (/复盘|规划|整理/.test(title)) return {name: 'clipboard', tone: 'accent'};
  if (/速写|绘画|练习/.test(title)) return {name: 'edit', tone: 'muted'};
  return {name: 'book', tone: 'success'};
}
async function execute(id, input, confirmation) {
  const prepared = await services.prepare(ref(id), input);
  return await ui.review(prepared.planId, confirmation) ? services.commit(prepared.planId) : null;
}
const page = (state, title, children, footer, options = {}) => ({
  state,
  header: {title, compact: true, backIcon: 'chevron', ...(options.back ? {backEvent: {type: options.back}} : {}),
    actions: options.actions || [menuAction('刷新', 'refresh')]},
  ...(options.replaceForms ? {replaceForms: options.replaceForms} : {}),
  tree: {...column(children, options.spacing ?? 12), key: 'planner:batches:' + (options.key || state.screen || 'list'),
    scrollKey: 'planner:batches:' + (options.key || state.screen || 'list'),
    queueInputActions: true, footerStyle: 'flat',
    ...(footer ? {footer} : {}), ...(options.footerMessage ? {footerMessage: options.footerMessage} : {})},
});
const notices = state => state.error ? [{type: 'notice', tone: 'warning', text: state.error}] : [];

export async function renderBatches({state = {}, event, context = {}, formValues = {}} = {}) {
  state = {...state};
  state.screen ||= 'list';
  state.filter ||= 'all';
  state.search ||= '';
  state.tab ||= 'pending';
  state.selected ||= [];
  if (event?.type === 'creationBack') { state.screen = 'list'; delete state.creation; }
  if (event?.type === 'taskBack') { state.screen = 'detail'; delete state.taskDetail; }
  if (state.screen === 'task') {
    const rendered = await renderTaskDetail(state.taskDetail || {}, event, {taskId: state.taskId}, formValues,
      await query('availability.get'), {embedded: true});
    if (rendered.completed) {
      state.screen = 'detail'; delete state.taskDetail;
      return {...await showDetail(state), clearForms: rendered.clearForms};
    }
    return {...rendered, replaceForms: {...rendered.state.draft}, state: {...state, taskDetail: rendered.state},
      header: {...rendered.header, compact: true, backIcon: 'chevron',
        ...(!rendered.header?.backEvent ? {backEvent: {type: 'taskBack'}} : {})}};
  }
  if (state.screen === 'create') {
    const rendered = await renderCreation(state.creation || {}, event, formValues, await query('availability.get'), {embedded: true, batchMode: true});
    if (rendered.completed) {
      delete state.creation; state.screen = 'list'; delete state.cachedList; delete state.error;
      await ui.notify({message: '批量任务已创建', kind: 'success'});
      const result = await showList(state);
      return {...result, clearForms: rendered.clearForms};
    }
    return {...rendered, state: {...state, creation: rendered.state},
      header: {...rendered.header, compact: true, backIcon: 'chevron',
        ...(rendered.state.step === 'create' ? {title: '新建批量任务'} : {}),
        ...(!rendered.header?.backEvent ? {backEvent: {type: 'creationBack'}} : {})}};
  }
  try {
    if (event?.type === 'newBatch') {
      state.screen = 'create';
      return renderBatches({state, context, formValues: {}});
    }
    if (event?.type === 'search') { state.search = String(event.value ?? formValues.batchSearch ?? ''); }
    if (event?.type === 'filter') state.filter = event.status;
    if (event?.type === 'openBatch') {
      state.id = event.id; state.screen = 'detail'; state.tab = 'pending'; state.visibleRows = 4;
      state.selecting = false; state.selected = []; delete state.cachedDetail;
    }
    if (event?.type === 'backToList') { state.screen = 'list'; state.selecting = false; state.selected = []; }
    if (event?.type === 'backToDetail') { state.screen = 'detail'; delete state.preview; }
    if (event?.type === 'tab') { state.tab = event.status; state.selected = []; state.selecting = false; state.visibleRows = 4; }
    if (event?.type === 'moreRows') state.visibleRows = (state.visibleRows || 4) + 20;
    if (event?.type === 'selectMode') { state.selecting = !state.selecting; state.selected = []; }
    if (event?.type === 'selectRow') {
      const selected = new Set(state.selected);
      if (event.value ?? !selected.has(event.taskId)) selected.add(event.taskId); else selected.delete(event.taskId);
      if (selected.size > 200) throw Error('每次最多选择200项');
      state.selected = [...selected];
    }
    if (event?.type === 'selectAll') {
      const batch = await query('series.get', {id: state.id});
      state.selected = batch.rows.filter(item => item.status === 'pending').slice(0, 200).map(item => item.taskId);
    }
    if (event?.type === 'openTask') {
      state.taskId = event.taskId; state.screen = 'task'; delete state.taskDetail;
      return renderBatches({state, context, formValues: {}});
    }
    if (event?.type === 'status' || event?.type === 'endBatch') {
      const batch = state.cachedDetail || await query('series.get', {id: state.id});
      const status = event.type === 'endBatch' ? 'ended' : batch.status === 'paused' ? 'active' : 'paused';
      const label = status === 'ended' ? '结束批次' : status === 'paused' ? '暂停生成' : '恢复生成';
      const saved = await execute('series.status', {id: state.id, status, expectedRevision: batch.revision, operationKey: await ids.new()}, {
        title: label, confirmLabel: label, message: status === 'ended' ? '结束后停止补齐；已生成任务和完成记录保留。' :
          status === 'paused' ? '仅停止后续自动补齐，已生成的待执行任务和完成记录保留。' : '恢复后继续补齐未来30天，已生成任务和手动调整保持不变。',
      });
      if (saved) { await ui.notify({message: status === 'ended' ? '批次已结束' : status === 'paused' ? '已暂停生成' : '已恢复生成', kind: 'success'}); state.selecting = false; state.selected = []; }
    }
    if (event?.type === 'cancelSelected') {
      const batch = await query('series.get', {id: state.id});
      const selected = batch.rows.filter(item => state.selected.includes(item.taskId) && item.status === 'pending');
      if (!selected.length || selected.length !== state.selected.length) throw Error('所选任务状态已变化，请重新选择');
      const saved = await execute('series.tasks.cancel', {id: state.id, taskIds: selected.map(item => item.taskId),
        expectedTasks: Object.fromEntries(selected.map(item => [item.taskId, item.updatedAt])), operationKey: await ids.new()}, {
        title: '取消所选任务', confirmLabel: '取消' + selected.length + '项任务',
        message: '将取消所选' + selected.length + '项待执行任务，保留批次规则和完成记录。',
      });
      if (saved) { state.selected = []; state.selecting = false; await ui.notify({message: '所选任务已取消', kind: 'success'}); }
    }
    if (event?.type === 'issues') state.screen = 'issues';
    if (event?.type === 'retry') {
      state.retryPreview = await query('series.retry.preview', {id: state.id});
      state.screen = 'retry';
    }
    if (event?.type === 'applyRetry' && state.retryPreview) {
      if (await execute('series.retry.apply', {operationKey: await ids.new(), preview: state.retryPreview}, {
        title: '重新补齐', confirmLabel: '确认补齐', message: '按当前规则补齐未来30天，保留已生成任务。',
      })) {
        state.screen = 'detail'; delete state.retryPreview;
        await ui.notify({message: '补齐结果已更新', kind: 'success'});
      }
    }
    if (event?.type === 'editRules') {
      const batch = state.cachedDetail || await query('series.get', {id: state.id}), draft = batch.draft;
      state.editRevision = batch.revision;
      state.edit = {editTitle: draft.title, editDuration: draft.estimatedMinutes, editMin: draft.rules.interval.minDays,
        editMax: draft.rules.interval.maxDays, editStart: draft.rules.timeWindow.start, editEnd: draft.rules.timeWindow.end,
        editPreferredTime: draft.rules.preferredTime || null, editWeekdays: [...draft.rules.weekdays]};
      state.screen = 'edit'; delete state.preview;
    }
    if (state.screen === 'edit') {
      for (const key of editKeys) if (event?.type !== 'editRules' && Object.prototype.hasOwnProperty.call(formValues, key)) state.edit[key] = formValues[key];
      if (event?.type === 'editField' && editKeys.includes(event.key)) state.edit[event.key] = event.value;
      if (event?.type === 'previewRules') {
        const draft = state.edit;
        state.preview = await query('series.update.preview', {id: state.id, expectedRevision: state.editRevision,
          changes: {title: String(draft.editTitle).trim(), estimatedMinutes: Number(draft.editDuration),
            rules: {interval: {minDays: Number(draft.editMin), maxDays: Number(draft.editMax)},
              weekdays: draft.editWeekdays.map(Number), timeWindow: {start: draft.editStart, end: draft.editEnd}, preferredTime: draft.editPreferredTime || null}}});
        state.screen = 'editPreview';
      }
    }
    if (event?.type === 'resumeEdit') state.screen = 'edit';
    if (event?.type === 'applyRules' && state.preview) {
      if (await execute('series.update.apply', {operationKey: await ids.new(), preview: state.preview}, {
        title: '保存批量规则', confirmLabel: '保存规则',
        message: '仅对后续新生成的任务生效；已生成、已完成和手动调整的任务保持不变。',
      })) {
        state.screen = 'detail'; delete state.preview;
        await ui.notify({message: '规则已更新，后续新任务按新规则生成', kind: 'success'});
      }
    }
    delete state.error;
  } catch (error) {
    state.error = cleanError(error);
    if (state.screen === 'edit' && state.error.includes('批次已变更')) state.error = '批次已变更，请返回批次详情后重新编辑。';
  }
  return state.screen === 'list' ? showList(state) : showDetail(state);
}

async function showList(state) {
  let data;
  try {
    data = await query('series.list', {search: state.search, status: state.filter});
    state.cachedList = data;
  } catch (error) {
    state.error = cleanError(error); data = state.cachedList || {items: [], counts: {all: 0, active: 0, paused: 0, ended: 0}};
  }
  const statuses = ['all', 'active', 'paused', 'ended'];
  return page(state, '批量任务', [
    {type: 'input', key: 'batchSearch', presentation: 'search', inputMode: 'search', text: '搜索批量任务',
      value: state.search, clearable: true, onChangeEvent: {type: 'search'}},
    {type: 'tabs', variant: 'pills', scrollable: true, selectedIndex: statuses.indexOf(state.filter),
      items: statuses.map(status => ({label: (status === 'all' ? '全部' : statusLabels[status]) + ' ' + data.counts[status],
        event: {type: 'filter', status}}))},
    text('按批次管理，持续补齐未来30天', 'muted'),
    ...notices(state),
    ...data.items.map(batchCard),
    ...(!data.items.length && !state.error ? [card([column([
      icon('layers', {size: 32, tone: 'accent'}),
      text(state.search ? '没有找到匹配的批量任务' : state.filter === 'all' ? '还没有批量任务' : '此状态下暂无批量任务', 'heading'),
      text(state.search ? '试试其他名称，或清空搜索。' : '创建批量任务后，可在这里统一管理。', 'muted'),
      ...(state.search ? [button('清空搜索', {type: 'search', value: ''})] : state.filter !== 'all' ? [button('查看全部', {type: 'filter', status: 'all'})] : []),
    ], 12)])] : []),
    ...(state.error ? [button('重试', {type: 'refresh'}, 'outlined')] : []),
  ], column([button('新建批量任务', {type: 'newBatch'}, 'filled', {icon: 'add'})], 0),
  {replaceForms: {batchSearch: state.search}});
}

function batchCard(batch) {
  const look = appearance(batch.title), blocked = batch.status === 'active' && (batch.blocked || []).length > 0;
  return card([row([
    icon(look.name, {tone: look.tone, surface: true, surfaceSize: 40}),
    {...column([
      {type: 'row', spacing: 6, children: [text(batch.title, 'heading', {weight: 'semibold', maxLines: 1, overflow: 'ellipsis'}),
        badge(blocked ? '待处理' : statusLabels[batch.status], blocked ? 'warning' : statusTones[batch.status])]},
      text(intervalLabel(batch.draft) + ' · ' + batch.draft.estimatedMinutes + '分钟', 'muted'),
      ...(blocked ? [badge('补齐受阻 · 查看原因', 'warning')] : [
        text('已完成 ' + batch.completedCount + ' · 待执行 ' + batch.pendingCount, 'muted'),
        ...(batch.status === 'active' ? [row([icon('clock', {size: 15}), {...text(batch.next ?
          '下次 ' + dateLabel(batch.next.date) + ' ' + batch.next.start : '暂无待执行任务', 'muted'), flex: 1}], {spacing: 5})] : []),
      ]),
    ], 4), flex: 1},
    icon('right', {size: 20}),
  ], {crossAxisAlignment: 'start'})], {key: 'series:' + batch.id, event: {type: 'openBatch', id: batch.id}});
}

async function showDetail(state) {
  let batch;
  try { batch = await query('series.get', {id: state.id}); state.cachedDetail = batch; }
  catch (error) {
    state.error = cleanError(error); batch = state.cachedDetail;
    if (!batch) return page(state, '批次详情', [...notices(state), button('重试', {type: 'refresh'})], null, {back: 'backToList'});
  }
  const actions = [menuAction('刷新', 'refresh')];
  if (batch.status === 'active') actions.push(menuAction('重新补齐', 'retry', 'repeat'));
  if (issueLabels(batch).length) actions.push(menuAction('查看补齐问题', 'issues', 'warning'));
  if (batch.status !== 'ended') actions.push(menuAction('结束批次', 'endBatch', 'archive'));
  if (state.screen === 'edit' || state.screen === 'editPreview') return editPage(state, batch);
  if (state.screen === 'issues' || state.screen === 'retry') {
    const retry = state.screen === 'retry';
    const preview = state.retryPreview;
    const reasons = retry ? (preview?.blocked || []).flatMap(item => item.reasons || []) : issueLabels(batch);
    return page(state, retry ? '重新补齐' : '补齐问题', [
      card([text(batch.title, 'heading'), text(intervalLabel(batch.draft) + ' · ' + batch.draft.estimatedMinutes + '分钟', 'muted')]),
      ...(retry ? [text('本次可生成 ' + (preview?.assignedCount || 0) + ' 次任务', 'heading')] : []),
      ...reasons.map(reason => ({type: 'notice', tone: 'warning', text: String(reason)})),
      ...notices(state),
      ...(reasons.length ? [text('可修改允许时段或重复规则后，重新预览补齐。', 'muted')] : [text('当前没有补齐问题', 'muted')]),
    ], row([...(batch.status !== 'ended' ? [{...button('编辑规则', {type: 'editRules'}, 'outlined'), flex: 1}] : []),
      ...(batch.status === 'active' ? [{...button(retry ? '确认补齐' : '重新补齐', {type: retry ? 'applyRetry' : 'retry'}, 'filled'), flex: 1}] : [])]),
    {back: 'backToDetail'});
  }
  const pendingRows = batch.rows.filter(item => item.status === 'pending');
  state.selected = state.selected.filter(id => pendingRows.some(item => item.taskId === id));
  const rows = batch.rows.filter(item => item.status === state.tab);
  const visibleRows = rows.slice(0, state.visibleRows || 4);
  const draft = batch.draft;
  const content = [
    column([{type: 'row', spacing: 10, children: [text(batch.title, 'headline', {maxLines: 2, overflow: 'ellipsis'}), badge(statusLabels[batch.status], statusTones[batch.status])]},
      text(batch.status === 'active' ? '持续补齐未来30天' : batch.status === 'paused' ? '已暂停补齐，已生成任务保留' : '批次已结束，生成记录保留', 'muted')], 6),
    card([column([
      row([icon('repeat', {tone: 'accent'}), {...text(intervalLabel(draft) + ' · 每次' + draft.estimatedMinutes + '分钟'), flex: 1}]),
      row([icon('clock', {tone: 'accent'}), {...text('允许时段 ' + draft.rules.timeWindow.start + '–' + draft.rules.timeWindow.end), flex: 1}]),
      ...(draft.rules.preferredTime ? [row([icon('clock', {tone: 'accent'}), {...text('优先时间点 ' + draft.rules.preferredTime), flex: 1}]), text('有冲突时在允许时段内就近安排', 'muted')] : []),
      row([icon('calendar', {tone: 'accent'}), {...text(weekLabel(draft.rules.weekdays)), flex: 1}]),
    ], 10)]),
    row([{...text('已完成  ' + batch.completedCount, 'body', {align: 'center', color: 'muted'}), flex: 1},
      {...text('待执行  ' + batch.pendingCount, 'body', {align: 'center', color: 'muted'}), flex: 1}]),
    ...(issueLabels(batch).length ? [card([row([icon('warning', {tone: 'warning'}),
      {...text('补齐受阻 · 查看原因', 'body'), flex: 1}, icon('right')])], {event: {type: 'issues'}})] : []),
    row([{...text('已生成任务', 'heading', {weight: 'bold'}), flex: 1},
      button(state.selecting ? '完成选择' : '选择', {type: 'selectMode'}, 'text', {disabled: state.tab !== 'pending' || !pendingRows.length})]),
    {type: 'tabs', variant: 'underline', selectedIndex: ['pending', 'completed', 'cancelled'].indexOf(state.tab),
      items: [['pending', '待执行', batch.pendingCount], ['completed', '已完成', batch.completedCount], ['cancelled', '已取消', batch.cancelledCount]]
        .map(([status, label, count]) => ({label: label + ' ' + count, event: {type: 'tab', status}}))},
    ...(state.selecting ? [row([{...text('已选择 ' + state.selected.length + ' 项', 'muted'), flex: 1},
      button('全选', {type: 'selectAll'})])] : []),
    ...(visibleRows.length ? [card([column(visibleRows.flatMap((item, index) => [
      ...(index ? [{type: 'divider', height: 1}] : []), taskRow(item, batch, state),
    ]), 0)], {padding: 0})] : [text(state.tab === 'pending' ? '暂无待执行任务' : state.tab === 'completed' ? '暂无完成记录' : '暂无已取消任务', 'muted', {align: 'center'})]),
    ...(rows.length > visibleRows.length ? [button('查看其余' + (rows.length - visibleRows.length) + '次安排', {type: 'moreRows'})] : []),
    ...notices(state),
  ];
  const footer = state.selecting ? row([
    {...button('退出选择', {type: 'selectMode'}, 'outlined'), flex: 1},
    {...button('取消所选任务', {type: 'cancelSelected'}, 'filled', {disabled: !state.selected.length}), flex: 1},
  ]) : batch.status !== 'ended' ? row([
    {...button(batch.status === 'paused' ? '恢复生成' : '暂停生成', {type: 'status'}, 'outlined'), flex: 1},
    {...button('编辑规则', {type: 'editRules'}, 'filled'), flex: 1},
  ]) : null;
  return page(state, '批次详情', content, footer, {key: 'detail:' + batch.id, back: 'backToList', actions, spacing: 14,
    ...(footer && !state.selecting ? {footerMessage: text('暂停仅停止补齐，已生成任务保留', 'caption', {align: 'center', color: 'muted'})} : {})});
}

function taskRow(item, batch, state) {
  return {type: 'card', padding: 12, event: {type: state.selecting ? 'selectRow' : 'openTask', taskId: item.taskId}, children: [
    row([
      ...(state.selecting ? [{type: 'checkbox', key: 'batch-select:' + item.taskId, text: '', value: state.selected.includes(item.taskId),
        event: {type: 'selectRow', taskId: item.taskId}}] : []),
      {...column([text(dateLabel(item.date) || '未安排', 'body', {weight: 'semibold'}), text(weekdayLabel(item.date), 'muted')], 2), width: 65},
      {...column([text(item.title, 'body', {weight: 'semibold', maxLines: 1, overflow: 'ellipsis'}), text(item.start && item.end ? item.start + '–' + (item.endDate !== item.date ? dateLabel(item.endDate) + ' ' : '') + item.end : '时间未设置', 'muted', {maxLines: 2, overflow: 'ellipsis'})], 3), flex: 1},
      {...column([text('第' + (item.sequence + 1) + '次', 'muted', {maxLines: 2}),
        ...(item.status === 'cancelled' ? [badge('已取消')] : item.manual ? [badge('已调整')] :
          item.date === batch.today ? [badge('今天', 'accent')] : [])], 3), width: 56},
      ...(!state.selecting ? [icon('right', {size: 18})] : []),
    ], {spacing: 8}),
  ]};
}

function editPage(state, batch) {
  const preview = state.screen === 'editPreview', draft = state.edit;
  if (preview) {
    const value = state.preview;
    const labels = {title: '任务名称', estimatedMinutes: '每次耗时', rules: '重复与安排规则', notes: '描述', location: '地点', priority: '优先级'};
    return page(state, '规则变更预览', [
      text(batch.title, 'headline'),
      {type: 'notice', tone: 'info', text: '仅对后续新生成的任务生效；已生成任务、完成记录和手动调整保持不变。'},
      ...value.changes.map(change => card([text(labels[change.field] || change.field, 'heading'),
        ...(change.field === 'rules' ? [text(intervalLabel(value.draft) + ' · ' + weekLabel(value.draft.rules.weekdays)),
          text(value.draft.rules.timeWindow.start + '–' + value.draft.rules.timeWindow.end, 'muted'),
          text('优先时间点：' + (batch.draft.rules.preferredTime || '未设置') + ' → ' + (value.draft.rules.preferredTime || '未设置'), 'muted')] :
          [text(String(change.before ?? '未设置') + ' → ' + String(change.after ?? '未设置'))])])),
      text('修改已生成任务：0项', 'muted'), ...notices(state),
    ], row([{...button('继续编辑', {type: 'resumeEdit'}, 'outlined'), flex: 1},
      {...button('保存规则', {type: 'applyRules'}, 'filled', {disabled: !value.confirmable || !value.changes.length}), flex: 1}]),
    {back: 'resumeEdit'});
  }
  return page(state, '编辑规则', [
    {type: 'notice', tone: 'info', text: '更改仅影响后续新生成的任务，已生成任务保持不变。'},
    field('editTitle', '任务名称', draft.editTitle),
    field('editDuration', '每次耗时（分钟）', draft.editDuration, {inputMode: 'number', integer: true, min: 1, max: 1439}),
    row([{...field('editMin', '最小间隔（天）', draft.editMin, {inputMode: 'number', integer: true, min: 1, max: 366}), flex: 1},
      {...field('editMax', '最大间隔（天）', draft.editMax, {inputMode: 'number', integer: true, min: 1, max: 366}), flex: 1}]),
    text('每天一次请将最小、最大间隔都设为1天。', 'muted'),
    row([{...temporal('editStart', '允许开始', draft.editStart), flex: 1}, {...temporal('editEnd', '允许结束', draft.editEnd), flex: 1}]),
    {...temporal('editPreferredTime', '优先时间点（可选）', draft.editPreferredTime), clearable: true},
    text('先尝试指定时间；冲突时在当天允许时段内就近安排。清空后按原规则安排。', 'muted'),
    {type: 'multiSelect', key: 'editWeekdays', text: '允许星期', value: draft.editWeekdays,
      items: weekdays.map((label, index) => ({label, value: index + 1})), event: {type: 'editField', key: 'editWeekdays'}},
    ...notices(state),
  ], column([button('预览变更', {type: 'previewRules'}, 'filled')], 0),
  {back: 'backToDetail', replaceForms: draft});
}
