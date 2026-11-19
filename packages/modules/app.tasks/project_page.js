import {data, services, ui, clock} from '@xudian/sdk';
import {records} from './projects.js';
import {activitySummaries, isNewPending, recordPages} from './project_activity.js';

import {tabs, tabHeader, section, summaryCard, taskSummary, groupedRows} from './project_layout.js';

const directory='app.tasks.directory';
const row=(title,subtitle,event,icon)=>({type:'listTile',title,subtitle:subtitle||null,event,icon,iconTone:({folder:'warning',briefcase:'accent',calendar:'accent',check:'success',pin:'accent',unpin:'accent',calendarAdd:'accent',calendarRemove:'accent'})[icon]||'muted'});
const button=(text,event,variant='tonal')=>({type:'button',text,event,variant});
const action=(label,icon,event)=>({label,icon,event});
const field=(key,label,value='',options={})=>({key,label,value,...options});
const importanceNames=['低重要性','普通','高重要性'];
const sortLabels={recent:'最近推进优先',oldest:'最久未推进优先'};
const sortKey='projects.activitySort';
const text=(text,style='caption')=>({type:'text',text,style});
const heading=section;
const divider={type:'divider'};
const compareText=(a,b)=>a.localeCompare(b)|| (a<b?-1:a>b?1:0);
const clockLabel=(local,today)=>local?
  (local.date.slice(0,4)===today.slice(0,4)?local.date.slice(5):local.date).replaceAll('-','/')+' '+local.time:'';
const dateLabel=date=>Number(date.slice(5,7))+' 月 '+Number(date.slice(8))+' 日';
const footerBar=(...children)=>({type:'column',spacing:6,trailingSpacing:false,children});
const option=(value,label)=>({value,label});
const pickable=t=>!t.completedAt&&!t.plannedStartAt&&!t.projectQueued;
const revision=t=>({id:t.id,expectedUpdatedAt:t.updatedAt});
const scopeFilter=(field,value)=>value==null?{field,op:'isNull'}:{field,op:'eq',value};
const activeTaskFilter=filter=>({all:[scopeFilter('archivedAt',null),scopeFilter('deletedAt',null),filter]});
const activeTasks=filter=>records('tasks',activeTaskFilter(filter));
const activeTaskPages=filter=>recordPages('tasks',activeTaskFilter(filter));
function folderPath(f,folders){
  const names=[],seen=new Set();
  while(f&&!seen.has(f.id)){names.unshift(f.name);seen.add(f.id);f=folders.get(f.parentId);}
  return names.join(' / ');
}
function folderOptions(folders,projectId,label){
  return [option('',label),...[...folders.values()].filter(f=>f.projectId===projectId).map(f=>option(f.id,folderPath(f,folders)))];
}
async function command(id,input,confirmation){
  const plan=await services.prepare({moduleId:'app.tasks',serviceId:id,majorVersion:1},input);
  if(await ui.review(plan.planId,{...confirmation,message:confirmation.message.slice(0,6000),summaryOnly:true}))return services.commit(plan.planId);
}
async function timeLabels(tasks){
  const labels=new Map(),instants=[];
  for(const t of tasks){
    if(t.completedAt)instants.push({id:t.id,key:'completed',utc:t.completedAt,zone:t.completedTimezone});
    else if(t.plannedStartAt&&t.plannedEndAt){
      instants.push({id:t.id,key:'start',utc:t.plannedStartAt,zone:t.plannedTimezone},{id:t.id,key:'end',utc:t.plannedEndAt,zone:t.plannedTimezone});
    }
  }
  const fallback=instants.some(i=>!i.zone)?(await clock.systemTimezone()).zone:null;
  for(let i=0;i<instants.length;i+=256){
    const part=instants.slice(i,i+256);
    const times=await clock.toLocalMany(part.map(v=>({utc:v.utc,zone:v.zone||fallback})));
    part.forEach((v,index)=>{const entry=labels.get(v.id)||{};entry[v.key]=times[index];labels.set(v.id,entry)});
  }
  return labels;
}
function taskLabel(t,times,today){
  const local=times.get(t.id)||{};
  if(local.completed){
    return '已完成 · '+(t.actualCompletedOn&&t.actualCompletedOn!==local.completed.date?t.actualCompletedOn:clockLabel(local.completed,today));
  }
  if(local.end){
    const end=local.end.date===local.start.date?local.end.time:clockLabel(local.end,today);
    return clockLabel(local.start,today)+'–'+end;
  }
  return [t.projectQueued?'待安排':'未安排',t.plannedDate?'计划 '+t.plannedDate+'，时段待定':'',t.estimatedMinutes?t.estimatedMinutes+' 分钟':'未估时'].filter(Boolean).join(' · ');
}
function projectProgress(p,tasks,times,today){
  const done=tasks.filter(t=>t.completedAt).length;
  const pending=tasks.filter(t=>!t.completedAt&&!t.plannedStartAt&&t.projectQueued).length;
  const latest=tasks.reduce((date,t)=>{
    const end=times.get(t.id)?.end?.date;
    return end&&end>date?end:date;
  },'');
  let deviation='';
  if(p.targetDate){
    const date=p.completedOn||latest;
    const days=date?Math.round((Date.parse(date)-Date.parse(p.targetDate))/86400000):0;
    if(p.completedOn)deviation=days===0?'按期完成':(days<0?'提前 ':'延期 ')+Math.abs(days)+' 天完成';
    else if(days>0)deviation='预计延期 '+days+' 天 · 最晚安排 '+dateLabel(latest);
    else if(today>p.targetDate)deviation='已过目标日期';
  }
  return {done,pending,deviation};
}

function locationLabel(p, folders, folderId) {
  const path=folderPath(folders.get(p.folderId),folders)||'未分类';
  const folder=folderPath(folders.get(folderId),folders);
  return [path, p.name, folder].filter(Boolean).join(' / ');
}

async function activityRows(projects, extraCounts, activity, order, zone, today, folders, open, projectActions) {
  const entries=[...projects.values()]
    .filter(p=>!p.completedOn||extraCounts.get(p.id))
    .sort((a,b)=>{
      const left=activity.get(a.id)?.timestamp,right=activity.get(b.id)?.timestamp;
      if(left==null&&right!=null)return 1;
      if(left!=null&&right==null)return -1;
      if(left!=null&&right!=null&&left!==right)return order==='oldest'?left-right:right-left;
      return compareText(a.name,b.name)||compareText(a.id,b.id);
    });
  const labels=new Map();
  const dated=entries.filter(p=>activity.get(p.id)?.at);
  for(let index=0;index<dated.length;index+=256){
    const batch=dated.slice(index,index+256);
    const local=await clock.toLocalMany(batch.map(p=>({utc:activity.get(p.id).at,zone})));
    batch.forEach((p,i)=>labels.set(p.id,clockLabel(local[i],today)));
  }
  return entries.map(p=>{
    const path=folderPath(folders.get(p.folderId),folders)||'未分类';
    const status=p.completedOn?'完结 · 新增待办 '+extraCounts.get(p.id)+' 项':'未完结';
    const time=labels.has(p.id)?'上次推进 '+labels.get(p.id):'暂无推进记录';
    return wrap('activity:'+p.id,{
      ...row(p.name,path+'   ·   '+status+'\n'+time,open(p.id,null),'briefcase'),
      metaIcon:'clock',trailing:true,
    },projectActions(p),p.updatedAt);
  });
}
function wrap(key,child,actions,version){
  return {type:'swipeActions',key,menuTrigger:'longPress',extent:actions.length*104,revision:version,child:{trailing:false,...child},actions};
}
async function projectDialog(p,folderId,folders,today){
  const values=await ui.dialog({presentation:'compact',title:p?'项目设置':'新建项目',submitLabel:p?'保存':'创建',fields:[
    field('name','项目名称',p?.name||'',{required:true,maxLength:120}),
    field('status','项目状态',p?.completedOn?'finished':'open',p?{type:'select',
      options:[option('open','未完结'),option('finished','完结')]}:{value:'未完结',editable:false}),
    field('importance','重要性',String(p?.importance??1),{type:'select',options:importanceNames.map((n,i)=>option(String(i),n))}),
    field('targetDate','目标完成日期',p?.targetDate||'',{type:'date'}),
    field('folderId','所属分类',folderId||'',{type:'select',options:folderOptions(folders,null,'未分类')}),
  ]});
  if(!values)return;
  const input={name:values.name,importance:Number(values.importance),targetDate:values.targetDate||null,folderId:values.folderId||null};
  if(p)Object.assign(input,revision(p),{completedOn:values.status==='finished'?p.completedOn||today:null});
  return command(p?'project.edit':'project.create',input,{title:p?'保存项目设置':'创建项目',
    message:[values.name,values.status==='finished'?'完结':'未完结',importanceNames[input.importance],values.targetDate?'目标 '+values.targetDate:null,folderPath(folders.get(input.folderId),folders)||'未分类'].filter(Boolean).join(' · '),confirmLabel:p?'保存':'创建'});
}
export async function projectPage({state={},event={},context={}}){
  state={...state};event=event||{};
  const projectId=context.projectId||null,folderId=context.folderId||null;
  const projects=new Map((await records('projects')).filter(p=>!p.archivedAt).map(p=>[p.id,p]));
  const folders=new Map((await records('projectFolders')).map(f=>[f.id,f]));
  const p=projects.get(projectId),folder=folders.get(folderId);
  if((projectId&&!p)||(folderId&&(!folder||(folder.projectId||null)!==projectId)))return {state,tree:{type:'notice',text:'当前位置已变更，请返回目录'}};
  const root=!projectId&&!folderId&&!context.unfiled&&!context.taskId;
  const zone=(await clock.systemTimezone()).zone,today=await clock.today(zone);
  let order='recent';
  if(root&&state.tab==='activity')order=(await ui.preferences.get(sortKey))==='oldest'?'oldest':'recent';
  const pinsKey='projects.follow';
  let pins=(await ui.preferences.get(pinsKey))||[];
  if(!Array.isArray(pins))pins=[];
  const pinEvent=(kind,id)=>({type:'pin',kind,id});
  const pinAction=(kind,id)=>{
    const pinned=pins.includes(kind+':'+id);
    return action(pinned?'取消固定':'固定到跟进',pinned?'unpin':'pin',pinEvent(kind,id));
  };
  const projectActions=proj=>[pinAction('project',proj.id),action('项目设置','sliders',{type:'editProject',projectId:proj.id})];
  const editProject=event.projectId?projects.get(event.projectId):p;
  try {
    if(root&&event.type==='tab'&&tabs.includes(event.tab)){
      const previous=tabs.indexOf(state.tab||'directory');
      state.tabDirection=tabs.indexOf(event.tab)<previous?'previous':'next';
      state.tab=event.tab;
      if(state.tab==='activity')order=(await ui.preferences.get(sortKey))==='oldest'?'oldest':'recent';
    }
    if(event.type==='sort'&&root&&state.tab==='activity'&&Object.hasOwn(sortLabels,event.order)){
      order=event.order;
      await ui.preferences.set(sortKey,order);
    }
    if(event.type==='open')await ui.navigate(directory,event.location);
    if(event.type==='pin'){
      const key=event.kind+':'+event.id;
      pins=pins.includes(key)?pins.filter(v=>v!==key):[...pins,key];
      await ui.preferences.set(pinsKey,pins);
    }
    if(event.type==='newProject'||event.type==='editProject'){
      if(await projectDialog(event.type==='newProject'?null:editProject,event.type==='newProject'?folderId:editProject.folderId,folders,today))return projectPage({state,context});
    }
    if(event.type==='saveFolder'){
      const old=folders.get(event.id),values=await ui.dialog({presentation:'compact',title:old?'分类设置':'新建分类',fields:[
        field('name','分类名称',old?.name||'',{required:true}),
        ...(old?[field('parentId','上级分类',old.parentId||'',{type:'select',options:folderOptions(folders,projectId,p?'项目直属':'目录顶层').filter(o=>o.value!==old.id)})]:[]),
      ]});
      if(values&&await command('project.folder.save',{name:values.name,projectId,parentId:(old?values.parentId:folderId)||null,...(old?revision(old):{})},{title:old?'保存分类设置':'新建分类',message:values.name,confirmLabel:old?'保存':'创建'}))return projectPage({state,context});
    }
    if(event.type==='newTask'){
      const values=await ui.dialog({presentation:'compact',title:'新建任务',fields:[field('title','任务名称','',{required:true}),field('estimatedMinutes','预计分钟（可留空）')]});
      if(values)await command('task.create',{title:values.title,projectId,folderId,estimatedMinutes:values.estimatedMinutes?Number(values.estimatedMinutes):null},{title:'新建任务',message:values.title+' · '+locationLabel(p,folders,folderId),confirmLabel:'创建'});
    }
    if(event.type==='importTask'){
      const tasks=(await activeTasks({any:[scopeFilter('projectId',null),{field:'projectId',op:'ne',value:projectId}]})).filter(t=>!t.parentTaskId);
      if(!tasks.length)throw Error('没有可移入的独立任务');
      const values=await ui.dialog({presentation:'compact',title:'移入已有任务',description:'移至「'+locationLabel(p,folders,folderId)+'」',fields:[field('id','任务',tasks[0].id,{type:'select',options:tasks.map(t=>option(t.id,t.title))})]});
      if(values)await command('project.moveTask',{...revision(tasks.find(t=>t.id===values.id)),projectId,folderId},{title:'移入已有任务',message:tasks.find(t=>t.id===values.id).title+' → '+locationLabel(p,folders,folderId),confirmLabel:'移入'});
    }
    if(event.type==='moveTask'){
      const t=await data.get('tasks',event.id);
      const destinations=[option(JSON.stringify([null,'']),'无项目'),
        ...[...projects.values()].flatMap(dest=>folderOptions(folders,dest.id,'项目直属').map(o=>option(JSON.stringify([dest.id,o.value]),dest.name+' / '+o.label)))];
      const values=await ui.dialog({presentation:'compact',title:'移动任务',fields:[field('task','任务',t.title,{editable:false}),field('to','移至',JSON.stringify([t.projectId,t.folderId||'']),{type:'select',options:destinations})]});
      if(values){const [dest,sub]=JSON.parse(values.to);await command('project.moveTask',{...revision(t),projectId:dest,folderId:sub||null},{title:'移动任务',message:t.title+' → '+destinations.find(o=>o.value===values.to).label,confirmLabel:'移动'});}
    }
    if(event.type==='pick'){state.picking=true;state.selected={};}
    if(event.type==='back'){delete state.picking;delete state.selected;}
    if(event.type==='select'){
      state.selected={...state.selected};
      if(state.selected[event.id])delete state.selected[event.id];else state.selected[event.id]=event.expectedUpdatedAt;
    }
    if(['queue','apply','undo'].includes(event.type)){
      const undoing=event.type==='undo';
      let input,confirmation;
      if(undoing)input=state.undo;
      else if(event.type==='queue')input={projectId:event.projectId,queued:event.queued,tasks:[{id:event.id,expectedUpdatedAt:event.expectedUpdatedAt}]};
      else input={projectId,queued:true,tasks:Object.entries(state.selected||{}).map(([id,expectedUpdatedAt])=>({id,expectedUpdatedAt}))};
      if(input?.tasks.length){
        if(undoing)confirmation={title:'撤销待安排变更',message:'恢复 '+input.tasks.length+' 项任务原先的待安排状态',confirmLabel:'撤销'};
        else if(input.queued){
          const checked=await Promise.all(input.tasks.map(({id})=>data.get('tasks',id)));
          const minutes=checked.reduce((sum,t)=>sum+(t?.estimatedMinutes||0),0);
          const listed=checked.filter(Boolean).slice(0,40).map(t=>({
            title:t.title.slice(0,300),subtitle:(folderPath(folders.get(t.folderId),folders)||'项目直属').slice(0,540)
              +' · '+(t.estimatedMinutes?t.estimatedMinutes+' 分钟':'未估时'),
          }));
          const unknown=checked.filter(t=>!t?.estimatedMinutes).length;
          const duration=(unknown?'已知 ':'')+minutes+' 分钟'+(unknown?'，'+unknown+' 项未估时':'');
          const summary=(projects.get(input.projectId)?.name||'项目')+' · '+input.tasks.length+' 项 · '+duration;
          confirmation={title:'加入待安排',message:summary+(input.tasks.length>40?'（列出前 40 项）':''),
            items:listed,confirmLabel:'确认加入'};
        }else confirmation={title:'移出待安排',message:'保留任务与预计耗时',confirmLabel:'确认移出'};
        const result=await command(undoing?'project.pick.undo':'project.pick',input,confirmation);
        if(result){
          if(undoing)delete state.undo;
          else if(result.tasks.length)state.undo={projectId:input.projectId,tasks:result.tasks,undoId:result.undoId};
          state.undoMessage=undoing?'已撤销':(input.queued?'已加入待安排 ':'已移出待安排 ')+result.tasks.length+' 项';
          delete state.picking;delete state.selected;
          if(undoing)await ui.notify({message:state.undoMessage,kind:'success'});
        }
      }
    }
    if(event.type==='finish'){
      const next=p.completedOn?null:today;
      if(await command('project.edit',{...revision(p),completedOn:next},{
        title:next?'标记为完结':'重新开启项目',message:p.name,confirmLabel:next?'确认完结':'重新开启'
      }))return projectPage({state,context});
    }
    if(event.type==='ai'){
      try{await ui.navigate('app.ai.projectDraft',{projectId,projectName:p.name,folderId,projectPath:folderPath(folders.get(p.folderId),folders)||'未分类'});}
      catch(_){throw Error('请先安装并启用支持项目拆解的 AI 助手');}
    }
    if(event.type==='task')await ui.navigate('app.tasks.projectTask',{taskId:event.id});
    if(event.type==='completeTask'){
      const t=await data.get('tasks',context.taskId),taskZone=t.plannedTimezone||zone;
      const result=await command('task.setCompleted',{...revision(t),completed:!t.completedAt,...(!t.completedAt?{actualCompletedOn:await clock.today(taskZone),completedTimezone:taskZone}:{})},{
        title:t.completedAt?'重新打开任务':'标记已完成',message:t.title,confirmLabel:t.completedAt?'重新打开':'确认完成'
      });
      if(result)state.completionUndo=revision(result);
    }
    if(event.type==='undoCompletion'&&state.completionUndo){
      if(await command('task.undoCompletion',state.completionUndo,{title:'撤销完成操作',
        message:'恢复任务先前的完成状态',confirmLabel:'撤销'}))delete state.completionUndo;
    }
    if(event.type==='unschedule'){const task=await data.get('tasks',event.id);await command('task.updateFields',{id:event.id,expectedUpdatedAt:event.expectedUpdatedAt,changes:{plannedDate:null,plannedStartAt:null,plannedEndAt:null,plannedTimezone:null}},{title:'取消时段，移回待安排',message:task.title+' · 保留任务和预计耗时',confirmLabel:'确认移回'});}
    delete state.error;
  }catch(e){state.error=e.message||String(e);}
  const children=[],actions=[];
  const open=(projectId,folderId,unfiled=false)=>({type:'open',location:{projectId,folderId,unfiled}});
  const queueAction=t=>action(t.projectQueued?'移出待安排':'加入待安排',t.projectQueued?'calendarRemove':'calendarAdd',{type:'queue',...revision(t),projectId:t.projectId,queued:!t.projectQueued});
  const taskActions=t=>[...(!t.completedAt&&!t.plannedStartAt&&t.projectId?[queueAction(t)]:[]),pinAction('task',t.id)];
  let title=p?.name||'项目',footer;
  if(context.taskId){
    const t=await data.get('tasks',context.taskId);
    if(!t||t.deletedAt||t.archivedAt)return {state,tree:{type:'notice',text:'任务已不可用'}};
    const project=projects.get(t.projectId);
    title='任务详情';
    children.push(taskSummary(t,taskLabel(t,await timeLabels([t]),today)+(t.plannedStartAt&&!t.completedAt&&t.estimatedMinutes?' · '+t.estimatedMinutes+' 分钟':'')));
    if(t.notes)children.push({type:'text',text:t.notes});
    if(project)children.push(row('所属项目 · '+project.name,locationLabel(project,folders,t.folderId),{type:'open',location:{projectId:project.id,folderId:t.folderId,focusTaskId:t.id}},'briefcase'));
    children.push(heading('操作'));
    for(const a of taskActions(t))children.push(row(a.label,'',a.event,a.icon),divider);
    children.push(row('移动任务','选择目标项目和分类',{type:'moveTask',id:t.id},'folder'));
    if(t.plannedStartAt&&!t.completedAt&&!t.locked)children.push(divider,row('取消时段，移回待安排','保留任务和预计耗时',{type:'unschedule',...revision(t)},'calendarRemove'));
    footer=footerBar(
      button(t.completedAt?'重新打开任务':'标记已完成',{type:'completeTask'},'filled'),
      ...(state.completionUndo?.expectedUpdatedAt===t.updatedAt?[button('撤销',{type:'undoCompletion'},'text')]:[]),
    );
  }else{
    const following=root&&state.tab==='follow',advancing=root&&state.tab==='activity',unfiled=context.unfiled;
    const summaries=advancing||p?.completedOn?await activitySummaries(advancing?projects:new Map([[p.id,p]])):new Map();
    const visibleProjects=following?[...projects.values()].filter(proj=>pins.includes('project:'+proj.id)):p?[p]:[...projects.values()].filter(proj=>(proj.folderId||null)===folderId&&(folder||unfiled));
    const visibleIds=visibleProjects.map(proj=>proj.id);
    const projectTasks=new Map(),extraCounts=new Map(),tasks=[];
    if(advancing){
      const filter={all:[{field:'projectId',op:'notNull'},scopeFilter('completedAt',null)]};
      for await(const page of activeTaskPages(filter))for(const task of page){
        const project=projects.get(task.projectId);
        if(project&&isNewPending(task,project,summaries.get(project.id)?.legacyJoins))
          extraCounts.set(project.id,(extraCounts.get(project.id)||0)+1);
      }
    }else{
      if(visibleIds.length)tasks.push(...await activeTasks({field:'projectId',op:'in',value:visibleIds}));
      const pinnedIds=following?pins.filter(k=>k.startsWith('task:')).map(k=>k.slice(5)):[];
      if(pinnedIds.length){
        const loaded=new Set(tasks.map(t=>t.id));
        tasks.push(...(await activeTasks({field:'id',op:'in',value:pinnedIds})).filter(t=>!loaded.has(t.id)));
      }
      for(const t of tasks){
        if(!projectTasks.has(t.projectId))projectTasks.set(t.projectId,[]);
        projectTasks.get(t.projectId).push(t);
      }
    }
    const times=await timeLabels(tasks);
    const projectRow=proj=>{
      const associated=projectTasks.get(proj.id)||[];
      const progress=projectProgress(proj,associated,times,today);
      const status=proj.completedOn?'完结 · '+dateLabel(proj.completedOn)+' 完结':
        ['未完结','完成 '+progress.done+'/'+associated.length,proj.targetDate?'目标 '+dateLabel(proj.targetDate):''].filter(Boolean).join(' · ');
      return wrap('project:'+proj.id,{...row(proj.name,status,open(proj.id,null),'briefcase'),
        trailing:proj.importance===2?importanceNames[2]:false,trailingAccent:proj.importance===2},
        projectActions(proj),proj.updatedAt);
    };
    const taskRow=(t,showPath=false)=>wrap('task:'+t.id,{...row(t.title,[
      following?projects.get(t.projectId)?.name:null,
      showPath?folderPath(folders.get(t.folderId),folders):null,
      taskLabel(t,times,today),
    ].filter(Boolean).join(' · '),{type:'task',id:t.id},t.completedAt?'check':t.plannedStartAt?'calendar':'clipboard'),
      selected:context.focusTaskId===t.id},taskActions(t),t.updatedAt);
    if(state.picking&&p){
      title='挑任务';
      children.push(text(locationLabel(p,folders,null)));
      const candidates=tasks.filter(pickable),groups=new Map();
      groups.set('',[]);
      for(const t of candidates){const key=t.folderId||'';if(!groups.has(key))groups.set(key,[]);groups.get(key).push(t);}
      let minutes=0,count=0,unknown=0;
      const selected={};
      for(const [group,items] of groups){
        if(!items.length)continue;
        children.push(heading(folderPath(folders.get(group),folders)||'项目直属'));
        for(const t of items){
          const checked=!!state.selected?.[t.id];
          if(checked){selected[t.id]=state.selected[t.id];count++;if(t.estimatedMinutes)minutes+=t.estimatedMinutes;else unknown++;}
          children.push({type:'checkbox',key:'pick:'+t.id,text:t.title,detail:t.estimatedMinutes?t.estimatedMinutes+' 分钟':'未估时',value:checked,event:{type:'select',...revision(t)}});
        }
      }
      state.selected=selected;
      if(!candidates.length)children.push({type:'text',text:'没有可加入待安排的任务'});
      footer=footerBar({type:'row',layout:'flex',children:[
        {...text('已选 '+count+' 项','heading'),weight:'semibold',flex:1},
        {...text((unknown?'已知 ':'共 ')+minutes+' 分钟'+(unknown?'，'+unknown+' 项未估时':'')),align:'end',flex:2},
      ]},
        {...button('加入待安排',{type:'apply'},'filled'),disabled:!count});
    }else if(advancing){
      const rows=await activityRows(projects,extraCounts,summaries,order,zone,today,folders,open,projectActions);
      children.push({type:'row',layout:'flex',children:[
        {...text(rows.length+' 个项目','heading'),weight:'semibold',flex:1},
        {type:'menuButton',text:sortLabels[order],icon:'history',variant:'tonal',items:Object.entries(sortLabels).map(([value,label])=>({
          label,selected:order===value,event:{type:'sort',order:value},
        }))},
      ]});
      rows.forEach((item,i)=>{if(i)children.push(divider);children.push(item);});
      if(!rows.length)children.push({type:'emptyState',icon:'briefcase',iconSurface:true,title:'暂无待推进项目',
        text:'未完结的项目会出现在这里。完结项目有新增待办时也会出现。'});
    }else if(following){
      const pinnedTasks=tasks.filter(t=>pins.includes('task:'+t.id));
      if(visibleProjects.length)children.push(heading('项目',visibleProjects.length+' 个'));
      for(const proj of visibleProjects)children.push(projectRow(proj),divider);
      if(pinnedTasks.length)children.push(heading('任务',pinnedTasks.length+' 项'));
      for(const t of pinnedTasks)children.push(taskRow(t),divider);
      if(!children.length)children.push({type:'emptyState',title:'暂无跟进项',text:'长按项目或任务，选择「固定到跟进」。',icon:'pin',iconSurface:true});
    }else{
      title=folder?.name||(unfiled?'未分类':title);
      if(p){
        const projectPath=folderPath(folders.get(p.folderId),folders)||'未分类';
        if(folder)children.push(row('所属项目 · '+p.name,projectPath,open(p.id,null),'briefcase'),divider);
        else {
          const progress=projectProgress(p,tasks,times,today);
          const extras=tasks.filter(t=>isNewPending(t,p,summaries.get(p.id)?.legacyJoins));
          children.push(text(projectPath),summaryCard(p,progress,tasks.length,extras.length,importanceNames[p.importance??1],dateLabel));
          if(extras.length){
            children.push(heading('完结后新增待办'));
            for(const t of extras)children.push(taskRow(t,true),divider);
            const completed=tasks.filter(t=>t.completedAt);
            if(completed.length)children.push(heading('已完成'));
            for(const t of completed)children.push(taskRow(t,true),divider);
          }
        }
        actions.push({...action('挑任务','list',{type:'pick'}),presentation:'inline',variant:'tonal',overflowOnly:true},action('新建任务','add',{type:'newTask'}));
      }else if(folder)children.push(text('项目 / '+(folderPath(folders.get(folder.parentId),folders)||'目录')));
      if(!unfiled)actions.push(action('新建分类','folder',{type:'saveFolder'}));
      if(!p)actions.push(action('新建项目','add',{type:'newProject'}));
      if(p)actions.push(action('移入已有任务','importExport',{type:'importTask'}),action('用 AI 拆解','ai',{type:'ai'}),
        pinAction('project',p.id),{...action('项目设置','sliders',{type:'editProject'}),separatorBefore:true},action(p.completedOn?'重新开启项目':'标记为完结','check',{type:'finish'}));
      const childFolders=[...folders.values()].filter(f=>!unfiled&&(f.projectId||null)===projectId&&(f.parentId||null)===folderId);
      if(childFolders.length)children.push(heading('分类',root?childFolders.length+' 个分类':null));
      for(const f of childFolders){
        const subFolders=[...folders.values()].filter(child=>child.parentId===f.id).length;
        const total=p?tasks.filter(t=>t.folderId===f.id).length:[...projects.values()].filter(proj=>proj.folderId===f.id).length;
        const subtitle=[subFolders?subFolders+' 个分类':'',total+' '+(p?'项任务':'个项目')].filter(Boolean).join(' · ');
        children.push(wrap('folder:'+f.id,row(f.name,subtitle,open(projectId,f.id),'folder'),
          [action('分类设置','sliders',{type:'saveFolder',id:f.id})],f.updatedAt),divider);
      }
      if(root){
        const count=[...projects.values()].filter(proj=>!proj.folderId).length;
        if(count)children.push(row('未分类',count+' 个项目',open(null,null,true),'inbox'),divider);
      }
      if(!p){
        if(visibleProjects.length&&!unfiled)children.push(heading('项目'));
        for(const proj of visibleProjects)children.push(projectRow(proj),divider);
      }else{
        const extras=!folder&&tasks.some(t=>isNewPending(t,p,summaries.get(p.id)?.legacyJoins));
        const direct=tasks.filter(t=>(t.folderId||null)===folderId&&
          (!extras||(!isNewPending(t,p,summaries.get(p.id)?.legacyJoins)&&!t.completedAt)));
        // The board opens a folder route with its referenced row in view.
        direct.sort((a,b)=>Number(b.id===context.focusTaskId)-Number(a.id===context.focusTaskId));
        if(direct.length)children.push(heading(folder?'任务':'项目直属'));
        for(const t of direct)children.push(taskRow(t),divider);
      }
      if(root&&!children.length)children.push(button('新建分类',{type:'saveFolder'}));
      if(p&&!tasks.length)children.push(button('新建任务',{type:'newTask'}));
    }
  }
  if(state.error)children.unshift({type:'notice',text:state.error});
  if(state.undo?.tasks?.length&&!state.picking&&!footer)footer=footerBar({type:'row',layout:'flex',children:[
    {type:'icon',icon:'check',tone:'success',size:18},{...text(state.undoMessage||'已更新待安排','body'),flex:1},button('撤销',{type:'undo'},'text'),
  ]});
  const tab=state.tab||'directory';
  const scrollKey=root?'tab:'+tab:state.picking?'pick:'+projectId:context.taskId||folderId||projectId||'unfiled';
  return {state,header:{title,compact:!root,...(root?{titleStyle:'large'}:{}),actions,...(state.picking?{backEvent:{type:'back'}}:{})},
    tree:{type:'column',compact:true,spacing:0,trailingSpacing:false,scrollKey,
      ...(root?{header:tabHeader(tab),pageTransition:{direction:state.tabDirection||'next',duration:220}}:
        p?{pageTransition:{direction:state.picking?'forward':'back',duration:260}}:{}),
      children:groupedRows(children),...(footer?{footer}:{})}};
}
