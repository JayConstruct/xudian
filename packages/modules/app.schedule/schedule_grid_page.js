import {data,clock} from '@xudian/sdk';
import {weekday,teachingWeek} from './calendar.js';
import {queryWeek} from './schedule_queries.js';
import {command} from './schedule_commands.js';
import {button,text} from './page_controls.js';
import {displayDraft,displayDirty,resetDisplayDraft,scheduleRowHeight,scheduleShowWeekends} from './view_helpers.js';

export async function updateDisplay({t,state,event}) {
  const draft=displayDraft(t);
  if(event?.type==='displayWeekends' && typeof event.value==='boolean') {
    draft.showWeekends=event.value;draft.error=null;delete state.notice;delete state.revealWeekends;
  }
  if(event?.type==='displayHeight') {
    const height=Number(event.value),rowHeight=(height-48)/t.periods.length;
    if(Number.isFinite(rowHeight)&&rowHeight>=48&&rowHeight<=160) {draft.rowHeight=rowHeight;draft.error=null;delete state.notice;}
  }
  if(event?.type==='stepDisplay' && [1,-1].includes(event.delta)) {
    const count=t.periods.length,height=Math.round(48+count*draft.rowHeight)+event.delta;
    draft.rowHeight=(Math.max(48+count*48,Math.min(48+count*160,height))-48)/count;draft.error=null;delete state.notice;
  }
  if(event?.type==='defaultDisplay') {draft.rowHeight=72;draft.error=null;delete state.notice;}
  if(event?.type==='resetDisplay') {resetDisplayDraft(t);delete state.notice;delete state.revealWeekends;}
  if(event?.type==='saveDisplay') {
    try {
      if(draft.baseline!==scheduleRowHeight(t)||draft.baselineShowWeekends!==scheduleShowWeekends(t))throw new Error('显示设置已在其他页面修改。草稿已保留，请重新载入后编辑。');
      const saved=await command('schedule.timetable.save',{timetable:{...t,rowHeight:draft.rowHeight,showWeekends:draft.showWeekends},expectedTimetable:t});
      if(saved) {resetDisplayDraft(await data.get('timetables',t.id));delete state.revealWeekends;state.notice='显示设置已保存';}
    } catch(error) {draft.error=error.message;}
  }
}

export async function renderGrid({t,state}) {
  const today=await clock.today(t.timezone),week=Math.max(1,Math.min(t.totalWeeks,state.week||teachingWeek(t,today)));
  state.week=week;const result=await queryWeek({timetableId:t.id,teachingWeek:week}),local=await clock.local(t.timezone);
  const draft=displayDraft(t),dirty=displayDirty(draft),count=t.periods.length,height=48+count*draft.rowHeight,showDisplay=state.displayControls===true;
  const showWeekends=showDisplay?draft.showWeekends:scheduleShowWeekends(t)||state.revealWeekends===true;
  const columns=result.columns.filter(c=>showWeekends||weekday(c.id)<6).map(c=>({...c,title:['','一','二','三','四','五','六','日'][weekday(c.id)],subtitle:c.id.slice(5),highlight:c.id===today}));
  const rows=result.rows.map((row,i)=>({...row,title:String(t.periods[i].number),subtitle:`${t.periods[i].start}\n${t.periods[i].end}`,highlight:local.time>=t.periods[i].start&&local.time<t.periods[i].end}));
  const weekend=result.items.filter(item=>weekday(item.date)>=6).length;
  state.displayDraft={...draft,dirty};
  const floatingPanel=showDisplay?{title:'课表显示设置',closeLabel:'关闭显示调整',closeEvent:{type:'closeDisplay'},top:64,child:{type:'column',spacing:6,children:[
    {type:'switch',key:`display.${t.id}.weekends`,text:'显示周六和周日',value:draft.showWeekends,event:{type:'displayWeekends'}},
    text('默认仅显示周一至周五；开启后七天完整适配屏幕。'),
    text(`总高度 ${Math.round(height)} · 默认 ${48+count*72}`),
    {type:'slider',key:`display.${t.id}.height`,text:'课表总高度',min:48+count*48,max:48+count*160,divisions:112,value:height,event:{type:'displayHeight'}},
    {type:'row',children:[{...button('−1',{type:'stepDisplay',delta:-1}),disabled:draft.rowHeight<=48},{...button('+1',{type:'stepDisplay',delta:1}),disabled:draft.rowHeight>=160},text('每次调整总高度 1') ]},
    text(dirty?'预览中，尚未保存。关闭后恢复已保存显示设置。':'调整时课表同步预览。'),
    ...(draft.error?[text(draft.error)]:[]),
    ...(state.notice?[text(state.notice)]:[]),
    {type:'row',children:[button('恢复默认高度',{type:'defaultDisplay'}),...(dirty?[button('重新载入',{type:'resetDisplay'}),button('保存显示设置',{type:'saveDisplay'})]:[])]}
  ]}}:null;
  const header={autoHideChrome:!showDisplay,title:`第 ${week} 周`,titleEvent:{type:'chooseWeek'},actions:[
    {label:'切换课表',event:{type:'chooseTimetable'}},
    {label:'回到本周',event:{type:'currentWeek'}},
    {label:'今日课程',event:{type:'navigate',page:'today'}},
    {label:'课表设置',event:{type:'navigate',page:'settings'}},
    {label:'显示设置',event:{type:'openDisplay'}},
    ...(weekend?[{label:`周末课程 · ${weekend} 次`,event:{type:'weekend'}}]:[])
  ]};
  return {state,header,tree:{type:'column',template:'ui.page.timeGrid@1',edgeToEdge:true,fillHeight:true,underlapChrome:true,spacing:0,...(floatingPanel?{floatingPanel}:{}),children:[
    {type:'timeGrid',columns,rows,blocks:result.blocks.filter(b=>columns.some(c=>c.id===b.column)),corner:{title:result.columns[0].id.slice(0,4),subtitle:`${week}周`},options:{rowHeight:showDisplay?draft.rowHeight:scheduleRowHeight(t),headerHeight:48,labelWidth:42,fillWidth:true,fitColumns:true,underlapChrome:true}}
  ]}};
}
