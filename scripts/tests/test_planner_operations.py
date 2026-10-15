"""Planner operation primitives keep civil display and deadline facts separate."""
import subprocess
import unittest
from pathlib import Path

ENGINE = Path(__file__).resolve().parents[2] / 'packages/modules/app.planner/engine.js'


class PlannerOperationsTest(unittest.TestCase):
    def check(self, code):
        fixture = r'''
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const e = await import('data:text/javascript;base64,'+readFileSync(process.argv[1]).toString('base64'));
const a=e.availability({bufferMinutes:0,weekly:{'2':[{start:'09:00',end:'12:00'}]}});
const r=e.range({startDate:'2026-10-13',days:5},'2026-10-13');
'''
        run = subprocess.run(['node', '--input-type=module', '-e', fixture + code, str(ENGINE)],
                             text=True, capture_output=True)
        self.assertEqual(run.returncode, 0, run.stderr)

    def test_horizon_does_not_become_deadline(self):
        self.check(r'''
const t={id:'t',title:'Only name',notes:'Details'};
const c=e.taskCandidate(t,a,r);
assert.equal(c.requiresSelection,true);
assert.equal(c.dueDate,null);
assert.equal(c.planningEndDate,r.endDate);
assert.equal(c.estimatedMinutes,30);
assert.equal(t.dueDate,undefined);
assert.equal(e.arrange([c],a,r,[]).assigned.length,1);
assert.equal(c.task.plannedStartAt,undefined);
''')

    def test_current_deadline_remains_authoritative(self):
        self.check(r'''
const t={id:'t',title:'Moved deadline',dueDate:'2026-10-12',initialDeadline:{dueDate:'2026-10-20'}};
const c=e.taskCandidate(t,a,r);
assert.equal(c.requiresSelection,false);
assert.equal(c.status,'overdue');
assert.equal(c.endDate,'2026-10-12');
assert.equal(e.arrange([c],a,r,[]).assigned.length,0);
''')

    def test_display_date_does_not_place_task_on_its_deadline(self):
        self.check(r'''
const t={id:'t',title:'Independent',dueDate:'2026-10-16',plannedStartAt:'2026-10-13T01:00:00Z'};
const c=e.taskCandidate(t,a,r);
assert.equal(c.task.plannedStartAt,t.plannedStartAt);
assert.equal(c.dueDate,'2026-10-16');
assert.equal(c.status,'confirmed');
''')

    def test_half_open_overlap_includes_hidden_midnight_occupancy(self):
        self.check(r'''
const overnight={startAt:'2026-10-13T23:30:00Z',endAt:'2026-10-14T00:30:00Z'};
assert.equal(e.intervalsOverlap(overnight,{startAt:'2026-10-14T00:00:00Z',endAt:'2026-10-14T01:00:00Z'}),true);
assert.equal(e.intervalsOverlap(overnight,{startAt:'2026-10-14T00:30:00Z',endAt:'2026-10-14T01:00:00Z'}),false);
''')


if __name__ == '__main__':
    unittest.main()
