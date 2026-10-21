// Civil dates deliberately use UTC arithmetic; conversion to instants belongs to the host.
export const canonical=v=>JSON.stringify(normalize(v));
function normalize(v){if(Array.isArray(v))return v.map(normalize);if(v&&typeof v==='object')return Object.fromEntries(Object.keys(v).sort().filter(k=>v[k]!==undefined).map(k=>[k,normalize(v[k])]));return v;}
export function day(s){if(typeof s!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(s)||s<'0001-01-01'||!Number.isFinite(Date.parse(s+'T00:00:00Z'))||new Date(s+'T00:00:00Z').toISOString().slice(0,10)!==s)throw Error('日期无效');return s;}
export const add=(s,n)=>new Date(Date.parse(day(s)+'T00:00:00Z')+n*86400000).toISOString().slice(0,10);
export const weekday=s=>(new Date(day(s)+'T00:00:00Z').getUTCDay()+6)%7+1;
export function minute(s){if(typeof s!=='string'||!/^([01]\d|2[0-3]):[0-5]\d$/.test(s))throw Error('时间需为 HH:mm');return Number(s.slice(0,2))*60+Number(s.slice(3));}
export const time=n=>String(Math.floor(n/60)).padStart(2,'0')+':'+String(n%60).padStart(2,'0');
export function integer(n,min,max,label){if(!Number.isInteger(n)||n<min||n>max)throw Error(`${label}需在 ${min}–${max} 之间`);return n;}
export function slots(list){if(!Array.isArray(list)||list.length>20)throw Error('最多设置20个时段');return list.map(x=>{if(minute(x.start)>=minute(x.end))throw Error('时段不能跨午夜');return {start:x.start,end:x.end};}).sort((a,b)=>a.start.localeCompare(b.start));}
export function rule(value){const r={kind:'once',priority:0,estimatedMinutes:30,optional:false,status:'active',weekdays:[1,2,3,4,5,6,7],times:[{start:'09:00',end:'21:00'}],...value};if(typeof r.title!=='string'||!r.title.trim()||r.title.length>300)throw Error('请填写任务名称（最多300字）');r.title=r.title.trim();if(typeof r.timezone!=='string'||!r.timezone.trim())throw Error('请选择规划时区');if(!['once','daily','weekly','interval'].includes(r.kind)||!['active','paused','ended'].includes(r.status))throw Error('规则类型或状态无效');day(r.startDate);if(r.endDate){day(r.endDate);if(r.endDate<r.startDate)throw Error('结束日期早于开始日期');}integer(r.estimatedMinutes,1,1439,'耗时');integer(r.priority,0,3,'优先级');if(typeof r.optional!=='boolean')throw Error('有空再做需为开关');if(!Array.isArray(r.weekdays)||!r.weekdays.length||new Set(r.weekdays).size!==r.weekdays.length)throw Error('请选择不同星期');r.weekdays.forEach(x=>integer(x,1,7,'星期'));r.times=slots(r.times);if(!r.times.length)throw Error('请选择允许时段');if(r.kind==='weekly')integer(r.perWeek,1,r.weekdays.length,'每周次数');if(r.kind==='once'&&!r.endDate)throw Error('单次任务需要最晚日期');if(r.kind==='interval'){integer(r.maxGapDays,1,366,'最大间隔');integer(r.earlyDays,0,r.maxGapDays-1,'允许提前天数');if(r.optional)throw Error('必须满足最大间隔与忙时无限跳过互斥');if(r.lastCompletedOn)day(r.lastCompletedOn);else day(r.firstDeadline);}return r;}
export function range(input,today){const startDate=day(input.startDate||today),days=integer(input.days??7,1,28,'规划天数');return {startDate,days,endDate:add(startDate,days-1)};}
function taskFields(c,t){if(!t)return c;c.task=t;if(!c.ruleId)c.requiresSelection=!t.dueDate;if(t.locked!==undefined)c.locked=t.locked;c.title=t.title??c.title;c.priority=t.priority??c.priority;c.estimatedMinutes=t.estimatedMinutes??c.estimatedMinutes;c.status=t.completedAt?'completed':c.status||'pending';if(t.actualCompletedOn)c.actualCompletedOn=t.actualCompletedOn;if(t.dueDate&&t.dueDate<c.endDate)c.endDate=day(t.dueDate);if(t.deletedAt||t.archivedAt)c.status='cancelled';return c;}
function versionAt(r,date){return [...r.versions].reverse().find(v=>v.effectiveOn<=date);}
export function expand(rules,records,tasks,range,today){const result=[],byKey=new Map(records.map(o=>[o.id,o])),byTask=new Map(tasks.map(t=>[t.id,t]));
 const emit=(r,v,key,start,end,extra={})=>{const saved=byKey.get(key),t=saved?.taskId?byTask.get(saved.taskId):null;const defaults={id:key,ruleId:r.id,version:v.version,title:v.title,kind:v.kind,optional:v.optional,estimatedMinutes:v.estimatedMinutes,priority:v.priority,maxGapDays:v.maxGapDays,earlyDays:v.earlyDays,weekdays:v.weekdays,times:v.times,startDate:start,endDate:end,timezone:v.timezone,...extra},refresh=saved&&saved.version!==v.version&&!saved.taskId&&(saved.date||saved.startDate||start)>=today;const c=refresh?{...saved,...defaults,status:saved.status,locked:saved.locked,skipRecorded:saved.skipRecorded}:{...defaults,...saved};if(v.kind==='interval'){c.startDate=start;c.endDate=end;c.estimated=extra.estimated;c.earlyDays=v.earlyDays;c.maxGapDays=v.maxGapDays;c.sequence=extra.sequence;c.previousId=extra.previousId;c.earliestPossibleOn=extra.earliestPossibleOn;c.ruleEndDate=extra.ruleEndDate;c.effectiveUntil=extra.effectiveUntil;delete c.recalibrationConflict;delete c.previousWindow;const confirmedDate=saved?.date||t?.plannedDate;if(t&&!t.completedAt&&confirmedDate&&(confirmedDate<start||confirmedDate>end)){c.recalibrationConflict=true;c.previousWindow={startDate:saved.startDate,endDate:saved.endDate};}}taskFields(c,t);
 if(c.kind==='interval'&&c.status==='skipped'){c.skipRecorded=true;c.status='pending';}c.status=c.status||'pending';if(c.endDate<today&&!['completed','skipped','cancelled'].includes(c.status))c.status=['daily','weekly'].includes(c.kind)||c.optional?'missed':'overdue';if(c.endDate<range.startDate&&!['once','interval'].includes(c.kind))return;if((c.earliestPossibleOn||c.startDate)>range.endDate)return;result.push(c);if(result.length>200)throw Error('候选超过200项，请缩小日期范围或暂停部分规则');};
 for(const r of rules){const latest=versionAt(r,range.startDate)||r.versions.find(v=>v.effectiveOn<=range.endDate);if(!latest)continue;if(latest.kind==='once'){const v=latest;if(v.status==='active')emit(r,v,r.id+':once',v.startDate>v.effectiveOn?v.startDate:v.effectiveOn,v.endDate);continue;}
 if(latest.kind==='interval'){const v=latest;if(v.status!=='active')continue;const completed=records.filter(o=>o.ruleId===r.id&&byTask.get(o.taskId)?.completedAt).map(o=>({o,t:byTask.get(o.taskId)})).filter(x=>x.t.actualCompletedOn).sort((a,b)=>b.t.actualCompletedOn.localeCompare(a.t.actualCompletedOn)||a.o.id.localeCompare(b.o.id));const anchor=completed[0];let deadline=anchor?add(anchor.t.actualCompletedOn,v.maxGapDays):v.lastCompletedOn?add(v.lastCompletedOn,v.maxGapDays):v.firstDeadline;const firstSequence=anchor?integer(anchor.o.sequence,0,1000000,'间隔序号')+1:0;let n=0;
 const nextVersion=r.versions.find(x=>x.effectiveOn>v.effectiveOn),horizon=[range.endDate,v.endDate||range.endDate,nextVersion?add(nextVersion.effectiveOn,-1):range.endDate].sort()[0];
 let earliest=add(deadline,-v.earlyDays);if(earliest<v.startDate)earliest=v.startDate;if(earliest<v.effectiveOn)earliest=v.effectiveOn;
 while(earliest<=horizon){const sequence=firstSequence+n,key=r.id+':interval:'+sequence;const start=n?add(deadline,-v.earlyDays):earliest,end=[deadline,v.endDate||deadline,nextVersion?add(nextVersion.effectiveOn,-1):deadline].sort()[0];
 emit(r,v,key,start,end,{sequence,estimated:n>0,earliestPossibleOn:earliest,previousId:n? r.id+':interval:'+(sequence-1):null,ruleEndDate:v.endDate||null,effectiveUntil:nextVersion?add(nextVersion.effectiveOn,-1):null});
 if(deadline<range.startDate)break;deadline=add(deadline,v.maxGapDays);earliest=add(earliest,v.maxGapDays-v.earlyDays);if(++n>200)throw Error('间隔候选超过200项，请更新完成记录或缩小范围');}continue;}
 const weeks=new Set();for(let date=range.startDate;date<=range.endDate;date=add(date,1)){const v=versionAt(r,date);if(!v||v.status!=='active'||date<v.startDate||v.endDate&&date>v.endDate)continue;if(v.kind==='daily'){if(v.weekdays.includes(weekday(date)))emit(r,v,r.id+':daily:'+date,date,date);}else if(v.kind==='weekly'){const monday=add(date,1-weekday(date));if(weeks.has(monday))continue;weeks.add(monday);for(let n=0;n<v.perWeek;n++)emit(r,v,r.id+':weekly:'+monday+':'+n,v.startDate>monday?v.startDate:monday,v.endDate&&v.endDate<add(monday,6)?v.endDate:add(monday,6),{week:monday});}}}
 // Persisted history/confirmed instances survive pause, rule edits, and interval recalibration.
 for(const o of records)if(!result.some(x=>x.id===o.id)&&o.startDate<=range.endDate&&o.endDate>=range.startDate){const t=byTask.get(o.taskId);const c=taskFields({...o,status:o.status||'pending',outdated:true},t);if(c.endDate<today&&!['completed','skipped','cancelled'].includes(c.status))c.status=['daily','weekly'].includes(c.kind)||c.optional?'missed':'overdue';result.push(c);}
 if(result.length>200)throw Error('候选超过200项，请缩小范围');return result.sort((a,b)=>a.startDate.localeCompare(b.startDate)||a.id.localeCompare(b.id));}
export function availability(value){const a={timezone:'Asia/Shanghai',bufferMinutes:10,defaultMinutes:30,weekly:{},exceptions:{},busy:[],...value};integer(a.bufferMinutes,0,180,'缓冲');integer(a.defaultMinutes,1,1439,'默认耗时');for(const k of Object.keys(a.weekly)){integer(Number(k),1,7,'星期');a.weekly[k]=slots(a.weekly[k]);}for(const [d,s] of Object.entries(a.exceptions)){day(d);a.exceptions[d]=slots(s);}if(a.busy.length>500)throw Error('忙碌时段过多');for(const b of a.busy){day(b.date);slots([b]);}return a;}
export function arrange(candidates,a,range,busy,overrides={}){const assigned=[],unassigned=[],occupied=busy.map(x=>({...x})),loads={},buffer=a.bufferMinutes;const sorted=[...candidates].sort((x,y)=>Number(!x.locked)-Number(!y.locked)||Number(x.optional)-Number(y.optional)||x.endDate.localeCompare(y.endDate)||(Date.parse(x.endDate)-Date.parse(x.startDate))-(Date.parse(y.endDate)-Date.parse(y.startDate))||y.priority-x.priority||x.id.localeCompare(y.id));
 const ordered=[],byId=new Map(sorted.map(c=>[c.id,c])),visited=new Set();const visit=c=>{if(visited.has(c.id))return;visited.add(c.id);if(c.previousId&&byId.has(c.previousId))visit(byId.get(c.previousId));ordered.push(c);};sorted.forEach(visit);
 for(const original of ordered){let c={...original};if(c.previousId){const previous=assigned.find(x=>x.id===c.previousId)||(c.previousScheduledDate?{date:day(c.previousScheduledDate)}:null);if(!previous){unassigned.push({...c,reason:'前一次尚未安排，无法推演预计窗口'});continue;}const oldGap=c.earlyDays;c.endDate=add(previous.date,c.maxGapDays);c.startDate=add(c.endDate,-oldGap);if(c.ruleEndDate&&c.endDate>c.ruleEndDate)c.endDate=c.ruleEndDate;if(c.effectiveUntil&&c.endDate>c.effectiveUntil)c.endDate=c.effectiveUntil;if(c.task?.dueDate&&c.task.dueDate<c.endDate)c.endDate=c.task.dueDate;const oldDate=c.date||c.task?.plannedDate;if(c.task&&!c.task.completedAt&&oldDate&&(oldDate<c.startDate||oldDate>c.endDate)){c.recalibrationConflict=true;c.previousWindow=c.previousWindow||{startDate:original.startDate,endDate:original.endDate};}}
 const override=overrides[c.id],fixed=c.locked&&c.task?{date:c.localDate||c.task.plannedDate,start:c.localStart,end:c.localEnd}:override;
 let dates=[];for(let d=c.startDate>range.startDate?c.startDate:range.startDate;d<=c.endDate&&d<=range.endDate;d=add(d,1))if(c.weekdays.includes(weekday(d)))dates.push(d);dates.sort((x,y)=>c.kind==='interval'?y.localeCompare(x):(loads[x]||0)-(loads[y]||0)||x.localeCompare(y));let chosen;
 for(const d of dates){if(fixed&&fixed.date!==d)continue;if(c.reservedDates?.includes(d))continue;if(c.kind==='weekly'&&assigned.some(x=>x.ruleId===c.ruleId&&x.week===c.week&&x.date===d)||c.optional&&c.ruleId&&assigned.some(x=>x.ruleId===c.ruleId&&x.date===d))continue;const available=a.exceptions[d]??a.weekly[weekday(d)]??[];
 for(const allowed of c.times)for(const slot of available){const start=Math.max(minute(allowed.start),minute(slot.start)),end=Math.min(minute(allowed.end),minute(slot.end));for(let m=fixed?minute(fixed.start):Math.ceil(start/5)*5;m+c.estimatedMinutes<=end;m+=5){const finish=fixed?minute(fixed.end):m+c.estimatedMinutes;if(fixed&&(m<start||finish>end||finish<=m||finish-m!==c.estimatedMinutes))break;const blocked=occupied.some(b=>b.date===d&&(!c.taskId||b.id!==c.taskId)&&m<b.end+buffer&&finish+buffer>b.start);if(!blocked){chosen={...c,date:d,start:time(m),end:time(finish),priority:override?.priority??c.priority,locked:override?.locked??c.locked??false};break;}if(fixed)break;}if(chosen)break;}if(chosen)break;}
 if(chosen){assigned.push(chosen);occupied.push({date:chosen.date,start:minute(chosen.start),end:minute(chosen.end)});loads[chosen.date]=(loads[chosen.date]||0)+c.estimatedMinutes;}else unassigned.push({...c,reason:c.endDate<range.startDate?'已超期；原最晚日期保留，请明确修改窗口':fixed?'指定或锁定时段与窗口、可用时间或已有占用冲突':'当前未找到可行安排；可调整耗时、可用时段或允许窗口'});}
 return {assigned,unassigned};}

// A scheduling horizon is internal search state, never a user deadline.
export function taskCandidate(t,a,r){
 const dueDate=t.dueDate?day(t.dueDate):null;
 return {id:'task:'+t.id,taskId:t.id,ruleId:null,kind:'once',title:t.title,notes:t.notes||'',task:t,
  status:t.plannedStartAt?'confirmed':dueDate&&dueDate<r.startDate?'overdue':'pending',
  optional:false,locked:!!t.locked,timezone:a.timezone,priority:t.priority||0,
  estimatedMinutes:t.estimatedMinutes||a.defaultMinutes,weekdays:[1,2,3,4,5,6,7],
  times:[{start:'00:00',end:'23:59'}],startDate:r.startDate,endDate:dueDate||r.endDate,
  dueDate,requiresSelection:!dueDate,planningEndDate:r.endDate};
}
export function intervalsOverlap(a,b){return Date.parse(a.startAt)<Date.parse(b.endAt)&&Date.parse(b.startAt)<Date.parse(a.endAt);}

// Creation drafts deliberately contain relative rules, never historical task IDs.
export function creationDraft(value,today,timezone){
 const rules=value.rules||{},interval=rules.interval||{minDays:4,maxDays:6};
 if(Object.keys(rules).some(k=>!['interval','weekdays','timeWindow','optional','weekly','repeat'].includes(k)))throw Error('包含尚未支持的规则，请移除后重试');
 if(rules.weekly||rules.repeat||rules.optional)throw Error('此批量入口暂不支持该重复规则，请使用间隔规则');
 const minDays=integer(interval.minDays,1,366,'最小间隔'),maxDays=integer(interval.maxDays,minDays,366,'最大间隔');
 const v=rule({title:value.title,kind:'interval',startDate:value.firstDate||today,timezone:value.timezone||timezone,estimatedMinutes:value.estimatedMinutes??30,priority:value.priority??0,maxGapDays:maxDays,earlyDays:maxDays-minDays,firstDeadline:value.firstDate||today,weekdays:rules.weekdays||[1,2,3,4,5,6,7],times:[rules.timeWindow||{start:'09:00',end:'21:00'}]});
 if(value.days!==undefined&&value.days!==30)throw Error('滚动规划窗口固定为未来30天');
 if(value.autoExtend!==undefined&&typeof value.autoExtend!=='boolean')throw Error('持续补齐需为开关');
 if(value.notes!==undefined&&(typeof value.notes!=='string'||value.notes.length>10000))throw Error('任务描述最多10000字');
 return {title:v.title,notes:value.notes||'',estimatedMinutes:v.estimatedMinutes,priority:v.priority,timezone:v.timezone,firstDate:v.startDate,days:30,autoExtend:value.autoExtend!==false,rules:{interval:{minDays,maxDays},weekdays:v.weekdays,timeWindow:v.times[0]}};
}

export function arrangeCreation(draft,{seriesId='draft',startDate,endDate,records=[],tasks=[],a,busy=[],adjustments=[]}){
 let fixedSnapshots=null;
 if(adjustments.length){
  const baseline=arrangeCreation(draft,{seriesId,startDate,endDate,records,tasks,a,busy});fixedSnapshots=Object.fromEntries(baseline.assigned.map(c=>[c.id,{date:c.date,start:c.start,end:c.end}]));
  for(const adjustment of adjustments){const current=baseline.assigned.find(c=>c.id===adjustment.id);if(!current)continue;
   if(adjustment.scope==='following'){if(adjustments.some(x=>x.id!==adjustment.id&&baseline.assigned.some(c=>c.id===x.id&&c.sequence>current.sequence)))throw Error('后续已有手动安排，请仅调整本次或先还原后续修改');const delta=Math.round((Date.parse(day(adjustment.date))-Date.parse(current.date))/86400000),offset=minute(adjustment.start)-minute(current.start);for(const c of baseline.assigned.filter(c=>c.sequence>current.sequence)){const from=minute(c.start)+offset,to=minute(c.end)+offset;if(from<0||to>=1440)throw Error('联动后的时段跨午夜，请调整时间');fixedSnapshots[c.id]={date:add(c.date,delta),start:time(from),end:time(to)};}}
   fixedSnapshots[adjustment.id]=adjustment;
  }
 }
 const byTask=new Map(tasks.map(t=>[t.id,t])),history=records.filter(o=>o.seriesId===seriesId).sort((x,y)=>x.sequence-y.sequence),latest=history[history.length-1];
 const assigned=[],unassigned=[],conflicts=[],warnings=[],occupied=busy.map(b=>({...b}));
 const interval=draft.rules.interval,min=interval.minDays,max=interval.maxDays;
 let previous=latest?(byTask.get(latest.taskId)?.plannedDate||latest.date):null,sequence=latest?latest.sequence+1:0;
 const seen=new Set();
 for(const adjustment of adjustments){if(!adjustment||typeof adjustment.id!=='string'||seen.has(adjustment.id))throw Error('调整实例重复或无效');seen.add(adjustment.id);day(adjustment.date);if(minute(adjustment.start)>=minute(adjustment.end))throw Error('调整时段不能跨午夜');if(adjustment.scope&&!['only','following'].includes(adjustment.scope))throw Error('调整范围无效');}
 const effective={...a,weekly:Object.keys(a.weekly).length?a.weekly:Object.fromEntries([1,2,3,4,5,6,7].map(d=>[d,[draft.rules.timeWindow]]))};
 for(let n=0;n<200;n++,sequence++){
  let from=previous?add(previous,min):draft.firstDate>startDate?draft.firstDate:startDate,to=previous?add(previous,max):add(from,max-1);
  if(from<startDate)from=startDate;
  if(to<startDate){to=add(startDate,max-min);warnings.push('上次安排距今已超出最大间隔；保留原任务，从今天继续规划');}
  if(from>endDate)break;if(to>endDate)to=endDate;
  const id=seriesId+':batch:'+sequence,override=fixedSnapshots?.[id]||adjustments.find(x=>x.id===id),c={id,seriesId,sequence,index:sequence+1,ruleId:null,kind:previous?'interval':'once',title:draft.title,notes:draft.notes,estimatedMinutes:draft.estimatedMinutes,priority:draft.priority,timezone:draft.timezone,optional:false,weekdays:draft.rules.weekdays,times:[draft.rules.timeWindow],startDate:from,endDate:to,windowStart:from,windowEnd:to,maxGapDays:max,earlyDays:max-min};
  if(override&&minute(override.end)-minute(override.start)!==draft.estimatedMinutes){unassigned.push({...c,reason:'调整时长与任务耗时不同，请修改结束时间'});break;}
  const planned=arrange([c],effective,{startDate,endDate},occupied,override?{[id]:override}:{});
  if(!planned.assigned.length){unassigned.push({...c,reason:planned.unassigned[0]?.reason||'此窗口没有可用时间'});break;}
  const chosen=planned.assigned[0];if(adjustments.some(x=>x.id===id||x.scope==='following'&&Number(x.id.split(':').pop())<sequence))chosen.manualAdjusted=true;assigned.push(chosen);occupied.push({date:chosen.date,start:minute(chosen.start),end:minute(chosen.end)});previous=chosen.date;
 }
 for(const id of seen)if(!assigned.some(c=>c.id===id)&&!unassigned.some(c=>c.id===id))conflicts.push('调整实例已不在当前30天窗口：'+id);
 if(!latest&&draft.firstDate>endDate)conflicts.push('首次日期超出未来30天，请选择窗口内的日期');
 return {assigned,unassigned,conflicts,warnings};
}
