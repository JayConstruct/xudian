import {clock, data, ids, services} from '@xudian/sdk';

export const ideaRef = serviceId => ({moduleId: 'app.ideas', serviceId, majorVersion: 1});
const change = (id, value, result = {id}) => ({writes: [{collection: 'ideas', id, value}], result});

function clean(value, limit, label) {
  if (typeof value !== 'string' || !value.trim()) throw Error('请填写' + label);
  if (value.trim().length > limit) throw Error(label + '最多 ' + limit + ' 个字符');
  return value.trim();
}

async function timestamp() {
  const utc = await clock.now();
  const {zone} = await clock.systemTimezone();
  const {date, time} = await clock.toLocal({utc, zone});
  return {utc, date, time};
}

function checkRevision(idea, expected) {
  if (!idea || idea.revision !== expected) throw Error('这条想法已变化，请重新打开');
}

export async function recordIdea({body}) {
  const text = clean(body, 4000, '想法正文');
  const id = await ids.new();
  const created = await timestamp();
  return change(id, {id, body: text, createdAt: created.utc, localDate: created.date, created, modified: created, revision: 1, favorite: false, history: []});
}

export async function editIdea({id, revision, body}) {
  const idea = await data.get('ideas', id);
  checkRevision(idea, revision);
  const text = clean(body, 4000, '想法正文');
  if (text === idea.body) return {writes: [], result: {id}};
  return change(id, {...idea, body: text, modified: await timestamp(), revision: revision + 1});
}

export async function favoriteIdea({id, revision, favorite}) {
  const idea = await data.get('ideas', id);
  checkRevision(idea, revision);
  return change(id, {...idea, favorite, revision: revision + 1});
}

export async function completeIdea({id, revision, completed}) {
  const idea = await data.get('ideas', id);
  checkRevision(idea, revision);
  return change(id, {...idea, completed, revision: revision + 1});
}

export async function deleteIdea({id, revision}) {
  checkRevision(await data.get('ideas', id), revision);
  return change(id, null);
}

export async function createTarget({id, revision, kind, name, requestId}) {
  const idea = await data.get('ideas', id);
  const project = kind === 'project';
  const title = clean(name, project ? 120 : 300, project ? '项目名称' : '任务名称');
  const previous = idea?.history.find(item => item.requestId === requestId);
  if (previous) {
    if (previous.kind !== kind || previous.name !== title) throw Error('创建请求已经使用');
    return {writes: [], result: {id: previous.targetId}};
  }
  checkRevision(idea, revision);
  const result = await services.prepare({
    moduleId: 'app.tasks', serviceId: project ? 'project.create' : 'task.create', majorVersion: 1,
  }, project ? {name: title} : {title});
  const record = {requestId, kind, name: title, targetId: result.id, created: await timestamp()};
  return change(id, {...idea, history: [record, ...idea.history], revision: revision + 1}, {id: result.id});
}
