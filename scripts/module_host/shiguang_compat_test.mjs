import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {convert,suggestedMonday} from '../../packages/modules/app.import.shiguang/convert.js';
import {captureScript,compileBridge} from '../../packages/modules/app.import.shiguang/bridge.js';
import {adapters,loadAdapter,snapshot} from '../../packages/modules/app.import.shiguang/warehouse/catalog.js';
import {listAdapters} from '../../packages/modules/app.import.shiguang/schools.js';

const options={name:'测试课表',scope:'school/student/2026-autumn',firstMonday:'2026-09-07',totalWeeks:20};
const row={name:'数学',teacher:'老师',position:'A101',day:1,startSection:1,endSection:2,weeks:[5,1,3,1]};
test('maps course and recurrence, merges duplicate fragments with stable identities',()=>{
  const a=convert({payload:{courses:[row,{...row,weeks:[7]}]},options});
  assert.equal(a.courses.length,1);assert.equal(a.meetings.length,1);
  assert.deepEqual(a.meetings[0].weeks,[1,3,5,7]);
  assert.equal(a.meetings[0].location,'A101');assert.equal(a.complete,false);
  const b=convert({payload:[{...row,weeks:[9]}],options});
  assert.equal(a.meetings[0].sourceId,b.meetings[0].sourceId);
  assert.equal(a.timetable.periods.length,12);
});
test('converts supplied times, color and optional course fields',()=>{
  const draft=convert({payload:{courses:[{...row,color:-65536,remark:'备注',credit:2}],timeSlots:[{number:1,startTime:'08:00',endTime:'08:45'},{number:2,startTime:'08:50',endTime:'09:35'}],config:{semesterTotalWeeks:16}},options:{...options,totalWeeks:undefined,complete:true}});
  assert.equal(draft.timetable.totalWeeks,16);assert.equal(draft.courses[0].color,'#ff0000');
  assert.equal(draft.courses[0].notes,'备注');assert.equal(draft.courses[0].credit,2);
  assert.equal(draft.complete,true);assert.equal(draft.timetable.periods[1].start,'08:50');
});
test('warehouse course codes and random ids do not become meeting identities',()=>{
  const draft=convert({payload:[{...row,id:'course-code'},{...row,id:'course-code',day:2}],options});
  assert.equal(draft.meetings.length,2);
  const repeat=convert({payload:[{...row,id:'another-random-value'}],options});
  assert.equal(draft.meetings[0].sourceId,repeat.meetings[0].sourceId);
});
test('Sunday-start weeks preserve occurrence dates and reject unrepresentable first Sunday',()=>{
  const config={semesterStartDate:'2026-09-06',firstDayOfWeek:7};
  const draft=convert({payload:{courses:[{...row,day:7,weeks:[2,3]}],config},options});
  assert.deepEqual(draft.meetings[0].weeks,[1,2]);
  const meeting=draft.meetings[0];
  const actual=meeting.weeks.map(w=>new Date(Date.parse(draft.timetable.firstMonday+'T00:00:00Z')+((w-1)*7+meeting.weekday-1)*86400000).toISOString().slice(0,10));
  assert.deepEqual(actual,['2026-09-13','2026-09-20']);
  assert.throws(()=>convert({payload:{courses:[{...row,day:7,weeks:[1,2]}],config},options}),/第1周周日/);
  const monday=convert({payload:{courses:[row],config},options});
  assert.deepEqual(monday.meetings[0].weeks,[1,3,5]);
});
test('normalizes unsorted periods but rejects gaps and duplicate section numbers',()=>{
  const periods=[{number:'2',startTime:'08:50',endTime:'09:35'},{number:'1',startTime:'08:00',endTime:'08:45'}];
  assert.equal(convert({payload:{courses:[row],timeSlots:periods},options}).timetable.periods[0].start,'08:00');
  for(const number of [1,3])assert.throws(()=>convert({payload:{courses:[row],timeSlots:[periods[1],{...periods[0],number}]},options}),/连续排列/);
});
test('aligns semester dates to the source week convention',()=>{
  assert.equal(suggestedMonday({semesterStartDate:'2026-09-09',firstDayOfWeek:1}),'2026-09-07');
  assert.equal(suggestedMonday({semesterStartDate:'2026-09-06',firstDayOfWeek:7}),'2026-09-07');
  assert.equal(suggestedMonday({semesterStartDate:'2026-09-09',firstDayOfWeek:7}),'2026-09-07');
  assert.throws(()=>suggestedMonday({semesterStartDate:'2026-02-30'}),/日期不存在/);
});
test('rejects unsupported schedules and malformed records atomically',()=>{
  for (const changes of [{day:0},{weeks:[21]},{startSection:0},{isCustomTime:true},{teacher:4}]) {
    assert.throws(()=>convert({payload:[row,{...row,...changes}],options}));
  }
  assert.throws(()=>convert({payload:{courses:[row],comboSchedule:{publicSchedules:[{}]}},options}),/组合作息/);
  assert.throws(()=>convert({payload:{courses:[row],timeSlots:[{number:1,startTime:'08:00',endTime:'09:00'},{number:2,startTime:'08:50',endTime:'09:35'}]},options}),/重叠/);
  assert.throws(()=>convert({payload:[{...row,sourceId:'same'},{...row,sourceId:'same',day:2}],options}),/来源ID/);
});
function runtime() {
  const messages=[];
  const window={xudianCapture:{send:(type,value)=>messages.push({type,value})},confirm:()=>true,prompt:()=>null,alert:()=>{}};
  const context=vm.createContext({window});
  vm.runInContext(captureScript(''),context);
  return {window,messages,context};
}
test('stages all save calls until completion, supports old bridge aliases',async()=>{
  const {window,messages}=runtime(),api=window.AndroidBridgePromise;
  await api.saveImportedCourses(JSON.stringify([row]));
  await api.savePresetTimeSlots(JSON.stringify([{number:1,startTime:'08:00',endTime:'08:45'}]));
  await api.saveCourseConfig(JSON.stringify({semesterTotalWeeks:20}));
  assert.equal(messages.length,0);
  window.shiguangBridge.notifyTaskCompletion();window.shiguangBridge.notifyTaskCompletion();
  assert.equal(messages.length,1);assert.equal(messages[0].type,'complete');
  assert.equal(messages[0].value.courses[0].name,'数学');
  assert.equal(messages[0].value.timeSlots[0].number,1);
});
test('failed stage or empty result cannot signal successful completion',async()=>{
  const {window,messages}=runtime();
  await window.shiguangBridgePromise.saveImportedCourses(JSON.stringify([row]));
  await assert.rejects(window.shiguangBridgePromise.savePresetTimeSlots('{}'));
  window.shiguangBridge.notifyTaskCompletion();assert.equal(messages[0].type,'error');
  const empty=runtime();empty.window.shiguangBridge.notifyTaskCompletion();assert.equal(empty.messages[0].type,'error');
});
test('old asynchronous executions retain their original transport',async()=>{
  const {window,messages,context}=runtime(),old=window.shiguangBridge;
  await window.shiguangBridgePromise.saveImportedCourses(JSON.stringify([row]));
  const newer=[];window.xudianCapture={send:(type,value)=>newer.push({type,value})};
  vm.runInContext(captureScript(''),context);
  old.notifyTaskCompletion();assert.equal(messages.length,1);assert.equal(newer.length,0);
});
test('public bridge compiler validates version and final UTF-8 size',()=>{
  assert.throws(()=>compileBridge({script:'   '}),/不能为空/);
  assert.throws(()=>compileBridge({script:'void 0',bridgeVersion:2}),/版本/);
  assert.throws(()=>compileBridge({script:'中'.repeat(90000)}),/256 KiB/);
  const compiled=compileBridge({script:'window.shiguangBridge.showToast("学校脚本");'});
  assert.equal(compiled.bridgeVersion,1);
  assert.ok(Buffer.byteLength(compiled.script)<=256*1024);
  const messages=[];
  vm.runInNewContext(compiled.script,{window:{xudianCapture:{send:(type,value)=>messages.push({type,value})}}});
  assert.deepEqual(messages,[{type:'status',value:'学校脚本'}]);
});
test('named validators work through new Function and false means valid',async()=>{
  const answers=['bad','2026'];const errors=[];
  const {window,context}=runtime();
  window.prompt=()=>answers.shift();window.alert=value=>errors.push(value);
  // This matches the actual Android transport execution and its local scope.
  vm.runInContext('new Function('+JSON.stringify(captureScript(`
    function validateYear(value){return /^\\d{4}$/.test(value)?false:'请输入四位学年';}
    window.result=window.shiguangBridgePromise.showPrompt('学年','提示','2026','validateYear');
  `))+')()',context);
  assert.equal(await window.result,'2026');assert.deepEqual(errors,['请输入四位学年']);
});
test('selection cancellation returns null and invalid selection can be retried',async()=>{
  const {window}=runtime();
  assert.equal(await window.shiguangBridgePromise.showSingleSelection('学期',['秋','春']),null);
  const answers=['','0','3','2'];window.prompt=()=>answers.shift();
  assert.equal(await window.shiguangBridgePromise.showSingleSelection('学期','["秋","春"]',0),1);
});
test('maps exact custom times and numeric API strings without guessing',()=>{
  const draft=convert({payload:{courses:[{...row,isCustomTime:true,startSection:null,endSection:null,day:'1',weeks:['1','3'],customStartTime:'8:00:00',customEndTime:'09:35:00'}],timeSlots:[{number:'1',startTime:'8:00',endTime:'8:45'},{number:'2',startTime:'8:50:00',endTime:'9:35:00'}]},options});
  assert.equal(draft.meetings[0].startPeriod,1);assert.equal(draft.meetings[0].endPeriod,2);
  assert.equal(draft.timetable.periods[0].start,'08:00');assert.equal(draft.meetings[0].weekday,1);
  assert.ok(draft.warnings.some(s=>s.includes('自定义')));
  assert.throws(()=>convert({payload:[{...row,isCustomTime:true,customStartTime:'08:01',customEndTime:'09:35'}],options}),/无法准确/);
  assert.throws(()=>convert({payload:[{...row,isCustomTime:true,customStartTime:'08:00:10',customEndTime:'09:35'}],options}),/秒数/);
  assert.doesNotThrow(()=>convert({payload:[{...row,isCustomTime:false,customStartTime:'07:00',customEndTime:'08:00'}],options}));
});
test('all pinned warehouse adapters compile with the supported bridge and transport limit',async()=>{
  assert.equal(snapshot.adapters,adapters.length);
  for(const adapter of adapters){
    assert.deepEqual(adapter.unsupportedMethods,[],adapter.id);
    const loaded=await loadAdapter(adapter.id);
    const compiled=compileBridge({script:loaded.script});
    assert.doesNotThrow(()=>new vm.Script(compiled.script),adapter.id);
  }
});
test('school catalog supports search, safe pagination and absent adapters',async()=>{
  const results=listAdapters({search:'东北大学 研究生'});
  assert.ok(results.items.some(a=>a.school==='东北大学'&&a.category==='POSTGRADUATE'));
  assert.equal(listAdapters({search:'不存在的学校 qxz'}).total,0);
  assert.equal(listAdapters({page:999}).page,listAdapters().pages-1);
  assert.equal(listAdapters({page:-1}).page,0);
  assert.equal(new Set(adapters.map(a=>a.id)).size,adapters.length);
  await assert.rejects(loadAdapter('../../main.js'),/不存在/);
});

async function runWarehouseAdapter(id,{prompts=['2026','1'],payload,origin='https://school.example',cancel=false}={}) {
  const messages=[],requests=[],alertErrors=[];
  const sandbox={
    console:{log(){},warn(){},error(){}},URL,location:{origin,href:origin+'/'},
    xudianCapture:{send:(type,value)=>messages.push({type,value})},
    confirm:()=>!cancel,prompt:()=>prompts.shift()??null,alert:value=>alertErrors.push(value),
    fetch:async(url,options)=>{requests.push({url:String(url),options});return {ok:true,status:200,statusText:'OK',text:async()=>JSON.stringify(payload),json:async()=>payload};},
  };
  sandbox.window=sandbox;
  const context=vm.createContext(sandbox),{script}=await loadAdapter(id);
  vm.runInContext('new Function('+JSON.stringify(captureScript(script))+')()',context,{timeout:1000});
  // Advance only microtasks; fixtures never access a real server or account.
  for(let i=0;i<150;i++)await Promise.resolve();
  return {messages,requests,alertErrors};
}
test('unchanged YXHMC official JSON adapter validates input and imports thirteen periods',async()=>{
  const result=await runWarehouseAdapter('YXHMC',{prompts:['bad','2026','1'],payload:{kbList:[{kcmc:'数学',xm:'王老师',cdmc:'A101',xqj:'2',jcs:'1-2',zcd:'1-5周(单)'}]}});
  const complete=result.messages.find(m=>m.type==='complete');
  assert.ok(complete,JSON.stringify(result));assert.ok(result.alertErrors.length);
  const draft=convert({payload:complete.value,options});
  assert.equal(draft.timetable.periods.length,13);assert.deepEqual(draft.meetings[0].weeks,[1,3,5]);
});
test('unchanged NEU postgraduate official adapter imports string section IDs',async()=>{
  const result=await runWarehouseAdapter('NEU_2',{payload:{jcList:[{DM:'1',KSSJ:800,JSSJ:845},{DM:'2',KSSJ:850,JSSJ:935}],jgList:[{KCMC:'数学',JGJSXM:'老师',JASMC:'A101',XQ:'1',KSJCDM:'1',JSJCDM:'2',ZCBH:'10101'}]}});
  const complete=result.messages.find(m=>m.type==='complete');assert.ok(complete,JSON.stringify(result));
  const draft=convert({payload:complete.value,options});assert.equal(draft.meetings[0].endPeriod,2);assert.deepEqual(draft.meetings[0].weeks,[1,3,5]);
});
test('official adapters respect cancellation without fetching or completing',async()=>{
  const result=await runWarehouseAdapter('YXHMC',{cancel:true});
  assert.equal(result.requests.length,0);assert.ok(!result.messages.some(m=>m.type==='complete'));
  const selection=await runWarehouseAdapter('NEU_2',{prompts:['2026',null]});
  assert.equal(selection.requests.length,0);assert.ok(!selection.messages.some(m=>m.type==='complete'));
});
