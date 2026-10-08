// Deterministic compatibility code shipped by the host, incorporated into each
// derived package. Domain commands still execute through task JS services.
import {data,services,clock,ids,ui} from '@xudian/sdk';
const moduleId=definition.manifest.id;
const ref=(id,module=moduleId)=>({moduleId:module,serviceId:id,majorVersion:1});
const nowDate=()=>clock.today();
function fieldKey(key) { if(key.includes(':')&&!key.startsWith(moduleId+':')) throw new Error('字段属于其他模块'); return key.includes(':')?key:moduleId+':'+key; }
function valid(value,type,config={}) {
  switch(type) {
    case 'text':return typeof value==='string';case 'number':return typeof value==='number'&&Number.isFinite(value);case 'boolean':return typeof value==='boolean';
    case 'date':return typeof value==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(value)&&!Number.isNaN(Date.parse(value+'T00:00:00Z'))&&new Date(value+'T00:00:00Z').toISOString().slice(0,10)===value;
    case 'datetime':return typeof value==='string'&&/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(value)&&!Number.isNaN(Date.parse(value));
    case 'select':return typeof value==='string'&&config.options?.includes(value);
    case 'multiSelect':return Array.isArray(value)&&new Set(value).size===value.length&&value.every(v=>typeof v==='string'&&config.options?.includes(v));
    default:return false;
  }
}
async function entity(input) {
  const e=input.entity||{moduleId:'app.tasks',collection:'tasks',id:input.taskId};
  if(e.moduleId!=='app.tasks'||e.collection!=='tasks'||typeof e.id!=='string') throw new Error('实体引用无效');
  const task=await services.query(ref('task.get','app.tasks'),{id:e.id}); if(!task||task.deletedAt) throw new Error('任务不存在或已删除');
  return e;
}
export async function fieldSet(input) {
  if(!definition.manifest.permissions.includes('fields.write')) throw new Error('缺少字段写权限');
  const e=await entity(input),key=fieldKey(input.fieldKey),field=definition.fields.find(f=>moduleId+':'+f.id===key);
  if(!field||!valid(input.value,field.type,field.config)) throw new Error('字段类型或值无效');
  const id=`${e.id}:${key}`,value={id,entity:e,fieldKey:key,value:input.value,updatedAt:await clock.now()};
  const current=await data.get('fieldValues',id);
  if(current&&JSON.stringify(current.value)===JSON.stringify(input.value)) return {writes:[],events:[],result:{changed:false}};
  return {writes:[{collection:'fieldValues',id,value}],events:[{type:'task.updated',entity:e,fields:[key]}],result:{changed:true}};
}
export async function fieldClear(input) {
  if(!definition.manifest.permissions.includes('fields.write')) throw new Error('缺少字段写权限');
  const e=await entity(input),key=fieldKey(input.fieldKey),id=`${e.id}:${key}`;
  if(!definition.fields.some(f=>moduleId+':'+f.id===key)) throw new Error('字段不存在');
  const current=await data.get('fieldValues',id);
  return {writes:current?[{collection:'fieldValues',id,value:null}]:[],events:current?[{type:'task.updated',entity:e,fields:[key]}]:[],result:{changed:!!current}};
}
export async function fieldSetMany(input) {
  const writes=[],events=[];
  if(!Array.isArray(input.values)) throw new Error('字段批量值需为数组');
  for(const value of input.values) { const plan=await fieldSet(value);writes.push(...plan.writes);events.push(...plan.events); }
  return {writes,events,result:{changed:writes.length}};
}
export async function fieldQuery(input) {
  if(input._host?.extensionQuery===true && Array.isArray(input.entities)) {
    const values=await data.query('fieldValues',{filter:{field:'entity.id',op:'in',value:input.entities.map(e=>e.id)}});
    const valuesById=Object.fromEntries(input.entities.map(e=>[e.id,{}]));for(const v of values)valuesById[v.entity.id][v.fieldKey]=v.value;
    return {definitions:definition.fields.map(f=>({...f,key:moduleId+':'+f.id})),valuesById};
  }
  const e=await entity(input),values=await data.query('fieldValues',{filter:{field:'entity.id',op:'eq',value:e.id}});
  return {definitions:definition.fields.map(f=>({...f,key:moduleId+':'+f.id})),values:Object.fromEntries(values.map(v=>[v.fieldKey,v.value]))};
}
async function resolve(v,params={},event={}) {
  if(Array.isArray(v)) return Promise.all(v.map(x=>resolve(x,params,event)));
  if(v&&typeof v==='object') return Object.fromEntries(await Promise.all(Object.entries(v).map(async([k,x])=>[k,await resolve(x,params,event)])));
  if(typeof v!=='string') return v;
  let exact=/^\$param\.([a-z][a-zA-Z0-9_-]*)$/.exec(v);if(exact) return params[exact[1]];
  exact=/^\$event\.([a-zA-Z0-9_.]+)$/.exec(v);if(exact) return exact[1].split('.').reduce((x,k)=>x?.[k],event);
  exact=/^\$today(?:([+-])\s*(\d+)d)?$/.exec(v);
  if(exact) { const today=await nowDate();return new Date(Date.parse(today+'T00:00:00Z')+(exact[1]==='-'?-1:1)*Number(exact[2]||0)*86400000).toISOString().slice(0,10); }
  return v.replace(/\$param\.([a-z][a-zA-Z0-9_-]*)/g,(_,key)=>params[key]??'').replace(/\$event\.([a-zA-Z0-9_.]+)/g,(_,path)=>path.split('.').reduce((x,k)=>x?.[k],event)??'');
}
function filter(row,f,today) {
  if(!f) return true;if(f.all)return f.all.every(v=>filter(row,v,today));if(f.any)return f.any.some(v=>filter(row,v,today));if(f.not)return !filter(row,f.not,today);
  let actual=f.field.startsWith('fields.')?row.fields?.[fieldKey(f.field.slice(7))]:f.field.split('.').reduce((v,k)=>v?.[k],row),expected=f.value==='$today'?today:f.value;
  switch(f.op) {case 'eq':return actual===expected;case 'ne':return actual!==expected;case 'isNull':return actual==null;case 'notNull':return actual!=null;case 'contains':return Array.isArray(actual)&&actual.includes(expected);case 'lt':return actual!=null&&expected!=null&&actual<expected;case 'lte':return actual!=null&&expected!=null&&actual<=expected;case 'gt':return actual!=null&&expected!=null&&actual>expected;case 'gte':return actual!=null&&expected!=null&&actual>=expected;default:throw new Error('过滤操作无效');}
}
export async function applyTemplate(input) {
  const template=definition.templates.find(t=>t.id===input.templateId);if(!template)throw new Error('模板不存在');
  const params={};
  for(const p of template.parameters||[]) {
    const value=input.parameters?.[p.id]??p.default;
    if(value==null) {if(p.required)throw new Error('缺少参数：'+p.id);params[p.id]=null;continue;}
    if(!valid(value,p.type,{options:p.options}))throw new Error('参数类型无效：'+p.id);params[p.id]=value;
  }
  const writes=[],events=[];
  const taskIds={},projectId=template.project?(await services.prepare(ref('project.create','app.tasks'),await resolve(template.project,params))).id:null;
  for(const task of template.tasks||[]) {
    if(task.parentKey&&!taskIds[task.parentKey])throw new Error('父任务必须在前序创建');
    const input=await resolve(task,params);const result=await services.prepare(ref('task.create','app.tasks'),{...input,projectId,parentTaskId:task.parentKey?taskIds[task.parentKey]:null});taskIds[task.key]=result.id;
    for(const [key,value]of Object.entries(input.fields||{})) { const field=await fieldSet({taskId:result.id,fieldKey:key,value});writes.push(...field.writes);events.push(...field.events); }
  }
  return {writes,events,result:{projectId,taskIds,createdTasks:Object.keys(taskIds).length}};
}
export async function applyRule(input) {
  const rule=definition.rules.find(r=>r.id===input.ruleId);if(!rule)throw new Error('规则不存在');
  const event={...input.event,payload:{...(input.event.payload||{}),...(input.event.fields?{fields:input.event.fields}:{})}};let row=event.payload||{};
  if(rule.condition&&event.entity?.moduleId==='app.tasks') { const task=await services.query(ref('task.get','app.tasks'),{id:event.entity.id});const fields=definition.fields.length?(await fieldQuery({entity:event.entity})).values:{};row={...task,fields,completed:!!task?.completedAt,archived:!!task?.archivedAt,deleted:!!task?.deletedAt}; }
  if(!filter(row,rule.condition,await nowDate()))return {writes:[],events:[],result:{skipped:true}};
  const writes=[],events=[];
  for(const action of rule.actions) {
    const command=action.command,payload=await resolve(action.payload||{}, {},{...event,entityId:event.entity?.id});
    if(command==='field.set'||command==='field.clear') { const field=await (command==='field.set'?fieldSet(payload):fieldClear(payload));writes.push(...field.writes);events.push(...field.events); } else await services.prepare(ref(command,'app.tasks'),payload);
  }
  return {writes,events,result:{actionCount:rule.actions.length}};
}
async function executeTask(command,input) { const plan=await services.prepare(ref(command,'app.tasks'),input);if(await ui.review(plan.planId))return services.commit(plan.planId); }
export async function render({state={},context={},event,formValues={}}) {
  const page=definition.pages.find(p=>p.id===context.legacyPageId)||definition.pages[0],view=definition.views.find(v=>v.id===page?.view);
  if(!view)return {state,tree:{type:'column',children:[]}};
  let added=false;
  if(event?.type==='add'&&page.quickAdd) {
    const defaults=await resolve(page.quickAddDefaults||{});
    const result=await executeTask('task.create',{...defaults,title:formValues.quickTitle||event.value,projectId:context.projectId||defaults.projectId||null});added=!!result;
  }
  if(event?.type==='complete') await executeTask('task.setCompleted',{id:event.task.id,completed:event.value,expectedUpdatedAt:event.task.updatedAt});
  if(event?.type==='edit') {
    const t=event.task,values=await ui.dialog({title:'编辑任务',fields:[{key:'title',label:'标题',value:t.title,required:true,maxLength:300},{key:'priority',label:'优先级',type:'select',value:String(t.priority),options:[0,1,2,3].map(v=>({value:String(v),label:String(v)}))},{key:'dueDate',label:'到期日期（留空清除）',type:'date',value:t.dueDate},{key:'plannedDate',label:'计划日期（留空清除）',type:'date',value:t.plannedDate}]});
    if(values) await executeTask('task.updateFields',{id:t.id,expectedUpdatedAt:t.updatedAt,changes:{...values,priority:Number(values.priority),dueDate:values.dueDate||null,plannedDate:values.plannedDate||null}});
  }
  let tasks=await services.query(ref('task.list','app.tasks'),{view:'raw'}),today=await nowDate();
  tasks=tasks.filter(t=>filter(t,view.filter,today));
  const value=(t,key)=>key.startsWith('fields.')?t.fields?.[fieldKey(key.slice(7))]:key.split('.').reduce((value,k)=>value?.[k],t);
  if(view.sort?.length) tasks.sort((a,b)=>{for(const item of view.sort) {const av=value(a,item.field),bv=value(b,item.field);let comparison=av===bv?0:av==null?-1:bv==null?1:typeof av==='number'&&typeof bv==='number'?av-bv:String(av).localeCompare(String(bv));if(comparison)return item.direction==='desc'?-comparison:comparison;}return a.id.localeCompare(b.id);});
  if(view.limit)tasks=tasks.slice(0,view.limit);
  const writable=definition.manifest.permissions.includes('tasks.write');
  return {state,clearForms:added?['quickTitle']:[],tree:{type:'column',children:tasks.length?tasks.map(t=>({type:'card',children:[writable?{type:'checkbox',text:t.title,value:t.completed,event:{type:'complete',task:t}}:{type:'text',text:t.title},...(view.showFields||[]).map(k=>({type:'text',text:`${k}: ${t.fields?.[fieldKey(k)]??''}`})),...(writable?[{type:'button',text:'编辑',event:{type:'edit',task:t}}]:[])]})):[{type:'text',text:view.emptyText||'暂无内容'}],...(page.quickAdd&&writable?{footer:{type:'column',children:[{type:'input',key:'quickTitle',text:'添加任务…',event:{type:'add'}},{type:'button',text:'添加',event:{type:'add'}}]}}:{})}};
}
export async function renderTemplates({state={},event}) {
  if(event?.templateId) {
    const t=definition.templates.find(t=>t.id===event.templateId),parameters=await ui.dialog({title:t.title,fields:(t.parameters||[]).map(p=>({key:p.id,label:p.label,value:String(p.default??''),type:p.type==='select'?'select':p.type==='number'?'number':'text',options:p.options?.map(x=>({value:x,label:x}))}))});
    if(parameters) {for(const p of t.parameters||[])if(p.type==='number')parameters[p.id]=Number(parameters[p.id]);const plan=await services.prepare(ref('template.'+t.id),{templateId:t.id,parameters});if(await ui.review(plan.planId))await services.commit(plan.planId);}
  }
  return {state,tree:{type:'column',children:definition.templates.map(t=>({type:'button',text:t.title,event:{templateId:t.id}}))}};
}
