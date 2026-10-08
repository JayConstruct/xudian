const VIEW='inbox';
import {services,ui,clock} from '@xudian/sdk';
const ref=id=>({moduleId:'app.tasks',serviceId:id,majorVersion:1});
const button=(text,event)=>({type:'button',text,event});
const field=(key,label,value='',type='text',options)=>({key,label,value,type:['dueDate','plannedDate'].includes(key)?'date':type,required:['name','title'].includes(key),maxLength:key==='title'?300:120,...(options?{options}: {})});
async function execute(id,input) { const plan=await services.prepare(ref(id),input); if(await ui.review(plan.planId)) return services.commit(plan.planId); }
export async function render({state={},event,formValues={},context={}}) {
  state={...state}; let clearQuick=false;
  if(event?.type==='moreTasks')state.taskLimit=Math.min(10000,(state.taskLimit||50)+50);
  if(event?.type==='project') {state.project=event.project;state.taskLimit=50;}
  if(event?.type==='back') {delete state.project;state.taskLimit=50;}
  if(event?.type==='newProject') {
    const values=await ui.dialog({title:'新建项目',fields:[field('name','项目名称')]});
    if(values) await execute('project.create',values);
  }
  const projectId=state.project?.id||context.projectId;
  if(event?.type==='add') {
    const input={title:formValues.quickTitle||event.value,projectId:projectId||null};
    if(VIEW==='today') input.plannedDate=await clock.today();
    const result=await execute('task.create',input); clearQuick=!!result;
  }
  if(event?.type==='complete') await execute('task.setCompleted',{id:event.task.id,completed:event.value,expectedUpdatedAt:event.task.updatedAt});
  if(event?.type==='edit') {
    const t=event.task;
    const values=await ui.dialog({title:'编辑任务',fields:[field('title','标题',t.title),field('priority','优先级',String(t.priority),'select',[0,1,2,3].map(x=>({value:String(x),label:String(x)}))),field('dueDate','到期日期 YYYY-MM-DD（留空清除）',t.dueDate),field('plannedDate','计划日期 YYYY-MM-DD（留空清除）',t.plannedDate)]});
    if(values) await execute('task.updateFields',{id:t.id,changes:{...values,priority:Number(values.priority),dueDate:values.dueDate||null,plannedDate:values.plannedDate||null},expectedUpdatedAt:t.updatedAt});
  }
  if(event?.type==='field') {
    const f=event.field,entity={moduleId:'app.tasks',collection:'tasks',id:event.task.id},current=event.task.fields?.[f.key];
    const values=await ui.dialog({title:f.label||f.id,fields:[{key:'value',label:f.label||f.id,type:f.type,value:current ?? '',options:f.config?.options?.map(value=>({value,label:value}))}]});
    if(values) {
      const plan=await services.prepare({moduleId:f.moduleId,serviceId:f.commands.set,majorVersion:1},{entity,fieldKey:f.key,value:values.value});
      if(await ui.review(plan.planId)) await services.commit(plan.planId);
    }
  }
  if(event?.type==='clearField') {
    const f=event.field,plan=await services.prepare({moduleId:f.moduleId,serviceId:f.commands.clear,majorVersion:1},{entity:{moduleId:'app.tasks',collection:'tasks',id:event.task.id},fieldKey:f.key});
    if(await ui.review(plan.planId)) await services.commit(plan.planId);
  }
  const children=[]; let footer;
  if(VIEW==='projects'&&!projectId) {
    children.push(button('新建项目',{type:'newProject'}));
    for(const p of await services.query(ref('project.list'),{})) children.push(button(p.name,{type:'project',project:p}));
  } else {
    if(state.project) children.push(button(`返回项目 · ${state.project.name}`,{type:'back'}));
    const taskLimit=state.taskLimit||50;
    const tasks=await services.query(ref('task.list'),{limit:Math.min(10000,taskLimit+1),view:VIEW==='projects'?'all':VIEW,...(projectId?{projectId}: {})});
    if(!tasks.length) children.push({type:'text',text:VIEW==='today'?'暂无今天待办或逾期任务':VIEW==='inbox'?'收件箱为空':'这个项目还没有任务'});
    for(const task of tasks.slice(0,taskLimit)) children.push({type:'card',key:task.id,children:[{type:'checkbox',text:task.title,value:task.completed,event:{type:'complete',task}},
      {type:'text',text:[task.dueDate&&`到期 ${task.dueDate}`,task.plannedDate&&`计划 ${task.plannedDate}`,task.priority&&`优先级 ${task.priority}`].filter(Boolean).join(' · ')},button('编辑',{type:'edit',task}),...(task.fieldDefinitions||[]).map(field=>({type:'row',children:[{type:'text',text:(field.label||field.id)+': '+(Array.isArray(task.fields[field.key])?task.fields[field.key].join('、'):(task.fields[field.key]??'未设置'))},...(field.commands?.set?[button('修改字段',{type:'field',task,field}),button('清除字段',{type:'clearField',task,field})]:[])]}))]});
    if(tasks.length>taskLimit)children.push(button('加载更多任务',{type:'moreTasks'}));
    footer={type:'column',children:[{type:'input',key:'quickTitle',text:state.project?`添加到${state.project.name}…`:'添加任务…',event:{type:'add'}},button('添加',{type:'add'})]};
  }
  return {state,clearForms:clearQuick?['quickTitle']:[],tree:ui.component('ui.page.list@1',{key:'task-list',slots:{items:children,...(footer?{footer}: {})}})};
}
