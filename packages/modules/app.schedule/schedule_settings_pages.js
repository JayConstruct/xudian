import {data,clock} from '@xudian/sdk';
import {validateTimetable} from './calendar.js';
import {snapshot} from './schedule_queries.js';
import {command} from './schedule_commands.js';
import {button,go,text} from './page_controls.js';
import {defaultPeriods,periodDraft,semesterDraft,resetPeriodDraft,resetSemesterDraft,scheduleRowHeight,scheduleShowWeekends,periodError,periodDraftDirty,periodBaselineMatches,periodTableValue,periodTableBaseline,hydratePeriodDraft,periodDraftTimetable,periodDraftError,appendPeriods,timeMinutes,timeString,listTile} from './view_helpers.js';

function group(title, rows) {
  const children=rows.flatMap((row,i)=>i?[{type:'divider'},row]:[row]);
  return {type:'column',compact:true,spacing:4,children:[...(title?[{type:'sectionHeader',title}]:[]),{type:'card',children}]};
}

export async function updateSemester({t,state,event,formValues}) {
  const draft=semesterDraft(t);
  if(event?.type==='toggleTimezone')state.timezoneAdvanced=!state.timezoneAdvanced;
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

export async function updatePeriods({t,state,event,formValues}) {
  const draft=periodDraft(t);
  if(event?.type!=='resetPeriods'&&event?.type!=='chooseTimetable') {
    try {hydratePeriodDraft(draft,formValues[`periods.table.${t.id}`]);}catch(error){draft.error=error.message;}
  }
  if(event?.type==='periodTime') {
    const row=draft.periods.find(p=>p.number===event.number);
    if(row && ['start','end'].includes(event.part)) {
      row[event.part]=String(event.value);
      if(event.part==='end'&&!draft.manualEnds.includes(row.number))draft.manualEnds.push(row.number);
      if(event.part==='start'&&!draft.manualEnds.includes(row.number)) {
        try {const end=timeMinutes(row.start)+Number(draft.durationMinutes);row.end=end<1440?timeString(end):'';}catch(_){}
      }
    }
    draft.error=null;delete state.notice;
  }
  if(event?.type==='addPeriod') {
    try {
      if(draft.periods.length>=30)throw new Error('最多配置30个节次');
      const start=draft.periods.length?timeMinutes(draft.periods.at(-1).end)+5:8*60;
      const duration=Number(draft.durationMinutes);if(!/^\d+$/.test(draft.durationMinutes)||duration<1||duration>1440)throw new Error('每节时长需为1–1440分钟的整数');
      draft.periods.push({number:draft.periods.length+1,start:timeString(start),end:timeString(start+duration)});draft.error=null;
    } catch(error) {draft.error=error.message;}
  }
  if(event?.type==='removePeriod') {
    const filter={field:'timetableId',op:'eq',value:t.id},meetings=await data.query('meetings',{filter}),changes=await data.query('occurrenceChanges',{filter});
    if(event.number!==draft.periods.length)draft.error='只能删除最后一个节次，请先删除末尾未使用的节次';
    else if(meetings.some(m=>m.endPeriod>=event.number)||changes.some(c=>c.kind!=='cancel'&&c.endPeriod>=event.number)) draft.error=`第 ${event.number} 节或其后的节次已被课程安排或调课引用，请先调整课程。`;
    else if(draft.periods.length<=1) draft.error='至少保留一个节次';
    else {draft.periods=draft.periods.filter(p=>p.number!==event.number).map((p,i)=>({...p,number:i+1}));draft.manualEnds=draft.manualEnds.filter(number=>number!==event.number);draft.error=null;}
  }
  if(event?.type==='resetPeriods') {resetPeriodDraft(t);delete state.notice;}
  if(event?.type==='savePeriods') {
    try {
      if(!periodBaselineMatches(t,draft))throw new Error('作息已在其他页面修改。草稿已保留，请重新载入后编辑。');
      const value=periodDraftTimetable(t,draft),error=await periodError(value,draft.periods);if(error)throw new Error(error);
      const saved=await command('schedule.timetable.save',{timetable:value,expectedTimetable:t});
      if(saved) {resetPeriodDraft(await data.get('timetables',t.id));state.notice='作息设置已保存';}
    } catch(error) {draft.error=error.message;}
  }
  if(event?.type==='templatePeriods'||event?.type==='appendPeriods') {
    try {
      const periods=event.type==='templatePeriods'?defaultPeriods.map(p=>({...p})):appendPeriods(t.periods);
      if(JSON.stringify(periods)===JSON.stringify(t.periods)) {state.notice='当前作息已包含12个或更多节次';}
      else {
        const value=periodDraftTimetable(t,{...draft,periods,...(event.type==='templatePeriods'?{manualEnds:[],durationMinutes:'45'}:{})});
        const error=await periodError(value,periods);if(error)throw new Error(error);
        const saved=await command('schedule.timetable.save',{timetable:value,expectedTimetable:t});
        if(saved) {resetPeriodDraft(await data.get('timetables',t.id));state.notice=event.type==='templatePeriods'?'已应用12节作息模板':'已保留现有作息并补足至12节';}
      }
    } catch(error) {draft.error=error.message;}
  }
}

export async function renderSettings({t,timetables,state,children}) {
  const counts=t?await snapshot(t.id):{courses:[],meetings:[],changes:[]};
  children.push(group(null,[
    listTile(t?.name||'还没有课表',t?`${t.firstMonday} 起 · ${t.totalWeeks} 周`:'新建或导入课表后开始使用','calendar',t?{type:'chooseTimetable'}:{type:'navigate',page:'timetables'}),
    listTile('课程与安排',`${counts.courses.length} 门课程 · ${counts.meetings.length} 个周期安排 · ${counts.changes.length} 条调课`,'school',null,'')
  ]));
  children.push(group('课表配置',[go('学期设置','semester','名称、学期日期、周数与高级设置','tune'),go('作息设置','periods',t?`${t.periods.length} 个节次，按上午、下午和晚间编辑`:'设置各节次起止时间','schedule'),go('显示设置','display',t?`${scheduleShowWeekends(t)?'显示周末':'仅工作日'} · 课表总高度 ${48+t.periods.length*scheduleRowHeight(t)}`:'周末显示与课表总高度','tune'),go('课表管理','timetables',`${timetables.length} 张课表，可切换、新建或删除`,'list')]));
  children.push(group('课程与数据',[go('今日课程','today','查看今天的课程与上课时间','calendar'),go('课程管理','courses','课程信息与周期上课安排','school'),go('调课记录','changes','取消、移动与临时加课','history'),go('导入与备份','imports','JSON 备份与教务导入','importExport'),listTile('添加示例课表','独立课表，每天 3 门课程；重复添加会保留现有内容','school',{type:'createDemo'})]));
  return {state,tree:{type:'column',children}};
}

export function renderTimetables({t,timetables,state,children}) {
  children.push({type:'sectionHeader',title:'我的课表',count:timetables.length,action:{label:'新建课表',icon:'add',event:{type:'newTimetable'}}});
  for(const table of timetables) children.push(group(table.name,[listTile(table.id===t?.id?'当前课表':'选择课表',`${table.firstMonday} 起 · ${table.totalWeeks} 周`,'calendar',{type:'select',id:table.id}),listTile('删除课表','删除前展示实际变更并确认','history',{type:'delete',collection:'timetables',id:table.id})]));
  return {state,tree:{type:'column',children}};
}

export function renderSemester({t,state,event,children}) {
  const draft=semesterDraft(t),labels={name:'课表名称',firstMonday:'第一教学周周一（YYYY-MM-DD）',totalWeeks:'总教学周数'};
  children.push({type:'sectionHeader',title:'学期信息',subtitle:t.name});
  for(const [key,label] of Object.entries(labels))children.push({type:'input',key:`semester.${t.id}.${key}`,text:label,value:draft.values[key],onChangeEvent:{type:'semesterField',field:key}});
  children.push({type:'sectionHeader',title:'每周起始日'},{type:'segmented',selectedIndex:draft.values.displayWeekStart==='7'?1:0,items:[{label:'周一起始',event:{type:'semesterField',field:'displayWeekStart',value:'1'}},{label:'周日起始',event:{type:'semesterField',field:'displayWeekStart',value:'7'}}]});
  children.push(listTile(state.timezoneAdvanced?'收起高级设置':'高级设置','课表时间基准',null,{type:'toggleTimezone'}));
  if(state.timezoneAdvanced)children.push({type:'input',key:`semester.${t.id}.timezone`,text:'课表时区',value:draft.values.timezone,onChangeEvent:{type:'semesterField',field:'timezone'}},text('修改时区会影响课程对应的实际时间，保存前请核对。'));
  const dirty=JSON.stringify(draft.values)!==draft.baseline;
  state.semesterDraft={...draft,dirty};
  if(dirty)children.push(text('尚未保存。离开页面后草稿会保留，保存前会审核实际变更。'));
  if(draft.error)children.push(text(draft.error));
  const replaceForms=event?.type==='resetSemester'||event?.type==='chooseTimetable'?Object.fromEntries(Object.entries(draft.values).map(([key,value])=>[`semester.${t.id}.${key}`,value])):{};
  return {state,replaceForms,tree:{type:'column',children,footer:{type:'row',children:[{...button('重新载入',{type:'resetSemester'}),disabled:!dirty},{...button('保存学期设置',{type:'saveSemester'}),disabled:!dirty}]}}};
}

export function renderPeriods({t,state,children}) {
  const draft=periodDraft(t),dirty=periodDraftDirty(draft),validation=periodDraftError(t,draft),key=`periods.table.${t.id}`;
  state.periodsDraft={...draft,dirty,error:draft.error||validation};
  const value={...periodTableValue(draft),dirty,saveDisabled:!dirty||!!validation,resetDisabled:!dirty,error:validation};
  children.push(group(null,[listTile('当前课表',t.name,'calendar',null,'')]));
  const groups=[{label:'上午',ids:[]},{label:'下午',ids:[]},{label:'晚间',ids:[]}];
  for(const row of draft.periods) {
    const start=timeMinutes(row.start);
    groups[start<720?0:start<1080?1:2].ids.push(String(row.number));
  }
  children.push({type:'timeRangeTable',key,value,baseline:periodTableBaseline(draft),groups:groups.filter(g=>g.ids.length)});

  if(draft.error)children.push(text(draft.error));
  children.push(group('节次与模板',[
    listTile('添加节次','按每节时长在末尾增加节次','schedule',{type:'addPeriod'}),
    listTile('删除末尾节次',null,'history',{type:'removePeriod',number:draft.periods.length}),
    listTile('使用12节作息模板','替换当前起止时间，经过实际变更审核后保存','schedule',{type:'templatePeriods'}),
    ...(t.periods.length<12?[listTile('补足至12节','保留现有起止时间，仅在末尾追加节次','schedule',{type:'appendPeriods'})]:[])
  ]));
  return {state,replaceForms:{[key]:value},tree:{type:'column',children,footer:{type:'row',children:[{...button('放弃草稿',{type:'resetPeriods'}),disabled:{bind:['formValues',key,'resetDisabled']}},{...button('保存作息设置',{type:'savePeriods'}),disabled:{bind:['formValues',key,'saveDisabled']}}]}}};
}
