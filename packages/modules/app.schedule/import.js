import {data,ids} from '@xudian/sdk';
import {validateTimetable,validateMeeting,validateChange,occurrences,overlaps,addDays,validOriginal} from './calendar.js';
const canon=value=>JSON.stringify(normalize(value));
function normalize(v) { if(Array.isArray(v)) return v.map(normalize); if(v&&typeof v==='object') return Object.fromEntries(Object.keys(v).sort().map(k=>[k,normalize(v[k])])); return v; }
export function draftFromBackup(backup) {
  if(backup.backupFormat!==1 || typeof backup.datasetId!=='string' || !backup.datasetId) throw new Error('备份版本或数据集标识无效');
  const source=collection=> (backup[collection]||[]).map(x=>({...x,sourceId:x.id}));
  return {draftVersion:1,scope:`json:${backup.datasetId}`,adapterVersion:'json@1',complete:true,
    timetable:backup.timetable,courses:source('courses'),meetings:source('meetings'),
    occurrenceChanges:source('occurrenceChanges'),warnings:[]};
}
function clean(value) { const result={...value}; for(const key of ['sourceId','id','timetableId','createdAt','updatedAt']) delete result[key]; return result; }
export async function importPlan(input) {
  const {draft,targetTimetableId,mode='new',choices={}}=input;
  if(draft?.draftVersion!==1 || typeof draft.scope!=='string'||!draft.scope || typeof draft.adapterVersion!=='string'||typeof draft.complete!=='boolean') throw new Error('ScheduleImportDraft v1 无效');
  if(!['new','merge','replaceSource'].includes(mode)) throw new Error('导入模式无效');
  const caller=input._host?.callerModuleId;
  if(!caller) throw new Error('缺少宿主调用身份');
  const sourceKey=canon([caller,draft.scope]);
  const tables=await data.query('timetables'),courses=await data.query('courses'),meetings=await data.query('meetings'),changes=await data.query('occurrenceChanges');
  const sources=await data.query('importSources');
  let t=mode==='new'?null:tables.find(t=>t.id===targetTimetableId);
  if(mode!=='new'&&!t) throw new Error('目标课表不存在');
  const tid=t?.id || await ids.new();
  if(!t) t={...clean(draft.timetable),id:tid,datasetId:await ids.new()};
  validateTimetable({...clean(draft.timetable),id:tid,datasetId:t.datasetId});
  validateTimetable(t);
  const source=sources.find(s=>s.timetableId===tid&&s.sourceKey===sourceKey);
  const mappings={...(source?.mappings||{})},writes=[],conflicts=[],warnings=[...(draft.warnings||[])];
  const incomingTable=clean(draft.timetable);
  if(mode!=='new' && source?.timetableBaseline) {
    const base=source.timetableBaseline,current=clean(t),merged={...current};
    delete incomingTable.datasetId;
    delete current.datasetId;
    for(const field of new Set([...Object.keys(base),...Object.keys(incomingTable),...Object.keys(current)])) {
      if(field==='datasetId') continue;
      const localChanged=canon(current[field])!==canon(base[field]),sourceChanged=canon(incomingTable[field])!==canon(base[field]);
      const key=`timetable:${field}`;
      if(localChanged&&sourceChanged&&canon(current[field])!==canon(incomingTable[field])) {
        if(!['local','source'].includes(choices[key])) conflicts.push({key,collection:'timetables',field,local:current[field],source:incomingTable[field]});
        if(choices[key]==='source') merged[field]=incomingTable[field];
      } else if(sourceChanged&&!localChanged) merged[field]=incomingTable[field];
    }
    const next={...merged,id:tid,datasetId:t.datasetId};
    validateTimetable(next);
    if(canon(t)!==canon(next)) writes.push({collection:'timetables',id:tid,value:next});
    t=next;
  }
  if(mode==='new') writes.push({collection:'timetables',id:tid,value:t});
  const working={courses:courses.filter(x=>x.timetableId===tid),meetings:meetings.filter(x=>x.timetableId===tid),occurrenceChanges:changes.filter(x=>x.timetableId===tid)};
  const refs={courses:new Map(),meetings:new Map()};
  const seen=new Set();
  for(const collection of ['courses','meetings','occurrenceChanges']) {
    const inputRows=draft[collection]||[];
    if(!Array.isArray(inputRows)) throw new Error('导入实体需为数组');
    for(const raw of inputRows) {
      const value=clean(raw);
      if(collection==='meetings') {
        value.courseId=refs.courses.get(raw.courseId);
        if(!value.courseId) throw new Error('导入安排引用不存在的课程');
      }
      if(collection==='occurrenceChanges') {
        value.meetingId=raw.kind==='extra'?null:refs.meetings.get(raw.meetingId);
        value.courseId=raw.courseId?refs.courses.get(raw.courseId):null;
        if(raw.kind!=='extra'&&!value.meetingId) throw new Error('单次变更引用不存在的安排');
      }
      const stable=raw.sourceId ?? canon(clean(raw));
      if(typeof stable!=='string'||!stable) throw new Error('sourceId 必须是稳定字符串');
      const key=`${collection}:${stable}`;
      if(seen.has(key)) throw new Error('来源实体标识重复'); seen.add(key);
      let mapping=mappings[key],local=mapping?working[collection].find(x=>x.id===mapping.localId):null;
      if(!mapping) {
        const identical=working[collection].find(x=>canon(clean(x))===canon(value));
        mapping={localId:identical?.id || await ids.new(),baseline:identical?clean(identical):null,deleted:false};
        local=identical;
      }
      refs[collection]?.set(raw.sourceId ?? raw.id ?? stable,mapping.localId);
      const incoming={...value,id:mapping.localId,timetableId:tid};
      if(mapping.deleted || (!local&&mapping.baseline)) {
        mappings[key]={...mapping,deleted:true,baseline:clean(incoming)};
        continue; // Re-import never resurrects local deletions.
      }
      if(collection==='courses' && (!incoming.name?.trim()||incoming.name.length>120)) throw new Error('课程名称无效');
      if(collection==='meetings') Object.assign(incoming,validateMeeting(incoming,t,working.courses));
      if(collection==='occurrenceChanges') validateChange(incoming,t,working.meetings,working.courses);
      let merged=incoming;
      if(local && mapping.baseline) {
        const current=clean(local),base=mapping.baseline,next=clean(incoming),mergedFields={...current};
        for(const field of new Set([...Object.keys(base),...Object.keys(next),...Object.keys(current)])) {
          const localChanged=canon(current[field])!==canon(base[field]);
          const sourceChanged=canon(next[field])!==canon(base[field]);
          const conflictKey=`${key}:${field}`;
          if(localChanged&&sourceChanged&&canon(current[field])!==canon(next[field])) {
            const choice=choices[conflictKey];
            if(!['local','source'].includes(choice)) conflicts.push({key:conflictKey,collection,field,local:current[field],source:next[field]});
            if(choice==='source') mergedFields[field]=next[field];
          } else if(sourceChanged&&!localChanged) mergedFields[field]=next[field];
        }
        merged={...mergedFields,id:local.id,timetableId:tid};
      }
      mappings[key]={...mapping,baseline:clean(incoming),deleted:false};
      if(!local||canon(local)!==canon(merged)) writes.push({collection,id:merged.id,value:merged});
      const index=working[collection].findIndex(x=>x.id===merged.id);
      if(index<0) working[collection].push(merged); else working[collection][index]=merged;
    }
  }
  const nonempty=(draft.courses?.length||0)+(draft.meetings?.length||0)>0;
  if(mode==='replaceSource'&&draft.complete&&nonempty) {
    for(const [key,mapping] of Object.entries(mappings)) {
      if(seen.has(key)||mapping.deleted) continue;
      const collection=key.slice(0,key.indexOf(':'));
      const local=working[collection]?.find(x=>x.id===mapping.localId);
      if(!local) { mapping.deleted=true; continue; }
      const dependent=collection==='courses'&&working.meetings.some(m=>m.courseId===local.id) ||
        collection==='meetings'&&working.occurrenceChanges.some(c=>c.meetingId===local.id);
      const conflictKey=`${key}:delete`;
      if(dependent || canon(clean(local))!==canon(mapping.baseline)) {
        if(choices[conflictKey]!=='source') {
          if(choices[conflictKey]!=='local') conflicts.push({key:conflictKey,collection,field:'delete',local,source:null});
          continue;
        }
        if(dependent) { warnings.push('已保留存在本地安排或调课的来源实体'); continue; }
      }
      writes.push({collection,id:local.id,value:null});
      working[collection]=working[collection].filter(x=>x.id!==local.id); mapping.deleted=true;
    }
  }
  // Changing a recurrence cannot silently orphan an existing occurrence change.
  for(const m of working.meetings) validateMeeting(m,t,working.courses);
  for(const c of [...working.occurrenceChanges]) {
    const meeting=working.meetings.find(m=>m.id===c.meetingId);
    if(c.kind!=='extra' && (!meeting || !validOriginal(meeting,t,c.originalDate))) {
      const key=`occurrenceChanges:${c.id}:orphan`,options=c.kind==='cancel'?['discard']:['discard','extra'];
      if(!options.includes(choices[key])) {
        conflicts.push({key,collection:'occurrenceChanges',field:'失效调课',local:c,source:null,options});
        continue;
      }
      const replacement=choices[key]==='extra'?{...c,kind:'extra',meetingId:null,
        courseId:c.courseId || meetings.find(m=>m.id===c.meetingId)?.courseId}:null;
      // Replace a staged write for this record; it must have one final value.
      const index=writes.findIndex(w=>w.collection==='occurrenceChanges'&&w.id===c.id);
      if(index>=0) writes.splice(index,1);
      writes.push({collection:'occurrenceChanges',id:c.id,value:replacement});
      working.occurrenceChanges=working.occurrenceChanges.filter(x=>x.id!==c.id);
      if(replacement) { validateChange(replacement,t,working.meetings,working.courses); working.occurrenceChanges.push(replacement); }
    } else validateChange(c,t,working.meetings,working.courses);
  }
  warnings.push(...overlaps(occurrences(t,working.courses,working.meetings,working.occurrenceChanges,t.firstMonday,addDays(t.firstMonday,t.totalWeeks*7))));
  if(conflicts.length) return {writes:[],events:[],result:{timetableId:tid,conflicts,warnings,blocked:true}};
  const sourceId=source?.id || await ids.new();
  writes.push({collection:'importSources',id:sourceId,value:{id:sourceId,timetableId:tid,sourceKey,scope:draft.scope,callerModuleId:caller,timetableBaseline:{...incomingTable,datasetId:undefined},mappings}});
  const batchId=await ids.new();
  writes.push({collection:'importBatches',id:batchId,value:{id:batchId,timetableId:tid,sourceId,adapterVersion:draft.adapterVersion,complete:draft.complete,mode,summary:canon(draft),warnings}});
  return {writes,events:[{type:'schedule.imported',timetableId:tid,batchId}],result:{timetableId:tid,conflicts:[],warnings,blocked:false}};
}
