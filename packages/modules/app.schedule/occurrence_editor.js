import {data,clock} from '@xudian/sdk';
import {command} from './schedule_commands.js';
import {snapshot,currentOccurrence} from './schedule_queries.js';
import {action,fixedActions,lessonDate,pageResult,pair,periodLabel,shortDate,summary} from './course_layout.js';

const slot=item=>periodLabel(item.startPeriod,item.endPeriod);
const changedOn=change=>change.kind==='cancel'?change.originalDate:change.date;
const dismiss={type:'closeEditor'};

async function saveOccurrence(t,draft,courses) {
  const {item,change:previous,values,kind:selected}=draft;
  const originalDate=item?.originalDate||values.date,extra=!item||previous?.kind==='extra';
  if(extra&&item&&selected==='cancel')return undoChange(t,previous.id);
  const kind=extra?'extra':selected;
  const base={kind,timetableId:t.id,originalDate:item?.originalDate||values.date,meetingId:item?.meetingId||null,...(previous?{id:previous.id}:{})};
  const change=kind==='cancel'?base:{...base,date:values.date,courseId:values.courseId,startPeriod:Number(values.startPeriod),endPeriod:Number(values.endPeriod),location:values.location,teacher:values.teacher};
  const itemName=item?.title||courses.find(c=>c.id===change.courseId)?.name||'课程';
  const delta=(label,from,to)=>({title:label,subtitle:from?`${from} → ${to}`:to});
  const rows=kind==='cancel'?[{title:'本次安排',subtitle:'取消本次课程'}]:[
    delta('日期',item&&shortDate(item.date),shortDate(change.date)),
    delta('上课节次',item&&slot(item),slot(change)),
    delta('地点',item&&(item.location||'未填写'),change.location||'未填写'),
    ...(item?.courseId&&item.courseId!==change.courseId?[delta('课程',item.title,courses.find(c=>c.id===change.courseId)?.name||'课程')]:[]),
    ...(item?.teacher!==change.teacher?[delta('教师',item?.teacher,change.teacher||'未填写')]:[])
  ];
  return command('schedule.change.save',{change,...(item?{expectedChange:previous||null}:{})},{
    title:item?'确认单次调课':'确认临时加课',message:itemName+' · '+(item?'原计划 '+shortDate(originalDate):lessonDate(change.date)),
    subject:kind==='cancel'?'取消一次课程':extra?'临时加课':'移动一次课程',icon:'calendar',section:'本次调整',
    confirmLabel:kind==='cancel'?'确认取消':extra?'确认加课':'确认调课',summaryOnly:true,items:rows
  });
}

export async function undoChange(t,id) {
  const {courses,meetings,changes}=await snapshot(t.id),change=changes.find(c=>c.id===id);
  if(!change)throw new Error('本次变更已不存在。');
  const meeting=meetings.find(m=>m.id===change.meetingId);
  const course=courses.find(c=>c.id===(change.courseId||meeting?.courseId));
  const impact=change.kind==='extra'?'将移除这一次临时加课。':`将恢复 ${shortDate(change.originalDate)} ${slot(meeting)}的原安排。`;
  return command('schedule.entity.delete',{collection:'occurrenceChanges',id,expected:change},{
    title:'撤销本次变更？',subject:course?.name||'课程',message:[shortDate(changedOn(change)),change.location||meeting?.location].filter(Boolean).join(' · '),
    icon:'school',section:impact,summaryOnly:true,items:[],confirmLabel:'确认撤销'
  });
}


export async function renderOccurrenceEditor({t,context,state,event,formValues}) {
  const title=context.mode==='extra'?'临时加课':'单次调课';
  const close=()=>({...pageResult(state,title,[]),dismissPage:true});
  if(event?.type==='closeEditor')return close();
  const courses=t?await data.query('courses',{filter:{field:'timetableId',op:'eq',value:t.id}}):[];
  if(!state.draft && t) {
    const current=context.mode==='extra'?null:await currentOccurrence(t,context);
    if(current?.item||context.mode==='extra') {
      const item=current?.item||null;
      state.draft={item,change:current?.change||null,meeting:current?.meeting||null,kind:'replace',values:{
        courseId:item?.courseId||courses[0]?.id||'',date:item?.date||await clock.today(t.timezone),
        startPeriod:String(item?.startPeriod||1),endPeriod:String(item?.endPeriod||Math.min(2,t.periods.length)),
        teacher:item?.teacher||'',location:item?.location||''
      }};
    }
  }
  const draft=state.draft;
  if(!t||!draft)return pageResult(state,title,[{type:'emptyState',icon:'calendar',iconSurface:true,
    title:'这次课程已不存在',text:'返回课表刷新后，可查看最新安排。',padding:36}],fixedActions(action('返回',dismiss)));
  for(const key of Object.keys(draft.values)){
    if(formValues[key]!==undefined)draft.values[key]=formValues[key];
  }
  if(event?.type==='kind') {draft.kind=event.value;delete draft.error;}
  if(event?.type==='save') {
    try {
      const saved=await saveOccurrence(t,draft,courses);
      if(saved)return close();
      delete draft.error;
    } catch(error){draft.error=error.message;}
  }
  const {values,item}=draft;
  const field=(type,key,label,props={})=>({type,key,text:label,value:values[key],presentation:'labeled',...props});
  const select=(key,label,items)=>field('select',key,label,{items,event:{type:'field'}});
  const periodItems=t.periods.map(({number})=>({value:String(number),label:`第 ${number} 节`}));
  const children=[];
  if(item)children.push(summary(item.title,lessonDate(item.originalDate)+' · '+slot(draft.meeting||item),'school'),
    {type:'segmented',items:[{label:'移动或换地点',event:{type:'kind',value:'replace'}},{label:'取消本次',event:{type:'kind',value:'cancel'}}],selectedIndex:draft.kind==='cancel'?1:0});
  if(item && draft.kind==='cancel') {
    children.push({type:'notice',tone:'info',text:draft.change?.kind==='extra'?'将移除这一次临时加课。':`仅取消 ${shortDate(item.originalDate)} 的这一次课。其他教学周仍按原周期安排上课。`});
  } else {
    children.push({type:'column',spacing:10,trailingSpacing:false,children:[
      {type:'sectionHeader',compact:true,title:'本次安排'},
      select('courseId','课程',courses.map(c=>({value:c.id,label:c.name}))),
      field('dateInput','date','日期',{clearable:false,event:{type:'field'}}),
      pair(select('startPeriod','开始节次',periodItems),select('endPeriod','结束节次',periodItems)),
      field('input','location','地点'),field('input','teacher','教师')
    ]});
  }
  if(draft.error)children.push({type:'notice',tone:'error',text:draft.error});
  const result=pageResult(state,title,children,{queueInputActions:true,...fixedActions(action('取消',dismiss,true),
    {...action('继续',{type:'save'}),disabled:draft.kind!=='cancel'&&!values.courseId})});
  result.header.backIcon='close';
  return result;
}
