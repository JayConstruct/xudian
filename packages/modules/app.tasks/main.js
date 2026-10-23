import {data,ids,clock,services,ui,extensions} from '@xudian/sdk';
const ref=id=>({moduleId:'app.tasks',serviceId:id,majorVersion:1});
function cleanTitle(value,max,label) { if(typeof value!=='string'||!value.trim()||value.trim().length>max) throw new Error(`${label}需为1–${max}个字符`); return value.trim(); }
function validDate(value) {
  if(value==null) return;
  if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(value)||Number(value.slice(0,4))<1) throw new Error('日期格式必须为 YYYY-MM-DD');
  const date=new Date(value+'T00:00:00Z');
  if(!Number.isFinite(date.getTime())||date.toISOString().slice(0,10)!==value) throw new Error('日期不存在');
}
function utc(value,label='时间') {
  if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$/.test(value))throw new Error(`${label}必须为 UTC 时间`);
  validDate(value.slice(0,10));
  const parsed=new Date(value);
  if(!Number.isFinite(parsed.getTime())||parsed.toISOString().slice(0,19)!==value.slice(0,19))throw new Error(`${label}无效`);
  return parsed.toISOString();
}
const precisionFields=['plannedStartAt','plannedEndAt','plannedTimezone'];
const deadlineFields=['dueDate','dueAt','dueTimezone'];
const extraFields=[...precisionFields,'estimatedMinutes','executionExpiresOn','actualCompletedOn','completedTimezone','dueAt','dueTimezone','initialDeadline','deadlineHistory','locked'];
function notes(value) { if(typeof value!=='string')throw new Error('任务描述必须为文本');return value; }
function deadline(value) { return Object.fromEntries(deadlineFields.map(k=>[k,value[k]??null])); }
async function normalizeDeadline(value,changes) {
  // A date-only edit replaces the previous exact instant, while retaining its zone.
  if('dueDate' in changes&&!('dueAt' in changes))value.dueAt=null;
  validDate(value.dueDate);
  if(value.dueDate==null&&value.dueAt==null){value.dueDate=null;value.dueAt=null;value.dueTimezone=null;return value;}
  if(value.dueTimezone!=null&&(typeof value.dueTimezone!=='string'||!value.dueTimezone))throw new Error('截止时区无效');
  if(value.dueAt!=null) {
    if(!value.dueTimezone)throw new Error('精确截止需提供时区');
    value.dueAt=utc(value.dueAt,'截止时间');
    value.dueDate=(await clock.toLocal({utc:value.dueAt,zone:value.dueTimezone})).date;
  } else if(value.dueTimezone!=null)await clock.toLocal({utc:await clock.now(),zone:value.dueTimezone});
  return value;
}
async function normalizePlan(value,changes) {
  if('plannedDate' in changes&&!precisionFields.some(k=>k in changes))for(const k of precisionFields)value[k]=null;
  if(value.estimatedMinutes!=null&&(!Number.isSafeInteger(value.estimatedMinutes)||value.estimatedMinutes<1))throw new Error('预计时长必须为正整数分钟');
  validDate(value.executionExpiresOn);
  const precise=precisionFields.some(k=>value[k]!=null);
  if(!precise)return value;
  if(precisionFields.some(k=>value[k]==null)||typeof value.plannedTimezone!=='string'||!value.plannedTimezone)throw new Error('精确计划需同时提供开始、结束时间和时区');
  value.plannedStartAt=utc(value.plannedStartAt,'开始时间');value.plannedEndAt=utc(value.plannedEndAt,'结束时间');
  if(value.plannedEndAt<=value.plannedStartAt)throw new Error('结束时间必须晚于开始时间');
  const start=await clock.toLocal({utc:value.plannedStartAt,zone:value.plannedTimezone});
  value.plannedDate=start.date;
  return value;
}
const unexpired=day=>({any:[{field:'executionExpiresOn',op:'isNull'},{field:'executionExpiresOn',op:'gte',value:day}]});
const associated=(day,today)=>({any:[{field:'plannedDate',op:'eq',value:day},{field:'dueDate',op:day===today?'lte':'eq',value:day}]});
function dailyFilter(day,today) {
  const pending={all:[{field:'completedAt',op:'isNull'},unexpired(day),associated(day,today)]};
  if(day>=today)return pending;
  return {any:[pending,{all:[{field:'completedAt',op:'notNull'},{any:[associated(day,today),{field:'actualCompletedOn',op:'eq',value:day}]}]}]};
}
function dailyMember(task,day,today) {
  const linked=task.plannedDate===day||(day===today?task.dueDate!=null&&task.dueDate<=day:task.dueDate===day);
  return task.completedAt?day<today&&(linked||task.actualCompletedOn===day):linked&&(task.executionExpiresOn==null||task.executionExpiresOn>=day);
}
function priority(p) { if(!Number.isInteger(p)||p<0||p>3) throw new Error('优先级必须在0–3之间'); }
export async function taskGet({id}) { return data.get('tasks',id); }
const taskSort=[{field:'priority',direction:'desc'},{field:'createdAt',direction:'asc'}];
const taskPageSize=1000;
async function* taskPages(options) {
  for(let offset=0;;offset+=taskPageSize) {
    const page=await data.query('tasks',{...options,offset,limit:taskPageSize});
    yield page;
    if(page.length<taskPageSize)return;
  }
}
// Paged filtered reads for the date strip; no task extensions or project lookups.
export async function taskDayCounts({dates}) {
  if(!Array.isArray(dates)||!dates.length||dates.length>7||new Set(dates).size!==dates.length)throw new Error('请选择1至7个不同日期');
  dates.forEach(date=>{if(date==null)throw new Error('日期不存在');validDate(date);});
  const today=await clock.today(),conditions=['deletedAt','archivedAt','parentTaskId'].map(field=>({field,op:'isNull'}));
  conditions.push({any:dates.map(day=>dailyFilter(day,today))});
  const days=dates.map(date=>({date,pending:0,completed:0,overdue:0,loadedPending:0,loadedCompleted:0,hasMore:false,truncated:false}));
  // Stream sorted pages: only counters and the first 50 statuses per day remain
  // in memory, even when the collection exceeds the host's per-query limit.
  for await(const records of taskPages({filter:{all:conditions},sort:taskSort})) {
    for(const task of records)for(const day of days) {
      const date=day.date;
      if(!dailyMember(task,date,today))continue;
      const loaded=day.pending+day.completed<50;
      if(task.completedAt){day.completed++;if(loaded)day.loadedCompleted++;}
      else {day.pending++;if(loaded)day.loadedPending++;}
      if(date===today&&!task.completedAt&&task.dueDate!=null&&task.dueDate<today)day.overdue++;
      day.hasMore=day.pending+day.completed>50;
    }
  }
  return {today,days};
}
export async function taskList({filter,projectId,view='all',today,date,query='',offset=0,limit=10000}={}) {
  if(!Number.isInteger(offset)||offset<0||!Number.isInteger(limit)||limit<1||limit>10000) throw new Error('分页参数无效');
  const conditions=[];
  if(filter)conditions.push(filter);
  let currentDate,selectedDate;
  if(view==='daily') {
    currentDate=await clock.today();selectedDate=date??currentDate;validDate(selectedDate);
  }
  if(view!=='raw')for(const field of ['deletedAt','archivedAt','parentTaskId'])conditions.push({field,op:'isNull'});
  if(view!=='raw'&&!['daily','today','completed'].includes(view))conditions.push({field:'completedAt',op:'isNull'});
  if(view==='completed')conditions.push({field:'completedAt',op:'notNull'});
  if(projectId!==undefined)conditions.push(projectId===null?{field:'projectId',op:'isNull'}:{field:'projectId',op:'eq',value:projectId});
  if(view==='inbox')conditions.push({field:'projectId',op:'isNull'});
  if(view==='today') {today=today||await clock.today();validDate(today);conditions.push(dailyFilter(today,today));}
  // Historical dates include associated tasks and their actual completion day.
  if(view==='daily')conditions.push(dailyFilter(selectedDate,currentDate));
  const options={filter:{all:conditions},sort:view==='completed'?[{field:'completedAt',direction:'desc'},{field:'id',direction:'asc'}]:taskSort};
  let tasks;
  if(query) {
    // Keep QuickJS Unicode casing semantics and paginate after matching.
    // Stop once the requested matching page is full; extensions see that page only.
    tasks=[];
    const needle=query.toLowerCase();let matched=0;
    search:for await(const page of taskPages(options))for(const task of page) {
      if(!task.title.toLowerCase().includes(needle))continue;
      if(matched++<offset)continue;
      tasks.push(task);
      if(tasks.length===limit)break search;
    }
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
  const now=await clock.now(),value={id:await ids.new(),title,projectId:input.projectId||null,parentTaskId:input.parentTaskId||null,notes:notes(input.notes??''),priority:p,
    dueDate:input.dueDate||null,plannedDate:input.plannedDate||null,completedAt:null,archivedAt:null,deletedAt:null,createdAt:now,updatedAt:now};
  for(const k of extraFields)value[k]=input[k]??null;
  value.actualCompletedOn=null;value.completedTimezone=null;
  value.locked=input.locked??false;if(typeof value.locked!=='boolean')throw new Error('固定时间必须为布尔值');
  await normalizePlan(value,input);await normalizeDeadline(value,input);
  value.initialDeadline=deadline(value);value.deadlineHistory=[];
  return {writes:[{collection:'tasks',id:value.id,value}],events:[{type:'task.created',entity:{moduleId:'app.tasks',collection:'tasks',id:value.id}}],result:value};
}
function snapshot(t) { return Object.fromEntries(['id','title','notes','priority','dueDate','plannedDate','projectId','parentTaskId','completedAt','archivedAt','deletedAt','updatedAt',...extraFields].map(k=>[k,t[k]??null])); }
function canonical(v) { const stable=x=>Array.isArray(x)?x.map(stable):x&&typeof x==='object'?Object.fromEntries(Object.keys(x).sort().map(k=>[k,stable(x[k])])):x;return JSON.stringify(stable(v)); }
// Keep the optimistic token advancing even when writes share a clock tick.
async function nextUpdatedAt(previous) {
  const now=await clock.now(),prior=Date.parse(previous||'');
  return Number.isFinite(prior)&&prior>=Date.parse(now)?new Date(prior+1).toISOString():now;
}
async function check(input) {
  const t=await data.get('tasks',input.id); if(!t||t.deletedAt) throw new Error('任务已不可用');
  if(input.expectedUpdatedAt&&t.updatedAt!==input.expectedUpdatedAt||input.expectedValues&&Object.entries(input.expectedValues).some(([k,v])=>canonical(v)!==canonical(t[k]??null))) throw new Error('任务已被其他操作修改，请重新生成方案');
  return t;
}
export async function taskUpdate(input) {
  const t=await check(input),changes={...input.changes};
  for(const k of Object.keys(changes)) if(!['title','notes','priority',...deadlineFields,'plannedDate',...precisionFields,'estimatedMinutes','executionExpiresOn','locked'].includes(k)) throw new Error(`不支持修改字段：${k}`);
  if('title' in changes) changes.title=cleanTitle(changes.title,300,'任务标题');
  if('notes' in changes) changes.notes=notes(changes.notes);
  if('locked' in changes&&typeof changes.locked!=='boolean')throw new Error('固定时间必须为布尔值');
  if('priority' in changes) priority(changes.priority);
  if('dueDate' in changes) validDate(changes.dueDate); if('plannedDate' in changes) validDate(changes.plannedDate);
  const value=await normalizeDeadline(await normalizePlan({...t,...changes},changes),changes);
  if(t.locked&&changes.locked!==false&&['plannedDate',...precisionFields,'estimatedMinutes'].some(k=>canonical(t[k]??null)!==canonical(value[k]??null)))throw new Error('任务时间已固定，请先解除固定');
  if(canonical(deadline(t))!==canonical(deadline(value))) {
    value.initialDeadline=t.initialDeadline??deadline(t);
    value.deadlineHistory=[...(t.deadlineHistory||[]),{changedAt:await clock.now(),before:deadline(t),after:deadline(value)}];
  }
  const fields=Object.keys(value).filter(k=>canonical(t[k]??null)!==canonical(value[k]??null));
  if(!fields.length)return {writes:[],events:[],result:snapshot(t)};
  value.updatedAt=await nextUpdatedAt(t.updatedAt);
  return {writes:[{collection:'tasks',id:t.id,value}],events:[{type:'task.updated',entity:{moduleId:'app.tasks',collection:'tasks',id:t.id},fields}],result:snapshot(value)};
}
export async function taskComplete(input) {
  const t=await check(input);if(typeof input.completed!=='boolean')throw new Error('completed必须为布尔值');
  if(!input.completed&&('actualCompletedOn' in input||'completedTimezone' in input))throw new Error('重新打开任务不能指定完成日期');
  if(!input.completed&&!t.completedAt)return {writes:[],events:[],result:snapshot(t)};
  const value={...t};
  if(input.completed) {
    // A date correction keeps the original audit timestamp.
    if(!t.completedAt||'actualCompletedOn' in input||'completedTimezone' in input) {
      const zone=input.completedTimezone??t.completedTimezone??t.plannedTimezone??'UTC';
      if(typeof zone!=='string'||!zone)throw new Error('完成时区无效');
      const now=await clock.now();
      const local=await clock.toLocal({utc:now,zone});
      const day='actualCompletedOn' in input?input.actualCompletedOn:t.actualCompletedOn??local.date;validDate(day);
      value.completedAt=t.completedAt||now;value.actualCompletedOn=day;value.completedTimezone='completedTimezone' in input?input.completedTimezone:zone;
    }
  } else {value.completedAt=null;value.actualCompletedOn=null;value.completedTimezone=null;}
  if(canonical(value)===canonical(t))return {writes:[],events:[],result:snapshot(t)};
  value.updatedAt=await nextUpdatedAt(t.updatedAt);
  const type=input.completed?(t.completedAt?'task.completionCorrected':'task.completed'):'task.reopened';
  return {writes:[{collection:'tasks',id:t.id,value}],events:[{type,entity:{moduleId:'app.tasks',collection:'tasks',id:t.id}}],result:snapshot(value)};
}
export async function taskRange({startAt,endAt}) {
  startAt=utc(startAt);endAt=utc(endAt);if(endAt<=startAt)throw new Error('时间范围无效');
  const items=[];
  const filter={all:[{field:'deletedAt',op:'isNull'},{field:'plannedStartAt',op:'lt',value:endAt},{field:'plannedEndAt',op:'gt',value:startAt}]};
  for await(const page of taskPages({filter,sort:[{field:'plannedStartAt',direction:'asc'},{field:'id',direction:'asc'}]}))items.push(...page);
  return items;
}
export async function taskRestore({id,expected,value}) {
  if(!expected||typeof expected!=='object'||Array.isArray(expected)||expected.id!==id||value!==null&&(!value||typeof value!=='object'||Array.isArray(value)||value.id!==id))throw new Error('恢复任务数据无效');
  const current=await data.get('tasks',id);
  if(canonical(current)!==canonical(expected))throw new Error('任务已被其他操作修改，无法撤销');
  if(canonical(current)===canonical(value))return {writes:[],events:[],result:value};
  return {writes:[{collection:'tasks',id,value}],events:[{type:value===null?'task.deleted':'task.restored',entity:{moduleId:'app.tasks',collection:'tasks',id}}],result:value};
}
export async function render({state={},event}) {
  if(event?.type==='new') {
    const values=await ui.dialog({title:'新建任务',fields:[{key:'title',label:'任务标题'}]});
    if(values) { const plan=await services.prepare(ref('task.create'),values); if(await ui.review(plan.planId)) await services.commit(plan.planId); }
  }
  return {state,tree:{type:'column',children:[{type:'button',text:'新建任务',event:{type:'new'}},...(await taskList()).map(t=>({type:'text',text:t.title}))]}};
}
