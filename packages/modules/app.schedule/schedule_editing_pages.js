import {data,ui,clock} from '@xudian/sdk';
import {normalizeWeeks,addDays,weekday} from './calendar.js';
import {customCourseColor} from './colors.js';
import {snapshot,currentOccurrence} from './schedule_queries.js';
import {command} from './schedule_commands.js';
import {field,text} from './page_controls.js';
import {defaultPeriods,listTile,group} from './view_helpers.js';

function periodsText(periods) { return periods.map(p=>`${p.start}-${p.end}`).join('\n'); }
function parsePeriods(text) { return text.split(/\n|,/).filter(x=>x.trim()).map((line,i)=>{ const [start,end]=line.trim().split('-'); return {number:i+1,start,end}; }); }

export async function handleEditing({t,state,event,selectTimetable}) {
  if(event?.type==='newTimetable'||event?.type==='settings') {
    const original=event.type==='settings'?t:null;
    const zone=original?{zone:original.timezone,source:'existing'}:await clock.systemTimezone();
    const today=await clock.today(zone.zone);
    const values=await ui.dialog({title:original?'课表与作息':'新建课表',fields:[
      field('name','课表名称',original?.name||'大学课表'),field('firstMonday','第一周周一',original?.firstMonday||addDays(today,1-weekday(today))),
      field('totalWeeks','总教学周数',String(original?.totalWeeks||20),'number'),
      field('displayWeekStart','显示起始',String(original?.displayWeekStart||1),'select',[{value:'1',label:'周一'},{value:'7',label:'周日'}]),
      field('periods','每行一个节次 HH:mm-HH:mm',periodsText(original?.periods||defaultPeriods),'multiline')]});
    if(values) {
      const saved=await command('schedule.timetable.save',{timetable:{...original,...values,timezone:zone.zone,totalWeeks:Number(values.totalWeeks),displayWeekStart:Number(values.displayWeekStart),periods:parsePeriods(values.periods)},...(original?{expectedTimetable:original}:{})});
      if(saved) { state.timetableId=saved.result.id; selectTimetable(saved.result.id); if(zone.source==='fallback')state.notice='请在学期设置的高级设置中核对时间设置。'; }
    }
  }
  if(event?.type==='course') {
    if(!t) throw new Error('先创建课表');
    const current=event.course?.id?await data.get('courses',event.course.id):event.course,meeting=event.meeting?.id?await data.get('meetings',event.meeting.id):event.meeting;
    const values=await ui.dialog({title:current?'编辑课程与安排':'添加课程',fields:[field('name','课程名称',current?.name),field('code','课程代码',current?.code),field('color','颜色 #RRGGBB（留空自动）',current?customCourseColor(current):''),field('notes','备注',current?.notes,'multiline'),
      field('weekday','星期（1–7）',String(meeting?.weekday||1),'number'),field('startPeriod','开始节次',String(meeting?.startPeriod||1),'number'),field('endPeriod','结束节次',String(meeting?.endPeriod||2),'number'),
      field('weeks','周次（例如1-16单、1,4,8-10）',meeting?.weeks.join(',')||`1-${t.totalWeeks}`),field('teacher','教师',meeting?.teacher),field('location','地点',meeting?.location),
      field('orphanPolicy','失效调课处理','ask','select',[{value:'ask',label:'有失效调课时阻止保存'},{value:'discard',label:'撤销失效调课'},{value:'extra',label:'保留为临时课程'}])]});
    if(values) await command('schedule.course.save',{course:{...current,id:current?.id,timetableId:t.id,name:values.name,code:values.code,color:values.color,colorMode:values.color?.trim()?'custom':'auto',notes:values.notes},
      meeting:{...meeting,id:meeting?.id,timetableId:t.id,weekday:Number(values.weekday),startPeriod:Number(values.startPeriod),endPeriod:Number(values.endPeriod),weeks:normalizeWeeks(values.weeks,t.totalWeeks),teacher:values.teacher,location:values.location},orphanPolicy:values.orphanPolicy});
  }
  if(event?.type==='editOccurrence'||event?.type==='extra') {
    const item=event.item;
    const courses=await data.query('courses',{filter:{field:'timetableId',op:'eq',value:t.id}});
    const values=await ui.dialog({title:item?'单次调课':'临时加课',fields:[
      field('kind','操作',item?'replace':'extra','select',item?[{value:'replace',label:'移动或换地点'},{value:'cancel',label:'取消本次'}]:[{value:'extra',label:'临时加课'}]),
      field('courseId','课程',item?.courseId||courses[0]?.id,'select',courses.map(c=>({value:c.id,label:c.name}))),
      field('date','日期',item?.date||await clock.today(t.timezone)),field('startPeriod','开始节次',String(item?.startPeriod||1),'number'),field('endPeriod','结束节次',String(item?.endPeriod||2),'number'),field('location','地点',item?.location),field('teacher','教师',item?.teacher)]});
    if(values) await command('schedule.change.save',{change:{...values,id:event.change?.id,timetableId:t.id,originalDate:item?.originalDate||values.date,meetingId:item?.meetingId||null,startPeriod:Number(values.startPeriod),endPeriod:Number(values.endPeriod)}});
  }
  if(event?.type==='delete') await command('schedule.entity.delete',{collection:event.collection,id:event.id});
}

export async function renderOccurrence({t,state,context,children}) {
  const current=await currentOccurrence(t,context);
  if(!current)children.push(text('这次课程已不存在。请返回课表刷新后查看。'));
  else {
    const {item,course,meeting,change}=current;
    children.push(group(course?.name||item?.title||'课程详情',[
      listTile('调课状态',current.cancelled?'已取消':change?.kind==='extra'?'临时加课':change?'已调整':'原计划','history',null,''),
      listTile('日期',current.cancelled?`${context.originalDate} · 已取消`:`${item.date} · 星期${['','一','二','三','四','五','六','日'][weekday(item.date)]}`,'calendar',null,''),
      ...(item?[listTile('上课时间',`第 ${item.startPeriod}–${item.endPeriod} 节 · ${t.periods[item.startPeriod-1]?.start||''}–${t.periods[item.endPeriod-1]?.end||''}`,'schedule',null,''),listTile('地点',item.location||'未填写','school',null,''),listTile('教师',item.teacher||'未填写','school',null,'')]:[]),
      ...(course?.code?[listTile('课程代码',course.code,'school',null,'')]:[]),
      ...(course?.notes?[listTile('备注',course.notes,'list',null,'')]:[]),
      ...(meeting?[listTile('周期安排',`星期${meeting.weekday} · 第 ${meeting.startPeriod}–${meeting.endPeriod} 节 · ${meeting.weeks.join(',')} 周`,'schedule',null,'')]:[]),
      ...(item&&item.date!==item.originalDate?[listTile('原上课日期',item.originalDate,'history',null,'')]:[])
    ]));
    children.push(group('操作',[
      ...(item?[listTile('单次调课','只调整本次课程的时间、地点或取消本次','history',{type:'singleChange'})]:[]),
      ...(meeting?[listTile('编辑周期安排','修改此安排的上课周次、节次和课程信息','school',{type:'editRecurrence'})]:[]),
      ...(change?[listTile('撤销本次变更','恢复周期安排中的原课程','history',{type:'delete',collection:'occurrenceChanges',id:change.id})]:[])
    ]));
  }
  return {state,tree:{type:'column',children}};
}

export async function renderCoursesAndChanges({page,t,state,children}) {
  if(page==='app.schedule.courses') {
    const {courses,meetings}=await snapshot(t.id);
    children.push({type:'sectionHeader',title:'课程与安排',count:courses.length,action:{label:'添加课程',icon:'add',event:{type:'course'}}});
    if(!courses.length)children.push(text('还没有课程，添加课程后配置上课安排。'));
    for(const course of courses) {
      const arrangements=meetings.filter(m=>m.courseId===course.id);
      children.push(group(course.name,[text([course.code,course.notes].filter(Boolean).join(' · ')),...arrangements.map(m=>({type:'disclosure',key:'arrangement:'+m.id,text:`星期${m.weekday} · 第 ${m.startPeriod}–${m.endPeriod} 节`,children:[
        text(`${m.weeks.join(',')} 周 · ${m.location||'未填地点'} · ${m.teacher||'未填教师'}`),listTile('编辑安排',null,'schedule',{type:'course',course,meeting:m}),listTile('删除安排',null,'history',{type:'delete',collection:'meetings',id:m.id})
      ]})),listTile('增加安排',null,'schedule',{type:'course',course}),listTile('删除课程',null,'history',{type:'delete',collection:'courses',id:course.id})]));
    }
  } else if(page==='app.schedule.changes') {
    const {courses,meetings,changes}=await snapshot(t.id);
    children.push({type:'sectionHeader',title:'单次课程变更',count:changes.length,action:{label:'临时加课',icon:'add',event:{type:'extra'}}});
    if(!changes.length)children.push(text('暂无单次调课记录。点击周视图中的课程可查看与调整本次上课。'));
    for(const change of changes) {
      const course=courses.find(c=>c.id===(change.courseId||meetings.find(m=>m.id===change.meetingId)?.courseId));
      children.push(group(course?.name||'单次课程变更',[text(`${change.originalDate} → ${change.kind==='cancel'?'取消':change.date}${change.kind==='extra'?' · 临时课':''}`),listTile('撤销变更',null,'history',{type:'delete',collection:'occurrenceChanges',id:change.id})]));
    }
  }
  return {state,tree:{type:'column',children}};
}
