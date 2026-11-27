import {clock, data, ids, services, ui} from '@xudian/sdk';
import {ideaRef} from './commands.js';
import {counts, offsetDate, pageTree, searchLabel, when} from './timeline.js';
export {recordIdea, editIdea, favoriteIdea, completeIdea, deleteIdea, createTarget} from './commands.js';

async function submit(id, input, confirm) {
  const plan = await services.prepare(ideaRef(id), input);
  if (!plan.writes.length) return true;
  if (!await ui.review(plan.planId, {summaryOnly: true, ...confirm})) return false;
  await services.commit(plan.planId);
  return true;
}

async function formAction(idea, kind) {
  const edit = kind === 'edit';
  const project = kind === 'project';
  const noun = project ? '项目' : '任务';
  const title = edit ? '编辑想法' : project ? '创建项目' : '创建待安排任务';
  const submitLabel = edit ? '保存' : '创建' + noun;
  const key = edit ? 'body' : 'name';
  const serviceId = edit ? 'idea.edit' : 'idea.createTarget';
  const fixed = {id: idea.id, revision: idea.revision};
  if (!edit) Object.assign(fixed, {kind, requestId: await ids.new()});
  let value = edit ? idea.body : '';
  let error = '';
  while (true) {
    const field = {key, value, label: edit ? '想法正文' : noun + '名称', required: true,
      presentation: 'labeled', maxLength: edit ? 4000 : project ? 120 : 300};
    if (edit) Object.assign(field, {type: 'multiline', minLines: 3, maxLines: 6, metadata: [
      {icon: 'clock', text: '创建于 ' + when(idea.created)}, {icon: 'edit', text: '修改于 ' + when(idea.modified)}]});
    else Object.assign(field, {summary: {title: '想法原文', subtitle: idea.body, icon: 'book', presentation: 'quote'},
      hintText: '输入' + noun + '名称', destination: {icon: project ? 'folder' : 'tasks', label: '创建到',
        title: project ? '项目根目录' : '任务规划 · 待安排', hint: project ? '' : '计划时间和截止日期均留空。'}});
    const values = await ui.dialog({presentation: 'compact', fullWidthActions: true, title, submitLabel,
      description: error || null, fields: [field],
      command: {ref: ideaRef(serviceId), input: fixed, fields: {[key]: key}}});
    if (!values) return;
    value = values[key];
    try {
      await submit(serviceId, {...fixed, [key]: value}, {title, message: value.trim().slice(0, 500),
        confirmLabel: submitLabel});
      return;
    } catch (failure) {
      const current = await data.get('ideas', idea.id);
      if (!current || current.revision !== idea.revision) throw failure;
      error = failure.message;
    }
  }
}

export async function render({context = {}, state = {}, event, formValues = {}} = {}) {
  state = {...state};
  let forms = {...formValues};
  const result = {};
  const screen = context.pageId === 'app.ideas.search' ? 'search' : context.pageId === 'app.ideas.day' ? 'day' : 'home';
  const today = await clock.today();
  if (screen === 'search') state.favorite = context.favorite === true;
  if (screen === 'day' && !state.date) state.date = context.date || today;
  const type = event?.type;
  if (type) delete state.error;
  try {
    if (type === 'record' && forms.body?.trim()) {
      if (await submit('idea.record', {body: forms.body}, {title: '记下想法', message: forms.body.trim().slice(0, 500), confirmLabel: '记下'})) {
        state.scrollRequest = (state.scrollRequest || 0) + 1;
        state.favorite = false;
        state.limit = 40;
        result.clearForms = ['body'];
        forms.body = '';
        delete state.saveError;
      }
    } else if (type === 'filter') {
      state.scrollRequest = (state.scrollRequest || 0) + 1;
      state.favorite = event.favorite; state.limit = 40; delete state.expanded;
    } else if (type === 'query' || type === 'clearSearch') {
      forms.query = type === 'clearSearch' ? '' : (forms.query ?? event.value ?? '');
      if (state.query !== forms.query) state.scrollRequest = (state.scrollRequest || 0) + 1;
      state.query = forms.query; state.limit = 40;
      if (type === 'clearSearch') result.clearForms = ['query'];
    } else if (type === 'openDay' || type === 'openSearch') {
      if (type === 'openDay') await ui.navigate('app.ideas.day', {date: event.date});
      else await ui.navigate('app.ideas.search', {favorite: !!state.favorite});
    } else if (type === 'stepDay' || type === 'selectDay') {
      state.scrollRequest = (state.scrollRequest || 0) + 1;
      state.date = type === 'stepDay' ? offsetDate(state.date, event.days) : event.value;
      state.limit = 40; delete state.expanded;
      result.replaceForms = {day: state.date};
    } else if (type === 'history') {
      state.expanded = state.expanded === event.id ? null : event.id;
    } else if (type === 'more') {
      state.limit = (state.limit || 40) + 40;
    } else if (['edit', 'favorite', 'complete', 'delete', 'target'].includes(type)) {
      const idea = await data.get('ideas', event.id);
      if (!idea || idea.revision !== event.revision) throw Error('这条想法已变化，请重新打开');
      const fixed = {id: idea.id, revision: idea.revision};
      if (type === 'favorite') {
        const label = idea.favorite ? '取消收藏' : '收藏';
        await submit('idea.favorite', {...fixed, favorite: !idea.favorite}, {title: label, message: idea.body.slice(0, 500), confirmLabel: label});
      } else if (type === 'complete') {
        const label = idea.completed ? '标为未完成' : '直接完成';
        await submit('idea.complete', {...fixed, completed: !idea.completed}, {title: label, message: idea.body.slice(0, 500), confirmLabel: label});
      } else if (type === 'delete') {
        await submit('idea.delete', fixed, {title: '删除这条想法？', subject: '想法原文', icon: 'book', presentation: 'quote',
          message: idea.body.slice(0, 4000), ...(idea.history.length ? {notice: '已创建的 ' + counts(idea, ' 和 ') + ' 会保留。'} : {}), confirmLabel: '删除想法'});
      } else await formAction(idea, type === 'edit' ? 'edit' : event.kind);
    }
  } catch (failure) {
    if (type === 'record') state.saveError = failure.message + '，暂未保存';
    else state.error = failure.message;
  }
  const title = screen === 'home' ? '想法' : screen === 'search' ? searchLabel(state.favorite) : '按日期查看';
  return {...result, state, header: {title, compact: true, minHeight: 64, titleStyle: 'large', backIcon: 'arrow',
    actions: screen === 'home' ? [{label: searchLabel(state.favorite), icon: 'search', event: {type: 'openSearch'}}] : []},
    tree: await pageTree(state, screen, today, forms)};
}
