import {data} from '@xudian/sdk';
import {validateTimetable,validateMeeting,validateChange} from './calendar.js';
export const defaultPeriods=[['08:00','08:45'],['08:50','09:35'],['09:50','10:35'],['10:40','11:25'],['11:30','12:15'],['14:00','14:45'],['14:50','15:35'],['15:45','16:30'],['16:35','17:20'],['18:30','19:15'],['19:20','20:05'],['20:10','20:55']].map(([start,end],i)=>({number:i+1,start,end}));
const periodDrafts=new Map(),semesterDrafts=new Map(),displayDrafts=new Map();
export const scheduleRowHeight=t=>t.rowHeight??72;
export function displayDraft(t) {let draft=displayDrafts.get(t.id);if(!draft || draft.rowHeight===draft.baseline&&draft.baseline!==scheduleRowHeight(t))draft=resetDisplayDraft(t);return draft;}
export function resetDisplayDraft(t) {const draft={rowHeight:scheduleRowHeight(t),baseline:scheduleRowHeight(t),error:null};displayDrafts.set(t.id,draft);return draft;}
const copy=value=>JSON.parse(JSON.stringify(value));
export const timeMinutes=value=>{if(typeof value!=='string'||!/^\d{2}:\d{2}$/.test(value)) throw new Error('时间格式需为 HH:mm');const [h,m]=value.split(':').map(Number);if(h>23||m>59)throw new Error('时间需在00:00–23:59之间');return h*60+m;};
export const timeString=value=>{if(value<0||value>=1440)throw new Error('追加节次将跨午夜，请先调整作息');return String(Math.floor(value/60)).padStart(2,'0')+':'+String(value%60).padStart(2,'0');};
export function periodDraft(t) {let draft=periodDrafts.get(t.id);if(!draft){draft={periods:copy(t.periods),baseline:JSON.stringify(t.periods),error:null};periodDrafts.set(t.id,draft);}else if(JSON.stringify(draft.periods)===draft.baseline&&draft.baseline!==JSON.stringify(t.periods)){draft=resetPeriodDraft(t);}return draft;}
export function resetPeriodDraft(t) {const draft={periods:copy(t.periods),baseline:JSON.stringify(t.periods),error:null};periodDrafts.set(t.id,draft);return draft;}
const semesterValues=t=>({name:t.name,firstMonday:t.firstMonday,totalWeeks:String(t.totalWeeks),timezone:t.timezone,displayWeekStart:String(t.displayWeekStart)});
export function semesterDraft(t) {let draft=semesterDrafts.get(t.id);if(!draft){draft={values:semesterValues(t),baseline:JSON.stringify(semesterValues(t)),error:null};semesterDrafts.set(t.id,draft);}else if(JSON.stringify(draft.values)===draft.baseline&&draft.baseline!==JSON.stringify(semesterValues(t))){draft=resetSemesterDraft(t);}return draft;}
export function resetSemesterDraft(t) {const draft={values:semesterValues(t),baseline:JSON.stringify(semesterValues(t)),error:null};semesterDrafts.set(t.id,draft);return draft;}
export async function periodError(t,periods) {
  try {
    validateTimetable({...t,periods});
    const filter={field:'timetableId',op:'eq',value:t.id},courses=await data.query('courses',{filter}),meetings=await data.query('meetings',{filter}),changes=await data.query('occurrenceChanges',{filter});
    for(const m of meetings) validateMeeting(m,{...t,periods},courses);
    for(const c of changes) validateChange(c,{...t,periods},meetings,courses);
    return null;
  } catch(error) {return error.message;}
}
export function appendPeriods(existing) {
  const rows=copy(existing);
  if(rows.length>=12)return rows;
  let end=rows.length?timeMinutes(rows.at(-1).end):-1;
  for(let i=rows.length;i<12;i++){
    const template=defaultPeriods[i],duration=timeMinutes(template.end)-timeMinutes(template.start);
    const gap=i?Math.max(5,timeMinutes(template.start)-timeMinutes(defaultPeriods[i-1].end)):0;
    const start=Math.max(timeMinutes(template.start),end+gap);
    rows.push({number:i+1,start:timeString(start),end:timeString(start+duration)});end=start+duration;
  }
  return rows;
}
export const listTile=(title,subtitle,icon,event,trailing)=>({type:'listTile',title,...(subtitle?{subtitle}:{}),...(icon?{icon}:{}),...(event?{event}:{}),...(trailing!==undefined?{trailing}: {})});
export const group=(title,children)=>({type:'card',children:[{type:'text',text:title,style:'title'},...children]});
export async function importSummary(plan,draft) {
  const summary={courses:draft?.courses?.length||0,meetings:draft?.meetings?.length||0,changes:draft?.occurrenceChanges?.length||0,added:0,updated:0,deleted:0,conflicts:plan?.result?.conflicts||[],warnings:plan?.result?.warnings||draft?.warnings||[]};
  for(const write of plan?.writes||[]) {
    if(!['timetables','courses','meetings','occurrenceChanges'].includes(write.collection))continue;
    if(write.value===null)summary.deleted++;
    else if(await data.get(write.collection,write.id))summary.updated++;
    else summary.added++;
  }
  return summary;
}
