import {services,ui,files} from '@xudian/sdk';
import {draftFromBackup} from './import.js';
import {exportBackup} from './schedule_queries.js';
import {ref} from './schedule_commands.js';
import {field,text} from './page_controls.js';
import {importSummary,importFieldLabels,importValue} from './view_helpers.js';
import {action,courseRow,fact,fixedActions,pageResult,section,summary} from './course_layout.js';

async function offerImportedSchedule(result,state) {
  try {
    const answer=await ui.dialog({title:'导入完成',description:'课程已保存，是否打开课表？',submitLabel:'打开课表',fields:[]});
    if(answer) await ui.navigate('app.schedule.home',{timetableId:result.timetableId});
  } catch(error) {state.notice='导入已保存，暂时无法打开课表：'+error.message;}
}

function importConflictField(conflict,choices,draft) {
  const basis=conflict.key==='timetable:timeBasis';
  const describe=value=>importValue(conflict.field,value);
  const subtitle=basis?conflict.field:'冲突字段 · '+(importFieldLabels[conflict.field]||conflict.field);
  const id=conflict.key.slice(conflict.collection.length+1,-conflict.field.length-1);
  const raw=draft[conflict.collection]?.find(row=>row.sourceId===id);
  const courseId=raw?.courseId||draft.meetings?.find(meeting=>meeting.sourceId===raw?.meetingId)?.courseId;
  const title=raw?.name||draft.courses?.find(course=>course.sourceId===courseId)?.name||draft.timetable.name;
  const options=conflict.options?conflict.options.map(value=>({value,label:value==='extra'?'保留为临时课':'撤销失效调课',subtitle:describe(conflict.local),icon:'calendar'})):[
    {value:'local',label:basis?'保留目标基准，重新解释导入周次/节次':'保留本地',subtitle:describe(conflict.local),icon:'location'},
    {value:'source',label:basis?'采用来源基准，影响目标内全部课程':'采用来源',subtitle:describe(conflict.source),icon:'location'}
  ];
  return {...field(conflict.key,'保留哪一项',choices[conflict.key]||conflict.options?.[0]||(basis?'':'local'),'select',options),
    presentation:'list',summary:{title,subtitle,icon:'school'},required:true};
}

export async function handleImport({page,t,state,context,event,selectTimetable}) {
  if(event?.type==='export') await files.saveText(`${t.name}.json`,JSON.stringify(await exportBackup({timetableId:t.id}),null,2));
  if(event?.type==='import') {
    const raw=await files.readText();
    if(raw) {state.importDraft=draftFromBackup(JSON.parse(raw));delete state.importPlan;delete state.importSummary;delete state.importInput;delete state.importError;}
  }
  if(page==='app.schedule.home' && (context.importPlanId||context.draft) && !state.importRouted) {
    state.importRouted=true; await ui.navigate('app.schedule.imports',{...context,timetableId:t?.id});
  }
  if(page!=='app.schedule.home' && context.importPlanId && !state.adapterHandled) {
    state.adapterPlan=await services.adopt(context.importPlanId); state.adapterHandled=true;
  }
  if(event?.type==='cancelAdapter') {delete state.adapterPlan;state.notice='已取消导入，课表未修改';}
  if(event?.type==='confirmAdapter' && state.adapterPlan && !state.adapterPlan.result.blocked) {
    try {
      if(await ui.review(state.adapterPlan.planId)) {
        const result=await services.commit(state.adapterPlan.planId);
        state.timetableId=result.timetableId; selectTimetable(result.timetableId); delete state.adapterPlan;state.notice='导入已保存';
        await offerImportedSchedule(result,state);
      }
    } catch(error) {state.importError='导入预览已失效或无法保存，请重新预览：'+error.message;delete state.adapterPlan;}
  }
  if(page!=='app.schedule.home' && context.draft&&!state.importDraft&&!state.importFinished) state.importDraft=context.draft;
  if(event?.type==='cancelImport') { delete state.importDraft;delete state.importPlan;delete state.importSummary;delete state.importInput;delete state.importError;state.importFinished=true; }
  if((event?.type==='saveImport'||event?.type==='previewImport') && state.importDraft) {
    const modes=[{value:'new',label:'新建课表',icon:'add'},...(t?[
      {value:'merge',label:'合并当前课表',icon:'importExport',subtitle:t.name},{value:'replaceSource',label:'替换指定来源',icon:'importExport'}
    ]:[])];
    const values=await ui.dialog({title:'导入方式',presentation:'sheet',fullWidthActions:true,
      fields:[{...field('mode','导入目标',state.importInput?.mode||(t?'merge':'new'),'select',modes),presentation:'list',required:true}]});
    if(values) {
      state.importInput={draft:state.importDraft,targetTimetableId:t?.id,mode:values.mode,choices:{}};
      const plan=await services.prepare(ref('schedule.import.prepare'),state.importInput);
      state.importPlan={planId:plan.planId,result:plan.result};state.importSummary=await importSummary(plan,state.importDraft);delete state.importError;
    }
  }
  if(event?.type==='resolveImport' && state.importPlan?.result.conflicts?.length) {
    const choices=await ui.dialog({title:'来源和本地修改冲突',presentation:'sheet',fullWidthActions:true,submitLabel:'重新预览',fields:state.importPlan.result.conflicts.map(conflict=>importConflictField(conflict,state.importInput.choices,state.importDraft))});
    if(choices) {
      state.importInput={...state.importInput,choices:{...state.importInput.choices,...choices}};
      const plan=await services.prepare(ref('schedule.import.prepare'),state.importInput);
      state.importPlan={planId:plan.planId,result:plan.result};state.importSummary=await importSummary(plan,state.importDraft);delete state.importError;
    }
  }
  if(event?.type==='confirmImport' && state.importPlan && !state.importPlan.result.blocked) {
    try {
      if(await ui.review(state.importPlan.planId)) {
        const result=await services.commit(state.importPlan.planId);state.timetableId=result.timetableId;selectTimetable(result.timetableId);state.importFinished=true;state.notice='导入已保存';delete state.importDraft;delete state.importPlan;delete state.importSummary;delete state.importInput;
        await offerImportedSchedule(result,state);
      }
    } catch(error) {state.importError='导入预览已失效或无法保存，请重新预览：'+error.message;delete state.importPlan;}
  }
}

export async function renderImports({t,state,children}) {
  let actions=[],planReview;
  if(!state.importPlan?.result.blocked)children.push(summary(t?.name||'新建课表',t?'当前导入目标':'导入 JSON 备份后创建新课表','calendar',null,false,t?{type:'chooseTimetable'}:null),
    section('备份文件',[
      courseRow('JSON 导入','选择课表备份并预览','download',{type:'import'}),
      ...(t?[courseRow('JSON 导出','导出课程、安排与单次变更','upload',{type:'export'})]:[])
    ]));
  if(state.importError)children.push({type:'notice',tone:'error',text:state.importError});
  if(state.adapterPlan) {
    const totals=await importSummary(state.adapterPlan,null);
    children.push(section('教务适配器导入预览',[fact('实际变更',`新增 ${totals.added} 项 · 修改 ${totals.updated} 项 · 删除 ${totals.deleted} 项`),
      fact('检查结果',`冲突 ${totals.conflicts.length} 项 · 警告 ${totals.warnings.length} 项`),...totals.warnings.map(text),...totals.details]));
    actions=[action('取消导入',{type:'cancelAdapter'},true)];
    if(!state.adapterPlan.result.blocked) {
      actions.push(action('确认导入',{type:'confirmAdapter'}));planReview={planId:state.adapterPlan.planId,eventType:'confirmAdapter'};
    }
  }
  if(state.importDraft) {
    const totals=state.importSummary||await importSummary(null,state.importDraft);
    const rows=[fact('备份内容',`${totals.courses} 门课程 · ${totals.meetings} 个周期安排`),fact('单次变更',totals.changes+' 条'),
      fact('来源范围',state.importDraft.complete?'完整结果':'局部结果')];
    if(state.importPlan)rows.push(fact('实际变更',`新增 ${totals.added} 项 · 修改 ${totals.updated} 项 · 删除 ${totals.deleted} 项`),
      fact('检查结果',`冲突 ${totals.conflicts.length} 项 · 警告 ${totals.warnings.length} 项`));
    children.push(section('导入预览',rows),...totals.warnings.map(message=>({type:'notice',tone:'warning',text:message})));
    if(state.importPlan) {
      if(totals.details.length)children.push(section('实际变更',totals.details));
      children.push(section('导入方式',[courseRow('重新选择方式并预览',null,'importExport',{type:'saveImport'})]));
    } else {
      children.push(section('备份内容',[{type:'disclosure',text:'查看原始数据',icon:'code',children:[{type:'source',text:JSON.stringify(state.importDraft,null,2)}]}]));
    }
    actions=[action('取消导入',{type:'cancelImport'},true)];
    if(!state.importPlan)actions.push(action('选择方式并预览',{type:'saveImport'}));
    else if(totals.conflicts.length)actions.push(action('处理导入冲突',{type:'resolveImport'}));
    else if(!state.importPlan.result.blocked) {
      actions.push(action('确认保存导入',{type:'confirmImport'}));planReview={planId:state.importPlan.planId,eventType:'confirmImport'};
    }
  }
  const result=pageResult(state,'导入与备份',children,{...(actions.length?fixedActions(...actions):{}),...(planReview?{planReview}:{})});
  if(state.adapterHandled)delete result.header;
  return result;
}
