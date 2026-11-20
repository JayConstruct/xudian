import {data} from '@xudian/sdk';
import {normalizeWeeks} from './calendar.js';
import {courseColor,customCourseColor} from './colors.js';
import {button,text} from './page_controls.js';
import {command} from './schedule_commands.js';
import {snapshot} from './schedule_queries.js';
import {listTile} from './view_helpers.js';

const weekdays=['周一','周二','周三','周四','周五','周六','周日'];
export const orphanPolicies=[
  {value:'ask',label:'有失效调课时阻止保存'},
  {value:'discard',label:'撤销失效调课'},
  {value:'extra',label:'保留为临时课程'}
];
const formKey=field=>'schedule.course.'+field;
const divider={type:'divider',height:1};
const divided=rows=>rows.flatMap((row,index)=>index?[divider,row]:[row]);
const card=(children,padding=0)=>({type:'card',variant:'outlined',padding,children});
const inset=(child,padding=[0,0,0,0])=>({type:'inset',padding,children:[child]});
const pair=(...children)=>({type:'row',layout:'flex',spacing:10,crossAxisAlignment:'start',children:children.map(child=>({...child,flex:1}))});
const caption=title=>({type:'sectionHeader',title,compact:true});
const footer=(...children)=>({footerStyle:'edge',footer:pair(...children)});
const header=(title,options)=>({title,minHeight:65,...options});
const editorEvent=(courseId,meetingId)=>({type:'course',courseId,meetingId});
const deleteEvent=(collection,id)=>({type:'delete',collection,id});

function weekRanges(weeks) {
  const ranges=[];
  for(const week of [...new Set(weeks)].sort((a,b)=>a-b)) {
    const last=ranges.at(-1);
    if(last && week===last[1]+1)last[1]=week;
    else ranges.push([week,week]);
  }
  return ranges.map(([start,end])=>start===end?String(start):`${start}–${end}`).join(',');
}

export function courseValues(t,course,meeting) {
  return {
    name:course?.name??'',code:course?.code??'',color:course?customCourseColor(course):'',notes:course?.notes??'',
    weekday:String(meeting?.weekday??1),weeks:meeting?weekRanges(meeting.weeks):`1–${t.totalWeeks}`,
    startPeriod:String(meeting?.startPeriod??1),endPeriod:String(meeting?.endPeriod??Math.min(2,t.periods.length)),
    teacher:meeting?.teacher??'',location:meeting?.location??'',orphanPolicy:'ask'
  };
}

export function saveCourseValues(t,course,meeting,values) {
  const color=String(values.color??'').trim();
  if(color && !/^#[0-9a-f]{6}$/i.test(color))throw new Error('颜色需使用 #RRGGBB 格式，留空可自动分配颜色');
  return command('schedule.course.save',{
    course:{...course,timetableId:t.id,name:values.name,code:values.code,color,colorMode:color?'custom':'auto',notes:values.notes},
    meeting:{...meeting,timetableId:t.id,weekday:Number(values.weekday),startPeriod:Number(values.startPeriod),endPeriod:Number(values.endPeriod),weeks:normalizeWeeks(values.weeks.replace(/[–—]/g,'-'),t.totalWeeks),teacher:values.teacher,location:values.location},
    orphanPolicy:values.orphanPolicy,
    ...(course?{expectedCourse:course}:{}),
    ...(meeting?{expectedMeeting:meeting}:{})
  });
}

function readForm(values,formValues) {
  return Object.fromEntries(Object.entries(values).map(([key,value])=>[key,String(formValues[formKey(key)]??value)]));
}

function formField(values,key,label,type='input',props={}) {
  return {type,key:formKey(key),text:label,value:values[key],presentation:'labeled',...props};
}

function renderEditor(t,state,formValues,replaceForms) {
  const {editor}=state;
  const values=readForm(editor.values,formValues);
  const field=(key,label,props)=>formField(values,key,label,'input',props);
  const select=(key,label,items,props)=>formField(values,key,label,'select',{
    items,event:{type:'courseField',field:key},...props
  });
  const periodItems=t.periods.map(({number})=>({value:String(number),label:`第 ${number} 节`}));
  const cancel={type:'cancelCourse'};
  const policy=orphanPolicies.find(({value})=>value===values.orphanPolicy)??orphanPolicies[0];
  const children=[
    inset({type:'column',spacing:10,trailingSpacing:false,children:[
      caption('课程信息'),
      field('name','课程名称'),
      pair(field('code','课程代码'),field('color','颜色',{hintText:'#RRGGBB'})),
      field('notes','备注',{minLines:1,maxLines:5})
    ]},[0,2,0,22]),
    inset({type:'column',spacing:10,trailingSpacing:false,children:[
      caption('周期安排'),
      pair(select('weekday','星期',weekdays.map((label,index)=>({value:String(index+1),label}))),field('weeks','周次',{hintText:'例如 1-16单'})),
      pair(select('startPeriod','开始节次',periodItems,{showIndicator:false}),select('endPeriod','结束节次',periodItems,{showIndicator:false})),
      pair(field('teacher','教师'),field('location','地点'))
    ]},[0,3,0,14]),
    {type:'column',spacing:6,trailingSpacing:false,children:[
      inset(caption('调课处理')),
      card([
        {...listTile('失效调课处理',policy.label,'history',{type:'toggleOrphanPolicy'}),trailingIcon:editor.showOrphanPolicy?'up':'down',expanded:editor.showOrphanPolicy===true,minHeight:66},
        ...(editor.showOrphanPolicy?orphanPolicies.map(option=>({
          ...listTile(option.label,null,null,{type:'orphanPolicy',value:option.value},false),
          selected:policy.value===option.value
        })):[])
      ])
    ]},
    ...(editor.error?[{type:'notice',tone:'error',text:editor.error}]:[])
  ];
  return {state,replaceForms,
    header:header(editor.course?'编辑课程与安排':'添加课程',{backIcon:'close',backEvent:cancel}),
    tree:{type:'column',scrollKey:'course-editor',spacing:0,trailingSpacing:false,queueInputActions:true,children,
      ...footer({...button('取消',cancel),variant:'outlined'},{...button('保存',{type:'saveCourse'}),variant:'filled'})}
  };
}

function arrangementRow(meeting,state) {
  const expanded=state.openArrangement===meeting.id;
  const periods=meeting.startPeriod===meeting.endPeriod?meeting.startPeriod:`${meeting.startPeriod}–${meeting.endPeriod}`;
  const subtitle=[`第 ${weekRanges(meeting.weeks)} 周`,meeting.teacher,meeting.location].filter(Boolean).join(' · ');
  const row={
    ...listTile(`${weekdays[meeting.weekday-1]} · 第 ${periods} 节`,subtitle,'schedule',{type:'toggleArrangement',id:meeting.id}),
    trailingIcon:expanded?'up':'down',expanded,iconTone:'muted',iconSurfaceSize:26,minHeight:55,minVerticalPadding:8
  };
  return expanded?[row,{
    type:'inset',padding:[26,0,8,0],children:[{type:'row',spacing:0,children:[
      {...button('编辑安排',editorEvent(meeting.courseId,meeting.id)),variant:'text'},
      {...button('删除安排',deleteEvent('meetings',meeting.id)),variant:'text',tone:'danger'}
    ]}]
  }]:[row];
}

function courseCardRows(course,arrangements,state) {
  const expanded=state.openCourse===course.id;
  const subtitle=[course.code,expanded&&course.notes?course.notes:`${arrangements.length} 个周期安排`].filter(Boolean).join(' · ');
  const header={
    ...listTile(course.name,subtitle,'school',{type:'toggleCourse',id:course.id}),
    trailingIcon:expanded?'up':'down',trailingColor:courseColor(course),expanded,minHeight:65
  };
  if(!expanded)return [header];
  return [
    header,
    ...(arrangements.length?[{
      type:'inset',padding:[12,0,12,4],
      children:[{type:'card',tone:'soft',padding:0,children:arrangements.flatMap(meeting=>arrangementRow(meeting,state))}]
    }]:[]),
    {...listTile('增加安排',null,'add',editorEvent(course.id)),iconTone:'muted',iconSurfaceSize:32,minHeight:58},
    divider,
    {...listTile('删除课程',null,'delete',deleteEvent('courses',course.id)),iconTone:'muted',iconSurfaceSize:32,minHeight:58,tone:'danger'}
  ];
}

function renderCourseList(t,state,children,courses,meetings,clearForms) {
  const isSpring=Number(t.firstMonday.slice(5,7))<8;
  const summary=`${t.firstMonday.slice(0,4)} 年${isSpring?'春季':'秋季'} · ${t.totalWeeks} 个教学周`;
  children.push(inset(card([{
    ...listTile(t.name,summary,'calendar',null,false),
    iconTone:'accent',iconSurfaceSize:45,titleStyle:'heading',minHeight:85
  }]),[0,1,0,0]));
  if(courses.length) {
    const arrangementsByCourse=new Map();
    for(const meeting of meetings) {
      if(!arrangementsByCourse.has(meeting.courseId))arrangementsByCourse.set(meeting.courseId,[]);
      arrangementsByCourse.get(meeting.courseId).push(meeting);
    }
    for(const arrangements of arrangementsByCourse.values()) {
      arrangements.sort((a,b)=>a.weekday-b.weekday||a.startPeriod-b.startPeriod||a.endPeriod-b.endPeriod);
    }
    const cards=[];
    let collapsed=[];
    for(const course of courses) {
      const rows=courseCardRows(course,arrangementsByCourse.get(course.id)??[],state);
      if(course.id===state.openCourse) {
        if(collapsed.length)cards.push(card(divided(collapsed)));
        collapsed=[];
        cards.push(card(rows));
      } else collapsed.push(rows[0]);
    }
    if(collapsed.length)cards.push(card(divided(collapsed)));
    children.push({
      type:'column',spacing:0,trailingSpacing:false,
      children:[
        inset({...caption('课程与安排'),count:`${courses.length} 门课程`,countPosition:'end'}),
        {type:'column',spacing:20,trailingSpacing:false,children:cards.map(section=>inset(section))}
      ]
    });
  } else {
    children.push(card([{
      type:'emptyState',icon:'school',iconSurface:true,iconTone:'muted',iconSurfaceSize:46,title:'还没有课程',
      text:'添加课程后，可设置上课时间和地点。',padding:36
    }]));
  }
  return {state,clearForms,header:header('课程管理'),
    tree:{type:'column',scrollKey:'course-management',spacing:courses.length?16:20,trailingSpacing:false,children,
      ...footer({...button('添加课程',editorEvent()),variant:'filled'})}
  };
}

export async function renderCourseManagement({t,state,event,formValues,children}) {
  if(state.courseManagementTimetable!==t.id) {
    delete state.editor;
    delete state.openCourse;
    delete state.openArrangement;
    state.courseManagementTimetable=t.id;
  }
  let replaceForms={},clearForms=[];
  if(event?.type==='course') {
    const [course,meeting]=await Promise.all([
      event.courseId?data.get('courses',event.courseId):null,
      event.meetingId?data.get('meetings',event.meetingId):null
    ]);
    if((event.courseId&&course?.timetableId!==t.id)||(event.meetingId&&(!meeting||meeting.courseId!==course?.id||meeting.timetableId!==t.id))) {
      children.push(text('课程或周期安排已不存在'));
    } else {
      const values=courseValues(t,course,meeting);
      state.editor={course,meeting,values};
      replaceForms=Object.fromEntries(Object.entries(values).map(([key,value])=>[formKey(key),value]));
      formValues={};
    }
  }
  if(state.editor) {
    const editor=state.editor;
    if(event?.type==='courseField' && Object.hasOwn(editor.values,event.field)) {
      editor.values[event.field]=String(event.value);
    }
    if(event?.type==='toggleOrphanPolicy')editor.showOrphanPolicy=!editor.showOrphanPolicy;
    if(event?.type==='orphanPolicy' && orphanPolicies.some(({value})=>value===event.value)) {
      editor.values.orphanPolicy=event.value;
      editor.showOrphanPolicy=false;
      formValues={...formValues,[formKey('orphanPolicy')]:event.value};
      replaceForms[formKey('orphanPolicy')]=event.value;
    }
    if(event?.type==='saveCourse') {
      try {
        editor.error=null;
        if(await saveCourseValues(t,editor.course,editor.meeting,readForm(editor.values,formValues)))delete state.editor;
      } catch(error) {
        editor.error=error.message;
      }
    }
    if(event?.type==='cancelCourse')delete state.editor;
    if(state.editor)return renderEditor(t,state,formValues,replaceForms);
    clearForms=Object.keys(editor.values).map(formKey);
  }
  if(event?.type==='toggleCourse') {
    state.openCourse=state.openCourse===event.id?null:event.id;
    state.openArrangement=null;
  }
  if(event?.type==='toggleArrangement')state.openArrangement=state.openArrangement===event.id?null:event.id;
  const {courses,meetings}=await snapshot(t.id,t);
  if(!courses.some(({id})=>id===state.openCourse))delete state.openCourse;
  if(!meetings.some(({id,courseId})=>id===state.openArrangement&&courseId===state.openCourse))delete state.openArrangement;
  return renderCourseList(t,state,children,courses,meetings,clearForms);
}
