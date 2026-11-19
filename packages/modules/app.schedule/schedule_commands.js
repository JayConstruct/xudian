import {data,services,ui,clock,ids} from '@xudian/sdk';
import {validateTimetable,validateMeeting,validateChange,validOriginal} from './calendar.js';
import {snapshot} from './schedule_queries.js';

function normalized(value) { if(Array.isArray(value))return value.map(normalized);if(value&&typeof value==='object')return Object.fromEntries(Object.keys(value).sort().map(key=>[key,normalized(value[key])]));return value; }
export async function saveTimetable({timetable,expectedTimetable}) {
  const id=timetable.id || await ids.new(),current=await data.get('timetables',id);
  const timezone=timetable.timezone??current?.timezone??(await clock.systemTimezone()).zone;
  const value={...timetable,id,datasetId:timetable.datasetId || current?.datasetId || await ids.new(),timezone};
  validateTimetable(value); await clock.today(value.timezone);
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

export const ref=id=>({moduleId:'app.schedule',serviceId:id,majorVersion:1});

export async function command(id,input) {
  const plan=await services.prepare(ref(id),input);
  if(plan.result?.blocked) return plan;
  if(await ui.review(plan.planId)) return {result:await services.commit(plan.planId)};
  return null;
}
