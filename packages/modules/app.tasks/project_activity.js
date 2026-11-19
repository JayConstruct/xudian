import {clock, data} from '@xudian/sdk';

const collection = 'projectActivity';
export const legacyActivityId = projectId => 'legacy:' + projectId;
export const completionRound = project => project?.completedOn
  ? project.completionRound || legacyActivityId(project.id)
  : null;
export const operationKey = (operation, projectId) => operation + ':' + projectId;

export async function* recordPages(collection, filter) {
  const limit = 1000;
  for (let offset = 0;; offset += limit) {
    const rows = await data.query(collection, {
      ...(filter ? {filter} : {}), sort: [{field: 'id', direction: 'asc'}], offset, limit,
    });
    yield rows;
    if (rows.length < limit) return;
  }
}

export const scheduleFields = ['plannedDate', 'plannedStartAt', 'plannedEndAt', 'plannedTimezone'];
export function scheduleChanged(before, after) {
  return scheduleFields.some(field => (before[field] ?? null) !== (after[field] ?? null));
}

export function attachActivity(task, kind, activityId) {
  task.projectActivity = {...task.projectActivity, [kind]: activityId};
}

// Nested commands prepared into the same transaction share an operation ID.
// Keep one timestamp per project, even if the operation affects many tasks.
export async function recordActivity(writes, projectId, operation, contributions) {
  if (!projectId || !contributions.length) return;
  const id = operationKey(operation, projectId);
  const previous = await data.get(collection, id);
  const value = {
    id, projectId,
    at: previous?.at || await clock.now(),
    contributions: [...new Set([...(previous?.contributions || []), ...contributions])],
  };
  writes.push({collection, id, value, commitTimestamps: ['at']});
}

export async function recordTaskActivity(writes, task, kind, operation) {
  if (!task.projectId) return;
  attachActivity(task, kind, operationKey(operation, task.projectId));
  await recordActivity(writes, task.projectId, operation, [kind + ':' + task.id]);
}

export async function undoActivity(writes, current, restored, kinds) {
  const changes = new Map();
  for (const kind of kinds) {
    const id = current.projectActivity?.[kind];
    if (!id || id === restored?.projectActivity?.[kind]) continue;
    if (!changes.has(id)) changes.set(id, []);
    changes.get(id).push(kind + ':' + current.id);
  }
  for (const [id, removed] of changes) {
    const previous = await data.get(collection, id);
    if (!previous) continue;
    const contributions = previous.contributions.filter(key => !removed.includes(key));
    if (contributions.length === previous.contributions.length) continue;
    writes.push({collection, id, value: contributions.length ? {...previous, contributions} : null});
  }
}

export function isNewPending(task, project, legacyJoins) {
  const round = completionRound(project);
  return !!round && !task.completedAt && !task.archivedAt && !task.deletedAt &&
    (task.joinedInRound === round ||
      (task.joinedInRound === undefined && round === legacyActivityId(project.id) && legacyJoins?.has(task.id)));
}

// Read the journal in pages. A removed contribution cannot mask an earlier
// successful operation, including one belonging to a different task.
export async function activitySummaries(projects) {
  const summaries = new Map();
  for await (const page of recordPages(collection)) {
    for (const row of page) {
      if (!projects.has(row.projectId)) continue;
      const summary = summaries.get(row.projectId) || {at: null, legacyJoins: null};
      if (row.legacyJoins) summary.legacyJoins = new Set(row.legacyJoins);
      const timestamp = instant(row.at);
      if (timestamp != null && (summary.timestamp == null || timestamp > summary.timestamp)) {
        summary.timestamp = timestamp;
        summary.at = row.at;
      }
      summaries.set(row.projectId, summary);
    }
  }
  return summaries;
}

// Date.parse drops the microseconds supplied by the host.
export function instant(value) {
  const milliseconds = Date.parse(value || '');
  if (!Number.isFinite(milliseconds)) return null;
  const fraction = value.match(/\.(\d+)Z$/)?.[1] || '';
  return milliseconds + Number(fraction.padEnd(6, '0').slice(3, 6)) / 1000;
}
