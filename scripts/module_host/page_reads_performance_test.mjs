// Run with: node --experimental-vm-modules scripts/module_host/page_reads_performance_test.mjs
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import vm from 'node:vm';

const root=resolve(import.meta.dirname,'../..');
const sdk=readFileSync(resolve(root,'packages/xquickjs/lib/xquickjs.dart'),'utf8').match(/const sdkSource = r'''([\s\S]*?)''';/)[1];
async function moduleFor(id,host,replace=source=>source) {
  const base=resolve(root,'packages/modules',id),context=vm.createContext({__host:host}),modules=new Map();
  const sourceModule=(path)=>{
    if(!modules.has(path))modules.set(path,new vm.SourceTextModule(path==='@xudian/sdk'?sdk:replace(readFileSync(path,'utf8'),path),{context,identifier:path}));
    return modules.get(path);
  };
  const module=sourceModule(resolve(base,'main.js'));
  await module.link((name,from)=>sourceModule(name==='@xudian/sdk'?name:resolve(dirname(from.identifier),name)));
  await module.evaluate();
  return module.namespace;
}
const clone=value=>JSON.parse(JSON.stringify(value));
function local({utc,zone}) {
  const values=Object.fromEntries(new Intl.DateTimeFormat('en-CA',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).formatToParts(new Date(utc)).map(part=>[part.type,part.value]));
  return {date:`${values.year}-${values.month}-${values.day}`,time:`${values.hour}:${values.minute}`};
}
const legacyLabels=`async function plannedLabels(tasks,selectedDate) {
  const labels=[];
  for(const task of tasks) {
    if(task.plannedStartAt&&task.plannedEndAt&&task.plannedTimezone) {
      const start=await clock.toLocal({utc:task.plannedStartAt,zone:task.plannedTimezone}),end=await clock.toLocal({utc:task.plannedEndAt,zone:task.plannedTimezone});
      const startDate=start.date===selectedDate?'':\`\${shortDate(start.date,selectedDate)} \`;
      const endDate=end.date===start.date?'':\`\${shortDate(end.date,selectedDate)} \`;
      labels.push(\`计划 \${startDate}\${start.time}–\${endDate}\${end.time} (\${task.plannedTimezone})\`);
    } else labels.push(task.plannedDate&&\`计划 \${task.plannedDate===selectedDate?'当天':shortDate(task.plannedDate,selectedDate)}\`);
  }
  return labels;
}
`;
for(const count of [0,50,129,10000]) {
  const tasks=Array.from({length:count},(_,index)=>({id:'task-'+index,title:'任务 '+index,plannedStartAt:'2026-11-01T05:30:00Z',plannedEndAt:'2026-11-01T06:30:00Z',plannedTimezone:index%2?'Asia/Shanghai':'America/New_York'}));
  if(count<10000)tasks.push({id:'date-only',title:'按日安排',plannedDate:'2026-11-01'});
  async function render(legacy) {
    const batches=[],calls=[];
    const module=await moduleFor('app.views.today',async(method,args)=>{
      calls.push(method);
      if(method==='clock.today')return '2026-11-01';
      if(method==='services.query')return args.ref.serviceId==='task.list'?tasks:[];
      if(method==='clock.toLocal')return local(args);
      if(method==='clock.toLocalMany'){
        assert.ok(args.items.length<=256);
        batches.push(args.items.length);
        return args.items.map(local);
      }
      throw Error('Unexpected request '+method);
    },source=>legacy?source.replace(/async function plannedLabels\(tasks,selectedDate\) \{[\s\S]*?(?=async function deadlineLabels)/,legacyLabels):source);
    return {result:clone(await module.render({context:{pageId:'app.views.today.tasks',selectedDate:'2026-11-01'},state:{selectedDate:'2026-11-01',taskLimit:10000}})),batches,calls};
  }
  const current=await render(false),legacy=await render(true);
  assert.deepEqual(current.result,legacy.result);
  assert.equal(current.calls.filter(method=>method==='clock.toLocal').length,0);
  assert.equal(legacy.calls.filter(method=>method==='clock.toLocal').length,count*2);
  assert.equal(current.batches.length,Math.ceil(count/128));
  console.log(`today ${count} precise plans: ${count*2} -> ${current.batches.length} clock bridges, identical tree`);
}

const legacySnapshot=`async function snapshot(timetableId) {
  const t=await data.get('timetables',timetableId);if(!t)throw Error('课表不存在');
  const filter={field:'timetableId',op:'eq',value:timetableId};
  return {t,courses:await data.query('courses',{filter}),meetings:await data.query('meetings',{filter}),changes:await data.query('occurrenceChanges',{filter})};
}
`;
function utc({date,time,zone}) {
  const wall=Date.parse(`${date}T${time}:00Z`);
  let instant=wall;
  for(let iteration=0;iteration<4;iteration++) {
    const current=local({utc:new Date(instant).toISOString(),zone});
    const offset=Date.parse(`${current.date}T${current.time}:00Z`)-instant;
    const next=wall-offset;
    if(next===instant)return {status:'unique',instants:[new Date(instant).toISOString()]};
    instant=next;
  }
  throw Error('Fixture time did not resolve');
}
const tables=['America/New_York','Asia/Shanghai'].map(zone=>({id:zone,name:zone,firstMonday:'2026-10-26',totalWeeks:2,timezone:zone,periods:[{number:1,start:'09:00',end:'10:00'}]}));
async function feed(input,legacy) {
  const calls=[],pending=new Map();
  const module=await moduleFor('app.schedule',async(method,args)=>{
    calls.push([method,args]);
    if(method==='clock.today')return args.zone?local({utc:'2026-11-01T03:00:00Z',zone:args.zone}).date:'2026-11-01';
    if(method==='clock.local')return local({utc:'2026-11-01T03:00:00Z',zone:args.zone});
    if(method==='clock.now')return '2026-11-01T03:00:00Z';
    if(method==='clock.toUtc')return utc(args);
    if(method==='data.get')return tables.find(table=>table.id===args.id);
    if(method==='data.query'){
      if(args.collection==='timetables')return tables;
      const timetableId=args.filter.value;
      const value=args.collection==='courses'?[{id:'course',timetableId,name:'数学'}]:args.collection==='meetings'?[{id:'meeting',courseId:'course',timetableId,weeks:[1],weekday:timetableId==='America/New_York'?6:7,startPeriod:1,endPeriod:1}]:[];
      if(legacy)return value;
      return new Promise(resolve=>{
        pending.set(args.collection,{resolve,value});
        if(pending.size===3){for(const {resolve,value} of pending.values())resolve(value);pending.clear();}
      });
    }
    throw Error('Unexpected request '+method);
  },source=>legacy?source.replace(/async function snapshot\([\s\S]*?(?=export async function queryTimetables)/,legacySnapshot).replace('todayFromSnapshot(content,selectedDate===undefined?local.date:date)','todayFromSnapshot(content,selectedDate===undefined?await clock.today(timetable.timezone):date)'):source);
  const timeout=setTimeout(()=>{throw Error('Independent snapshot requests did not arrive together');},2000);
  try{return {result:clone(await module.queryTodayFeed(input)),calls};}finally{clearTimeout(timeout);}
}
for(const input of [{},{date:'2026-11-01'},{date:'2026-10-31'},{date:'9999-12-31'}]) {
  const current=await feed(input,false),legacy=await feed(input,true);
  assert.deepEqual(current.result,legacy.result);
  assert.equal(current.calls.filter(([method])=>method==='data.get').length,0);
  assert.equal(legacy.calls.filter(([method])=>method==='data.get').length,2);
  assert.equal(current.calls.filter(([method,args])=>method==='clock.today'&&args.zone).length,0);
  console.log(`schedule ${input.date||'today'}: timetable reads 3 -> 1, identical timezone feed, independent reads dispatched together`);
}
