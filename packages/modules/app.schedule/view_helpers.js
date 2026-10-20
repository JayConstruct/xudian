import {data} from '@xudian/sdk';
import {validateTimetable,validateMeeting,validateChange} from './calendar.js';
export const defaultPeriods=[['08:00','08:45'],['08:50','09:35'],['09:50','10:35'],['10:40','11:25'],['11:30','12:15'],['14:00','14:45'],['14:50','15:35'],['15:45','16:30'],['16:35','17:20'],['18:30','19:15'],['19:20','20:05'],['20:10','20:55']].map(([start,end],i)=>({number:i+1,start,end}));
const periodDrafts=new Map(),semesterDrafts=new Map(),displayDrafts=new Map();
export const scheduleRowHeight=t=>t.rowHeight??72;
export const scheduleShowWeekends=t=>t.showWeekends===true;
export const displayDirty=draft=>draft.rowHeight!==draft.baseline||draft.showWeekends!==draft.baselineShowWeekends;
export function displayDraft(t) {let draft=displayDrafts.get(t.id);if(!draft || !displayDirty(draft)&&(draft.baseline!==scheduleRowHeight(t)||draft.baselineShowWeekends!==scheduleShowWeekends(t)))draft=resetDisplayDraft(t);return draft;}
export function resetDisplayDraft(t) {const draft={rowHeight:scheduleRowHeight(t),baseline:scheduleRowHeight(t),showWeekends:scheduleShowWeekends(t),baselineShowWeekends:scheduleShowWeekends(t),error:null};displayDrafts.set(t.id,draft);return draft;}
const copy=value=>JSON.parse(JSON.stringify(value));
export const timeMinutes=value=>{if(typeof value!=='string'||!/^\d{2}:\d{2}$/.test(value)) throw new Error('时间格式需为 HH:mm');const [h,m]=value.split(':').map(Number);if(h>23||m>59)throw new Error('时间需在00:00–23:59之间');return h*60+m;};
export const timeString=value=>{if(value<0||value>=1440)throw new Error('追加节次将跨午夜，请先调整作息');return String(Math.floor(value/60)).padStart(2,'0')+':'+String(value%60).padStart(2,'0');};
function periodDefaults(t) {
  const counts=new Map();
  for(const row of t.periods) {const length=timeMinutes(row.end)-timeMinutes(row.start);counts.set(length,(counts.get(length)||0)+1);}
  const inferred=[...counts].sort((a,b)=>b[1]-a[1])[0]?.[0]||45;
  const duration=t.periodDurationMinutes??inferred;
  const manual=t.periodManualEnds??t.periods.filter(row=>timeMinutes(row.end)-timeMinutes(row.start)!==duration).map(row=>row.number);
  return {durationMinutes:String(duration),manualEnds:[...manual].sort((a,b)=>a-b)};
}
export const periodDraftDirty=draft=>JSON.stringify(draft.periods)!==draft.baseline||JSON.stringify({durationMinutes:draft.durationMinutes,manualEnds:draft.manualEnds})!==draft.baselineSettings;
export const periodBaselineMatches=(t,draft)=>draft.baseline===JSON.stringify(t.periods)&&draft.baselineSettings===JSON.stringify(periodDefaults(t));
export function periodDraft(t) {let draft=periodDrafts.get(t.id);if(!draft)draft=resetPeriodDraft(t);else if(!periodDraftDirty(draft)&&(draft.baseline!==JSON.stringify(t.periods)||draft.baselineSettings!==JSON.stringify(periodDefaults(t))))draft=resetPeriodDraft(t);return draft;}
export function resetPeriodDraft(t) {const settings=periodDefaults(t),draft={periods:copy(t.periods),...settings,baseline:JSON.stringify(t.periods),baselineSettings:JSON.stringify(settings),error:null};periodDrafts.set(t.id,draft);return draft;}
export function periodTableValue(draft) {
  return {durationMinutes:draft.durationMinutes,rows:draft.periods.map(row=>({id:String(row.number),label:`第 ${row.number} 节`,start:row.start,end:row.end,manualEnd:draft.manualEnds.includes(row.number)})),...(draft.baseline?{baselineToken:JSON.stringify([draft.baseline,draft.baselineSettings])}:{})};
}
export function periodTableBaseline(draft) {const settings=JSON.parse(draft.baselineSettings);return periodTableValue({periods:JSON.parse(draft.baseline),...settings});}
export function hydratePeriodDraft(draft,value) {
  if(value===undefined)return;
  let baseline=draft.baseline,settings=draft.baselineSettings;
  // Local native edits can outlive the JS draft and an external data update.
  // Carry their original basis so reopening never silently rebases old edits.
  if(value?.baselineToken!==undefined) {
    const token=JSON.parse(value.baselineToken);
    if(!Array.isArray(token)||token.length!==2||token.some(item=>typeof item!=='string')||!Array.isArray(JSON.parse(token[0]))||typeof JSON.parse(token[1]).durationMinutes!=='string'||!Array.isArray(JSON.parse(token[1]).manualEnds))throw new Error('作息草稿依据无效，请重新载入');
    [baseline,settings]=token;
  }
  if(!value||typeof value!=='object'||!Array.isArray(value.rows)||value.rows.length<1||value.rows.length>30||value.rows.some((row,i)=>!row||row.id!==String(i+1)||typeof row.start!=='string'||typeof row.end!=='string'||typeof row.manualEnd!=='boolean'))throw new Error('作息草稿格式无效，请重新载入');
  draft.baseline=baseline;draft.baselineSettings=settings;
  draft.periods=value.rows.map((row,i)=>({number:i+1,start:row.start,end:row.end}));
  draft.durationMinutes=String(value.durationMinutes??'');
  draft.manualEnds=value.rows.filter(row=>row.manualEnd).map(row=>Number(row.id));
}
export function periodDraftTimetable(t,draft) {
  if(!/^\d+$/.test(draft.durationMinutes))throw new Error('每节时长需为1–1440分钟的整数');
  return {...t,periods:draft.periods,periodDurationMinutes:Number(draft.durationMinutes),periodManualEnds:[...draft.manualEnds]};
}
export function periodDraftError(t,draft) {try {validateTimetable(periodDraftTimetable(t,draft));return null;}catch(error){return error.message;}}
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
export const listTile=(title,subtitle,icon,event,trailing)=>({type:'listTile',title,...(subtitle?{subtitle}:{}),...(event?{event}:{}),...(trailing!==undefined?{trailing}: {})});
export const group=(title,children)=>({type:'column',children:[{type:'sectionHeader',title},...children]});
const importFieldLabels={name:'名称',code:'课程代码',color:'颜色',notes:'备注',credit:'学分',firstMonday:'第一周周一',totalWeeks:'学期周数',timezone:'时区',displayWeekStart:'每周起始日',periods:'作息',weekday:'星期',startPeriod:'开始节次',endPeriod:'结束节次',weeks:'教学周',teacher:'教师',location:'地点',kind:'调整类型',originalDate:'原上课日期',date:'日期',startTime:'开始时间',endTime:'结束时间'};
const importValue=(field,value)=>value===undefined||value===null||value===''?'未设置':field==='weekday'?'周'+['','一','二','三','四','五','六','日'][value]:field==='periods'?(value||[]).map(p=>`${p.number}: ${p.start}–${p.end}`).join('；'):Array.isArray(value)?value.join('、'):typeof value==='object'?JSON.stringify(value):String(value);
export async function importSummary(plan,draft) {
  const summary={courses:draft?.courses?.length||0,meetings:draft?.meetings?.length||0,changes:draft?.occurrenceChanges?.length||0,added:0,updated:0,deleted:0,details:[],conflicts:plan?.result?.conflicts||[],warnings:plan?.result?.warnings||draft?.warnings||[]};
  const courseNames=new Map();
  for(const write of plan?.writes||[]) if(write.collection==='courses')courseNames.set(write.id,(write.value||write.before)?.name||'课程');
  for(const write of plan?.writes||[]) {
    if(!['timetables','courses','meetings','occurrenceChanges'].includes(write.collection))continue;
    const before=Object.prototype.hasOwnProperty.call(write,'before')?write.before:await data.get(write.collection,write.id);
    const after=write.value;
    const action=after===null?'删除':before?'修改':'新增';
    if(action==='删除')summary.deleted++;else if(action==='修改')summary.updated++;else summary.added++;
    const value=after||before||{};
    let name=value.name||'';
    if(!name && value.courseId) {
      if(!courseNames.has(value.courseId))courseNames.set(value.courseId,(await data.get('courses',value.courseId))?.name||'课程');
      name=courseNames.get(value.courseId);
    }
    const kind={timetables:'课表',courses:'课程',meetings:'上课安排',occurrenceChanges:'单次调整'}[write.collection];
    const fields=Object.keys(importFieldLabels).filter(field=>JSON.stringify(before?.[field])!==JSON.stringify(after?.[field]));
    const description=fields.map(field=>`${importFieldLabels[field]}：${before&&after?importValue(field,before[field])+' → ':''}${importValue(field,(after||before)?.[field])}`).join('\n');
    summary.details.push(listTile(`${action}${kind}${name?' · '+name:''}`,description,'calendar',null));
  }
  return summary;
}
