import {data} from '@xudian/sdk';
import {ideaRef} from './commands.js';

const text = (value, style = 'body', extra = {}) => ({type: 'text', text: value, style, ...extra});
const button = (label, event, extra = {}) => ({type: 'button', text: label, event, variant: 'text', ...extra});
const column = (children, spacing = 0) => ({type: 'column', children, spacing, trailingSpacing: false});
const row = (children, spacing = 6) => ({type: 'row', layout: 'flex', spacing, children});
const inset = (children, padding) => ({type: 'inset', padding, children});
const card = (children, padding = 12, extra = {}) => ({type: 'card', variant: 'outlined', padding, children, ...extra});
const glyph = (icon, size) => ({type: 'icon', icon, size});
const pageSize = 40;
export const dateLabel = date => Number(date.slice(5, 7)) + ' 月 ' + Number(date.slice(8)) + ' 日';
export const when = stamp => dateLabel(stamp.date) + ' ' + stamp.time;
const weekday = day => '周' + '日一二三四五六'[new Date(day + 'T12:00:00Z').getUTCDay()];

export function offsetDate(date, offset) {
  const value = new Date(date + 'T12:00:00Z');
  value.setUTCDate(value.getUTCDate() + offset);
  return value.toISOString().slice(0, 10);
}

export function counts(idea, separator = ' · ') {
  const projects = idea.history.filter(item => item.kind === 'project').length;
  const tasks = idea.history.length - projects;
  return [tasks && tasks + ' 个任务', projects && projects + ' 个项目'].filter(Boolean).join(separator);
}

function historyPanel(history) {
  const children = [text('创建记录', 'caption', {weight: 'semibold'})];
  for (const [index, item] of history.entries()) {
    if (index) children.push({type: 'divider'});
    const task = item.kind === 'task';
    children.push(inset([row([glyph(task ? 'tasks' : 'folder', 18), {
      ...column([text(item.name, 'body', {weight: 'semibold'}),
        text((task ? '任务' : '项目') + ' · ' + when(item.created), 'caption')]), flex: 1,
    }], 10)], [0, 8, 0, 8]));
  }
  return card(children, 12, {radius: 15});
}

function timelineRow(idea, state, query, first, last, divider) {
  const linked = idea.history.length > 0;
  const details = [text(idea.body, 'prose', {highlight: query})];
  if (linked) {
    const open = state.expanded === idea.id;
    details.push(inset([{type: 'row', alignment: 'start', children: [button('已创建 · ' + counts(idea), {type: 'history', id: idea.id}, {
      presentation: 'compact', variant: 'outlined', icon: 'branch', trailingIcon: open ? 'up' : 'down',
    })]}], [0, 8, 0, 0]));
    if (open) details.push(inset([historyPanel(idea.history)], [0, 4, 0, 0]));
  }
  const action = (label, icon, type, extra = {}, style = {}) =>
    ({label, icon, event: {type, id: idea.id, revision: idea.revision, ...extra}, ...style});
  const content = linked ? card(details, 12, {tone: 'selected', radius: 15}) : column(details);
  const menu = {type: 'swipeActions', key: idea.id, menuTrigger: 'longPress', menuAlign: 'start', revision: idea.revision,
    extent: 240, child: content,
    actions: [action('创建待安排任务', 'tasks', 'target', {kind: 'task'}), action('创建项目', 'folder', 'target', {kind: 'project'}),
      action(idea.favorite ? '取消收藏' : '收藏', 'star', 'favorite', {}, {dividerBefore: true}),
      action('编辑想法', 'edit', 'edit'), action('删除想法', 'delete', 'delete', {}, {dividerBefore: true, tone: 'danger'})]};
  return {type: 'timelineItem', key: idea.id, time: idea.created.time, detailIcon: idea.favorite ? 'starFilled' : null,
    variant: 'compact', filled: linked, first, last, divider, child: menu};
}

// Keep only the visible slice when searching or counting a large collection.
async function list(state, screen, query) {
  const rows = [];
  let total = 0;
  const needle = query.toLowerCase();
  const options = {sort: [{field: 'createdAt', direction: 'desc'}, {field: 'id', direction: 'desc'}]};
  if (screen === 'day') options.filter = {field: 'localDate', op: 'eq', value: state.date};
  if (screen === 'home' && state.favorite) options.filter = {field: 'favorite', op: 'eq', value: true};
  if (screen !== 'search' || needle) {
    for (let offset = 0; ; offset += 200) {
      const batch = await data.query('ideas', {...options, offset, limit: 200});
      for (const idea of batch) {
        if (needle && !idea.body.toLowerCase().includes(needle)) continue;
        total++;
        if (rows.length < (state.limit || pageSize)) rows.push(idea);
      }
      if (batch.length < 200) break;
    }
  }
  return {rows, total};
}

function empty(screen, favorite, query) {
  const blank = (icon, title, message, extra) => ({type: 'emptyState', icon, title, text: message,
    presentation: 'illustrated', padding: 0, ...extra});
  if (screen === 'search') return query
    ? [blank('search', '没有找到相关想法', '试试其他关键词，或清空「' + query + '」。'), button('清空搜索词', {type: 'clearSearch'})]
    : [blank('search', '搜索想法', '输入关键词查找想法正文。')];
  if (screen === 'day') return [blank('calendar', '当天没有记录', '可以切换日期查看其他想法。')];
  return favorite ? [blank('star', '还没有收藏的想法', '长按一条想法，选择「收藏」，就能在这里找到它。',
    {artwork: 'artwork/favorites-empty.png'}), button('查看全部想法', {type: 'filter', favorite: false})]
    : [blank('edit', '还没有想法', '在下方写下一句话，点「记下」保存。', {artwork: 'artwork/empty.png'})];
}

function toolbar(screen, state, total) {
  if (screen === 'search') return {type: 'input', key: 'query', text: '搜索想法', presentation: 'search', inputMode: 'search',
    clearable: true, value: state.query || '', onChangeEvent: {type: 'query'}, event: {type: 'query'}};
  if (screen === 'day') {
    const arrow = (label, icon, days) => button(label, {type: 'stepDay', days}, {presentation: 'plainIcon', icon, width: 42});
    return column([row([{type: 'dateInput', key: 'day', flex: 1, text: dateLabel(state.date).replaceAll(' ', ''),
      caption: weekday(state.date), presentation: 'button', value: state.date, editable: false, event: {type: 'selectDay'}},
      card([row([arrow('上一天', 'left', -1), arrow('下一天', 'right', 1)], 0)], 0, {radius: 14, width: 86})]),
      {type: 'divider'}], 12);
  }
  const search = !state.favorite && total > 0;
  return {...row([{type: 'tabs', variant: 'pills', density: 'compact', selectedIndex: state.favorite ? 1 : 0, items: [
    {label: '全部', event: {type: 'filter', favorite: false}},
    {label: '收藏', icon: 'star', event: {type: 'filter', favorite: true}}]},
    ...(search ? [button('搜索想法', {type: 'openSearch'}, {icon: 'search', variant: 'outlined', presentation: 'search', flex: 1})] : []),
    text(total + (state.favorite ? ' 条收藏' : ' 条想法'), 'caption', {align: 'end', flex: search ? 0 : 1})], 10),
    wrapBelow: 300};
}

function composer(forms, state) {
  const event = {type: 'record'};
  const command = {ref: ideaRef('idea.record'), input: {body: {bind: ['formValues', 'body']}}};
  const input = {type: 'input', key: 'body', flex: 1, hintText: '写下此刻的想法…', presentation: 'borderless',
    minLines: 1, maxLines: 3, keepFocusOnSubmit: true, event, command, onChangeEvent: {type: 'draft'}};
  const children = [row([glyph('edit', 18), input, button(state.saveError ? '重试' : '记下', event, {
    command, variant: 'filled', presentation: 'compact', trailingIcon: 'enter', disabled: !String(forms.body || '').trim()})], 9)];
  if (state.saveError) children.push(inset([{type: 'notice', tone: 'warning', presentation: 'inline', text: state.saveError}], [0, 5, 0, 0]));
  return card(children, 10, {radius: 18, focusKey: 'body', tone: state.saveError ? 'danger' : 'neutral'});
}

export async function pageTree(state, screen, today, forms) {
  const query = screen === 'search' ? String(forms.query ?? state.query ?? '').trim() : '';
  const {rows, total} = await list(state, screen, query);
  const children = [];
  if (screen === 'search' && total) children.push(text(total + ' 条匹配的想法', 'caption'));
  const yesterday = offsetDate(today, -1);
  for (const [index, idea] of rows.entries()) {
    const day = idea.created.date, previous = rows[index - 1], first = day !== previous?.created.date;
    if (first) {
      const relative = day === today ? '今天' : day === yesterday ? '昨天' : '';
      const title = screen === 'day' ? '当天想法' : relative || dateLabel(day);
      const caption = screen === 'day' ? total + ' 条' : (relative ? dateLabel(day) + ' · ' : '') + weekday(day);
      children.push(inset([{type: 'sectionLabel', title, caption,
        ...(screen === 'home' ? {event: {type: 'openDay', date: day}, chevron: !state.favorite} : {})}],
        [0, index || screen === 'search' ? 18 : 2, 0, 8]));
    }
    children.push(timelineRow(idea, state, query, first, day !== rows[index + 1]?.created.date,
      !first && !previous.history.length && !idea.history.length));
  }
  if (!rows.length) children.push(inset([column(empty(screen, state.favorite, query), 8)], [12, 0, 12, 44]));
  if (rows.length < total) children.push(button('查看更多', {type: 'more'}));
  if (state.error) children.unshift({type: 'notice', tone: 'warning', text: state.error});
  const tree = {...column(children), key: 'ideas:' + screen, scrollRequest: state.scrollRequest, queueInputActions: true, centerLast: !rows.length,
    header: inset([toolbar(screen, state, total)], [20, 8, 20, 4])};
  if (screen === 'home') Object.assign(tree, {footerStyle: 'composer', footer: composer(forms, state)});
  return tree;
}
