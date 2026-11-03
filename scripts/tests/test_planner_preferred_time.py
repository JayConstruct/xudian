"""Preferred times rank a date's feasible starts without changing date rules."""
import subprocess
import unittest
from pathlib import Path


ENGINE = Path(__file__).resolve().parents[2] / 'packages/modules/app.planner/engine.js'


class PlannerPreferredTimeTest(unittest.TestCase):
    def check(self, code):
        fixture = r'''
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const e = await import('data:text/javascript;base64,'+readFileSync(process.argv[1]).toString('base64'));
const date='2026-11-03';
const rules={interval:{minDays:1,maxDays:1},weekdays:[1,2,3,4,5,6,7],timeWindow:{start:'18:00',end:'22:00'}};
const draft = extra => e.creationDraft({title:'论文',timezone:'UTC',firstDate:date,estimatedMinutes:30,rules,...extra},date,'UTC');
const a=e.availability({timezone:'UTC',bufferMinutes:0,weekly:{'2':[{start:'18:00',end:'22:00'}]}});
const plan=(d,extra={})=>e.arrangeCreation(d,{seriesId:'series',startDate:date,endDate:date,a,...extra});
const preferred=(value='20:03',extra={})=>draft({rules:{...rules,preferredTime:value},...extra});
'''
        run = subprocess.run(['node', '--input-type=module', '-e', fixture + code, str(ENGINE)],
                             text=True, capture_output=True)
        self.assertEqual(run.returncode, 0, run.stderr)

    def test_exact_minute_is_not_rounded_to_five_minute_grid(self):
        self.check(r'''
const p=plan(preferred());
assert.equal(p.assigned[0].start,'20:03');
assert.equal(p.assigned[0].end,'20:33');
assert.equal(p.assigned[0].preferredTime,'20:03');
assert.equal(p.unassigned.length,0);
''')

    def test_conflict_uses_nearest_valid_start_and_earlier_tie(self):
        self.check(r'''
const p=plan(preferred(),{busy:[{date,start:e.minute('20:03'),end:e.minute('20:33')}]});
assert.equal(p.assigned[0].start,'20:35');
const tie=plan(preferred('20:00',{estimatedMinutes:5}),{busy:[{date,start:e.minute('20:00'),end:e.minute('20:05')}]});
assert.equal(tie.assigned[0].start,'19:55');
const buffered=plan(preferred('20:00',{estimatedMinutes:5}),{a:{...a,bufferMinutes:10},busy:[{date,start:e.minute('20:00'),end:e.minute('20:05')}]});
assert.equal(buffered.assigned[0].start,'19:45');
''')

    def test_rank_across_available_fragments_and_exception_slots(self):
        self.check(r'''
const fragments={...a,weekly:{'2':[{start:'18:00',end:'18:30'},{start:'20:00',end:'21:00'}]}};
assert.equal(plan(preferred(),{a:fragments}).assigned[0].start,'20:03');
const excluded={...a,weekly:{'2':[{start:'18:00',end:'19:30'},{start:'20:50',end:'22:00'}]}};
assert.equal(plan(preferred(),{a:excluded}).assigned[0].start,'20:50');
const exceptions={...a,exceptions:{[date]:[{start:'18:00',end:'18:30'},{start:'21:00',end:'21:45'}]}};
assert.equal(plan(preferred(),{a:exceptions}).assigned[0].start,'21:00');
''')

    def test_window_validation_and_explicit_clear(self):
        self.check(r'''
for(const value of ['17:59','21:31','22:00','24:00','20:3','',5])assert.throws(()=>preferred(value));
assert.equal(preferred('21:30').rules.preferredTime,'21:30');
assert.equal(preferred('18:00').rules.preferredTime,'18:00');
assert.deepEqual(preferred(null),draft({}));
assert.equal('preferredTime' in preferred(null).rules,false);
''')

    def test_manual_override_and_locked_position_take_priority(self):
        self.check(r'''
const d=preferred();
const manual=plan(d,{adjustments:[{id:'series:batch:0',date,start:'19:07',end:'19:37',scope:'only'}]});
assert.equal(manual.assigned[0].start,'19:07');
assert.equal(manual.assigned[0].manualAdjusted,true);
const c={...plan(d).assigned[0],id:'locked',locked:true,task:{plannedDate:date},localDate:date,localStart:'19:07',localEnd:'19:37'};
const locked=e.arrange([c],a,{startDate:date,endDate:date},[]);
assert.equal(locked.assigned[0].start,'19:07');
assert.equal(locked.assigned[0].locked,true);
const blocked=plan(d,{busy:[{date,start:e.minute('19:00'),end:e.minute('20:00')}],adjustments:[{id:'series:batch:0',date,start:'19:07',end:'19:37',scope:'only'}]});
assert.equal(blocked.assigned.length,0);
assert.equal(blocked.unassigned.length,1);
''')

    def test_absent_preference_keeps_legacy_results_and_date_order(self):
        self.check(r'''
const legacy=plan(draft({}));
assert.equal(legacy.assigned[0].start,'18:00');
assert.equal('preferredTime' in legacy.assigned[0],false);
const intervalRules={...rules,interval:{minDays:2,maxDays:3}};
const original=draft({rules:intervalRules});
const revised=draft({rules:{...intervalRules,preferredTime:'20:03'}});
const allDays={...a,weekly:Object.fromEntries([1,2,3,4,5,6,7].map(d=>[d,[{start:'18:00',end:'22:00'}]]))};
const options={a:allDays,endDate:'2026-11-20'};
const first=plan(original,options).assigned,second=plan(revised,options).assigned;
assert.deepEqual(second.map(c=>[c.date,c.sequence,c.windowStart,c.windowEnd]),first.map(c=>[c.date,c.sequence,c.windowStart,c.windowEnd]));
assert.equal(second.every(c=>c.start==='20:03'),true);
''')


if __name__ == '__main__':
    unittest.main()
