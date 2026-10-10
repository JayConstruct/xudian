// All arithmetic is on civil dates. Device timezone and DST never affect weeks.
export const dayMs = 86400000;
export function civil(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new Error('日期格式必须为 YYYY-MM-DD');
  const millis = Date.parse(value+'T00:00:00Z');
  if (!Number.isFinite(millis) || new Date(millis).toISOString().slice(0,10)!==value) throw new Error('日期不存在');
  return millis;
}
export const date = value => new Date(value).toISOString().slice(0,10);
export const addDays = (value, days) => date(civil(value)+days*dayMs);
export const weekday = value => (new Date(civil(value)).getUTCDay()+6)%7+1;
export const teachingWeek = (t, value) => Math.floor((civil(value)-civil(t.firstMonday))/(7*dayMs))+1;
export const occurrenceDate = (t, week, day) => addDays(t.firstMonday,(week-1)*7+day-1);
export function normalizeWeeks(input, total) {
  let weeks = input;
  if (typeof weeks === 'string') {
    let text=weeks.trim(), parity=null;
    if (text.endsWith('单') || text.endsWith('双')) { parity=text.endsWith('单')?1:0; text=text.slice(0,-1); }
    weeks=[];
    for (const token of text.split(/[,，\s]+/).filter(Boolean)) {
      if (/^\d+$/.test(token)) weeks.push(Number(token));
      else if (/^\d+-\d+$/.test(token)) {
        const [start,end]=token.split('-').map(Number);
        if(end<start || end-start>1000) throw new Error('周次范围无效');
        for(let w=start;w<=end;w++) weeks.push(w);
      } else throw new Error('周次格式：1-16单 或 1,3,8-10');
    }
    if(parity!==null) weeks=weeks.filter(w=>w%2===parity);
  }
  if(!Array.isArray(weeks) || !weeks.length || weeks.some(w=>!Number.isInteger(w)||w<1||w>total)) throw new Error('周次超出课表范围');
  return [...new Set(weeks)].sort((a,b)=>a-b);
}
function minutes(text) {
  if(!/^\d{2}:\d{2}$/.test(text)) throw new Error('作息时间需为 HH:mm');
  const [h,m]=text.split(':').map(Number);
  if(h>23 || m>59) throw new Error('作息时间无效');
  return h*60+m;
}
export function validateTimetable(t) {
  if(!t.name?.trim() || t.name.length>120) throw new Error('请输入课表名称（最多120字）');
  civil(t.firstMonday);
  if(weekday(t.firstMonday)!==1) throw new Error('第一教学周必须从周一开始');
  if(!Number.isInteger(t.totalWeeks)||t.totalWeeks<1||t.totalWeeks>100) throw new Error('总周数需在1–100之间');
  if(typeof t.timezone!=='string' || !t.timezone) throw new Error('缺少课表时区');
  if(![1,7].includes(t.displayWeekStart)) throw new Error('显示起始需为周一或周日');
  if(!Array.isArray(t.periods)||!t.periods.length||t.periods.length>30) throw new Error('配置1–30个节次');
  if(t.rowHeight!==undefined && (!Number.isFinite(t.rowHeight)||t.rowHeight<48||t.rowHeight>160)) throw new Error('课表每节显示高度需在48–160之间');
  if(t.showWeekends!==undefined && typeof t.showWeekends!=='boolean') throw new Error('周末显示设置需为开关值');
  let end=-1;
  t.periods.forEach((p,i)=> {
    if(p.number!==i+1 || minutes(p.start)<end || minutes(p.end)<=minutes(p.start)) throw new Error('节次必须连续，时间不重叠、不跨午夜');
    end=minutes(p.end);
  });
  return t;
}
export function validateMeeting(m,t,courses) {
  if(!courses.some(c=>c.id===m.courseId && c.timetableId===t.id)) throw new Error('课程引用不存在');
  if(!Number.isInteger(m.weekday)||m.weekday<1||m.weekday>7) throw new Error('星期需在1–7之间');
  if(!Number.isInteger(m.startPeriod)||!Number.isInteger(m.endPeriod)||m.startPeriod<1||m.endPeriod<m.startPeriod||m.endPeriod>t.periods.length) throw new Error('节次范围无效');
  return {...m,weeks:normalizeWeeks(m.weeks,t.totalWeeks)};
}
export function validOriginal(m,t,original) {
  const w=teachingWeek(t,original);
  return weekday(original)===m.weekday && m.weeks.includes(w);
}
export function validateChange(c,t,meetings,courses) {
  civil(c.originalDate);
  if(!['cancel','replace','extra'].includes(c.kind)) throw new Error('调课类型无效');
  const m=meetings.find(m=>m.id===c.meetingId);
  if(c.kind!=='extra' && (!m || !validOriginal(m,t,c.originalDate))) throw new Error('原课程实例不存在');
  if(c.kind!=='cancel') {
    civil(c.date);
    if(!courses.some(x=>x.id===(c.courseId || m?.courseId))) throw new Error('调课课程不存在');
    if(!Number.isInteger(c.startPeriod)||!Number.isInteger(c.endPeriod)||c.startPeriod<1||c.endPeriod<c.startPeriod||c.endPeriod>t.periods.length) throw new Error('调课节次无效');
  }
  return c;
}
export function occurrences(t,courses,meetings,changes,start,end) {
  const result=[], byCourse=new Map(courses.map(c=>[c.id,c]));
  const append=(m,day,change=null)=> {
    const course=byCourse.get(change?.courseId || m?.courseId);
    if(!course) return;
    const item={...m,...change,courseId:course.id,date:day,title:course.name,color:course.color,
      originalDate:change?.originalDate || day,meetingId:change?.meetingId || m?.id,
      occurrenceId:change?.kind==='extra'?change.id:`${m.id}:${change?.originalDate || day}`};
    delete item.weeks; result.push(item);
  };
  for(const m of meetings) {
    for(const w of m.weeks) {
      const day=occurrenceDate(t,w,m.weekday);
      if(day<start || day>=end) continue;
      if(!changes.some(c=>c.kind!=='extra'&&c.meetingId===m.id&&c.originalDate===day)) append(m,day);
    }
  }
  for(const c of changes) {
    if(c.kind==='cancel'||c.date<start||c.date>=end) continue;
    append(meetings.find(m=>m.id===c.meetingId),c.date,c);
  }
  return result.sort((a,b)=>a.date.localeCompare(b.date)||a.startPeriod-b.startPeriod||a.title.localeCompare(b.title));
}
export function overlaps(items) {
  const warnings=[];
  for(let i=0;i<items.length;i++) for(let j=i+1;j<items.length;j++) {
    const a=items[i],b=items[j];
    if(a.date===b.date && a.startPeriod<=b.endPeriod && b.startPeriod<=a.endPeriod) warnings.push(`${a.date}：${a.title} / ${b.title} 节次重叠`);
  }
  return [...new Set(warnings)];
}
