import {data,ids,clock,services,ui,extensions} from '@xudian/sdk';
const ref=id=>({moduleId:'app.tasks',serviceId:id,majorVersion:1});
function cleanTitle(value,max,label) { if(typeof value!=='string'||!value.trim()||value.trim().length>max) throw new Error(`${label}需为1–${max}个字符`); return value.trim(); }
function validDate(value) {
  if(value==null) return;
  if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(value)||new Date(value+'T00:00:00Z').toISOString().slice(0,10)!==value) throw new Error('日期格式必须为 YYYY-MM-DD');
}
function priority(p) { if(!Number.isInteger(p)||p<0||p>3) throw new Error('优先级必须在0–3之间'); }
export async function taskGet({id}) { return data.get('tasks',id); }
export async function taskList({filter,projectId,view='all',today,query='',offset=0,limit=10000}={}) {
  if(!Number.isInteger(offset)||offset<0||!Number.isInteger(limit)||limit<1||limit>10000) throw new Error('分页参数无效');
  const conditions=[];
  if(filter)conditions.push(filter);
  if(view!=='raw')for(const field of ['deletedAt','archivedAt','completedAt','parentTaskId'])conditions.push({field,op:'isNull'});
  if(projectId!==undefined)conditions.push(projectId===null?{field:'projectId',op:'isNull'}:{field:'projectId',op:'eq',value:projectId});
  if(view==='inbox')conditions.push({field:'projectId',op:'isNull'});
  if(view==='today') {today=today||await clock.today();conditions.push({any:[{field:'dueDate',op:'lte',value:today},{field:'plannedDate',op:'eq',value:today}]});}
  const options={filter:{all:conditions},sort:[{field:'priority',direction:'desc'},{field:'createdAt',direction:'asc'}]};
  let tasks;
  if(query) {
    tasks=await data.query('tasks',options);
    tasks=tasks.filter(t=>t.title.toLowerCase().includes(query.toLowerCase())).slice(offset,offset+limit);
  } else tasks=await data.query('tasks',{...options,offset,limit});
  const extra=await extensions.queryMany(tasks.filter(t=>!t.deletedAt).map(t=>({moduleId:'app.tasks',collection:'tasks',id:t.id})));
  return tasks.map(t=>({...t,completed:!!t.completedAt,archived:!!t.archivedAt,deleted:!!t.deletedAt,fields:extra.valuesById[t.id]||{},fieldDefinitions:extra.definitions}));
}
export async function projectList() { return (await data.query('projects')).filter(p=>!p.archivedAt); }
export async function projectCreate({name}) {
  const now=await clock.now(),value={id:await ids.new(),name:cleanTitle(name,120,'项目名称'),createdAt:now,updatedAt:now,archivedAt:null};
  return {writes:[{collection:'projects',id:value.id,value}],events:[{type:'project.created',entity:{moduleId:'app.tasks',collection:'projects',id:value.id}}],result:{id:value.id}};
}
export async function taskCreate(input) {
  const title=cleanTitle(input.title,300,'任务标题'),p=input.priority??0; priority(p); validDate(input.dueDate); validDate(input.plannedDate);
  if(input.projectId) { const project=await data.get('projects',input.projectId); if(!project||project.archivedAt) throw new Error('项目不可用'); }
  if(input.parentTaskId) {
    const parent=await data.get('tasks',input.parentTaskId);
    if(!parent||parent.deletedAt||parent.archivedAt) throw new Error('父任务不可用');
    if((parent.projectId||null)!==(input.projectId||null)) throw new Error('子任务必须与父任务属于同一项目');
  }
  const now=await clock.now(),value={id:await ids.new(),title,projectId:input.projectId||null,parentTaskId:input.parentTaskId||null,notes:'',priority:p,
    dueDate:input.dueDate||null,plannedDate:input.plannedDate||null,completedAt:null,archivedAt:null,deletedAt:null,createdAt:now,updatedAt:now};
  return {writes:[{collection:'tasks',id:value.id,value}],events:[{type:'task.created',entity:{moduleId:'app.tasks',collection:'tasks',id:value.id}}],result:{id:value.id}};
}
function snapshot(t) { return Object.fromEntries(['id','title','priority','dueDate','plannedDate','projectId','parentTaskId','completedAt','archivedAt','deletedAt','updatedAt'].map(k=>[k,t[k]])); }
function canonical(v) { if(v&&typeof v==='object'&&!Array.isArray(v)) return JSON.stringify(Object.fromEntries(Object.keys(v).sort().map(k=>[k,v[k]]))); return JSON.stringify(v); }
async function check(input) {
  const t=await data.get('tasks',input.id); if(!t||t.deletedAt) throw new Error('任务已不可用');
  if(input.expectedUpdatedAt&&t.updatedAt!==input.expectedUpdatedAt||input.expectedValues&&canonical(input.expectedValues)!==canonical(snapshot(t))) throw new Error('任务已被其他操作修改，请重新生成方案');
  return t;
}
export async function taskUpdate(input) {
  const t=await check(input),changes={...input.changes};
  for(const k of Object.keys(changes)) if(!['title','priority','dueDate','plannedDate'].includes(k)) throw new Error(`不支持修改字段：${k}`);
  if('title' in changes) changes.title=cleanTitle(changes.title,300,'任务标题');
  if('priority' in changes) priority(changes.priority);
  if('dueDate' in changes) validDate(changes.dueDate); if('plannedDate' in changes) validDate(changes.plannedDate);
  if(!Object.keys(changes).some(k=>canonical(t[k])!==canonical(changes[k]))) return {writes:[],events:[],result:snapshot(t)};
  const value={...t,...changes,updatedAt:await clock.now()};
  return {writes:[{collection:'tasks',id:t.id,value}],events:[{type:'task.updated',entity:{moduleId:'app.tasks',collection:'tasks',id:t.id},fields:Object.keys(changes)}],result:snapshot(value)};
}
export async function taskComplete(input) {
  const t=await check(input); if(typeof input.completed!=='boolean') throw new Error('completed必须为布尔值');
  if(!!t.completedAt===input.completed) return {writes:[],events:[],result:snapshot(t)};
  const now=await clock.now(),value={...t,completedAt:input.completed?now:null,updatedAt:now};
  return {writes:[{collection:'tasks',id:t.id,value}],events:[{type:input.completed?'task.completed':'task.reopened',entity:{moduleId:'app.tasks',collection:'tasks',id:t.id}}],result:snapshot(value)};
}
export async function render({state={},event}) {
  if(event?.type==='new') {
    const values=await ui.dialog({title:'新建任务',fields:[{key:'title',label:'任务标题'}]});
    if(values) { const plan=await services.prepare(ref('task.create'),values); if(await ui.review(plan.planId)) await services.commit(plan.planId); }
  }
  return {state,tree:{type:'column',children:[{type:'button',text:'新建任务',event:{type:'new'}},...(await taskList()).map(t=>({type:'text',text:t.title}))]}};
}
