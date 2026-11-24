import {data,clock} from '@xudian/sdk';
import {civil,dayMs,addDays,teachingWeek,weekday,occurrences,overlaps} from './calendar.js';
import {timeMinutes} from './view_helpers.js';

export async function snapshot(timetableId,timetable) {
  const t=timetable??await data.get('timetables',timetableId); if(!t) throw new Error('课表不存在');
  const filter={field:'timetableId',op:'eq',value:timetableId};
  // All reads retain the invocation's host SnapshotSession. Dispatch these
  // independent requests together to avoid three JS/host wait cycles; the
  // store remains responsible for database scheduling and revision checks.
  const [courses,meetings,changes]=await Promise.all([
    data.query('courses',{filter}),data.query('meetings',{filter}),data.query('occurrenceChanges',{filter}),
  ]);
  return {t,courses,meetings,changes};
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
function feedDate(value) {
  if(typeof value!=='string'||Number(value.slice(0,4))<1)throw new Error('日期不存在');
  civil(value);return value;
}
export async function queryToday({timetableId,date:selectedDate}) {
  const content=await snapshot(timetableId),today=selectedDate===undefined?await clock.today(content.t.timezone):feedDate(selectedDate);
  return todayFromSnapshot(content,today);
}
function todayFromSnapshot({t,courses,meetings,changes},today) {
  // A civil-date prefix upper bound also includes 9999-12-31 without creating
  // an unsupported five-digit year for the exclusive next-day boundary.
  return {date:today,teachingWeek:teachingWeek(t,today),items:occurrences(t,courses,meetings,changes,today,today+'\uffff')};
}
// Inclusive civil range. Reuse the same occurrences as the timetable views,
// then resolve each local period boundary in its own timetable timezone.
export async function queryBusy({startDate,endDate}) {
  feedDate(startDate);feedDate(endDate);
  const length=(civil(endDate)-civil(startDate))/dayMs+1;
  if(length<1||length>30)throw new Error('忙碌查询请选择1–30天');
  const items=[];
  for(const timetable of await data.query('timetables')) {
    const {t,courses,meetings,changes}=await snapshot(timetable.id,timetable);
    for(const item of occurrences(t,courses,meetings,changes,startDate,endDate+'\uffff')) {
      const startTime=t.periods[item.startPeriod-1].start,endTime=t.periods[item.endPeriod-1].end;
      const start=await clock.toUtc({date:item.date,time:startTime,zone:t.timezone}),end=await clock.toUtc({date:item.date,time:endTime,zone:t.timezone});
      if(start.status!=='unique'||end.status!=='unique'||start.instants.length!==1||end.instants.length!==1)throw new Error(`${t.name} ${item.date} 的课程时间存在夏令时歧义或不存在`);
      if(end.instants[0]<=start.instants[0])throw new Error('课程结束时间必须晚于开始时间');
      items.push({id:t.id+'|'+item.occurrenceId,startAt:start.instants[0],endAt:end.instants[0],timetableId:t.id,date:item.date,timezone:t.timezone,title:item.title,courseId:item.courseId,colorKey:item.courseId,color:item.color,
        ...(typeof item.location==='string'&&item.location.trim()?{location:item.location.trim()}:{}),
        ...(typeof item.teacher==='string'&&item.teacher.trim()?{teacher:item.teacher.trim()}:{}),
      });
    }
  }
  items.sort((a,b)=>a.startAt.localeCompare(b.startAt)||a.id.localeCompare(b.id));
  return {startDate,endDate,items};
}
export async function queryTodayFeed({date:selectedDate}={}) {
  const date=selectedDate===undefined?await clock.today():feedDate(selectedDate),items=[];
  const now=selectedDate===undefined?null:Date.parse(await clock.now());
  for(const timetable of await data.query('timetables')) {
    // The list query already read this timetable in the same invocation.
    // One local-clock read supplies both today's date and sorting metadata.
    const [content,local]=await Promise.all([snapshot(timetable.id,timetable),clock.local(timetable.timezone)]);
    const today=todayFromSnapshot(content,selectedDate===undefined?local.date:date);
    const offsets=new Map();
    const offset=time=> {
      if(!offsets.has(time))offsets.set(time,clock.toUtc({date,time,zone:timetable.timezone}).then(result=> {
        if(result.status!=='unique'||result.instants.length!==1)throw new Error(`${timetable.name} ${date} ${time} 的课程时间存在夏令时歧义或不存在，请查看课表确认`);
        return (Date.parse(result.instants[0])-now)/60000;
      }));
      return offsets.get(time);
    };
    for(const item of today.items) {
      const startTime=timetable.periods[item.startPeriod-1].start,endTime=timetable.periods[item.endPeriod-1].end;
      const [startOffset,endOffset]=selectedDate===undefined?[
        (civil(item.date)-civil(local.date))/dayMs*1440+timeMinutes(startTime)-timeMinutes(local.time),
        (civil(item.date)-civil(local.date))/dayMs*1440+timeMinutes(endTime)-timeMinutes(local.time),
      ]:await Promise.all([offset(startTime),offset(endTime)]);
      items.push({...item,timetableId:timetable.id,timetableName:timetable.name,timezone:timetable.timezone,startTime,endTime,
        // Compare course times relative to now so different timetable timezones
        // still sort chronologically, including when their civil dates differ.
        startOffset,endOffset,...(now===null?{}:{startAt:new Date(now+startOffset*60000).toISOString(),endAt:new Date(now+endOffset*60000).toISOString()}),isLocalToday:item.date===local.date});
    }
  }
  items.sort((left,right)=>left.startOffset-right.startOffset||left.title.localeCompare(right.title)||left.timetableId.localeCompare(right.timetableId));
  return {date,items};
}

export async function exportBackup({timetableId}) {
  const {t,courses,meetings,changes}=await snapshot(timetableId);
  return {backupFormat:1,datasetId:t.datasetId,timetable:t,courses,meetings,occurrenceChanges:changes};
}

export async function currentOccurrence(t,reference) {
  const {courses,meetings,changes}=await snapshot(t.id);
  const change=changes.find(c=>c.kind==='extra'?c.id===reference.occurrenceId:c.meetingId===reference.meetingId&&c.originalDate===reference.originalDate);
  const meeting=meetings.find(m=>m.id===reference.meetingId);
  if(change?.kind==='cancel') return {cancelled:true,change,meeting,course:courses.find(c=>c.id===meeting?.courseId)};
  const day=change?.date||(meeting?reference.originalDate:reference.date)||reference.originalDate;
  if(!day)return null;
  const item=occurrences(t,courses,meetings,changes,day,addDays(day,1)).find(x=>x.occurrenceId===reference.occurrenceId || reference.meetingId&&x.meetingId===reference.meetingId&&x.originalDate===reference.originalDate);
  return item?{item,change,meeting,course:courses.find(c=>c.id===item.courseId)}:null;
}

export function occurrenceReference(item) { return {occurrenceId:item.occurrenceId,meetingId:item.meetingId||null,originalDate:item.originalDate,date:item.date}; }
