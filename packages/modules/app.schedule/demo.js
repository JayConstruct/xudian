import {data,clock} from '@xudian/sdk';
import {addDays,weekday,validateTimetable,validateMeeting} from './calendar.js';
import {defaultPeriods} from './view_helpers.js';

const demoId='schedule-demo-v1',demoMarker='schedule-demo-v1';
export async function createDemo({timezone}={}) {
  const existing=await data.get('timetables',demoId);
  if(existing) {
    if(existing.demoMarker!==demoMarker)throw new Error('示例课表标识已被其他课表使用，未修改任何内容');
    return {writes:[],events:[],result:{timetableId:demoId,alreadyExists:true}};
  }
  const zone=timezone===undefined?await clock.systemTimezone():{zone:timezone,source:'explicit'};
  timezone=zone.zone;
  const today=await clock.today(timezone);
  const timetable=validateTimetable({id:demoId,datasetId:demoId,demoMarker,name:'示例课表',firstMonday:addDays(today,1-weekday(today)),totalWeeks:20,timezone,displayWeekStart:1,showWeekends:true,periods:defaultPeriods});
  const examples=[
    {name:'高等数学',code:'DEMO-MATH',color:'#486DA4',startPeriod:1,endPeriod:2,location:'教学楼 A101',teacher:'陈老师'},
    {name:'程序设计',code:'DEMO-CODE',color:'#6A8065',startPeriod:6,endPeriod:7,location:'实验楼 B203',teacher:'李老师'},
    {name:'大学英语',code:'DEMO-ENGLISH',color:'#A47C50',startPeriod:10,endPeriod:11,location:'教学楼 C305',teacher:'王老师'}
  ];
  const courses=examples.map((item,index)=>({id:`${demoId}-course-${index+1}`,timetableId:demoId,name:item.name,code:item.code,color:item.color,notes:'示例数据，可编辑或删除。'}));
  const meetings=examples.flatMap((item,index)=>Array.from({length:7},(_,day)=>validateMeeting({id:`${demoId}-meeting-${index+1}-${day+1}`,timetableId:demoId,courseId:courses[index].id,weekday:day+1,startPeriod:item.startPeriod,endPeriod:item.endPeriod,weeks:Array.from({length:20},(_,i)=>i+1),location:item.location,teacher:item.teacher},timetable,courses)));
  // The entire example is committed atomically in its own timetable. A repeat
  // leaves every existing record, including edited example records, untouched.
  const writes=[{collection:'timetables',id:demoId,value:timetable},...courses.map(value=>({collection:'courses',id:value.id,value})),...meetings.map(value=>({collection:'meetings',id:value.id,value}))];
  for(const write of writes)if(await data.get(write.collection,write.id))throw new Error('示例数据标识已被使用，未修改任何内容');
  return {writes,events:[{type:'schedule.updated',timetableId:demoId}],result:{timetableId:demoId,date:today,courses:courses.length,alreadyExists:false,timezone,timezoneSource:zone.source}};
}
