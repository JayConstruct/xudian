import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {convert,suggestedMonday} from '../../packages/modules/app.import.shiguang/convert.js';
import {captureScript,compileBridge} from '../../packages/modules/app.import.shiguang/bridge.js';

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
