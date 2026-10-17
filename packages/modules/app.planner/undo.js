import {services, clock} from '@xudian/sdk';
import {add, canonical, intervalsOverlap} from './engine.js';

const taskRef = serviceId => ({moduleId: 'app.tasks', serviceId, majorVersion: 1});
const courseRef = {moduleId: 'app.schedule', serviceId: 'schedule.query.busy', majorVersion: 1};
function planned(task) {
  if (!task || task.deletedAt || !task.plannedStartAt || !task.plannedEndAt) return null;
  return {id: task.id, title: task.title || '任务', startAt: task.plannedStartAt, endAt: task.plannedEndAt};
}
function samePosition(before, after) {
  return !!after && Date.parse(before.startAt) === Date.parse(after.startAt) && Date.parse(before.endAt) === Date.parse(after.endAt);
}
async function instant(date, time, zone) {
  const value = await clock.toUtc({date, time, zone});
  if (value.status !== 'unique') throw Error('撤销已停止：当前忙碌时段存在时区歧义，请先到来源修正');
  return value.instants[0];
}
function restoration(batch) {
  return batch.changes.map(change => {
    const before = planned(change.before);
    const after = change.after === undefined ? {startAt: change.fields?.plannedStartAt, endAt: change.fields?.plannedEndAt} : planned(change.after);
    return before && !samePosition(before, after) ? before : null;
  }).filter(Boolean);
}
function fact(target, kind, occupied) {
  return {taskId: target.id, kind, id: String(occupied.id),
    startAt: new Date(occupied.startAt).toISOString(), endAt: new Date(occupied.endAt).toISOString()};
}
async function overlaps(batch, availability) {
  const restored = restoration(batch);
  if (!restored.length) return [];
  const finalPlans = batch.changes.map(change => planned(change.before)).filter(Boolean);
  const affected = new Set(batch.changes.map(change => change.taskId));
  const hasCourses = (await services.directory()).some(service => service.moduleId === courseRef.moduleId);
  const found = [];
  for (const target of restored) {
    const addOverlap = (kind, occupied, label) => {
      if (occupied && intervalsOverlap(target, occupied)) found.push({fact: fact(target, kind, occupied), title: target.title, label: label || occupied.title || '已有占用'});
    };
    for (const other of finalPlans) if (target.id !== other.id) addOverlap('task', other);
    const tasks = await services.query(taskRef('task.range'), {startAt: target.startAt, endAt: target.endAt});
    for (const task of tasks) if (!affected.has(task.id)) addOverlap('task', planned(task));
    // A course's civil date can lie on either side of the UTC date. Read the
    // same bounded inclusive ranges when capturing and checking a restoration.
    const from = add(target.startAt.slice(0, 10), -1), to = add(target.endAt.slice(0, 10), 1);
    if (hasCourses) {
      for (let startDate = from; startDate <= to; startDate = add(startDate, 30)) {
        const endDate = add(startDate, 29) < to ? add(startDate, 29) : to;
        let courses;
        try { courses = await services.query(courseRef, {startDate, endDate}); }
        catch (error) { throw Error('撤销已停止：无法读取当前课程占用，请检查课表后重试。' + String(error)); }
        for (const course of courses.items) addOverlap('course', course, '课程 ' + (course.title || ''));
      }
    }
    for (const busy of availability.busy || []) if (busy.date >= from && busy.date <= to) {
      addOverlap('busy', {
        id: `${busy.date}|${busy.start}|${busy.end}`,
        startAt: await instant(busy.date, busy.start, availability.timezone),
        endAt: await instant(busy.date, busy.end, availability.timezone),
      }, busy.title || '忙碌时段');
    }
  }
  return found;
}

// Only occupancy facts are stored: source identity and exact occupied range.
// Display metadata changes do not turn an unchanged overlap into a new one.
export async function captureUndoOccupancy(batch, availability) {
  const values = (await overlaps(batch, availability)).map(value => value.fact);
  const unique = new Map(values.map(value => [canonical(value), value]));
  return {version: 1, overlaps: [...unique.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([, value]) => value)};
}

// Legacy history has no baseline and keeps the strict protection. New history
// can return to an unchanged pre-existing overlap, but cannot add a new one.
export async function validateUndoOccupancy(batch, availability) {
  const baseline = batch.undoOccupancy?.version === 1 && Array.isArray(batch.undoOccupancy.overlaps)
    ? new Set(batch.undoOccupancy.overlaps.map(canonical)) : new Set();
  for (const overlap of await overlaps(batch, availability)) {
    if (!baseline.has(canonical(overlap.fact))) throw Error(`撤销已停止：${overlap.title}恢复后的时间与${overlap.label}冲突`);
  }
}
