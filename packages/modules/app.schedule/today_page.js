import {ui,clock} from '@xudian/sdk';
import {occurrenceReference,queryToday,queryTodayFeed} from './schedule_queries.js';
import {button,text} from './page_controls.js';

export async function renderTodayFeed({state={},event,context={}}={}) {
  state={...state};
  if(event?.type==='viewSchedule')await ui.navigate('app.schedule.home');
  if(event?.type==='openCourse')await ui.navigate('app.schedule.occurrence',{timetableId:event.timetableId,...event.reference});
  const today=await queryTodayFeed(context.selectedDate===undefined?{}:{date:context.selectedDate}),currentDate=await clock.today(),multipleTables=new Set(today.items.map(item=>item.timetableId)).size>1;
  if(state.feedDate!==today.date) {state.feedDate=today.date;state.coursesExpanded=false;}
  if(event?.type==='toggleCourses'&&event.date===today.date)state.coursesExpanded=!state.coursesExpanded;
  const current=today.items.find(item=>item.startOffset<=0&&item.endOffset>0),next=today.items.find(item=>item.startOffset>0);
  const last=today.items.reduce((latest,item)=>!latest||item.endOffset>latest.endOffset?item:latest,null);
  const focus=today.date===currentDate?(current||next||last):today.date<currentDate?last:today.items[0];
  const visible=state.coursesExpanded?today.items:focus?[focus]:[];
  const children=[{type:'sectionHeader',title:today.date===currentDate?'今日课程':'当日课程',count:today.items.length,action:{label:'查看课表',event:{type:'viewSchedule'}}}];
  if(!today.items.length)children.push({type:'text',text:today.date===currentDate?'今天没有课程':`${today.date} 没有课程`,style:'muted'});
  for(const item of visible)children.push({type:'agendaItem',key:item.occurrenceId+'|'+item.timetableId,title:item.title,
    startTime:item.startTime,endTime:item.endTime,color:item.color,
    subtitle:[`第 ${item.startPeriod}–${item.endPeriod} 节`,[item.location,item.teacher].filter(Boolean).join(' · '),multipleTables?item.timetableName:null,item.date!==today.date?item.date:null].filter(Boolean).join(' · '),
    ...(item.isLocalToday&&item.startOffset<=0&&item.endOffset>0?{badge:'正在上课'}:item.isLocalToday&&item.startOffset>0&&item.startOffset<=30?{badge:'即将开始'}:!state.coursesExpanded?{badge:today.date<currentDate?'当日最后一节':today.date>currentDate?'当日首节':item.endOffset<=0?'已结束':'下一节'}:{}),
    event:{type:'openCourse',timetableId:item.timetableId,reference:occurrenceReference(item)},
  });
  if(today.items.length)children.push(button(state.coursesExpanded?'收起课程':`全部课程（${today.items.length}）`,{type:'toggleCourses',date:today.date}));
  return {state,tree:{type:'column',children}};
}

export async function renderToday({t,state,children}) {
  const today=await queryToday({timetableId:t.id});children.push({type:'sectionHeader',title:today.date,subtitle:`第 ${today.teachingWeek} 教学周`,count:today.items.length});
  if(!today.items.length)children.push(text('今天没有课程'));
  for(const item of today.items)children.push({type:'agendaItem',key:item.occurrenceId,title:item.title,startTime:t.periods[item.startPeriod-1].start,endTime:t.periods[item.endPeriod-1].end,color:item.color,subtitle:`第 ${item.startPeriod}–${item.endPeriod} 节 · ${item.location||'未填地点'} · ${item.teacher||'未填教师'}`,event:{type:'occurrence',item}});
  return {state,tree:{type:'column',children}};
}
