import {card,column,footer,group,heading,input,text,tile} from './ui.js';
import {importLocation,locationModes,locationSettings,locationSummary} from './locations.js';

export const semesterFormKeys=['name','firstMonday','totalWeeks','displayWeekStart','complete'];
export const modeOptions=[{value:'merge',label:'合并课程',subtitle:'保留其他安排'},{value:'replaceSource',label:'替换该来源的课程'}];
const showMode=mode=>modeOptions.find(option=>option.value===mode)?.label||'新建课表';
const select=(key,text,value,items,event)=>({type:'select',presentation:'labeled',key,text,value,items,event:{type:event}});

export function semesterPage({configuration}) {
  const {base,settings}=configuration;
  const mode=modeOptions.find(option=>option.value===settings.mode);
  const modeDescription=mode?.subtitle?`${mode.label}，${mode.subtitle}`:mode?.label;
  return {
    footer:footer('生成导入预览','saveSemester'),
    body:column([
      heading('学期信息'),
      input('name','课表名称',settings.name,{presentation:'labeled'}),
      {type:'dateInput',key:'firstMonday',text:'第一教学周',presentation:'labeled',editable:false,value:settings.firstMonday,event:{type:'semesterDate'}},
      {type:'row',layout:'flex',children:[
        input('totalWeeks','学期周数',String(settings.totalWeeks),{presentation:'labeled',inputMode:'number',integer:true,min:1,max:100,flex:1}),
        {...select('displayWeekStart','每周起始日',String(settings.displayWeekStart),[{value:'1',label:'周一'},{value:'7',label:'周日'}],'semesterField'),flex:1},
      ]},
      ...(base?[
        heading('导入范围'),
        {...card(
          {...tile('导入方式',{subtitle:modeDescription,icon:'importExport',event:{type:'editImportMode'}}),trailingIcon:'down'},
          {type:'divider',height:1},
          {type:'switch',key:'complete',text:'采集结果包含本学期全部课程',subtitle:'替换来源时用于识别已消失的课程。',value:settings.complete,event:{type:'semesterField'}},
        ),padding:0},
      ]:[]),
      heading('地点与来源'),
      group(
        tile('地点处理',{subtitle:locationSummary(settings),icon:'location',event:{type:'locations'}}),
        tile('来源标识',{subtitle:settings.scope||'自动识别学校与学期',icon:'link',event:{type:'editScope'}}),
      ),
    ]),
  };
}

export function pastePage(state) {
  return {
    footer:footer('使用此脚本','applyScript'),
    body:column([
      heading('学校脚本'),
      {type:'sourceEditor',key:'scriptText',value:state.script||'',text:'学校脚本',hintText:'粘贴学校适配器完整 JavaScript',presentation:'code',minLines:8,maxLines:16},
      text('脚本仅在当前会话保留。采集后先预览课程，再确认是否导入。','muted'),
    ]),
  };
}

export function locationExamples(payload,options) {
  let settings;
  try {settings=locationSettings(options);} catch {return [];}
  const rows=Array.isArray(payload)?payload:payload?.courses;
  if (!Array.isArray(rows)) return [];
  const examples=new Map();
  for (const row of rows) {
    if (typeof row?.position!=='string' || !row.position.trim()) continue;
    const result=importLocation(row.position,settings);
    if (settings.locationMode!=='keep' && result===row.position) continue;
    examples.set(row.position,result||'（不导入地点）');
    if (examples.size===3) break;
  }
  return [...examples];
}

export function locationsPage({locationDraft,configuration,payload}) {
  const {locationMode,campusNames}=locationDraft;
  const examples=locationExamples(configuration?.payload??payload,locationDraft);
  const subtitles=['按教务系统原文导入','保留楼栋与教室编号','导入后地点留空'];
  return {
    footer:footer(configuration?'应用':'应用到预览','applyLocations'),
    body:column([
      heading('地点处理'),
      group(...locationModes.map((mode,index)=>({
        ...tile(index===1?'去掉校区名称':mode.label,{subtitle:subtitles[index],icon:['location','edit','close'][index],
          event:{type:'locationMode',value:mode.value},trailing:false,selected:locationMode===mode.value}),
        ...(locationMode===mode.value?{trailingIcon:'check'}:{}),
      }))),
      ...(locationMode==='removeCampus'?[heading('要去掉的校区名称'),input('campusNames','每行一个',campusNames,{presentation:'labeled',multiline:true,minLines:1,maxLines:6,onChangeEvent:{type:'editCampusNames'}})]:[]),
      ...(examples.length?[heading('处理示例'),group(...examples.map(([original,result])=>tile(result,{icon:'location',subtitle:`原地点 · ${original}`})))]:[]),
      text(locationMode==='removeCampus'&&!examples.length&&campusNames.trim()?'未匹配填写的校区名称，原地点保留。':'仅匹配地点开头或末尾的完整校区名。更改后可在草稿中复核。','muted'),
    ]),
  };
}

const conflictFields={
  location:'上课地点',teacher:'教师',name:'名称',code:'课程代码',notes:'备注',color:'颜色',credit:'学分',
  weeks:'教学周',weekday:'星期',startPeriod:'开始节次',endPeriod:'结束节次',firstMonday:'第一教学周',
  totalWeeks:'教学周数',timezone:'时区',displayWeekStart:'每周起始日',periods:'节次作息',delete:'来源中已移除',
};
const showConflictValue=value=>typeof value==='string'?value:value==null?'无':JSON.stringify(value);
export function conflictOptions(conflict) {
  if (conflict.options) return conflict.options.map(value=>({value,label:value==='extra'?'保留为临时课':'撤销失效调课',subtitle:showConflictValue(conflict.local)}));
  const basis=conflict.key==='timetable:timeBasis';
  return [
    {value:'local',label:'保留本地',subtitle:`${basis?'按目标基准重新解释导入课程\n':''}${showConflictValue(conflict.local)}`},
    {value:'source',label:'采用来源',subtitle:`${basis?'影响目标内全部课程\n':''}${showConflictValue(conflict.source)}`},
  ];
}

function conflictTitle(conflict,courses,meetings) {
  if (conflict.key==='timetable:timeBasis') return '首次导入时间基准';
  const prefix=`${conflict.collection}:`;
  const sourceId=conflict.key.slice(prefix.length,-(conflict.field.length+1));
  const course=courses.get(sourceId)||courses.get(meetings.get(sourceId));
  return [course,conflictFields[conflict.field]||conflict.field].filter(Boolean).join(' · ');
}

export function conflictsPage(state) {
  const {conflicts,warnings}=state.plan.result;
  const courses=new Map(state.input.draft.courses.map(course=>[course.sourceId,course.name]));
  const meetings=new Map(state.input.draft.meetings.map(meeting=>[meeting.sourceId,meeting.courseId]));
  const items=conflicts.map((conflict,index)=>column([
    card(column([text(conflictTitle(conflict,courses,meetings),'heading'),text(conflict.key==='timetable:timeBasis'?'来源与目标课表的时间基准不同。':'本地与导入来源都修改了同一个字段。','muted')])),
    heading('保留哪一项'),
    group(...conflictOptions(conflict).map(({value,label,subtitle})=>{
      const selected=state.conflictChoices[conflict.key]===value;
      return {
        ...tile(label,{subtitle,icon:value==='source'?'school':'edit',event:{type:'pickConflict',index,value},selected,trailing:false}),
        ...(selected?{trailingIcon:'check'}:{}),
      };
    })),
  ]));
  return {
    footer:footer('重新查看实际变更','applyConflicts'),
    body:column([
      heading('待处理冲突',{count:`${conflicts.length} 项`,countPosition:'end',compact:true}),...items,
      ...(warnings||[]).filter(warning=>!state.input.draft.warnings.includes(warning)).map(warning=>text(warning,'muted')),
      text('选择后会重新生成变更计划，确认导入前仍可返回。','muted'),
    ]),
  };
}

export function previewPage(state) {
  const {draft,mode}=state.input;
  const {timetable}=draft;
  const blocked=state.plan?.result?.blocked;
  const warnings=new Set([...draft.warnings,...(state.plan?.result?.warnings||[])]);
  const metrics=[[draft.courses.length,'课程'],[draft.meetings.length,'上课安排'],[timetable.totalWeeks,'教学周']];
  return {
    footer:footer(blocked?'处理导入冲突':'查看实际变更',blocked?'conflicts':'preview'),
    body:column([
      {...card({type:'row',layout:'flex',spacing:12,children:[
        {type:'icon',icon:'calendar',surface:true,surfaceSize:44},
        column([text(timetable.name,'heading'),text(`第一周 ${timetable.firstMonday} · 每天 ${timetable.periods.length} 节`,'muted')],{flex:1,spacing:4}),
      ]}),padding:14},
      {type:'card',tone:'selected',padding:12,children:[{type:'row',layout:'flex',children:metrics.map(([value,label])=>column([
        {...text(String(value),'headline'),align:'center',color:'primary'},
        {...text(label,'caption'),align:'center'},
      ],{flex:1,spacing:2}))}]},
      heading('本次导入'),
      group(
        tile('目标课表',{trailing:state.options?.targetName||timetable.name}),
        tile('导入方式',{trailing:showMode(mode)}),
        tile('来源',{trailing:state.options?.scopeAlias||'自动识别学校与学期'}),
        ...(state.payload?[tile('处理地点',{subtitle:locationSummary(state.options),icon:'location',event:{type:'locations'}})]:[]),
      ),
      heading('配置'),
      group(
        ...(state.payload?[tile('修改学期配置',{icon:'tune',event:{type:'configure'}})]:[]),
        {...tile('取消本次导入',{icon:'close',event:{type:'clear'}}),tone:'danger'},
      ),
      text('课程尚未保存。下一步可核对新增、修改和冲突。','muted'),
      ...(blocked?[{type:'notice',text:`${state.plan.result.conflicts.length} 项冲突需要处理`,tone:'warning'}]:[]),
      ...(state.timezoneNotice?[text(state.timezoneNotice,'muted')]:[]),
      ...[...warnings].filter(warning=>!state.timezoneNotice?.startsWith(warning)).map(warning=>text(warning,'muted')),
    ]),
  };
}
