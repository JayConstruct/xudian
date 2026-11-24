import {data,ui,clock} from '@xudian/sdk';
import {addDays,weekday} from './calendar.js';
import {courseValues,orphanPolicies,saveCourseValues,weekRanges} from './course_management.js';
import {snapshot,currentOccurrence,occurrenceReference} from './schedule_queries.js';
import {command} from './schedule_commands.js';
import {undoChange} from './occurrence_editor.js';
import {field} from './page_controls.js';
import {defaultPeriods} from './view_helpers.js';
import {action,courseRow,fact,fixedActions,lessonDate,pageResult,periodLabel,section,shortDate,summary,weekdayNames} from './course_layout.js';

const labeled=(key,label,value,type,options,layout={})=>({...field(key,label,value,type,options),presentation:'labeled',...layout});
const slot=item=>periodLabel(item.startPeriod,item.endPeriod);
const changedOn=change=>change.kind==='cancel'?change.originalDate:change.date;

async function editTimetable(t,state,selectTimetable) {
  const zone=t?{zone:t.timezone,source:'existing'}:await clock.systemTimezone();
  const today=await clock.today(zone.zone);
  const values=await ui.dialog({title:t?'课表与作息':'新建课表',presentation:'page',fullWidthActions:true,fields:[
    labeled('name','课表名称',t?.name||'大学课表','text',null,{section:'学期信息',required:true,maxLength:120}),
    labeled('firstMonday','第一周周一',t?.firstMonday||addDays(today,1-weekday(today)),'date',null,{required:true,clearable:false}),
    labeled('totalWeeks','总教学周数',String(t?.totalWeeks||20),'number',null,{integer:true,min:1,max:100,row:'weeks'}),
    labeled('displayWeekStart','显示起始',String(t?.displayWeekStart||1),'select',[{value:'1',label:'周一'},{value:'7',label:'周日'}],{row:'weeks'}),
    labeled('periods','每行一个节次',(t?.periods||defaultPeriods).map(p=>p.start+'-'+p.end).join('\n'),'multiline',null,
      {section:'作息',minLines:7,maxLines:7,helperText:'按顺序填写，使用 HH:mm-HH:mm。例如 08:00-08:45。',required:true})
  ]});
  if(!values)return;
  const periods=values.periods.split(/\n|,/).filter(line=>line.trim()).map((line,i)=>{
    const [start,end]=line.trim().split('-');
    return {number:i+1,start,end};
  });
  const saved=await command('schedule.timetable.save',{timetable:{...t,...values,timezone:zone.zone,totalWeeks:Number(values.totalWeeks),displayWeekStart:Number(values.displayWeekStart),periods},...(t?{expectedTimetable:t}:{})});
  if(saved) {
    state.timetableId=saved.result.id;selectTimetable(saved.result.id);
    if(zone.source==='fallback')state.notice='请在学期设置的高级设置中核对时间设置。';
  }
}

export async function handleEditing({t,state,event,selectTimetable}) {
  if(event?.type==='newTimetable'||event?.type==='settings')await editTimetable(event.type==='settings'?t:null,state,selectTimetable);
  if(event?.type==='course') {
    if(!t) throw new Error('先创建课表');
    const current=event.course?.id?await data.get('courses',event.course.id):event.course,meeting=event.meeting?.id?await data.get('meetings',event.meeting.id):event.meeting;
    if(event.course?.id&&!current||event.meeting?.id&&!meeting)throw new Error('课程或周期安排已不存在');
    const initial=courseValues(t,current,meeting);
    const values=await ui.dialog({title:current?'编辑课程与安排':'添加课程',fields:[field('name','课程名称',initial.name),field('code','课程代码',initial.code),field('color','颜色 #RRGGBB（留空自动）',initial.color),field('notes','备注',initial.notes,'multiline'),
      field('weekday','星期（1–7）',initial.weekday,'number'),field('startPeriod','开始节次',initial.startPeriod,'number'),field('endPeriod','结束节次',initial.endPeriod,'number'),
      field('weeks','周次（例如1-16单、1,4,8-10）',initial.weeks),field('teacher','教师',initial.teacher),field('location','地点',initial.location),
      field('orphanPolicy','失效调课处理',initial.orphanPolicy,'select',orphanPolicies)]});
    if(values) await saveCourseValues(t,current,meeting,values);
  }
  if(event?.type==='editOccurrence'||event?.type==='extra')await ui.navigate('app.schedule.occurrenceEditor',{
    timetableId:t.id,...(event.item?occurrenceReference(event.item):{mode:'extra'})
  });
  if(event?.type==='undoChange')await undoChange(t,event.id);
  if(event?.type==='delete')await command('schedule.entity.delete',{collection:event.collection,id:event.id});
}

export async function renderOccurrence({t,state,context,children}) {
  const current=t&&await currentOccurrence(t,context);
  if(!current) {
    children.push({type:'emptyState',icon:'calendar',iconSurface:true,iconTone:'muted',title:'这次课程已不存在',text:'返回课表刷新后，可查看最新安排。',padding:36});
    return pageResult(state,'课程详情',children,fixedActions(action('返回课表',{type:'navigate',page:'home'})));
  }
  const {item,course,meeting,change,cancelled}=current;
  const extra=change?.kind==='extra',date=cancelled?change.originalDate:item.date;
  const status=cancelled?'已取消':extra?'临时加课':change?'已调整':'原计划';
  children.push(summary(course.name,[course.code,t.name].filter(Boolean).join(' · '),'school',status,cancelled),
    section('本次上课',[fact('日期',lessonDate(date)),
      ...(item?[fact('上课时间',`${slot(item)} · ${t.periods[item.startPeriod-1].start}–${t.periods[item.endPeriod-1].end}`),fact('地点',item.location||'未填写'),fact('教师',item.teacher||'未填写')]:[]),
      ...(change?.kind==='replace'&&item.date!==item.originalDate?[fact('原上课日期',lessonDate(item.originalDate))]:[])]),
    section('课程信息',[...(meeting?[fact('周期安排',`第 ${weekRanges(meeting.weeks)} 周 · ${weekdayNames[meeting.weekday-1]} · ${slot(meeting)}`)]:[]),fact('备注',course.notes||'未填写')]),
    section('操作',[...(item?[courseRow('单次调课','调整本次时间、地点或取消本次','calendar',{type:'singleChange'})]:[]),
      ...(meeting?[courseRow('编辑周期安排','修改上课周次、节次和课程信息','edit',{type:'editRecurrence'})]:[]),
      ...(change?[courseRow('撤销本次变更',extra?'移除这一次临时加课':'恢复原周期安排','history',{type:'undoChange',id:change.id})]:[])])
  );
  return pageResult(state,'课程详情',children);
}

export async function renderChanges({t,state,children}) {
  const {courses,meetings,changes}=await snapshot(t.id);
  const ordered=[...changes].sort((left,right)=>left.originalDate.localeCompare(right.originalDate)||
    (left.startPeriod||0)-(right.startPeriod||0)||left.id.localeCompare(right.id));
  const rows=ordered.map(change=>{
    const meeting=meetings.find(m=>m.id===change.meetingId);
    const course=courses.find(c=>c.id===(change.courseId||meeting?.courseId));
    const label=change.kind==='extra'?'临时加课':change.kind==='cancel'?'已取消':'移动上课';
    const date=change.kind==='replace'?`${shortDate(change.originalDate)} → ${shortDate(change.date)}`:shortDate(changedOn(change));
    const item={occurrenceId:change.kind==='extra'?change.id:change.meetingId+':'+change.originalDate,meetingId:change.meetingId,originalDate:change.originalDate,date:changedOn(change)};
    return {type:'row',layout:'flex',spacing:0,children:[
      {...courseRow(course?.name||'课程',date+' · '+label,'calendar',{type:'occurrence',item},false),flex:1},
      {type:'button',variant:'text',text:'撤销',event:{type:'undoChange',id:change.id}}
    ]};
  });
  if(!rows.length)rows.push({type:'emptyState',icon:'calendar',iconSurface:true,iconTone:'muted',title:'暂无单次调课记录',text:'可从课表中的课程发起单次调课，也可临时加课。',padding:31});
  children.push(section('单次课程变更',rows,changes.length+' 条'));
  return pageResult(state,'调课记录',children,fixedActions(action('临时加课',{type:'extra'})));
}
