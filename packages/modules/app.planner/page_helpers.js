import {clock} from '@xudian/sdk';

export const text = value => ({type: 'text', text: value});
export const button = (label, event, variant = 'tonal') => ({type: 'button', text: label, event, variant});
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
