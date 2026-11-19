import {services,ui,files} from '@xudian/sdk';
import {draftFromBackup} from './import.js';
import {exportBackup} from './schedule_queries.js';
import {ref} from './schedule_commands.js';
import {button,field,text} from './page_controls.js';
import {group,importSummary,listTile} from './view_helpers.js';

async function offerImportedSchedule(result,state) {
  try {
    const answer=await ui.dialog({title:'导入完成',description:'课程已保存，是否打开课表？',submitLabel:'打开课表',fields:[]});
    if(answer) await ui.navigate('app.schedule.home',{timetableId:result.timetableId});
  } catch(error) {state.notice='导入已保存，暂时无法打开课表：'+error.message;}
}

function importConflictField(conflict,choices) {
  const basis=conflict.key==='timetable:timeBasis';
  const options=conflict.options?conflict.options.map(value=>({value,label:value==='extra'?'保留为临时课':'撤销失效调课'})):basis?
    [{value:'local',label:'保留目标基准，重新解释导入周次/节次'},{value:'source',label:'采用来源基准，影响目标内全部课程'}]:
    [{value:'local',label:'保留本地'},{value:'source',label:'采用来源'}];
  return {...field(conflict.key,`${conflict.field}：本地 ${JSON.stringify(conflict.local)} / 来源 ${JSON.stringify(conflict.source)}`,choices[conflict.key]||conflict.options?.[0]||(basis?'':'local'),'select',options),...(basis?{required:true}:{})};
}

export async function handleImport({page,t,state,context,event,selectTimetable}) {
  if(event?.type==='export') await files.saveText(`${t.name}.json`,JSON.stringify(await exportBackup({timetableId:t.id}),null,2));
  if(event?.type==='import') {
    const raw=await files.readText();
    if(raw) {state.importDraft=draftFromBackup(JSON.parse(raw));delete state.importPlan;delete state.importSummary;delete state.importError;}
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
    const values=await ui.dialog({title:'导入方式',fields:[field('mode','模式',t?'merge':'new','select',[{value:'new',label:'新建课表'},{value:'merge',label:'合并当前课表'},{value:'replaceSource',label:'替换指定来源'}])]});
    if(values) {
      state.importInput={draft:state.importDraft,targetTimetableId:t?.id,mode:values.mode,choices:{}};
      const plan=await services.prepare(ref('schedule.import.prepare'),state.importInput);
      state.importPlan={planId:plan.planId,result:plan.result};state.importSummary=await importSummary(plan,state.importDraft);delete state.importError;
    }
  }
  if(event?.type==='resolveImport' && state.importPlan?.result.conflicts?.length) {
    const choices=await ui.dialog({title:'来源和本地修改冲突',fields:state.importPlan.result.conflicts.map(conflict=>importConflictField(conflict,state.importInput.choices))});
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
  let footer,planReview;
  children.push(group('数据来源',[
    listTile(t?.name||'新建课表',t?'当前导入目标；导入时可以选择新建课表':'导入 JSON 备份后创建新课表','calendar',t?{type:'chooseTimetable'}:null),
    listTile('JSON 导入','选择课表备份，预览后确认保存','importExport',{type:'import'}),
    ...(t?[listTile('JSON 导出','包含课程、安排与单次变更，不含凭据','importExport',{type:'export'})]:[])
  ]));
  if(state.importError)children.push(text(state.importError));
  if(state.adapterPlan) {
    const summary=await importSummary(state.adapterPlan,null);
    children.push(group('教务适配器导入预览',[text(`新增 ${summary.added} 项 · 修改 ${summary.updated} 项 · 删除 ${summary.deleted} 项`),text(`冲突 ${summary.conflicts?.length||0} 项 · 警告 ${summary.warnings?.length||0} 项`),...((summary.warnings||[]).map(text)),text('以下是本次导入将实际写入的变更，确认后保存。'),...summary.details]));
    footer={type:'row',children:[button('取消导入',{type:'cancelAdapter'}),...(!state.adapterPlan.result.blocked?[button('确认导入',{type:'confirmAdapter'})]:[])]};
    if(!state.adapterPlan.result.blocked)planReview={planId:state.adapterPlan.planId,eventType:'confirmAdapter'};
  }
  if(state.importDraft) {
    const summary=state.importSummary||await importSummary(null,state.importDraft);
    children.push(group('导入预览',[
      text(`${summary.courses} 门课程 · ${summary.meetings} 个安排 · ${summary.changes} 条单次变更`),
      text(`来源：${state.importDraft.scope} · ${state.importDraft.complete?'完整结果':'局部结果'}`),
      ...(state.importPlan?[text(`新增 ${summary.added} 项 · 修改 ${summary.updated} 项 · 删除 ${summary.deleted} 项`),text(`冲突 ${summary.conflicts.length} 项 · 警告 ${summary.warnings.length} 项`)]:[]),
      ...summary.warnings.map(w=>text('提醒：'+w)),
      ...summary.conflicts.map(c=>listTile(c.field,`本地：${JSON.stringify(c.local)}
来源：${JSON.stringify(c.source)}`,'history',null,'')),
      ...(state.importPlan?summary.details:[{type:'source',text:JSON.stringify(state.importDraft,null,2)}]),
      button(state.importPlan?'重新选择方式并预览':'选择方式并预览实际变更',{type:'saveImport'}),
      ...(state.importPlan?.result.conflicts?.length?[button('处理导入冲突',{type:'resolveImport'})]:[]),
    ]));
    footer={type:'row',children:[button('取消导入',{type:'cancelImport'}),...(state.importPlan&&!state.importPlan.result.blocked?[button('确认保存导入',{type:'confirmImport'})]:[])]};
    if(state.importPlan&&!state.importPlan.result.blocked)planReview={planId:state.importPlan.planId,eventType:'confirmImport'};
  }
  return {state,tree:{type:'column',children,...(footer?{footer}:{}),...(planReview?{planReview}:{})}};
}
