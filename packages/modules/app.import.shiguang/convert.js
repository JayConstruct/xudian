// Pure conversion: no credentials, browser access, or database writes.
const object = (value, label) => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error(`${label}需为对象`);
  return value;
};
const text = (value, label, max = 120) => {
  if (typeof value !== 'string' || !value.trim() || value.length > max) throw new Error(`${label}无效`);
  return value.trim();
};
const integer = (value, min, max, label) => {
  if (!Number.isInteger(value) || value < min || value > max) throw new Error(`${label}需在${min}–${max}之间`);
  return value;
};
const canonical = value => JSON.stringify(value);
export const defaultTimeSlots = [['08:00','08:45'],['08:50','09:35'],['09:50','10:35'],['10:40','11:25'],['11:30','12:15'],['14:00','14:45'],['14:50','15:35'],['15:45','16:30'],['16:35','17:20'],['18:30','19:15'],['19:20','20:05'],['20:10','20:55']].map(([startTime,endTime],i)=>({number:i+1,startTime,endTime}));
function civil(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new Error('日期需为 YYYY-MM-DD');
  const time = Date.parse(value+'T00:00:00Z');
  if (!Number.isFinite(time) || new Date(time).toISOString().slice(0,10)!==value) throw new Error('日期不存在');
  return time;
}
export function suggestedMonday(config = {}) {
  if (!config.semesterStartDate) return '';
  const time=civil(config.semesterStartDate),day=(new Date(time).getUTCDay()+6)%7+1;
  // Sunday-based semester weeks have their Monday one day after that Sunday.
  return new Date(time+(config.firstDayOfWeek===7 ? 1-day%7 : -(day-1))*86400000).toISOString().slice(0,10);
}
function minutes(value) {
  if (typeof value !== 'string' || !/^\d{2}:\d{2}$/.test(value)) throw new Error('作息时间需为 HH:mm');
  const [h,m]=value.split(':').map(Number);
  if (h>23 || m>59) throw new Error('作息时间无效');
  return h*60+m;
}
export function convert({payload, options = {}}) {
  const input=Array.isArray(payload)?{courses:payload}:object(payload,'拾光数据');
  object(options,'导入配置');
  const config=input.config==null?{}:object(input.config,'学期配置');
  if (!Array.isArray(input.courses) || input.courses.length>10000) throw new Error('需提供 courses 数组，最多10000条');
  if (input.timeSlots!=null && !Array.isArray(input.timeSlots)) throw new Error('作息需为数组');
  if (input.comboSchedule!=null && object(input.comboSchedule,'组合作息').publicSchedules?.length) throw new Error('当前课表暂不支持按日期切换的组合作息，请先选择单一作息方案');
  const name=text(options.name,'课表名称'),scope=text(options.scope,'来源标识',500);
  const firstMonday=options.firstMonday || suggestedMonday(config);
  if (new Date(civil(firstMonday)).getUTCDay()!==1) throw new Error('第一教学周需选择周一');
  const totalWeeks=integer(options.totalWeeks??config.semesterTotalWeeks??20,1,100,'学期周数');
  const displayWeekStart=options.displayWeekStart??config.firstDayOfWeek??1;
  if (![1,7].includes(displayWeekStart)) throw new Error('每周起始日仅支持周一或周日');
  const timezone=text(options.timezone??'Asia/Shanghai','时区');
  const warnings=[];
  const slots=input.timeSlots?.length?input.timeSlots:(options.timeSlots??defaultTimeSlots);
  if (!input.timeSlots?.length) warnings.push(options.timeSlots?'使用所选课表的现有作息，请确认与学校一致':'来源没有作息，使用12节作息模板，请确认与学校一致');
  if (!Array.isArray(slots) || !slots.length || slots.length>30) throw new Error('作息需为1–30个连续节次');
  let previous=-1;
  const periods=slots.map((slot,i)=>{
    object(slot,'节次');
    if (slot.number!==i+1) throw new Error('作息节次需从1开始连续排列');
    const start=slot.startTime??slot.start,end=slot.endTime??slot.end;
    if (minutes(start)<previous || minutes(end)<=minutes(start)) throw new Error('作息不能重叠或跨午夜');
    previous=minutes(end);return {number:i+1,start,end};
  });
  const courses=new Map(),meetings=new Map();
  let missingIdentity=false;
  for (const [i,raw] of input.courses.entries()) {
    const row=object(raw,`第${i+1}条课程`),name=text(row.name,`第${i+1}条课程名称`);
    if (row.isCustomTime===true || row.customStartTime || row.customEndTime) throw new Error(`「${name}」使用自定义时间，当前课表只支持节次安排`);
    const weekday=integer(row.day,1,7,'星期'),startPeriod=integer(row.startSection,1,periods.length,'开始节次'),endPeriod=integer(row.endSection,startPeriod,periods.length,'结束节次');
    if (!Array.isArray(row.weeks) || !row.weeks.length) throw new Error(`「${name}」缺少明确周次`);
    const weeks=[...new Set(row.weeks.map(w=>integer(w,1,totalWeeks,'课程周次')))].sort((a,b)=>a-b);
    const teacher=row.teacher??'',location=row.position??'';
    if (typeof teacher!=='string' || typeof location!=='string' || teacher.length>500 || location.length>500) throw new Error('教师或地点无效');
    const courseId=row.courseSourceId==null ? 'course:'+canonical([name,row.code??'']) : text(row.courseSourceId,'课程来源ID',500);
    const course={sourceId:courseId,name,...(row.code?{code:text(row.code,'课程代码')}:{}),...(row.remark?{notes:text(row.remark,'课程备注',300)}:{})};
    if (row.color!=null) {
      if (!Number.isInteger(row.color)) throw new Error('拾光课程颜色需为整数');
      course.color='#'+(row.color&0xffffff).toString(16).padStart(6,'0');
    }
    if (row.credit!=null) {
      if (typeof row.credit!=='number'||!Number.isFinite(row.credit)||row.credit<0) throw new Error('课程学分无效');
      course.credit=row.credit;
    }
    const priorCourse=courses.get(courseId);
    if (priorCourse && canonical(priorCourse)!==canonical(course)) throw new Error(`「${name}」同一课程的信息不一致，请先修正来源数据`);
    courses.set(courseId,course);
    const stable=row.sourceId??row.id;
    if (stable==null) missingIdentity=true;
    const sourceId=stable==null?'meeting:'+canonical([courseId,weekday,startPeriod,endPeriod,teacher,location]):text(stable,'安排来源ID',500);
    const meeting={sourceId,courseId,weekday,startPeriod,endPeriod,weeks,teacher,location};
    const prior=meetings.get(sourceId);
    if (prior) {
      if (canonical({...prior,weeks:[]})!==canonical({...meeting,weeks:[]})) throw new Error('同一安排来源ID对应不同上课安排');
      meeting.weeks=[...new Set([...prior.weeks,...weeks])].sort((a,b)=>a-b);
    }
    meetings.set(sourceId,meeting);
  }
  if (missingIdentity) warnings.push('来源未提供稳定安排ID；周次变化可以合并，改名、教师、地点或节次变化可能识别为新安排');
  if (!meetings.size) warnings.push('来源课程为空，不会清空已有课表');
  return {draftVersion:1,scope:'shiguang:'+scope,adapterVersion:'shiguang-compat@1.1.0',complete:options.complete===true,
    timetable:{name,firstMonday,totalWeeks,timezone,displayWeekStart,periods},courses:[...courses.values()],meetings:[...meetings.values()],occurrenceChanges:[],warnings};
}
