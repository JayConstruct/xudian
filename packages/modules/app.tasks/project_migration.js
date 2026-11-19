import {clock, data} from '@xudian/sdk';
import {instant, legacyActivityId, recordPages, scheduleChanged} from './project_activity.js';

async function* history(collection) {
  let cursor = 0;
  for (;;) {
    const entries = await data.migrationHistory(collection, cursor);
    if (!entries.length) return;
    yield* entries;
    cursor = entries[entries.length - 1].sequence;
  }
}

export async function migrateProjectActivity() {
  const projects = new Map();
  const writes = [];
  for await (const page of recordPages('projects')) {
    for (const project of page) {
      const id = legacyActivityId(project.id);
      projects.set(project.id, {project, value: {id, projectId: project.id, at: null, legacyJoins: []}});
    }
  }
  if (!projects.size) return {writes};
  const candidates = new Map();
  const note = (projectId, key, at) => {
    if (projects.has(projectId) && instant(at) != null) candidates.set(key, {projectId, at});
  };
  const closure = new Map();
  for await (const {id, sequence, before, after, at} of history('projects')) {
    if (!projects.has(id) || !before || !after || !!before.completedOn === !!after.completedOn) continue;
    note(id, 'project:' + sequence, at);
    if (after.completedOn) closure.set(id, {sequence, completedOn: after.completedOn});
    else closure.delete(id);
  }

  const joins = new Map(), seen = new Set(), revisions = new Map();
  for await (const {id, sequence, before, after, at} of history('tasks')) {
    const beforeKey = before?.updatedAt, afterKey = after?.updatedAt;
    const taskRevisions = revisions.get(id) || new Map();
    revisions.set(id, taskRevisions);
    const restored = afterKey && beforeKey !== afterKey && taskRevisions.has(afterKey);
    if (restored) {
      // Existing planner undo writes the old snapshot, including its revision.
      candidates.delete('task:' + id + ':' + beforeKey);
      const join = taskRevisions.get(afterKey);
      if (join) joins.set(id, join);
      else joins.delete(id);
      continue;
    }
    if (after?.projectId && (!before ? !seen.has(id) : before.projectId !== after.projectId)) {
      joins.set(id, {projectId: after.projectId, sequence, at});
      note(after.projectId, 'task:' + id + ':' + afterKey, at);
    } else if (before?.projectId && after && before.projectId === after.projectId &&
        (scheduleChanged(before, after) || !!before.completedAt !== !!after.completedAt)) {
      note(after.projectId, 'task:' + id + ':' + afterKey, at);
    } else if (!after && before?.createdAt === beforeKey) {
      // A planner-created task removed by undo has no surviving creation.
      candidates.delete('task:' + id + ':' + beforeKey);
    }
    if (afterKey) taskRevisions.set(afterKey, joins.get(id) || null);
    seen.add(id);
  }

  const backfill = (projectId, at) => {
    const value = projects.get(projectId)?.value;
    if (value && instant(at) != null && (value.at == null || instant(at) > instant(value.at))) value.at = at;
  };
  for (const {projectId, at} of candidates.values()) backfill(projectId, at);

  const zone = (await clock.systemTimezone()).zone;
  for await (const page of recordPages('tasks', {field: 'projectId', op: 'notNull'})) {
    const unproven = [];
    for (const task of page) {
      const entry = projects.get(task.projectId);
      if (!entry) continue;
      const {project, value} = entry;
      if (task.completedAt && !seen.has(task.id)) backfill(project.id, task.completedAt);
      if (!project.completedOn) continue;
      const knownJoin = joins.get(task.id);
      const join = knownJoin?.projectId === project.id ? knownJoin : null;
      const finish = closure.get(project.id);
      if (join && finish?.completedOn === project.completedOn) {
        if (join.sequence > finish.sequence) value.legacyJoins.push(task.id);
      } else {
        // With only a date, same-day order is unknowable. A task created on a
        // later day necessarily joined after closure, even if it moved later.
        const time = join?.at || task.createdAt;
        if (instant(time) != null) unproven.push({id: task.id, value, completedOn: project.completedOn, utc: time});
      }
    }
    for (let index = 0; index < unproven.length; index += 256) {
      const batch = unproven.slice(index, index + 256);
      const local = await clock.toLocalMany(batch.map(({utc}) => ({utc, zone})));
      batch.forEach(({id, value, completedOn}, i) => {
        if (local[i].date > completedOn) value.legacyJoins.push(id);
      });
    }
  }
  for (const {value} of projects.values()) {
    if (value.at || value.legacyJoins.length) writes.push({collection: 'projectActivity', id: value.id, value});
  }
  return {writes};
}
