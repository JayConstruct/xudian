const VIEW='daily';
import {services,ui,clock} from '@xudian/sdk';
const ref=id=>({moduleId:'app.tasks',serviceId:id,majorVersion:1});
const button=(text,event)=>({type:'button',text,event});
const label=text=>({type:'text',text,style:'muted'});
const section=(title,count,action)=>({type:'sectionHeader',title,count,...(action?{action}: {})});
function validDate(value) {
  if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(value)||Number(value.slice(0,4))<1) throw new Error('请选择有效日期');
  const date=new Date(value+'T00:00:00Z');
  if(!Number.isFinite(date.getTime())||date.toISOString().slice(0,10)!==value) throw new Error('请选择有效日期');
  return value;
}
function weekDays(today) {
  const date=new Date(today+'T00:00:00Z');
  return Array.from({length:5},(_,i)=>{
    const day=new Date(date.getTime()+(i-2)*86400000);
    return {date:day.toISOString().slice(0,10),label:['周日','周一','周二','周三','周四','周五','周六'][day.getUTCDay()]};
  }).filter(day=>/^\d{4}-\d{2}-\d{2}$/.test(day.date)&&Number(day.date.slice(0,4))>0);
}
async function overview(state,event,context) {
  const today=await clock.today(),selectedDate=validDate(event?.type==='selectDate'?event.value:context.selectedDate??today);
  const days=weekDays(selectedDate),counts=await services.query(ref('task.dayCounts'),{dates:days.map(day=>day.date)});
  const selected=counts.days.find(day=>day.date===selectedDate),pending=selected.loadedPending,completed=selected.loadedCompleted;
  const summary=selected.hasMore?(selectedDate<today?`已加载 ${pending} 项待办 · ${completed} 项已完成 · 还有更多任务`:'50+ 项待办'):[`${pending} 项待办`,...(completed?[`${completed} 项已完成`]:[])].join(' · ');
  return {state,runtimeContextPatch:{selectedDate},tree:{type:'dayOverview',key:'day-overview',date:selectedDate,todayDate:today,dateHeading:false,dateControls:false,summary,
    days:days.map(day=>({...day,...counts.days.find(count=>count.date===day.date),isToday:day.date===today})),selectedDate,event:{type:'selectDate'}}};
}
const field=(key,label,value='',type='text',options)=>({key,label,value,type:['dueDate','plannedDate'].includes(key)?'date':type,required:['name','title'].includes(key),maxLength:key==='title'?300:120,...(options?{options}: {})});
async function execute(id,input) { const plan=await services.prepare(ref(id),input); if(await ui.review(plan.planId)) return services.commit(plan.planId); }
export async function render({state={},event,formValues={},context={}}) {
  state={...state};
  if(context.pageId==='app.views.today.home')return {state,runtimeContextPatch:{selectedDate:validDate(context.selectedDate??await clock.today())},tree:{type:'column',children:[]}};
  if(context.pageId==='app.views.today.overview')return overview(state,event,context);
  const today=await clock.today(),selectedDate=validDate(context.selectedDate??today);
  if(state.selectedDate!==selectedDate){state.taskLimit=50;state.selectedDate=selectedDate;}
  let clearQuick=false;
  if(event?.type==='toggleQuick')state.quickExpanded=!state.quickExpanded;
  if(event?.type==='moreTasks')state.taskLimit=Math.min(10000,(state.taskLimit||50)+50);
  if(event?.type==='project') {state.project=event.project;state.taskLimit=50;}
  if(event?.type==='back') {delete state.project;state.taskLimit=50;}
  if(event?.type==='newProject') {
    const values=await ui.dialog({title:'新建项目',fields:[field('name','项目名称')]});
    if(values) await execute('project.create',values);
  }
  const projectId=state.project?.id||context.projectId;
  const scope=`${VIEW}:${selectedDate}:${projectId||''}`;
  if(state.feedback?.scope!==scope)delete state.feedback;
  const feedback=(removeKeys=[],highlightKeys=[])=>{
    state.feedbackSequence=(state.feedbackSequence||0)+1;
    state.feedback={scope,key:state.feedbackSequence,removeKeys,highlightKeys};
  };
  if(event?.type==='add') {
    const input={title:formValues.quickTitle||event.value,projectId:projectId||null};
    if(VIEW==='daily') input.plannedDate=selectedDate;
    const result=await execute('task.create',input); clearQuick=!!result;
    if(result)feedback([],[result.id]);
  }
  if(event?.type==='complete') {
    const result=await execute('task.setCompleted',{id:event.task.id,completed:event.value,expectedUpdatedAt:event.task.updatedAt});
    // A presentation failure must not turn an already committed write into an
    // apparent command failure or invite a duplicate submission.
    if(result) {
      if(event.value)feedback([event.task.id]);
      try {await ui.notify({message:event.value?'任务已完成':'任务已重新打开',kind:'success',duration:1800});}catch(_) {}
    }
  }
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
  const children=[];
  if(VIEW==='projects'&&!projectId) {
    children.push({...button('新建项目',{type:'newProject'}),key:'feed:new-project'});
    for(const p of await services.query(ref('project.list'),{})) children.push({...button(p.name,{type:'project',project:p}),key:'project:'+p.id});
  } else {
    if(state.project) children.push({...button(`返回项目 · ${state.project.name}`,{type:'back'}),key:'feed:back'});
    const taskLimit=state.taskLimit||50;
    const tasks=await services.query(ref('task.list'),{limit:Math.min(10000,taskLimit+1),view:VIEW==='projects'?'all':VIEW,date:selectedDate,...(projectId?{projectId}: {})});
    const projects=await services.query(ref('project.list'),{}),projectNames=new Map(projects.map(project=>[project.id,project.name]));
    const hasMore=tasks.length>taskLimit;
    children.push({...section(selectedDate<today?'当日任务':'待办事项',hasMore?`${taskLimit}+`:tasks.length,{label:'添加任务',icon:'add',event:{type:'toggleQuick'}}),key:'feed:heading'});
    if(!tasks.length)children.push({...label(selectedDate===today?'暂无今天待办或逾期任务':`${selectedDate} 没有安排任务`),key:'feed:empty'});
    for(const task of tasks.slice(0,taskLimit)) {
      const fields=(task.fieldDefinitions||[]).map(field=>({type:'row',children:[
        label((field.label||field.id)+': '+(Array.isArray(task.fields[field.key])?task.fields[field.key].join('、'):(task.fields[field.key]??'未设置'))),
        ...(field.commands?.set?[button('修改字段',{type:'field',task,field}),button('清除字段',{type:'clearField',task,field})]:[]),
      ]}));
      children.push({type:'taskItem',key:task.id,title:task.title,completed:task.completed,
        subtitle:[task.dueDate&&`到期 ${task.dueDate}`,task.plannedDate&&`计划 ${task.plannedDate}`,projectNames.get(task.projectId),task.priority&&`优先级 ${task.priority}`].filter(Boolean).join(' · '),
        event:{type:'complete',task},openEvent:{type:'edit',task},
        ...(fields.length?{children:[{type:'disclosure',key:'task-fields:'+task.id,text:'扩展字段',children:fields}]}: {}),
      });
    }
    if(hasMore)children.push({...button('加载更多任务',{type:'moreTasks'}),key:'feed:more'});
    children.push({...label(tasks.length?'完成一项，就少一份牵挂。':selectedDate===today?'把今天想做的事记下来。':'把这一天想做的事记下来。'),key:'feed:hint'});
    // The host owns the collapse and keeps the input element mounted. New task
    // rows may shift this group without losing focus, selection or the draft.
    children.push({type:'transition',key:'quick-add',visible:!!state.quickExpanded,collapse:true,duration:220,child:{type:'column',key:'quick-add-content',children:[
      button('收起添加',{type:'toggleQuick'}),
      {type:'input',key:'quickTitle',text:state.project?`添加到${state.project.name}…`:'添加任务…',event:{type:'add'}},
      button('添加',{type:'add'}),
    ]}});
  }
  return {state,clearForms:clearQuick?['quickTitle']:[],tree:{type:'keyedList',key:'task-feed',scope,
    feedbackKey:state.feedback?.key,removeKeys:state.feedback?.removeKeys||[],highlightKeys:state.feedback?.highlightKeys||[],duration:220,children}};
}
