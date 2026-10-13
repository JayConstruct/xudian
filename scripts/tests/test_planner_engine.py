"""Exercise planner civil-date expansion and scheduling without the host bridge."""
import subprocess
import unittest
from pathlib import Path


ENGINE = Path(__file__).resolve().parents[2] / 'packages/modules/app.planner/engine.js'


class PlannerEngineTest(unittest.TestCase):
    def check(self, code):
        fixture = r'''
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const e = await import('data:text/javascript;base64,'+readFileSync(process.argv[1]).toString('base64'));
const v = overrides => e.rule({id:'r',title:'练习',startDate:'2026-10-13',timezone:'Asia/Shanghai',kind:'interval',maxGapDays:6,earlyDays:2,lastCompletedOn:'2026-10-13',effectiveOn:'2026-10-13',version:1,...overrides});
const rules = overrides => [{id:'r',versions:[v(overrides)]}];
const a = e.availability({bufferMinutes:0,weekly:Object.fromEntries([1,2,3,4,5,6,7].map(d=>[d,[{start:'09:00',end:'12:00'}]]))});
const range = (start='2026-10-13',days=14) => e.range({startDate:start,days},start);
const candidate = overrides => ({id:'one',ruleId:'r',kind:'once',title:'任务',status:'pending',optional:false,startDate:'2026-10-13',endDate:'2026-10-13',weekdays:[1,2,3,4,5,6,7],times:[{start:'09:00',end:'12:00'}],estimatedMinutes:30,priority:0,...overrides});
'''
        run = subprocess.run(['node', '--input-type=module', '-e', fixture + code, str(ENGINE)],
                             text=True, capture_output=True)
        self.assertEqual(run.returncode, 0, run.stderr)

    def test_rule_edit_refreshes_future_unconfirmed_defaults_and_keeps_status(self):
        self.check(r'''
const first=v({kind:'once',startDate:'2026-10-15',endDate:'2026-10-19'});
const saved=e.expand([{id:'r',versions:[first]}],[],[],range(),'2026-10-13')[0];
const updated=v({kind:'once',version:2,effectiveOn:'2026-10-14',startDate:'2026-10-16',endDate:'2026-10-22',title:'新版规则',estimatedMinutes:60,priority:3,weekdays:[4,5],times:[{start:'10:00',end:'11:00'}]});
for(const status of ['pending','skipped','cancelled']) {
 const c=e.expand([{id:'r',versions:[first,updated]}],[{...saved,status,locked:true}],[],range('2026-10-14',14),'2026-10-14')[0];
 assert.equal(c.id,saved.id);
 assert.equal(c.version,2);
 assert.equal(c.title,'新版规则');
 assert.equal(c.estimatedMinutes,60);
 assert.equal(c.priority,3);
 assert.deepEqual(c.weekdays,[4,5]);
 assert.deepEqual(c.times,[{start:'10:00',end:'11:00'}]);
 assert.equal(c.startDate,'2026-10-16');
 assert.equal(c.endDate,'2026-10-22');
 assert.equal(c.status,status);
 assert.equal(c.locked,true);
}
''')

    def test_rule_edit_keeps_confirmed_instances_and_past_history(self):
        self.check(r'''
const first=v({kind:'once',startDate:'2026-10-13',endDate:'2026-10-19'});
const saved=e.expand([{id:'r',versions:[first]}],[],[],range(),'2026-10-13')[0];
const updated=v({kind:'once',version:2,effectiveOn:'2026-10-14',startDate:'2026-10-16',endDate:'2026-10-22',title:'新版规则',estimatedMinutes:60});
const history=[{id:'r',versions:[first,updated]}];
const old=e.expand(history,[saved],[],range('2026-10-14',14),'2026-10-14')[0];
assert.equal(old.version,1);
assert.equal(old.title,first.title);
assert.equal(old.startDate,saved.startDate);
const future={...saved,startDate:'2026-10-15',taskId:'t',status:'confirmed'};
const confirmed=e.expand(history,[future],[{id:'t'}],range('2026-10-14',14),'2026-10-14')[0];
assert.equal(confirmed.version,1);
assert.equal(confirmed.title,first.title);
assert.equal(confirmed.estimatedMinutes,30);
assert.equal(confirmed.startDate,'2026-10-15');
assert.equal(confirmed.endDate,'2026-10-19');
''')

    def test_daily_and_weekly_cross_year_without_rollover_debt(self):
        self.check(r'''
const daily=[{id:'r',versions:[v({kind:'daily',effectiveOn:'2026-12-28',startDate:'2026-12-28',endDate:'2027-01-10',weekdays:[1,2,3,4,5]})]}];
const c=e.expand(daily,[],[],range('2026-12-28',14),'2026-12-28');
assert.equal(c.length,10);
assert.equal(c[0].startDate,'2026-12-28');assert.equal(c.at(-1).startDate,'2027-01-08');
assert.equal(new Set(c.map(x=>x.id)).size,10);
const weekly=[{id:'r',versions:[v({kind:'weekly',perWeek:2,effectiveOn:'2026-12-28',startDate:'2026-12-28',endDate:'2027-01-10'})]}];
const weeks=e.expand(weekly,[],[],range('2026-12-28',14),'2026-12-28');
assert.equal(weeks.length,4);assert.equal(weeks[2].week,'2027-01-04');
''')

    def test_interval_actual_completion_recalibrates_window(self):
        self.check(r'''
const record={id:'r:interval:0',sequence:0,ruleId:'r',taskId:'t',startDate:'2026-10-17',endDate:'2026-10-19'};
const tasks=[{id:'t',completedAt:'2026-10-17T10:00:00Z',actualCompletedOn:'2026-10-17'}];
const c=e.expand(rules(),[record],tasks,range('2026-10-20',4),'2026-10-20');
assert.equal(c[0].startDate,'2026-10-21');
assert.equal(c[0].endDate,'2026-10-23');
assert.equal(c[0].estimated,false);
assert.equal(c[0].id,'r:interval:1');
''')

    def test_confirmed_projection_keeps_stable_id_and_flags_recalibration(self):
        self.check(r'''
const original=e.expand(rules(),[],[],range(),'2026-10-13');
const records=[{...original[0],taskId:'first',date:'2026-10-19'},
 {...original[1],taskId:'next',date:'2026-10-25',status:'confirmed'}];
const tasks=[{id:'first',completedAt:'2026-10-17T10:00:00Z',actualCompletedOn:'2026-10-17'},
 {id:'next',plannedDate:'2026-10-25'}];
const c=e.expand(rules(),records,tasks,range('2026-10-20',7),'2026-10-20');
const next=c.filter(x=>x.id==='r:interval:1');
assert.equal(next.length,1);
assert.equal(next[0].startDate,'2026-10-21');
assert.equal(next[0].endDate,'2026-10-23');
assert.equal(next[0].taskId,'next');
assert.equal(next[0].date,'2026-10-25');
assert.equal(next[0].recalibrationConflict,true);
assert.equal(next[0].estimated,false);
''')

    def test_reopen_restores_original_sequence_and_recomputes_pending_windows(self):
        self.check(r'''
const original=e.expand(rules(),[],[],range(),'2026-10-13');
const records=[{...original[0],taskId:'first'},
 {...original[1],startDate:'2026-10-01',endDate:'2026-10-02',status:'pending'}];
const completed=[{id:'first',completedAt:'2026-10-17T10:00:00Z',actualCompletedOn:'2026-10-17'}];
const after=e.expand(rules(),records,completed,range(),'2026-10-13');
assert.equal(after.filter(x=>x.id==='r:interval:1').length,1);
assert.equal(after.find(x=>x.id==='r:interval:1').startDate,'2026-10-21');
const reopened=e.expand(rules(),records,[{id:'first',completedAt:null}],range(),'2026-10-13');
assert.equal(reopened.find(x=>x.id==='r:interval:0').endDate,'2026-10-19');
assert.equal(reopened.find(x=>x.id==='r:interval:1').endDate,'2026-10-25');
assert.equal(reopened.find(x=>x.id==='r:interval:1').estimated,true);
''')

    def test_attached_existing_tasks_keep_hard_due_date_and_current_fields(self):
        self.check(r'''
const saved=candidate({id:'task:t',ruleId:null,taskId:'t',endDate:'2026-10-20'});
const tasks=[{id:'t',title:'用户新标题',priority:3,estimatedMinutes:45,dueDate:'2026-10-14'}];
const c=e.expand([], [saved],tasks,range(),'2026-10-13');
assert.equal(c[0].endDate,'2026-10-14');
assert.equal(c[0].title,'用户新标题');
assert.equal(c[0].priority,3);
assert.equal(c[0].estimatedMinutes,45);
assert.ok(e.arrange(c,a,range(),[]).assigned.every(x=>x.date<='2026-10-14'));
const overdue=e.expand([], [saved],[{...tasks[0],dueDate:'2026-10-12'}],range(),'2026-10-13');
assert.equal(overdue[0].status,'overdue');
assert.equal(e.arrange(overdue,a,range(),[]).assigned.length,0);
''')

    def test_early_projection_can_enter_horizon(self):
        self.check(r'''
const c=e.expand(rules(),[],[],range('2026-10-13',10),'2026-10-13');
assert.equal(c.length,2);
assert.equal(c[1].estimated,true);
const p=e.arrange(c,a,range('2026-10-13',10),[],{[c[0].id]:{date:'2026-10-17',start:'09:00',end:'09:30'}});
assert.equal(p.assigned.length,2);
const projected=p.assigned.find(x=>x.estimated);
assert.equal(projected.startDate,'2026-10-21');
assert.equal(projected.endDate,'2026-10-23');
assert.equal(projected.date,'2026-10-22');
''')

    def test_locked_interval_successor_waits_for_its_predecessor(self):
        self.check(r'''
const c=e.expand(rules(),[],[],range(),'2026-10-13');
const successor={...c[1],locked:true,taskId:'t',task:{plannedDate:'2026-10-23'},localDate:'2026-10-23',localStart:'09:00',localEnd:'09:30'};
const p=e.arrange([c[0],successor],a,range(),[],{[c[0].id]:{date:'2026-10-17',start:'09:00',end:'09:30'}});
assert.equal(p.assigned.length,2);
assert.equal(p.assigned[0].sequence,0);
assert.equal(p.assigned[1].sequence,1);
assert.equal(p.assigned[1].date,'2026-10-23');
''')

    def test_selected_successor_uses_existing_predecessor_date(self):
        self.check(r'''
const c=e.expand(rules(),[],[],range(),'2026-10-13');
const successor={...c[1],previousScheduledDate:'2026-10-17'};
const p=e.arrange([successor],a,range(),[]);
assert.equal(p.assigned.length,1);
assert.equal(p.assigned[0].startDate,'2026-10-21');
assert.equal(p.assigned[0].endDate,'2026-10-23');
assert.equal(p.assigned[0].date,'2026-10-23');
''')

    def test_skipping_interval_does_not_reset_or_erase_overdue(self):
        self.check(r'''
const record={id:'r:interval:0',sequence:0,ruleId:'r',status:'skipped',startDate:'2026-10-17',endDate:'2026-10-19'};
const c=e.expand(rules(),[record],[],range('2026-10-20',7),'2026-10-20');
assert.equal(c.length,1);
assert.equal(c[0].endDate,'2026-10-19');
assert.equal(c[0].status,'overdue');
assert.equal(c[0].skipRecorded,true);
assert.equal(e.arrange(c,a,range('2026-10-20',7),[]).assigned.length,0);
''')

    def test_interval_respects_rule_start_and_end(self):
        self.check(r'''
const c=e.expand(rules({startDate:'2026-10-18',endDate:'2026-10-22'}),[],[],range(),'2026-10-13');
assert.equal(c[0].startDate,'2026-10-18');
const p=e.arrange(c,a,range(),[],{[c[0].id]:{date:'2026-10-18',start:'09:00',end:'09:30'}});
assert.ok(p.assigned.every(x=>x.date<='2026-10-22'));
assert.ok(p.assigned.every(x=>x.date>='2026-10-18'));
''')

    def test_future_version_does_not_generate_early(self):
        self.check(r'''
assert.equal(e.expand(rules({effectiveOn:'2026-11-01'}),[],[],range(),'2026-10-13').length,0);
const c=e.expand(rules({kind:'once',effectiveOn:'2026-10-15',endDate:'2026-10-19'}),[],[],range(),'2026-10-13');
assert.equal(c[0].startDate,'2026-10-15');
''')

    def test_pause_preserves_confirmed_occurrences(self):
        self.check(r'''
const record=candidate({id:'saved',kind:'interval',taskId:'t',status:'confirmed',startDate:'2026-10-17',endDate:'2026-10-19'});
const c=e.expand(rules({status:'paused'}),[record],[{id:'t',title:'已确认'}],range(),'2026-10-13');
assert.equal(c.length,1);
assert.equal(c[0].id,'saved');
assert.equal(c[0].status,'confirmed');
''')

    def test_weekly_occurrences_use_distinct_unreserved_days(self):
        self.check(r'''
const c=[0,1,2].map(i=>candidate({id:String(i),kind:'weekly',week:'2026-10-12',endDate:'2026-10-18',reservedDates:['2026-10-13','2026-10-14']}));
const p=e.arrange(c,a,range(),[]);
assert.equal(p.assigned.length,3);
assert.equal(new Set(p.assigned.map(x=>x.date)).size,3);
assert.ok(p.assigned.every(x=>!c[0].reservedDates.includes(x.date)));
''')

    def test_locked_occupancy_remains_exact_and_blocks_other_tasks(self):
        self.check(r'''
const locked=candidate({id:'locked',locked:true,taskId:'t',task:{plannedDate:'2026-10-12'},localDate:'2026-10-13',localStart:'09:00',localEnd:'09:30'});
const second=candidate({id:'other',times:[{start:'09:00',end:'10:00'}]});
const p=e.arrange([second,locked],a,range(),[{id:'t',date:'2026-10-13',start:540,end:570}]);
assert.equal(p.assigned[0].id,'locked');
assert.equal(p.assigned[0].start,'09:00');
assert.equal(p.assigned[1].start,'09:30');
const mismatch=e.arrange([{...locked,estimatedMinutes:45}],a,range(),[]);
assert.equal(mismatch.assigned.length,0);
''')

    def test_busy_buffers_and_rule_times_are_hard_constraints(self):
        self.check(r'''
const settings={...a,bufferMinutes:10};
const c=candidate({times:[{start:'09:00',end:'10:00'}]});
const p=e.arrange([c],settings,range(),[{date:'2026-10-13',start:540,end:570}]);
assert.equal(p.assigned.length,0);
''')

    def test_unrelated_optional_tasks_can_share_day(self):
        self.check(r'''
const c=[candidate({id:'a',ruleId:null,optional:true}),candidate({id:'b',ruleId:null,optional:true})];
const p=e.arrange(c,a,range(),[]);
assert.equal(p.assigned.length,2);
assert.equal(p.assigned[0].end,p.assigned[1].start);
''')

    def test_short_windows_do_not_overflow_and_manual_exceptions_win(self):
        self.check(r'''
const settings={...a,exceptions:{'2026-10-13':[{start:'10:00',end:'10:20'}]}};
assert.equal(e.arrange([candidate()],settings,range(),[]).assigned.length,0);
const closed={...a,exceptions:{'2026-10-13':[]}};
assert.equal(e.arrange([candidate()],closed,range(),[]).assigned.length,0);
''')

    def test_pause_stops_future_interval_projections(self):
        self.check(r'''
const history=[{id:'r',versions:[v(),v({version:2,status:'paused',effectiveOn:'2026-10-21'})]}];
const c=e.expand(history,[],[],range(),'2026-10-13');
const p=e.arrange(c,a,range(),[],{[c[0].id]:{date:'2026-10-17',start:'09:00',end:'09:30'}});
assert.ok(p.assigned.every(x=>x.date<'2026-10-21'));
''')

    def test_weekly_uses_allowed_weekdays_and_optional_interval_is_rejected(self):
        self.check(r'''
const c=e.expand(rules({kind:'weekly',perWeek:2,weekdays:[2,4]}),[],[],range('2026-10-13',7),'2026-10-13');
assert.ok(c.length>=2);
const p=e.arrange(c,a,range('2026-10-13',7),[]);
assert.ok(p.assigned.every(x=>[2,4].includes(e.weekday(x.date))));
assert.throws(()=>v({optional:true}),/互斥/);
''')


if __name__ == '__main__':
    unittest.main()
