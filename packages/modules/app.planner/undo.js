import {services, clock} from '@xudian/sdk';
import {add, intervalsOverlap} from './engine.js';

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
function checkOverlap(restored, occupied, label) {
  if (intervalsOverlap(restored, occupied)) throw Error(`撤销已停止：${restored.title}恢复后的时间与${label || occupied.title || '已有占用'}冲突`);
}

// Reverting notes or deleting a newly created task adds no occupancy. Check only
// ranges that actually return, without imposing a present-time restriction on history.
export async function validateUndoOccupancy(batch, availability) {
  const finalPlans = batch.changes.map(change => planned(change.before)).filter(Boolean);
  const restored = batch.changes.map(change => {
    const before = planned(change.before);
    return before && !samePosition(before, planned(change.after)) ? before : null;
  }).filter(Boolean);
  if (!restored.length) return;
  const affected = new Set(batch.changes.map(change => change.taskId));
  const directory = await services.directory();
  const hasCourses = directory.some(service => service.moduleId === courseRef.moduleId);
  for (const target of restored) {
    for (const other of finalPlans) if (target.id !== other.id) checkOverlap(target, other);
    const tasks = await services.query(taskRef('task.range'), {startAt: target.startAt, endAt: target.endAt});
    for (const task of tasks) if (!affected.has(task.id)) checkOverlap(target, planned(task));
    // Any IANA zone can place a course on the UTC date before or after this
    // range. Query civil dates on both sides, in bounded inclusive chunks.
    const from = add(target.startAt.slice(0, 10), -1), to = add(target.endAt.slice(0, 10), 1);
    if (hasCourses) {
      for (let startDate = from; startDate <= to; startDate = add(startDate, 30)) {
        const endDate = add(startDate, 29) < to ? add(startDate, 29) : to;
        let courses;
        try { courses = await services.query(courseRef, {startDate, endDate}); }
        catch (error) { throw Error('撤销已停止：无法读取当前课程占用，请检查课表后重试。' + String(error)); }
        for (const course of courses.items) checkOverlap(target, course, '课程 ' + (course.title || ''));
      }
    }
    for (const busy of availability.busy || []) if (busy.date >= from && busy.date <= to) {
      const block = {
        startAt: await instant(busy.date, busy.start, availability.timezone),
        endAt: await instant(busy.date, busy.end, availability.timezone),
      };
      checkOverlap(target, block, busy.title || '忙碌时段');
    }
  }
}
