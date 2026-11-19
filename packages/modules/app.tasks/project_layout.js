// Presentation shared by the project directory, detail pages and task picker.
const column = (children, spacing = 0) => ({type: 'column', children, spacing, trailingSpacing: false});
const line = children => ({type: 'row', layout: 'flex', children});
const text = (text, style, options = {}) => ({type: 'text', text, style, ...options});
export const tabs = ['directory', 'activity', 'follow'];

export function tabHeader(selected) {
  const labels = ['目录', '待推进', '跟进'];
  const items = tabs.map((tab, i) => ({label: labels[i], event: {type: 'tab', tab}}));
  return {type: 'inset', children: [
    {type: 'segmented', variant: 'sliding', items, selectedIndex: tabs.indexOf(selected)},
  ]};
}

export function section(title, count) {
  const heading = {type: 'sectionHeader', compact: true, title};
  return count ? line([{...heading, flex: 1}, text(count, 'caption')]) : heading;
}

export function summaryCard(p, progress, total, extra, importance, dateLabel) {
  let details = progress.pending + ' 项待安排';
  if (p.completedOn) details = '实际完结 ' + dateLabel(p.completedOn);
  if (extra) details = '完结后新增待办 ' + extra + ' 项';
  const status = {type: 'badge', text: p.completedOn ? '完结' : '未完结', tone: 'muted'};
  const priority = {type: 'badge', text: importance, tone: 'muted'};
  if (p.importance === 2) Object.assign(priority, {tone: 'warning', icon: 'flag'});

  const children = [
    {type: 'row', children: [status, priority]},
    line([
      {type: 'row', flex: 1, spacing: 4, children: [
        text(String(progress.done), 'metric', {color: 'primary', weight: 'bold'}),
        text('/ ' + total, 'title', {color: 'muted'}),
      ]},
      {...column([
        text('任务完成', 'heading', {align: 'end', weight: 'semibold'}),
        text(details, 'caption', {align: 'end'}),
      ], 2), flex: 1},
    ]),
    {type: 'progress', value: total ? progress.done / total : 0},
  ];
  if (p.targetDate) children.push({type: 'row', children: [
    {type: 'icon', icon: 'calendar', size: 15}, text('目标 ' + dateLabel(p.targetDate), 'caption'),
  ]});
  if (progress.deviation) children.push({type: 'row', children: [{
    type: 'badge', icon: p.completedOn ? 'check' : 'history', text: progress.deviation,
    tone: p.completedOn && !progress.deviation.startsWith('延期') ? 'success' : 'warning',
  }]});
  return {type: 'card', tone: 'selected', padding: 16, children: [column(children, 8)]};
}

export function taskSummary(task, label) {
  const icon = task.completedAt ? 'check' : task.plannedStartAt ? 'calendar' : 'clipboard';
  return {type: 'card', tone: 'selected', padding: 16, children: [{
    ...column([{type: 'icon', icon, surface: true, surfaceSize: 34},
      text(task.title, 'headline'), text(label, 'caption')], 6),
    crossAxisAlignment: 'start',
  }]};
}

export function groupedRows(children) {
  // Keep individual entries at the root for the host's lazy scroll view.
  const result = [], rows = [];
  function flush() {
    rows.forEach((child, index) => {
      const first = index === 0, last = index === rows.length - 1;
      const position = first && last ? 'only' : first ? 'first' : last ? 'last' : 'middle';
      result.push({type: 'groupItem', position, child,
        ...(child.key ? {key: 'surface:' + child.key} : {})});
    });
    rows.length = 0;
  }
  for (const child of children) {
    if (child.type === 'divider') continue;
    if (['listTile', 'checkbox', 'swipeActions'].includes(child.type)) {
      if (child.event?.location?.unfiled) flush();
      rows.push(child);
    } else {
      flush();
      result.push(child);
    }
  }
  flush();
  return result;
}
