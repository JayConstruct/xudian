import {data,services,ui,clock} from '@xudian/sdk';
import {teachingWeek} from './calendar.js';
import {ref} from './schedule_commands.js';
import {occurrenceReference,currentOccurrence} from './schedule_queries.js';
import {field,go,text} from './page_controls.js';
import {listTile} from './view_helpers.js';
import {renderSettings,renderTimetables,renderSemester,renderPeriods,updateSemester,updatePeriods} from './schedule_settings_pages.js';
import {renderGrid,updateDisplay} from './schedule_grid_page.js';
import {handleEditing,renderOccurrence,renderChanges} from './schedule_editing_pages.js';
import {renderOccurrenceEditor} from './occurrence_editor.js';
import {renderCourseManagement} from './course_management.js';
import {handleImport,renderImports} from './schedule_import_page.js';
import {renderToday} from './today_page.js';

let selectedTimetableId=null,selectionRevision=0,displayRequest=0;
function selectTimetable(id) { if(selectedTimetableId!==id) { selectedTimetableId=id; selectionRevision++; } }
function pageId(value) { return value.startsWith('app.')?value:'app.schedule.'+value; }

export async function render({state={},context={},event,formValues={}}) {
  state={...state};
  if(state.selectionRevision!==undefined && state.selectionRevision<selectionRevision) { state.timetableId=selectedTimetableId; delete state.week; }
  if(event?.type==='select') { state.timetableId=event.id; delete state.week; selectTimetable(event.id); }
  if(event?.type==='week') state.week=event.week;
  if(event?.type==='createDemo') {
    const plan=await services.prepare(ref('schedule.demo.create'),{});
    if(plan.result.alreadyExists)state.notice='示例课表已存在，保留了现有内容';
    else if(await ui.review(plan.planId)) {
      const saved=await services.commit(plan.planId);state.timetableId=saved.timetableId;selectTimetable(saved.timetableId);state.notice='已添加示例课表，今天会显示对应课程'+(saved.timezoneSource==='fallback'?'。请在学期设置的高级设置中核对时间设置。':'');
    }
  }
  let timetables=await data.query('timetables');
  let t=timetables.find(x=>x.id===(state.timetableId||context.timetableId||selectedTimetableId)) || timetables[0];
  const page=context.pageId||'app.schedule.home';
  if((page==='app.schedule.occurrence'||page==='app.schedule.occurrenceEditor') && context.timetableId)t=timetables.find(table=>table.id===context.timetableId);
  const gridPage=page==='app.schedule.home'||page==='app.schedule.display';
  if(page==='app.schedule.display' && state.displayControls===undefined)state.displayControls=true;
  if(page==='app.schedule.display' && state.displayRequest!==context.displayRequest) {state.displayControls=true;state.displayRequest=context.displayRequest;}
  if(gridPage && event?.type==='openDisplay')state.displayControls=true;
  if(gridPage && event?.type==='closeDisplay') {state.displayControls=false;delete state.notice;}
  if(page==='app.schedule.home') delete state.tab;
  if(t) { state.timetableId=t.id; if(!selectedTimetableId) selectedTimetableId=t.id; }
  if(t && state.weekendTimetableId!==t.id) {delete state.revealWeekends;state.weekendTimetableId=t.id;}
  if(event?.type==='weekend') state.revealWeekends=true;
  if(context.week && !state.week && state.selectionRevision===undefined) state.week=context.week;
  if(event?.type==='navigate') await ui.navigate(pageId(event.page),{timetableId:t?.id,week:state.week,...(event.page==='display'?{displayRequest:++displayRequest}:{})});
  if(event?.type==='currentWeek' && t) state.week=Math.max(1,Math.min(t.totalWeeks,teachingWeek(t,await clock.today(t.timezone))));
  if(event?.type==='occurrence' && t) await ui.panel('app.schedule.occurrence',{timetableId:t.id,...occurrenceReference(event.item)},{adaptive:true});
  if(event?.type==='singleChange' && t) {
    const current=await currentOccurrence(t,context);
    if(current?.item) event={type:'editOccurrence',item:current.item,change:current.change,meeting:current.meeting};
    else state.notice='这次课程已取消或不存在，请刷新后查看';
  }
  if(event?.type==='editRecurrence' && t) {
    const current=await currentOccurrence(t,context);
    if(current?.meeting&&current.course) event={type:'course',course:current.course,meeting:current.meeting};
    else state.notice='周期安排已不存在';
  }
  if(event?.type==='chooseTimetable') {
    const values=await ui.dialog({title:'切换课表',fields:[field('timetableId','课表',t?.id,'select',timetables.map(x=>({value:x.id,label:x.name})))]});
    if(values) { state.timetableId=values.timetableId; delete state.week;delete state.importPlan;delete state.importSummary;delete state.importInput;delete state.importError; selectTimetable(values.timetableId); t=timetables.find(x=>x.id===values.timetableId); }
  }
  if(event?.type==='chooseWeek' && t) {
    const today=await clock.today(t.timezone),current=Math.max(1,Math.min(t.totalWeeks,teachingWeek(t,today)));
    const values=await ui.dialog({title:'选择教学周',fields:[{...field('week','教学周',String(state.week||current),'select',Array.from({length:t.totalWeeks},(_,i)=>({value:String(i+1),label:String(i+1)}))),presentation:'grid',submitOnSelect:true,required:true}]});
    if(values) state.week=Number(values.week);
  }
  if(t && page==='app.schedule.semester') await updateSemester({t,state,event,formValues});
  if(t && gridPage) await updateDisplay({t,state,event});
  if(t && page==='app.schedule.periods') await updatePeriods({t,state,event,formValues});
  if(page!=='app.schedule.courses'||event?.type!=='course')await handleEditing({t,state,event,selectTimetable});
  await handleImport({page,t,state,context,event,selectTimetable});

  timetables=await data.query('timetables');
  t=timetables.find(x=>x.id===state.timetableId)||timetables[0];
  if(selectedTimetableId && !timetables.some(x=>x.id===selectedTimetableId)) selectTimetable(t?.id||null);
  state.selectionRevision=selectionRevision;
  const children=[];
  if(state.notice) children.push(text(state.notice));
  if(page==='app.schedule.settings') return renderSettings({t,timetables,state,children});
  if(page==='app.schedule.imports') return renderImports({t,state,children});
  if(page==='app.schedule.timetables') return renderTimetables({t,timetables,state,children});
  if(page==='app.schedule.occurrenceEditor')return renderOccurrenceEditor({
    t:timetables.find(table=>table.id===context.timetableId),context,state,event,formValues
  });
  if(page==='app.schedule.occurrence') {
    const target=context.timetableId?timetables.find(table=>table.id===context.timetableId):t;
    return renderOccurrence({t:target,state,context,children});
  }
  if(!t) {
    children.push(text('创建课表或导入 JSON 备份后开始使用'),listTile('新建课表','默认12节作息','calendar',{type:'newTimetable'}),go('导入与备份','imports','导入 JSON 备份','importExport'));
    const header=page==='app.schedule.home'?{title:'课表',actions:[{label:'课表设置',event:{type:'navigate',page:'settings'}}]}:page==='app.schedule.courses'?{title:'课程管理'}:undefined;
    return {state,...(header?{header}:{}),tree:{type:'column',children}};
  }
  state.timetableId=t.id;
  if(page==='app.schedule.semester') return renderSemester({t,state,event,children});
  if(page==='app.schedule.periods') return renderPeriods({t,state,children});
  if(page==='app.schedule.courses') return renderCourseManagement({t,state,event,formValues,children});
  if(page==='app.schedule.changes') return renderChanges({t,state,children});
  if(page==='app.schedule.today') return renderToday({t,state,children});
  return renderGrid({t,state});
}
