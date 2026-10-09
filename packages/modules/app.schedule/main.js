import {data,services,ui,clock,ids,files} from '@xudian/sdk';
import {civil,date,dayMs,addDays,teachingWeek,weekday,normalizeWeeks,validateTimetable,validateMeeting,validateChange,validOriginal,occurrences,overlaps} from './calendar.js';
import {draftFromBackup,importPlan} from './import.js';
export {importPlan};
let selectedTimetableId=null,selectionRevision=0,displayRequest=0;
function selectTimetable(id) { if(selectedTimetableId!==id) { selectedTimetableId=id; selectionRevision++; } }
const ref=id=>({moduleId:'app.schedule',serviceId:id,majorVersion:1});
import {defaultPeriods,periodDraft,semesterDraft,resetPeriodDraft,resetSemesterDraft,displayDraft,resetDisplayDraft,scheduleRowHeight,scheduleShowWeekends,displayDirty,periodError,appendPeriods,timeMinutes,timeString,listTile,group,importSummary} from './view_helpers.js';
async function snapshot(timetableId) {
  const t=await data.get('timetables',timetableId); if(!t) throw new Error('课表不存在');
  const filter={field:'timetableId',op:'eq',value:timetableId};
  return {t,courses:await data.query('courses',{filter}),meetings:await data.query('meetings',{filter}),changes:await data.query('occurrenceChanges',{filter})};
}
export async function queryTimetables() {
  return {timetables:await data.query('timetables')};
}
export async function queryWeek({timetableId,teachingWeek:week}) {
  const {t,courses,meetings,changes}=await snapshot(timetableId);
  if(!Number.isInteger(week)||week<1||week>t.totalWeeks) throw new Error('教学周超出范围');
  const monday=addDays(t.firstMonday,(week-1)*7),start=t.displayWeekStart===7?addDays(monday,-1):monday;
  const columns=Array.from({length:7},(_,i)=>({id:addDays(start,i),label:`${['','周一','周二','周三','周四','周五','周六','周日'][weekday(addDays(start,i))]}\n${addDays(start,i).slice(5)}`}));
  const items=occurrences(t,courses,meetings,changes,start,addDays(start,7));
  return {timetable:t,teachingWeek:week,columns,rows:t.periods.map(p=>({id:String(p.number),label:`${p.number}\n${p.start}–${p.end}`})),items,
    blocks:items.map(x=>({id:x.occurrenceId,column:x.date,start:x.startPeriod-1,end:x.endPeriod,title:x.title,
      subtitle:[x.location,x.teacher].filter(Boolean).join('\n'),color:x.color,event:{type:'occurrence',item:x}})),warnings:overlaps(items)};
}
export async function queryToday({timetableId}) {
  const {t,courses,meetings,changes}=await snapshot(timetableId),today=await clock.today(t.timezone);
  return {date:today,teachingWeek:teachingWeek(t,today),items:occurrences(t,courses,meetings,changes,today,addDays(today,1))};
}
function normalized(value) { if(Array.isArray(value))return value.map(normalized);if(value&&typeof value==='object')return Object.fromEntries(Object.keys(value).sort().map(key=>[key,normalized(value[key])]));return value; }
export async function saveTimetable({timetable,expectedTimetable}) {
  const value={...timetable,id:timetable.id || await ids.new(),datasetId:timetable.datasetId || await ids.new()};
  validateTimetable(value); await clock.today(value.timezone);
  const current=await data.get('timetables',value.id);
  if(expectedTimetable && JSON.stringify(normalized(current))!==JSON.stringify(normalized(expectedTimetable))) throw new Error('课表配置已发生变化，请重新载入后编辑');
  if(current) {
    const {courses,meetings,changes}=await snapshot(value.id);
    for(const m of meetings) validateMeeting(m,value,courses);
    for(const c of changes) validateChange(c,value,meetings,courses);
  }
  return {writes:[{collection:'timetables',id:value.id,value}],events:[{type:'schedule.updated',timetableId:value.id}],result:{id:value.id}};
}
export async function saveCourse({course,meeting,orphanPolicy}) {
  const {t,courses,meetings,changes}=await snapshot(course.timetableId),writes=[];
  const value={...course,id:course.id || await ids.new()};
  if(!value.name?.trim()||value.name.length>120) throw new Error('请输入课程名称（最多120字）');
  value.name=value.name.trim(); writes.push({collection:'courses',id:value.id,value});
  if(meeting) {
    const m=validateMeeting({...meeting,id:meeting.id || await ids.new(),courseId:value.id,timetableId:t.id},t,[...courses.filter(c=>c.id!==value.id),value]);
    const orphaned=changes.filter(c=>c.kind!=='extra'&&c.meetingId===m.id&&!validOriginal(m,t,c.originalDate));
    if(orphaned.length&&!['discard','extra'].includes(orphanPolicy)) throw new Error('安排变化使已有调课失去原实例，请选择撤销调课或保留为临时课');
    for(const c of orphaned) writes.push({collection:'occurrenceChanges',id:c.id,value:orphanPolicy==='discard'?null:
      c.kind==='cancel'?null:{...c,kind:'extra',meetingId:null,courseId:value.id}});
    writes.push({collection:'meetings',id:m.id,value:m});
  }
  return {writes,events:[{type:'schedule.updated',timetableId:t.id}],result:{id:value.id}};
}
export async function saveChange({change}) {
  const {t,courses,meetings,changes}=await snapshot(change.timetableId);
  const value={...change,id:change.id || await ids.new()}; validateChange(value,t,meetings,courses);
  const writes=[];
  const current=changes.find(c=>c.kind!=='extra'&&value.kind!=='extra'&&c.meetingId===value.meetingId&&c.originalDate===value.originalDate);
  if(current&&current.id!==value.id) writes.push({collection:'occurrenceChanges',id:current.id,value:null});
  writes.push({collection:'occurrenceChanges',id:value.id,value});
  return {writes,events:[{type:'schedule.updated',timetableId:t.id}],result:{id:value.id}};
}
export async function deleteEntity({collection,id}) {
  if(!['courses','meetings','occurrenceChanges','timetables'].includes(collection)) throw new Error('不可删除该集合');
  const value=await data.get(collection,id); if(!value) throw new Error('内容不存在');
  const tid=collection==='timetables'?id:value.timetableId,{courses,meetings,changes}=await snapshot(tid);
  const removed=new Map([[collection,new Set([id])]]);
  if(collection==='timetables') { removed.set('courses',new Set(courses.map(x=>x.id))); removed.set('meetings',new Set(meetings.map(x=>x.id))); removed.set('occurrenceChanges',new Set(changes.map(x=>x.id))); }
  if(collection==='courses') removed.set('meetings',new Set(meetings.filter(x=>x.courseId===id).map(x=>x.id)));
  if(removed.has('meetings')) removed.set('occurrenceChanges',new Set(changes.filter(x=>removed.get('meetings').has(x.meetingId)||collection==='courses'&&x.courseId===id).map(x=>x.id)));
  const writes=[];
  for(const [c,list] of removed) for(const id of list) writes.push({collection:c,id,value:null});
  for(const s of await data.query('importSources',{filter:{field:'timetableId',op:'eq',value:tid}})) {
    if(collection==='timetables') { writes.push({collection:'importSources',id:s.id,value:null}); continue; }
    const mappings={...s.mappings};
    for(const [key,m] of Object.entries(mappings)) if(removed.get(key.split(':')[0])?.has(m.localId)) mappings[key]={...m,deleted:true};
    writes.push({collection:'importSources',id:s.id,value:{...s,mappings}});
  }
  return {writes,events:[{type:'schedule.updated',timetableId:tid}],result:{id}};
}
export async function exportBackup({timetableId}) {
  const {t,courses,meetings,changes}=await snapshot(timetableId);
  return {backupFormat:1,datasetId:t.datasetId,timetable:t,courses,meetings,occurrenceChanges:changes};
}
async function command(id,input) {
  const plan=await services.prepare(ref(id),input);
  if(plan.result?.blocked) return plan;
  if(await ui.review(plan.planId)) return {result:await services.commit(plan.planId)};
  return null;
}
const button=(text,event)=>({type:'button',text,event});
const text=value=>({type:'text',text:value});
const field=(key,label,value='',type='text',options)=>({key,label,value,type,...(options?{options}: {})});
function periodsText(periods) { return periods.map(p=>`${p.start}-${p.end}`).join('\n'); }
function parsePeriods(text) { return text.split(/\n|,/).filter(x=>x.trim()).map((line,i)=>{ const [start,end]=line.trim().split('-'); return {number:i+1,start,end}; }); }
function pageId(value) { return value.startsWith('app.')?value:'app.schedule.'+value; }
async function currentOccurrence(t,reference) {
  const {courses,meetings,changes}=await snapshot(t.id);
  const change=changes.find(c=>c.kind==='extra'?c.id===reference.occurrenceId:c.meetingId===reference.meetingId&&c.originalDate===reference.originalDate);
  const meeting=meetings.find(m=>m.id===reference.meetingId);
  if(change?.kind==='cancel') return {cancelled:true,change,meeting,course:courses.find(c=>c.id===meeting?.courseId)};
  const day=change?.date||(meeting?reference.originalDate:reference.date)||reference.originalDate;
  if(!day)return null;
  const item=occurrences(t,courses,meetings,changes,day,addDays(day,1)).find(x=>x.occurrenceId===reference.occurrenceId || x.meetingId===reference.meetingId&&x.originalDate===reference.originalDate);
  return item?{item,change,meeting,course:courses.find(c=>c.id===item.courseId)}:null;
}
function occurrenceReference(item) { return {occurrenceId:item.occurrenceId,meetingId:item.meetingId||null,originalDate:item.originalDate,date:item.date}; }
export async function render({state={},context={},event,formValues={}}) {
  state={...state};
  if(state.selectionRevision!==undefined && state.selectionRevision<selectionRevision) { state.timetableId=selectedTimetableId; delete state.week; }
  if(event?.type==='select') { state.timetableId=event.id; delete state.week; selectTimetable(event.id); }
  if(event?.type==='week') state.week=event.week;
  let timetables=await data.query('timetables');
  let t=timetables.find(x=>x.id===(state.timetableId||context.timetableId||selectedTimetableId)) || timetables[0];
  const page=context.pageId||'app.schedule.home';
  const gridPage=page==='app.schedule.home'||page==='app.schedule.display';
  if(page==='app.schedule.display' && state.displayControls===undefined)state.displayControls=true;
  if(page==='app.schedule.display' && state.displayRequest!==context.displayRequest) {state.displayControls=true;state.displayRequest=context.displayRequest;}
  if(gridPage && event?.type==='openDisplay')state.displayControls=true;
  if(gridPage && event?.type==='closeDisplay') {state.displayControls=false;delete state.notice;}
  if(page==='app.schedule.home') delete state.tab;
  if(t) { state.timetableId=t.id; if(!selectedTimetableId) selectedTimetableId=t.id; }
  if(t && state.weekendTimetableId!==t.id) {delete state.revealWeekends;state.weekendTimetableId=t.id;}
  if(event?.type==='weekend') state.revealWeekends=true;
  if(context.week && !state.week && state.selectionRevision===undefined) state.week=context.week;
  if(event?.type==='navigate') await ui.navigate(pageId(event.page),{timetableId:t?.id,week:state.week,...(event.page==='display'?{displayRequest:++displayRequest}:{})});
  if(event?.type==='currentWeek' && t) state.week=Math.max(1,Math.min(t.totalWeeks,teachingWeek(t,await clock.today(t.timezone))));
  if(event?.type==='occurrence' && t) await ui.panel('app.schedule.occurrence',{timetableId:t.id,...occurrenceReference(event.item)},{adaptive:true});
  if(event?.type==='singleChange' && t) {
    const current=await currentOccurrence(t,context);
    if(current?.item) event={type:'editOccurrence',item:current.item,change:current.change};
    else state.notice='这次课程已取消或不存在，请刷新后查看';
  }
  if(event?.type==='editRecurrence' && t) {
    const current=await currentOccurrence(t,context);
    if(current?.meeting&&current.course) event={type:'course',course:current.course,meeting:current.meeting};
    else state.notice='周期安排已不存在';
  }
  if(event?.type==='chooseTimetable') {
    const values=await ui.dialog({title:'切换课表',fields:[field('timetableId','课表',t?.id,'select',timetables.map(x=>({value:x.id,label:x.name})))]});
    if(values) { state.timetableId=values.timetableId; delete state.week;delete state.importPlan;delete state.importSummary;delete state.importInput;delete state.importError; selectTimetable(values.timetableId); t=timetables.find(x=>x.id===values.timetableId); }
  }
  if(event?.type==='chooseWeek' && t) {
    const today=await clock.today(t.timezone),current=Math.max(1,Math.min(t.totalWeeks,teachingWeek(t,today)));
    const values=await ui.dialog({title:'选择教学周',fields:[field('week','教学周',String(state.week||current),'select',Array.from({length:t.totalWeeks},(_,i)=>({value:String(i+1),label:`第 ${i+1} 周${i+1===current?' · 本周':''}`})))]});
    if(values) state.week=Number(values.week);
  }
  if(t && page==='app.schedule.semester') {
    const draft=semesterDraft(t);
    if(event?.type==='semesterField') {draft.values[event.field]=String(event.value);draft.error=null;}
    if(event?.type==='resetSemester') {resetSemesterDraft(t);delete state.notice;}
    if(event?.type==='saveSemester') {
      try {
        for(const key of Object.keys(draft.values)) if(formValues[`semester.${t.id}.${key}`]!==undefined) draft.values[key]=String(formValues[`semester.${t.id}.${key}`]);
        const baseline={name:t.name,firstMonday:t.firstMonday,totalWeeks:String(t.totalWeeks),timezone:t.timezone,displayWeekStart:String(t.displayWeekStart)};
        if(draft.baseline!==JSON.stringify(baseline))throw new Error('学期设置已在其他页面修改。草稿已保留，请重新载入后编辑。');
        const value={...t,...draft.values,totalWeeks:Number(draft.values.totalWeeks),displayWeekStart:Number(draft.values.displayWeekStart)};
        validateTimetable(value);await clock.today(value.timezone);
        const saved=await command('schedule.timetable.save',{timetable:value,expectedTimetable:t});
        if(saved) {resetSemesterDraft(await data.get('timetables',t.id));state.notice='学期设置已保存';}
      } catch(error) {draft.error=error.message;}
    }
  }
  if(t && gridPage) {
    const draft=displayDraft(t);
    if(event?.type==='displayWeekends' && typeof event.value==='boolean') {
      draft.showWeekends=event.value;draft.error=null;delete state.notice;delete state.revealWeekends;
    }
    if(event?.type==='displayHeight') {
      const height=Number(event.value),rowHeight=(height-48)/t.periods.length;
      if(Number.isFinite(rowHeight)&&rowHeight>=48&&rowHeight<=160) {draft.rowHeight=rowHeight;draft.error=null;delete state.notice;}
    }
    if(event?.type==='stepDisplay' && [1,-1].includes(event.delta)) {
      const count=t.periods.length,height=Math.round(48+count*draft.rowHeight)+event.delta;
      draft.rowHeight=(Math.max(48+count*48,Math.min(48+count*160,height))-48)/count;draft.error=null;delete state.notice;
    }
    if(event?.type==='defaultDisplay') {draft.rowHeight=72;draft.error=null;delete state.notice;}
    if(event?.type==='resetDisplay') {resetDisplayDraft(t);delete state.notice;delete state.revealWeekends;}
    if(event?.type==='saveDisplay') {
      try {
        if(draft.baseline!==scheduleRowHeight(t)||draft.baselineShowWeekends!==scheduleShowWeekends(t))throw new Error('显示设置已在其他页面修改。草稿已保留，请重新载入后编辑。');
        const saved=await command('schedule.timetable.save',{timetable:{...t,rowHeight:draft.rowHeight,showWeekends:draft.showWeekends},expectedTimetable:t});
        if(saved) {resetDisplayDraft(await data.get('timetables',t.id));delete state.revealWeekends;state.notice='显示设置已保存';}
      } catch(error) {draft.error=error.message;}
    }
  }
  if(t && page==='app.schedule.periods') {
    const draft=periodDraft(t);
    if(event?.type==='periodTime') {
      const row=draft.periods.find(p=>p.number===event.number);
      if(row && ['start','end'].includes(event.part)) row[event.part]=String(event.value);
      draft.error=null;delete state.notice;
    }
    if(event?.type==='addPeriod') {
      try {
        if(draft.periods.length>=30)throw new Error('最多配置30个节次');
        const start=draft.periods.length?timeMinutes(draft.periods.at(-1).end)+5:8*60;
        draft.periods.push({number:draft.periods.length+1,start:timeString(start),end:timeString(start+45)});draft.error=null;
      } catch(error) {draft.error=error.message;}
    }
    if(event?.type==='removePeriod') {
      const filter={field:'timetableId',op:'eq',value:t.id},meetings=await data.query('meetings',{filter}),changes=await data.query('occurrenceChanges',{filter});
      if(event.number!==draft.periods.length)draft.error='只能删除最后一个节次，请先删除末尾未使用的节次';
      else if(meetings.some(m=>m.endPeriod>=event.number)||changes.some(c=>c.kind!=='cancel'&&c.endPeriod>=event.number)) draft.error=`第 ${event.number} 节或其后的节次已被课程安排或调课引用，请先调整课程。`;
      else if(draft.periods.length<=1) draft.error='至少保留一个节次';
      else {draft.periods=draft.periods.filter(p=>p.number!==event.number).map((p,i)=>({...p,number:i+1}));draft.error=null;}
    }
    if(event?.type==='resetPeriods') {resetPeriodDraft(t);delete state.notice;}
    if(event?.type==='savePeriods') {
      try {
        if(draft.baseline!==JSON.stringify(t.periods))throw new Error('作息已在其他页面修改。草稿已保留，请重新载入后编辑。');
        const error=await periodError(t,draft.periods);if(error)throw new Error(error);
        const saved=await command('schedule.timetable.save',{timetable:{...t,periods:draft.periods},expectedTimetable:t});
        if(saved) {resetPeriodDraft(await data.get('timetables',t.id));state.notice='作息设置已保存';}
      } catch(error) {draft.error=error.message;}
    }
    if(event?.type==='templatePeriods'||event?.type==='appendPeriods') {
      try {
        const periods=event.type==='templatePeriods'?defaultPeriods.map(p=>({...p})):appendPeriods(t.periods);
        if(JSON.stringify(periods)===JSON.stringify(t.periods)) {state.notice='当前作息已包含12个或更多节次';}
        else {
          const error=await periodError(t,periods);if(error)throw new Error(error);
          const saved=await command('schedule.timetable.save',{timetable:{...t,periods},expectedTimetable:t});
          if(saved) {resetPeriodDraft(await data.get('timetables',t.id));state.notice=event.type==='templatePeriods'?'已应用12节作息模板':'已保留现有作息并补足至12节';}
        }
      } catch(error) {draft.error=error.message;}
    }
  }
  if(event?.type==='newTimetable'||event?.type==='settings') {
    const original=event.type==='settings'?t:null;
    const today=await clock.today(original?.timezone || 'Asia/Shanghai');
    const values=await ui.dialog({title:original?'课表与作息':'新建课表',fields:[
      field('name','课表名称',original?.name||'大学课表'),field('firstMonday','第一周周一',original?.firstMonday||addDays(today,1-weekday(today))),
      field('totalWeeks','总教学周数',String(original?.totalWeeks||20),'number'),field('timezone','IANA 时区',original?.timezone||'Asia/Shanghai'),
      field('displayWeekStart','显示起始',String(original?.displayWeekStart||1),'select',[{value:'1',label:'周一'},{value:'7',label:'周日'}]),
      field('periods','每行一个节次 HH:mm-HH:mm',periodsText(original?.periods||defaultPeriods),'multiline')]});
    if(values) {
      const saved=await command('schedule.timetable.save',{timetable:{...original,...values,totalWeeks:Number(values.totalWeeks),displayWeekStart:Number(values.displayWeekStart),periods:parsePeriods(values.periods)}});
      if(saved) { state.timetableId=saved.result.id; selectTimetable(saved.result.id); }
    }
  }
  if(event?.type==='course') {
    if(!t) throw new Error('先创建课表');
    const current=event.course?.id?await data.get('courses',event.course.id):event.course,meeting=event.meeting?.id?await data.get('meetings',event.meeting.id):event.meeting;
    const values=await ui.dialog({title:current?'编辑课程与安排':'添加课程',fields:[field('name','课程名称',current?.name),field('code','课程代码',current?.code),field('color','颜色 #RRGGBB',current?.color||'#486DA4'),field('notes','备注',current?.notes,'multiline'),
      field('weekday','星期（1–7）',String(meeting?.weekday||1),'number'),field('startPeriod','开始节次',String(meeting?.startPeriod||1),'number'),field('endPeriod','结束节次',String(meeting?.endPeriod||2),'number'),
      field('weeks','周次（例如1-16单、1,4,8-10）',meeting?.weeks.join(',')||`1-${t.totalWeeks}`),field('teacher','教师',meeting?.teacher),field('location','地点',meeting?.location),
      field('orphanPolicy','失效调课处理','ask','select',[{value:'ask',label:'有失效调课时阻止保存'},{value:'discard',label:'撤销失效调课'},{value:'extra',label:'保留为临时课程'}])]});
    if(values) await command('schedule.course.save',{course:{...current,id:current?.id,timetableId:t.id,name:values.name,code:values.code,color:values.color,notes:values.notes},
      meeting:{...meeting,id:meeting?.id,timetableId:t.id,weekday:Number(values.weekday),startPeriod:Number(values.startPeriod),endPeriod:Number(values.endPeriod),weeks:normalizeWeeks(values.weeks,t.totalWeeks),teacher:values.teacher,location:values.location},orphanPolicy:values.orphanPolicy});
  }
  if(event?.type==='editOccurrence'||event?.type==='extra') {
    const item=event.item;
    const courses=await data.query('courses',{filter:{field:'timetableId',op:'eq',value:t.id}});
    const values=await ui.dialog({title:item?'单次调课':'临时加课',fields:[
      field('kind','操作',item?'replace':'extra','select',item?[{value:'replace',label:'移动或换地点'},{value:'cancel',label:'取消本次'}]:[{value:'extra',label:'临时加课'}]),
      field('courseId','课程',item?.courseId||courses[0]?.id,'select',courses.map(c=>({value:c.id,label:c.name}))),
      field('date','日期',item?.date||await clock.today(t.timezone)),field('startPeriod','开始节次',String(item?.startPeriod||1),'number'),field('endPeriod','结束节次',String(item?.endPeriod||2),'number'),field('location','地点',item?.location),field('teacher','教师',item?.teacher)]});
    if(values) await command('schedule.change.save',{change:{...values,id:event.change?.id,timetableId:t.id,originalDate:item?.originalDate||values.date,meetingId:item?.meetingId||null,startPeriod:Number(values.startPeriod),endPeriod:Number(values.endPeriod)}});
  }
  if(event?.type==='delete') await command('schedule.entity.delete',{collection:event.collection,id:event.id});
  if(event?.type==='export') await files.saveText(`${t.name}.json`,JSON.stringify(await exportBackup({timetableId:t.id}),null,2));
  if(event?.type==='import') {
    const raw=await files.readText();
    if(raw) {state.importDraft=draftFromBackup(JSON.parse(raw));delete state.importPlan;delete state.importSummary;delete state.importError;}
  }
  if(page==='app.schedule.home' && (context.importPlanId||context.draft) && !state.importRouted) {
    state.importRouted=true; await ui.navigate('app.schedule.imports',{...context,timetableId:t?.id});
  }
  if(page!=='app.schedule.home' && context.importPlanId && !state.adapterHandled) {
    state.adapterPlan=await services.adopt(context.importPlanId); state.adapterHandled=true;
  }
  if(event?.type==='confirmAdapter' && state.adapterPlan) {
    if(await ui.review(state.adapterPlan.planId)) {
      const result=await services.commit(state.adapterPlan.planId);
      state.timetableId=result.timetableId; selectTimetable(result.timetableId); delete state.adapterPlan;
    }
  }
  if(page!=='app.schedule.home' && context.draft&&!state.importDraft&&!state.importFinished) state.importDraft=context.draft;
  if(event?.type==='cancelImport') { delete state.importDraft;delete state.importPlan;delete state.importSummary;delete state.importInput;delete state.importError;state.importFinished=true; }
  if((event?.type==='saveImport'||event?.type==='previewImport') && state.importDraft) {
    const values=await ui.dialog({title:'导入方式',fields:[field('mode','模式',t?'merge':'new','select',[{value:'new',label:'新建课表'},{value:'merge',label:'合并当前课表'},{value:'replaceSource',label:'替换指定来源'}])]});
    if(values) {
      state.importInput={draft:state.importDraft,targetTimetableId:t?.id,mode:values.mode,choices:{}};
      const plan=await services.prepare(ref('schedule.import.prepare'),state.importInput);
      state.importPlan={planId:plan.planId,result:plan.result};state.importSummary=await importSummary(plan,state.importDraft);delete state.importError;
    }
  }
  if(event?.type==='resolveImport' && state.importPlan?.result.conflicts?.length) {
    const choices=await ui.dialog({title:'来源和本地修改冲突',fields:state.importPlan.result.conflicts.map(c=>field(c.key,`${c.field}：本地 ${JSON.stringify(c.local)} / 来源 ${JSON.stringify(c.source)}`,c.options?.[0]||'local','select',c.options?c.options.map(value=>({value,label:value==='extra'?'保留为临时课':'撤销失效调课'})):[{value:'local',label:'保留本地'},{value:'source',label:'采用来源'}]))});
    if(choices) {
      state.importInput={...state.importInput,choices};
      const plan=await services.prepare(ref('schedule.import.prepare'),state.importInput);
      state.importPlan={planId:plan.planId,result:plan.result};state.importSummary=await importSummary(plan,state.importDraft);delete state.importError;
    }
  }
  if(event?.type==='confirmImport' && state.importPlan && !state.importPlan.result.blocked) {
    try {
      if(await ui.review(state.importPlan.planId)) {
        const result=await services.commit(state.importPlan.planId);state.timetableId=result.timetableId;selectTimetable(result.timetableId);state.importFinished=true;state.notice='导入已保存';delete state.importDraft;delete state.importPlan;delete state.importSummary;delete state.importInput;
      }
    } catch(error) {state.importError='导入预览已失效或无法保存，请重新预览：'+error.message;delete state.importPlan;}
  }
  timetables=await data.query('timetables');
  t=timetables.find(x=>x.id===state.timetableId)||timetables[0];
  if(selectedTimetableId && !timetables.some(x=>x.id===selectedTimetableId)) selectTimetable(t?.id||null);
  state.selectionRevision=selectionRevision;
  const children=[];
  const go=(label,suffix,subtitle,icon='settings')=>listTile(label,subtitle,icon,{type:'navigate',page:suffix});
  if(state.notice) children.push(text(state.notice));
  if(page==='app.schedule.settings') {
    const counts=t?await snapshot(t.id):{courses:[],meetings:[],changes:[]};
    children.push(group('概览',[
      listTile(t?.name||'还没有课表',t?`${t.firstMonday} 起 · ${t.totalWeeks} 周 · ${t.timezone}`:'新建或导入课表后开始使用','calendar',t?{type:'chooseTimetable'}:{type:'navigate',page:'timetables'}),
      listTile('课程与安排',`${counts.courses.length} 门课程 · ${counts.meetings.length} 个周期安排 · ${counts.changes.length} 条调课`,'school',null,''),
      go('今日课程','today','查看今天的课程与上课时间','calendar')
    ]));
    children.push(group('课表配置',[go('学期设置','semester','名称、学期日期、周数与时区','tune'),go('作息设置','periods',t?`${t.periods.length} 个节次，按上午、下午和晚间编辑`:'设置各节次起止时间','schedule'),go('显示设置','display',t?`${scheduleShowWeekends(t)?'显示周末':'仅工作日'} · 课表总高度 ${48+t.periods.length*scheduleRowHeight(t)}`:'周末显示与课表总高度','tune'),go('课表管理','timetables',`${timetables.length} 张课表，可切换、新建或删除`,'list')]));
    children.push(group('课程与调课',[go('课程管理','courses','课程信息与周期上课安排','school'),go('调课记录','changes','取消、移动与临时加课','history')]));
    children.push(group('数据管理',[go('导入与备份','imports','JSON 备份与教务导入','importExport')]));
    return {state,tree:{type:'column',children}};
  }
  if(page==='app.schedule.imports') {
    children.push(group('数据来源',[
      listTile(t?.name||'新建课表',t?'当前导入目标；导入时可以选择新建课表':'导入 JSON 备份后创建新课表','calendar',t?{type:'chooseTimetable'}:null),
      listTile('JSON 导入','选择课表备份，预览后确认保存','importExport',{type:'import'}),
      ...(t?[listTile('JSON 导出','包含课程、安排与单次变更，不含凭据','importExport',{type:'export'})]:[])
    ]));
    if(state.importError)children.push(text(state.importError));
    if(state.adapterPlan) {
      const summary=await importSummary(state.adapterPlan,null);
      children.push(group('教务适配器导入预览',[text(`新增 ${summary.added} 项 · 修改 ${summary.updated} 项 · 删除 ${summary.deleted} 项`),text(`冲突 ${summary.conflicts?.length||0} 项 · 警告 ${summary.warnings?.length||0} 项`),...((summary.warnings||[]).map(text)),{type:'source',text:JSON.stringify(state.adapterPlan.result,null,2)},button('课表确认并保存导入',{type:'confirmAdapter'})]));
    }
    if(state.importDraft) {
      const summary=state.importSummary||await importSummary(null,state.importDraft);
      children.push(group('导入预览',[
        text(`${summary.courses} 门课程 · ${summary.meetings} 个安排 · ${summary.changes} 条单次变更`),
        text(`来源：${state.importDraft.scope} · ${state.importDraft.complete?'完整结果':'局部结果'}`),
        ...(state.importPlan?[text(`新增 ${summary.added} 项 · 修改 ${summary.updated} 项 · 删除 ${summary.deleted} 项`),text(`冲突 ${summary.conflicts.length} 项 · 警告 ${summary.warnings.length} 项`)]:[]),
        ...summary.warnings.map(w=>text('提醒：'+w)),
        ...summary.conflicts.map(c=>listTile(c.field,`本地：${JSON.stringify(c.local)}
来源：${JSON.stringify(c.source)}`,'history',null,'')),
        {type:'source',text:JSON.stringify(state.importDraft,null,2)},
        button(state.importPlan?'重新选择方式并预览':'选择方式并预览实际变更',{type:'saveImport'}),
        ...(state.importPlan?.result.conflicts?.length?[button('处理导入冲突',{type:'resolveImport'})]:[]),
        ...(state.importPlan&&!state.importPlan.result.blocked?[button('确认保存导入',{type:'confirmImport'})]:[]),
        button('取消导入',{type:'cancelImport'})
      ]));
    }
    return {state,tree:{type:'column',children}};
  }
  if(page==='app.schedule.timetables') {
    children.push(listTile('新建课表','默认使用12节作息，可在作息设置中调整','calendar',{type:'newTimetable'}));
    for(const table of timetables) children.push(group(table.name,[listTile(table.id===t?.id?'当前课表':'选择课表',`${table.firstMonday} 起 · ${table.totalWeeks} 周 · ${table.timezone}`,'calendar',{type:'select',id:table.id}),listTile('删除课表','删除前展示实际变更并确认','history',{type:'delete',collection:'timetables',id:table.id})]));
    return {state,tree:{type:'column',children}};
  }
  if(!t) {
    children.push(text('创建课表或导入 JSON 备份后开始使用'),listTile('新建课表','默认12节作息','calendar',{type:'newTimetable'}),go('导入与备份','imports','导入 JSON 备份','importExport'));
    return {state,...(page==='app.schedule.home'?{header:{title:'课表',actions:[{label:'课表设置',event:{type:'navigate',page:'settings'}}]}}:{}),tree:{type:'column',children}};
  }
  state.timetableId=t.id;
  if(page==='app.schedule.semester') {
    const draft=semesterDraft(t),labels={name:'课表名称',firstMonday:'第一教学周周一（YYYY-MM-DD）',totalWeeks:'总教学周数',timezone:'IANA 时区',displayWeekStart:'显示起始（1=周一，7=周日）'};
    for(const [key,label] of Object.entries(labels))children.push({type:'input',key:`semester.${t.id}.${key}`,text:label,value:draft.values[key],onChangeEvent:{type:'semesterField',field:key}});
    const dirty=JSON.stringify(draft.values)!==draft.baseline;
    state.semesterDraft={...draft,dirty};
    if(dirty)children.push(text('尚未保存。离开页面后草稿会保留，保存前会审核实际变更。'));
    if(draft.error)children.push(text(draft.error));
    const replaceForms=event?.type==='resetSemester'||event?.type==='chooseTimetable'?Object.fromEntries(Object.entries(draft.values).map(([key,value])=>[`semester.${t.id}.${key}`,value])):{};
    return {state,replaceForms,tree:{type:'column',children,...(dirty?{footer:{type:'row',children:[button('重新载入',{type:'resetSemester'}),button('保存学期设置',{type:'saveSemester'})]}}:{})}};
  }
  if(page==='app.schedule.periods') {
    const draft=periodDraft(t),dirty=JSON.stringify(draft.periods)!==draft.baseline,validation=await periodError(t,draft.periods);
    state.periodsDraft={...draft,dirty,error:draft.error||validation};
    const sessions=[['上午',[]],['下午',[]],['晚间',[]]];
    for(const row of draft.periods) {
      let hour=Number(row.start?.slice(0,2));if(!Number.isFinite(hour))hour=row.number<=5?8:row.number<=9?14:19;
      const target=hour<12?0:hour<18?1:2;
      sessions[target][1].push({type:'column',children:[
        text(`第 ${row.number} 节`),
        {type:'row',children:[{type:'timeInput',key:`periods.${row.number}.start`,text:'开始时间',value:row.start,event:{type:'periodTime',number:row.number,part:'start'}},{type:'timeInput',key:`periods.${row.number}.end`,text:'结束时间',value:row.end,event:{type:'periodTime',number:row.number,part:'end'}}]},
        ...(row.number===draft.periods.length?[listTile('删除末尾节次',null,'history',{type:'removePeriod',number:row.number})]:[])
      ]});
    }
    children.push(text(`${t.name} · ${draft.periods.length} 个节次`));
    for(const [label,rows] of sessions)if(rows.length)children.push(group(label,rows));
    if(dirty)children.push(text('尚未保存。离开页面后草稿会保留，保存前会审核实际变更。'));
    if(draft.error||validation)children.push(text(draft.error||validation));
    children.push(group('节次与模板',[
      listTile('添加节次','在末尾增加一个45分钟节次','schedule',{type:'addPeriod'}),
      listTile('使用12节作息模板','替换当前起止时间，经过实际变更审核后保存','schedule',{type:'templatePeriods'}),
      ...(t.periods.length<12?[listTile('补足至12节','保留现有起止时间，仅在末尾追加节次','schedule',{type:'appendPeriods'})]:[])
    ]));
    return {state,tree:{type:'column',children,...(dirty?{footer:{type:'row',children:[button('放弃草稿',{type:'resetPeriods'}),{...button('保存作息设置',{type:'savePeriods'}),disabled:!!validation}]}}:{})}};
  }
  if(page==='app.schedule.occurrence') {
    const current=await currentOccurrence(t,context);
    if(!current)children.push(text('这次课程已不存在。请返回课表刷新后查看。'));
    else {
      const {item,course,meeting,change}=current;
      children.push(group(course?.name||item?.title||'课程详情',[
        listTile('调课状态',current.cancelled?'已取消':change?.kind==='extra'?'临时加课':change?'已调整':'原计划','history',null,''),
        listTile('日期',current.cancelled?`${context.originalDate} · 已取消`:`${item.date} · 星期${['','一','二','三','四','五','六','日'][weekday(item.date)]}`,'calendar',null,''),
        ...(item?[listTile('上课时间',`第 ${item.startPeriod}–${item.endPeriod} 节 · ${t.periods[item.startPeriod-1]?.start||''}–${t.periods[item.endPeriod-1]?.end||''}`,'schedule',null,''),listTile('地点',item.location||'未填写','school',null,''),listTile('教师',item.teacher||'未填写','school',null,'')]:[]),
        ...(course?.code?[listTile('课程代码',course.code,'school',null,'')]:[]),
        ...(course?.notes?[listTile('备注',course.notes,'list',null,'')]:[]),
        ...(meeting?[listTile('周期安排',`星期${meeting.weekday} · 第 ${meeting.startPeriod}–${meeting.endPeriod} 节 · ${meeting.weeks.join(',')} 周`,'schedule',null,'')]:[]),
        ...(item&&item.date!==item.originalDate?[listTile('原上课日期',item.originalDate,'history',null,'')]:[])
      ]));
      children.push(group('操作',[
        ...(item?[listTile('单次调课','只调整本次课程的时间、地点或取消本次','history',{type:'singleChange'})]:[]),
        ...(meeting?[listTile('编辑周期安排','修改此安排的上课周次、节次和课程信息','school',{type:'editRecurrence'})]:[]),
        ...(change?[listTile('撤销本次变更','恢复周期安排中的原课程','history',{type:'delete',collection:'occurrenceChanges',id:change.id})]:[])
      ]));
    }
    return {state,tree:{type:'column',children}};
  }
  if(page==='app.schedule.courses') {
    const {courses,meetings}=await snapshot(t.id);
    children.push(listTile('添加课程','填写课程信息与上课安排','school',{type:'course'}));
    if(!courses.length)children.push(text('还没有课程，添加课程后配置上课安排。'));
    for(const course of courses) {
      const arrangements=meetings.filter(m=>m.courseId===course.id);
      children.push(group(course.name,[text([course.code,course.notes].filter(Boolean).join(' · ')),...arrangements.map(m=>group(`星期${m.weekday} · 第 ${m.startPeriod}–${m.endPeriod} 节`,[
        text(`${m.weeks.join(',')} 周 · ${m.location||'未填地点'} · ${m.teacher||'未填教师'}`),listTile('编辑安排',null,'schedule',{type:'course',course,meeting:m}),listTile('删除安排',null,'history',{type:'delete',collection:'meetings',id:m.id})
      ])),listTile('增加安排',null,'schedule',{type:'course',course}),listTile('删除课程',null,'history',{type:'delete',collection:'courses',id:course.id})]));
    }
  } else if(page==='app.schedule.changes') {
    const {courses,meetings,changes}=await snapshot(t.id);
    children.push(listTile('临时加课','在指定日期添加一次课程','calendar',{type:'extra'}));
    if(!changes.length)children.push(text('暂无单次调课记录。点击周视图中的课程可查看与调整本次上课。'));
    for(const change of changes) {
      const course=courses.find(c=>c.id===(change.courseId||meetings.find(m=>m.id===change.meetingId)?.courseId));
      children.push(group(course?.name||'单次课程变更',[text(`${change.originalDate} → ${change.kind==='cancel'?'取消':change.date}${change.kind==='extra'?' · 临时课':''}`),listTile('撤销变更',null,'history',{type:'delete',collection:'occurrenceChanges',id:change.id})]));
    }
  } else if(page==='app.schedule.today') {
    const today=await queryToday({timetableId:t.id});children.push(text(`${today.date} · 第${today.teachingWeek}教学周`));
    if(!today.items.length)children.push(text('今天没有课程'));
    for(const item of today.items)children.push(listTile(item.title,`第 ${item.startPeriod}–${item.endPeriod} 节 · ${item.location||'未填地点'} · ${item.teacher||'未填教师'}`,'school',{type:'occurrence',item}));
  } else {
    const today=await clock.today(t.timezone),week=Math.max(1,Math.min(t.totalWeeks,state.week||teachingWeek(t,today)));
    state.week=week;const result=await queryWeek({timetableId:t.id,teachingWeek:week}),local=await clock.local(t.timezone);
    const draft=displayDraft(t),dirty=displayDirty(draft),count=t.periods.length,height=48+count*draft.rowHeight,showDisplay=state.displayControls===true;
    const showWeekends=showDisplay?draft.showWeekends:scheduleShowWeekends(t)||state.revealWeekends===true;
    const columns=result.columns.filter(c=>showWeekends||weekday(c.id)<6).map(c=>({...c,title:['','一','二','三','四','五','六','日'][weekday(c.id)],subtitle:c.id.slice(5),highlight:c.id===today}));
    const rows=result.rows.map((row,i)=>({...row,title:String(t.periods[i].number),subtitle:`${t.periods[i].start}\n${t.periods[i].end}`,highlight:local.time>=t.periods[i].start&&local.time<t.periods[i].end}));
    const weekend=result.items.filter(item=>weekday(item.date)>=6).length;
    state.displayDraft={...draft,dirty};
    const floatingPanel=showDisplay?{title:'课表显示设置',closeLabel:'关闭显示调整',closeEvent:{type:'closeDisplay'},top:64,child:{type:'column',spacing:6,children:[
      {type:'switch',key:`display.${t.id}.weekends`,text:'显示周六和周日',value:draft.showWeekends,event:{type:'displayWeekends'}},
      text('默认仅显示周一至周五；开启后七天完整适配屏幕。'),
      text(`总高度 ${Math.round(height)} · 默认 ${48+count*72}`),
      {type:'slider',key:`display.${t.id}.height`,text:'课表总高度',min:48+count*48,max:48+count*160,divisions:112,value:height,event:{type:'displayHeight'}},
      {type:'row',children:[{...button('−1',{type:'stepDisplay',delta:-1}),disabled:draft.rowHeight<=48},{...button('+1',{type:'stepDisplay',delta:1}),disabled:draft.rowHeight>=160},text('每次调整总高度 1') ]},
      text(dirty?'预览中，尚未保存。关闭后恢复已保存显示设置。':'调整时课表同步预览。'),
      ...(draft.error?[text(draft.error)]:[]),
      ...(state.notice?[text(state.notice)]:[]),
      {type:'row',children:[button('恢复默认高度',{type:'defaultDisplay'}),...(dirty?[button('重新载入',{type:'resetDisplay'}),button('保存显示设置',{type:'saveDisplay'})]:[])]}
    ]}}:null;
    const header={autoHideChrome:!showDisplay,title:`第 ${week} 周`,leading:{label:t.name,event:{type:'chooseTimetable'}},titleEvent:{type:'chooseWeek'},actions:[
      {label:'回到本周',event:{type:'currentWeek'}},
      {label:'今日课程',event:{type:'navigate',page:'today'}},
      {label:'课表设置',event:{type:'navigate',page:'settings'}},
      {label:'显示设置',event:{type:'openDisplay'}},
      ...(weekend?[{label:`周末课程 · ${weekend} 次`,event:{type:'weekend'}}]:[])
    ]};
    return {state,header,tree:{type:'column',template:'ui.page.timeGrid@1',edgeToEdge:true,fillHeight:true,underlapChrome:true,spacing:0,...(floatingPanel?{floatingPanel}:{}),children:[
      {type:'timeGrid',columns,rows,blocks:result.blocks.filter(b=>columns.some(c=>c.id===b.column)),corner:{title:result.columns[0].id.slice(0,4),subtitle:`${week}周`},options:{rowHeight:showDisplay?draft.rowHeight:scheduleRowHeight(t),headerHeight:48,labelWidth:42,fillWidth:true,fitColumns:true,underlapChrome:true}}
    ]}};
  }
  return {state,tree:{type:'column',children}};
}
