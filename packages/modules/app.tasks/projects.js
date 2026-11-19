import {data, clock, ids} from '@xudian/sdk';
import {cleanTitle, validDate, nextUpdatedAt, check} from './task_values.js';

import {attachActivity, completionRound, operationKey, recordActivity, recordPages} from './project_activity.js';

export async function records(collection, filter) {
  const rows=[];
  for await (const page of recordPages(collection, filter)) rows.push(...page);
  return rows;
}
const write=(collection,value)=>({collection,id:value.id,value});
function change(writes,result){
  return {writes,events:writes.length?[{type:'project.changed'}]:[],result};
}
async function activeProject(id){
  const project=await data.get('projects',id);
  if(!project||project.archivedAt)throw Error('项目不可用');
  return project;
}
export async function validateFolder(id,projectId){
  if(!id)return;
  const folder=await data.get('projectFolders',id);
  if(!folder||(folder.projectId||null)!==(projectId||null))throw Error('分类不属于当前位置');
  return folder;
}
export async function folderList(){return records('projectFolders');}
export async function projectFields(input){
  const importance=input.importance??1;
  if(![0,1,2].includes(importance))throw Error('项目重要性无效');
  validDate(input.targetDate);
  await validateFolder(input.folderId,null);
  return {name:cleanTitle(input.name,120,'项目名称'),folderId:input.folderId||null,importance,targetDate:input.targetDate||null};
}
export async function folderSave(input){
  const projectId=input.projectId||null, parentId=input.parentId||null;
  if(projectId)await activeProject(projectId);
  const old=input.id?await validateFolder(input.id,projectId):null;
  if(old&&old.updatedAt!==input.expectedUpdatedAt)throw Error('分类已变更，请刷新');
  let parent=await validateFolder(parentId,projectId);
  const seen=new Set(input.id?[input.id]:[]);
  while(parent){
    if(seen.has(parent.id))throw Error('分类不能移入自身或下级分类');
    seen.add(parent.id);
    parent=await validateFolder(parent.parentId,projectId);
  }
  const folder={id:old?.id||await ids.new(),projectId,parentId,name:cleanTitle(input.name,120,'分类名称'),updatedAt:await nextUpdatedAt(old?.updatedAt)};
  return change([write('projectFolders',folder)],folder);
}
export async function projectEdit(input){
  const old=await activeProject(input.id);
  if(input.expectedUpdatedAt!==old.updatedAt)throw Error('项目已变更，请刷新');
  const fields=await projectFields({...old,...input});
  const project={...old,...fields};
  if('completedOn' in input){validDate(input.completedOn);project.completedOn=input.completedOn;}
  const stateChanged=!!old.completedOn!==!!project.completedOn;
  const writes=[];
  if (stateChanged) {
    const operation=input._host.operationId;
    project.completionRound=project.completedOn?operationKey(operation,project.id):null;
    await recordActivity(writes,project.id,operation,['state']);
  }
  if(Object.keys(project).every(k=>(project[k]??null)===(old[k]??null)))return change([],old);
  project.updatedAt=await nextUpdatedAt(old.updatedAt);
  writes.unshift(write('projects',project));
  return change(writes,project);
}

// A batch is one reviewed plan. Its undo token binds the exact prior queue
// state to the revisions returned by the successful operation.
export async function projectPick({projectId,tasks,queued,_host}) {
  await activeProject(projectId);
  const writes=[],changed=[],seen=new Set(),contributions=[];
  const activityId=operationKey(_host.operationId,projectId);
  for (const item of tasks) {
    if(seen.has(item.id))throw Error('重复任务');
    seen.add(item.id);
    const t=await check(item);
    if(t.projectId!==projectId||t.archivedAt||t.completedAt||t.plannedStartAt)throw Error('任务状态已变化，请重新挑选');
    if(!!t.projectQueued===queued)continue;
    const value={...t,projectQueued:queued,updatedAt:await nextUpdatedAt(t.updatedAt),
      queueUndo:{id:activityId,queued:!!t.projectQueued,previousActivity:t.projectActivity?.queue||null}};
    if (queued) {
      attachActivity(value,'queue',activityId);
      contributions.push('queue:'+t.id);
    }
    writes.push(write('tasks',value));
    changed.push({id:t.id,expectedUpdatedAt:value.updatedAt});
  }
  await recordActivity(writes,projectId,_host.operationId,contributions);
  return change(writes,{tasks:changed,undoId:activityId});
}

export async function projectUndoPick({projectId,tasks,undoId}) {
  await activeProject(projectId);
  const writes=[],seen=new Set(),restored=[];
  for (const item of tasks) {
    if(seen.has(item.id))throw Error('重复任务');
    seen.add(item.id);
    const t=await check(item);
    if(t.projectId!==projectId||t.archivedAt||t.completedAt||t.plannedStartAt||t.queueUndo?.id!==undoId)
      throw Error('任务状态已变化，无法撤销');
    const value={...t,projectQueued:t.queueUndo.queued,updatedAt:await nextUpdatedAt(t.updatedAt)};
    attachActivity(value,'queue',t.queueUndo.previousActivity);
    delete value.queueUndo;
    restored.push(t.id);
    writes.push(write('tasks',value));
  }
  // Update the shared journal entry once, even when many selected tasks undo it.
  const entry=await data.get('projectActivity',undoId);
  if (entry) {
    const contributions=entry.contributions.filter(key=>!restored.some(id=>key==='queue:'+id));
    writes.push({collection:'projectActivity',id:undoId,value:contributions.length?{...entry,contributions}:null});
  }
  return change(writes,{restored:restored.length});
}
export async function projectMoveTasks({id,expectedUpdatedAt,projectId,folderId,_host}){
  const project=projectId?await activeProject(projectId):null;
  if(folderId&&!project)throw Error('无项目任务不能指定分类');
  await validateFolder(folderId,projectId);
  const root=await check({id,expectedUpdatedAt});
  if(root.archivedAt)throw Error('任务已归档');
  if(root.parentTaskId&&root.projectId!==projectId)throw Error('请移动父任务，子任务将一同移入');
  const writes=[],pending=[root],seen=new Set(),contributions=[];
  const activityId=operationKey(_host.operationId,projectId);
  while(pending.length){
    const task=pending.pop();
    if(seen.has(task.id))throw Error('子任务层级有误');
    seen.add(task.id);
    const moved=task.projectId!==projectId;
    if(moved||(task.folderId||null)!==(folderId||null)){
      const value={...task,projectId,folderId:folderId||null,
        projectQueued:!!task.plannedStartAt||(!moved&&!!task.projectQueued),updatedAt:await nextUpdatedAt(task.updatedAt)};
      if(moved){
        value.joinedInRound=completionRound(project);
        if(project)attachActivity(value,'join',activityId);
        if(!task.archivedAt&&!task.deletedAt)contributions.push('join:'+task.id);
      }
      writes.push(write('tasks',value));
    }
    if(root.projectId!==projectId)pending.push(...await records('tasks',{field:'parentTaskId',op:'eq',value:task.id}));
  }
  await recordActivity(writes,projectId,_host.operationId,contributions);
  return change(writes,{id});
}
// The assistant supplies relative category paths. All new folders and tasks
// form one preview; resolving a new path never relies on uncommitted writes.
export async function buildOutline({projectId,folderId,items,_host},newTask){
  await activeProject(projectId);
  await validateFolder(folderId,projectId);
  const existing=await records('projectFolders',{field:'projectId',op:'eq',value:projectId});
  const key=(parent,name)=>JSON.stringify([parent||null,name]);
  const folders=new Map(existing.map(f=>[key(f.parentId,f.name),f]));
  const writes=[],contributions=[];
  const activityId=operationKey(_host.operationId,projectId);
  for(const item of items){
    let parentId=folderId||null;
    for(const label of item.path||[]){
      const name=cleanTitle(label,120,'分类名称'),path=key(parentId,name);
      if(!folders.has(path)){
        const folder={id:await ids.new(),name,parentId,projectId,updatedAt:await clock.now()};
        writes.push(write('projectFolders',folder));folders.set(path,folder);
      }
      parentId=folders.get(path).id;
    }
    const task=await newTask({title:item.title,notes:item.notes,estimatedMinutes:item.estimatedMinutes,projectId});
    task.folderId=parentId;
    attachActivity(task,'join',activityId);
    contributions.push('join:'+task.id);
    writes.push(write('tasks',task));
  }
  await recordActivity(writes,projectId,_host.operationId,contributions);
  return change(writes,{created:items.length});
}
