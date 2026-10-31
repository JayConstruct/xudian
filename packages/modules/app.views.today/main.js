const VIEW='daily';
import {services,ui,clock} from '@xudian/sdk';
const ref=id=>({moduleId:'app.tasks',serviceId:id,majorVersion:1});
const button=(text,event)=>({type:'button',text,event});
const label=text=>({type:'text',text,style:'muted'});
const completionInput=(task,zone)=>({id:task.id,completed:!task.completedAt,expectedUpdatedAt:task.updatedAt,...(!task.completedAt?{completedTimezone:task.plannedTimezone||zone}:{})});
const completionControl=(task,zone)=>({event:{type:'complete',task,completedTimezone:task.plannedTimezone||zone},command:{ref:ref('task.setCompleted'),input:completionInput(task,zone)}});
async function completionTimezone() {
  try{return (await clock.systemTimezone()).zone;}
  catch(error){if(String(error).includes('Preview forbids external capabilities'))return 'UTC';throw error;}
}
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
  const days=weekDays(selectedDate),counts=await services.query(ref('task.dayCounts'),{dates:days.map(day=>day.date),includeCompleted:true});
  const selected=counts.days.find(day=>day.date===selectedDate),pending=selected.loadedPending,completed=selected.loadedCompleted;
  const summary=selected.hasMore?`已加载 ${pending} 项待办 · ${completed} 项已完成 · 还有更多任务`:[`${pending} 项待办`,...(completed?[`${completed} 项已完成`]:[])].join(' · ');
  return {state,runtimeContextPatch:{selectedDate},tree:{type:'dayOverview',key:'day-overview',date:selectedDate,todayDate:today,dateHeading:false,dateControls:false,compact:true,summary,
    days:days.map(day=>({...day,...counts.days.find(count=>count.date===day.date),isToday:day.date===today})),selectedDate,event:{type:'selectDate'}}};
}
const courseRef={moduleId:'app.schedule',serviceId:'schedule.query.todayFeed',majorVersion:1};
async function courseFeed(date) {
  const directory=await services.directory();
  if(!directory.some(item=>item.moduleId===courseRef.moduleId&&item.id===courseRef.serviceId))return {available:false,items:[]};
  try{return {available:true,...await services.query(courseRef,{date})};}
  catch(error){return {available:true,items:[],error:String(error)};}
}
function courseNode(item) {
  return {type:'agendaItem',compact:true,key:'course:'+item.timetableId+':'+item.occurrenceId,title:item.title,startTime:item.startTime,endTime:item.endTime,color:item.color||'#AE8558',icon:'school',
    subtitle:[item.location||'未填地点',item.teacher].filter(Boolean).join(' · '),
    event:{type:'openCourse',reference:{timetableId:item.timetableId,occurrenceId:item.occurrenceId,meetingId:item.meetingId||null,originalDate:item.originalDate,date:item.date}}};
}
const field=(key,label,value='',type='text',options)=>({key,label,value,type:['dueDate','plannedDate'].includes(key)?'date':type,required:['name','title'].includes(key),maxLength:key==='title'?300:120,...(options?{options}: {})});
async function execute(id,input) { const plan=await services.prepare(ref(id),input); if(await ui.review(plan.planId)) return services.commit(plan.planId); }
function shortDate(value,selectedDate) {
  return value.slice(0,4)===selectedDate.slice(0,4)?`${Number(value.slice(5,7))}/${Number(value.slice(8,10))}`:value;
}
async function plannedLabels(tasks,selectedDate,localTimes=new Map()) {
  const labels=tasks.map(task=>task.plannedDate&&`计划 ${task.plannedDate===selectedDate?'当天':shortDate(task.plannedDate,selectedDate)}`);
  const precise=tasks.flatMap((task,index)=>task.plannedStartAt&&task.plannedEndAt&&task.plannedTimezone?[{task,index}]:[]);
  // The host accepts up to 256 instants. Keep pagination bounded too: two
  // boundaries per task, one bridge round trip for the usual 50-item page.
  for(let offset=0;offset<precise.length;offset+=128) {
    const batch=precise.slice(offset,offset+128);
    const local=await clock.toLocalMany(batch.flatMap(({task})=>[
      {utc:task.plannedStartAt,zone:task.plannedTimezone},
      {utc:task.plannedEndAt,zone:task.plannedTimezone},
    ]));
    batch.forEach(({task,index},i)=>{
      const start=local[i*2],end=local[i*2+1];
      localTimes.set(task.id,[start,end]);
      const startDate=start.date===selectedDate?'':`${shortDate(start.date,selectedDate)} `;
      const endDate=end.date===start.date?'':`${shortDate(end.date,selectedDate)} `;
      labels[index]=`计划 ${startDate}${start.time}–${endDate}${end.time}`;
    });
  }
  return labels;
}
async function deadlineLabels(tasks,selectedDate,today) {
  const labels=tasks.map(task=>task.dueDate?`${task.dueDate===today?'今天':shortDate(task.dueDate,selectedDate)}截止`:'');
  const exact=tasks.flatMap((task,index)=>task.dueAt?[{task,index}]:[]);
  const now=exact.length?Date.parse(await clock.now()):null;
  for(let offset=0;offset<exact.length;offset+=256) {
    const batch=exact.slice(offset,offset+256);
    const local=await clock.toLocalMany(batch.map(({task})=>({utc:task.dueAt,zone:task.dueTimezone||'UTC'})));
    batch.forEach(({task,index},position)=>{
      const value=local[position];
      labels[index]=`${value.date===today?'今天':shortDate(value.date,selectedDate)} ${value.time}截止`;
    });
  }
  return labels.map((value,index)=>{
    const task=tasks[index],overdue=task.dueAt?Date.parse(task.dueAt)<now:task.dueDate&&task.dueDate<today;
    return !task.completed&&overdue?`已逾期 · ${value}`:value;
  });
}
async function completionLabels(tasks) {
  const result=tasks.map(()=>''),completed=tasks.flatMap((task,index)=>task.completedAt?[{task,index}]:[]);
  const legacyZone=completed.some(({task})=>!task.completedTimezone)?await completionTimezone():null;
  for(let offset=0;offset<completed.length;offset+=256) {
    const batch=completed.slice(offset,offset+256);
    const local=await clock.toLocalMany(batch.map(({task})=>({utc:task.completedAt,zone:task.completedTimezone||legacyZone})));
    batch.forEach(({task,index},i)=>{
      const recorded=local[i],corrected=task.actualCompletedOn&&task.actualCompletedOn!==recorded.date;
      result[index]=corrected?`已完成 · 完成日期 ${task.actualCompletedOn} · 记录于 ${recorded.date} ${recorded.time}`:`已完成 · ${recorded.date} ${recorded.time}`;
    });
  }
  return result;
}
async function completedReview(state,event,today) {
  const limit=state.taskLimit||50,tasks=await services.query(ref('task.list'),{view:'completed',limit:Math.min(10000,limit+1)});
  const hasMore=tasks.length>limit,visible=tasks.slice(0,limit),completed=await completionLabels(visible);
  const plans=await plannedLabels(visible,today),deadlines=await deadlineLabels(visible,today,today);
  const projects=await services.query(ref('project.list'),{}),names=new Map(projects.map(project=>[project.id,project.name]));
  const children=[section('已完成任务',hasMore?`${limit}+`:tasks.length),label('按完成时间从近到远查看。点击勾选可重新打开任务。')];
  if(!tasks.length)children.push(label('还没有已完成的任务，完成后会在这里留下记录。'));
  visible.forEach((task,index)=>children.push({type:'taskItem',key:task.id,title:task.title,completed:true,
    subtitle:[completed[index],plans[index],deadlines[index],names.get(task.projectId)].filter(Boolean).join(' · '),
    ...completionControl(task,null),openEvent:{type:'edit',task},
  }));
  if(hasMore)children.push(button('加载更多记录',{type:'moreTasks'}));
  return {state,tree:{type:'column',children}};
}
export async function render({state={},event,formValues={},context={}}) {
  state={...state};
  if(context.pageId==='app.views.today.home')return {state,runtimeContextPatch:{selectedDate:validDate(context.selectedDate??await clock.today())},tree:{type:'column',children:[]}};
  if(context.pageId==='app.views.today.overview')return overview(state,event,context);
  const today=await clock.today(),selectedDate=validDate(context.selectedDate??today),review=context.pageId==='app.views.today.review';
  if(event?.type==='review')await ui.navigate('app.views.today.review');
  if(event?.type==='viewSchedule')await ui.navigate('app.schedule.home');
  if(event?.type==='openCourse')await ui.navigate('app.schedule.occurrence',event.reference);
  if(state.selectedDate!==selectedDate){state.taskLimit=50;state.selectedDate=selectedDate;}
  let clearQuick=false;
  if(event?.type==='toggleQuick')state.quickExpanded=!state.quickExpanded;
  if(event?.type==='moreTasks')state.taskLimit=Math.min(10000,(state.taskLimit||50)+50);
  if(event?.type==='project') {state.project=event.project;state.taskLimit=50;}
  if(event?.type==='back') {delete state.project;state.taskLimit=50;}
  if(event?.type==='newProject') {
    const values=await ui.dialog({title:'新建项目',fields:[field('name','项目名称')],command:{ref:ref('project.create'),input:{},fields:{name:'name'}}});
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
    if(event.value!==!event.task.completedAt)throw new Error('任务状态已变化，请重新打开后操作');
    const zone=event.completedTimezone||event.task.plannedTimezone||(event.value?(await clock.systemTimezone()).zone:null);
    const result=await execute('task.setCompleted',completionInput(event.task,zone));
    // A presentation failure must not turn an already committed write into an
    // apparent command failure or invite a duplicate submission.
    if(result) {
      feedback([],[event.task.id]);
      try {await ui.notify({message:event.value?'任务已完成':'任务已重新打开',kind:'success',duration:1800});}catch(_) {}
    }
  }
  if(event?.type==='edit') {
    const t=event.task;
    const values=await ui.dialog({title:'编辑任务',fields:[field('title','标题',t.title),field('priority','优先级',String(t.priority),'select',[0,1,2,3].map(x=>({value:String(x),label:String(x)}))),field('dueDate','到期日期 YYYY-MM-DD（留空清除）',t.dueDate),field('plannedDate','计划日期 YYYY-MM-DD（留空清除）',t.plannedDate)]});
    if(values) {
      const changes={...values,priority:Number(values.priority),dueDate:values.dueDate||null,plannedDate:values.plannedDate||null};
      for(const key of Object.keys(changes))if(changes[key]===(t[key]??null))delete changes[key];
      if(Object.keys(changes).length)await execute('task.updateFields',{id:t.id,changes,expectedUpdatedAt:t.updatedAt});
    }
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
  if(review)return completedReview(state,event,today);
  const children=[];
  if(VIEW==='projects'&&!projectId) {
    children.push({...button('新建项目',{type:'newProject'}),key:'feed:new-project'});
    for(const p of await services.query(ref('project.list'),{})) children.push({...button(p.name,{type:'project',project:p}),key:'project:'+p.id});
  } else {
    if(state.project) children.push({...button(`返回项目 · ${state.project.name}`,{type:'back'}),key:'feed:back'});
    const taskLimit=state.taskLimit||50;
    const tasks=await services.query(ref('task.list'),{limit:Math.min(10000,taskLimit+1),view:VIEW==='projects'?'all':VIEW,date:selectedDate,includeCompleted:true,...(projectId?{projectId}: {})});
    const projects=await services.query(ref('project.list'),{}),projectNames=new Map(projects.map(project=>[project.id,project.name]));
    const hasMore=tasks.length>taskLimit;
    // One status-independent page preserves ordering and pagination on completion.
    const allTasks=tasks.slice(0,taskLimit);
    const taskTimes=new Map();
    const planLabels=await plannedLabels(allTasks,selectedDate,taskTimes),dueLabels=await deadlineLabels(allTasks,selectedDate,today);
    const courses=await courseFeed(selectedDate);
    const pending=allTasks.filter(task=>!task.completedAt),done=allTasks.filter(task=>!!task.completedAt);
    children.push({type:'sectionHeader',key:'feed:heading',compact:true,title:`${pending.length}${hasMore?'+':''} 项待办${courses.error?' · 课程待加载':courses.available?` · ${courses.items.length} 节课程`:''}${done.length?` · ${done.length} 项已完成`:''}`,action:{label:'添加任务',icon:'add',event:{type:'toggleQuick'}}});
    if(courses.error)children.push({...label('课程暂时无法加载，请到课表查看'),key:'feed:course-error'});
    const now=Date.parse(await clock.now());
    const focus=selectedDate===today?courses.items.find(item=>item.startOffset<=0&&item.endOffset>0)||courses.items.find(item=>item.startOffset>0):null;
    if(focus)children.push({...courseNode(focus),key:'feed:next-course',hideTime:true,eyebrow:`${focus.startOffset<=0?'正在上课':'下一节课'}  ${focus.startTime} - ${focus.endTime}`,badge:focus.startOffset>0&&focus.startOffset<=60?`还有 ${Math.ceil(focus.startOffset)} 分钟`:undefined});
    const timed=[];
    for(const course of courses.items)timed.push({at:course.startAt?Date.parse(course.startAt):now+course.startOffset*60000,id:'course:'+course.timetableId+':'+course.occurrenceId,node:courseNode(course)});
    const unscheduled=[],otherTasks=[];
    const completionZone=allTasks.some(task=>!task.completedAt&&!task.plannedTimezone)?await completionTimezone():null;
    for(const [index,task] of allTasks.entries()) {
      const fields=(task.fieldDefinitions||[]).map(field=>({type:'row',children:[
        label((field.label||field.id)+': '+(Array.isArray(task.fields[field.key])?task.fields[field.key].join('、'):(task.fields[field.key]??'未设置'))),
        ...(field.commands?.set?[button('修改字段',{type:'field',task,field}),button('清除字段',{type:'clearField',task,field})]:[]),
      ]}));
      const times=task.plannedDate===selectedDate?taskTimes.get(task.id):null;
      const node={type:'taskItem',key:task.id,title:task.title,completed:task.completed,compact:true,
        ...(times?{startTime:times[0].time,endTime:(times[1].date!==times[0].date?'次日 ':'')+times[1].time,colorKey:task.id}:{}),
        subtitle:[task.completedAt?'已完成':null,dueLabels[index],times?null:planLabels[index],task.estimatedMinutes&&`${task.estimatedMinutes}分钟`,projectNames.get(task.projectId),task.priority&&`优先级 ${task.priority}`].filter(Boolean).join(' · '),
        ...completionControl(task,completionZone),openEvent:{type:'edit',task},
        ...(fields.length?{children:[{type:'disclosure',key:'task-fields:'+task.id,text:'扩展字段',children:fields}]}: {}),
      };
      if(times)timed.push({at:Date.parse(task.plannedStartAt),id:task.id,node});
      else if(task.plannedStartAt)otherTasks.push(node);
      else unscheduled.push(node);
    }
    timed.sort((a,b)=>a.at-b.at||a.id.localeCompare(b.id));
    children.push(...timed.map(item=>item.node));
    if(unscheduled.length)children.push({type:'sectionHeader',key:'feed:pending-heading',title:'待安排',count:unscheduled.length,compact:true},...unscheduled);
    if(!allTasks.length&&!courses.items.length)children.push({...label(selectedDate===today?'暂无今天待办或逾期任务':`${selectedDate} 没有安排任务`),key:'feed:empty'});
    if(otherTasks.length)children.push({type:'sectionHeader',key:'feed:other-heading',title:'其他任务',count:otherTasks.length,compact:true},...otherTasks);
    children.push({type:'row',key:'feed:links',children:[...(courses.available?[{...button('查看课表',{type:'viewSchedule'}),variant:'text'}]:[]),{...button('完成记录与复盘',{type:'review'}),variant:'text'}]});
    if(hasMore)children.push({...button('加载更多任务',{type:'moreTasks'}),key:'feed:more'});
    children.push({...label(tasks.length?'完成一项，就少一份牵挂。':selectedDate===today?'把今天想做的事记下来。':'把这一天想做的事记下来。'),key:'feed:hint'});
    const addCommand={ref:ref('task.create'),input:{title:{bind:['formValues','quickTitle']},projectId:projectId||null,...(VIEW==='daily'?{plannedDate:selectedDate}:{})}};
    // The host owns the collapse and keeps the input element mounted. New task
    // rows may shift this group without losing focus, selection or the draft.
    children.push({type:'transition',key:'quick-add',visible:!!state.quickExpanded,collapse:true,duration:220,child:{type:'column',key:'quick-add-content',children:[
      button('收起添加',{type:'toggleQuick'}),
      {type:'input',key:'quickTitle',text:state.project?`添加到${state.project.name}…`:'添加任务…',event:{type:'add'},command:addCommand},
      {...button('添加',{type:'add'}),command:addCommand},
    ]}});
    const quick=children.pop();
    children.splice(1,0,quick);
  }
  return {state,clearForms:clearQuick?['quickTitle']:[],tree:{type:'keyedList',key:'task-feed',compact:true,scope,
    feedbackKey:state.feedback?.key,removeKeys:state.feedback?.removeKeys||[],highlightKeys:state.feedback?.highlightKeys||[],duration:220,spacing:8,children}};
}
