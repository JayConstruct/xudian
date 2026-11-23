import {clock} from '@xudian/sdk';

export const text = value => ({type: 'text', text: value});
export const button = (label, event, variant = 'tonal') => ({type: 'button', text: label, event, variant, ...(variant === 'outlined' ? {tone: 'neutral'} : {})});
export const row = (title, subtitle, event) => ({type: 'listTile', title, subtitle, event});
export const checkbox = (key, label, value, event) => ({type: 'checkbox', key, text: label, value, event});
export const stamp = (date, time) => `${date}T${time}:00`;
const deadlineLabel = t => t?.dueDate || '未设置';
export async function localDeadlineLabels(values, defaultZone) {
  const exact = values.filter(t => t?.dueAt), labels = new Map();
  for (let i = 0; i < exact.length; i += 256) {
    const items = exact.slice(i, i + 256);
    const times = await clock.toLocalMany(items.map(t => ({utc: t.dueAt, zone: t.dueTimezone || defaultZone})));
    items.forEach((t, index) => labels.set(t, `${times[index].date} ${times[index].time}`));
  }
  return t => labels.get(t) || deadlineLabel(t);
}

export const monthDay = date => `${Number(date.slice(5, 7))}月${Number(date.slice(8, 10))}日`;
export const note = value => ({...text(value), style: 'caption', color: 'muted'});
export const pair = (...children) => ({
  type: 'row', layout: 'flex', spacing: 10, crossAxisAlignment: 'start',
  children: children.map(child => ({...child, flex: 1})),
});
export const footer = (...children) => ({footerStyle: 'edge', footer: pair(...children)});
export const pageInset = children => ({
  edgeToEdge: true, spacing: 0,
  children: [{type: 'inset', padding: [20, 6, 20, 16], children: [
    {type: 'column', children, spacing: 14, trailingSpacing: false},
  ]}],
});
export const section = (title, children, {action, ...options} = {}) => {
  const heading = {type: 'sectionHeader', title, compact: true, countPosition: 'end', ...options};
  const header = action ? {type: 'row', layout: 'flex', children: [
    {...heading, flex: 1}, {...button(action.label, action.event, 'text'), presentation: 'link'},
  ]} : heading;
  return {type: 'column', spacing: 8, trailingSpacing: false, children: [header, ...children]};
};
export const surface = rows => ({
  type: 'card', variant: 'outlined', padding: 0,
  children: rows.flatMap((child, index) => index ? [{type: 'divider', height: 1}, child] : [child]),
});
export const group = (title, rows, options) => section(title, [surface(rows)], options);
export const iconRow = (title, subtitle, event, icon, options = {}) => ({
  ...row(title, subtitle || null, event), icon, iconTone: 'muted', minHeight: subtitle ? 60 : 48, ...options,
});
export const keyValue = (title, value) => ({
  type: 'listTile', title, trailing: value, minHeight: 45, minVerticalPadding: 0,
});
export const hero = (title, subtitle, icon, status) => ({
  type: 'card', variant: 'outlined', padding: 16, children: [{
    type: 'inset', padding: [0, 3, 0, 3], children: [{
      type: 'row', layout: 'flex', spacing: 12, children: [
        {type: 'icon', icon, surface: true, surfaceSize: 45, size: 23, tone: 'accent'},
        {type: 'column', flex: 1, spacing: 3, trailingSpacing: false, children: [
          {...text(title), style: 'title', weight: 'bold'}, note(subtitle),
        ]},
        ...(status ? [{type: 'badge', text: status, tone: 'accent'}] : []),
      ],
    }],
  }],
});
