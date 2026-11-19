import {clock, data} from '@xudian/sdk';
export function cleanTitle(value,max,label) { if(typeof value!=='string'||!value.trim()||value.trim().length>max) throw new Error(`${label}需为1–${max}个字符`); return value.trim(); }
export function validDate(value) {
  if(value==null) return;
  if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(value)||Number(value.slice(0,4))<1) throw new Error('日期格式必须为 YYYY-MM-DD');
  const date=new Date(value+'T00:00:00Z');
  if(!Number.isFinite(date.getTime())||date.toISOString().slice(0,10)!==value) throw new Error('日期不存在');
}
export function canonical(v) { const stable=x=>Array.isArray(x)?x.map(stable):x&&typeof x==='object'?Object.fromEntries(Object.keys(x).sort().map(k=>[k,stable(x[k])])):x;return JSON.stringify(stable(v)); }
// Keep the optimistic token advancing even when writes share a clock tick.
export async function nextUpdatedAt(previous) {
  const now=await clock.now(),prior=Date.parse(previous||'');
  return Number.isFinite(prior)&&prior>=Date.parse(now)?new Date(prior+1).toISOString():now;
}
export async function check(input) {
  const t=await data.get('tasks',input.id); if(!t||t.deletedAt) throw new Error('任务已不可用');
  if(input.expectedUpdatedAt&&t.updatedAt!==input.expectedUpdatedAt||input.expectedValues&&Object.entries(input.expectedValues).some(([k,v])=>canonical(v)!==canonical(t[k]??null))) throw new Error('任务已被其他操作修改，请重新生成方案');
  return t;
}
