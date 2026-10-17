#!/usr/bin/env python3
"""Build an optional, reviewed fixture module; never connects to a device.

The generated module creates real app.tasks records through its public service.
No production module, existing task, installation, or view setting is changed.
Artifacts belong under the ignored dist/verification directory.
"""

import argparse
from datetime import date, datetime, timedelta, timezone
import json
from pathlib import Path

try:
    from .build_packages import pack
except ImportError:
    from build_packages import pack

ROOT = Path(__file__).resolve().parents[2]
MODULE_ID = 'app.verify.planner'
VERSION = '1.0.0'


def fixtures(start_date):
    origin = date.fromisoformat(start_date)
    local_zone = timezone(timedelta(hours=8))

    def day(offset):
        return (origin + timedelta(days=offset)).isoformat()

    def instant(offset, time):
        return datetime.fromisoformat(f'{day(offset)}T{time}:00').replace(
            tzinfo=local_zone).astimezone(timezone.utc).isoformat().replace('+00:00', 'Z')

    def item(key, title, duration, *, due=None, slot=None, locked=False):
        value = {'title': title, 'estimatedMinutes': duration,
                 'notes': f'planner-v4-fixture:{start_date}:{key}'}
        if due is not None:
            value['dueDate'] = day(due)
        if slot:
            offset, start, end = slot
            value.update(plannedStartAt=instant(offset, start),
                         plannedEndAt=instant(offset, end),
                         plannedTimezone='Asia/Shanghai', locked=locked)
        return value

    return [
        item('paper', '阅读论文', 90, due=2),
        item('notes-pending', '整理笔记', 150),
        item('english', '英语练习', 45, due=3),
        item('shopping', '采购清单', 30),
        item('review', '复习提纲', 60, due=4),
        item('archive', '资料归档', 60),
        item('outline', '写作提纲', 60, slot=(0, '09:00', '10:00')),
        item('report', '项目报告', 90, due=3, slot=(0, '10:25', '11:55')),
        item('notes-scheduled', '整理笔记', 30, slot=(0, '12:30', '13:00')),
        item('discussion', '小组讨论', 60, slot=(1, '13:00', '14:00'), locked=True),
        item('materials', '整理资料', 60, slot=(2, '09:00', '10:00')),
        item('email', '回复邮件', 3, slot=(2, '11:00', '11:03')),
        item('expense', '提交报销', 4, slot=(2, '11:05', '11:09')),
        item('meeting', '确认会议', 3, slot=(2, '11:12', '11:15')),
    ]


def definition():
    return {
        'formatVersion': 3,
        'manifest': {
            'id': MODULE_ID, 'name': '规划视觉验收数据', 'version': VERSION,
            'hostApi': '^1.25.0', 'dataVersion': 1,
            'permissions': ['ui', 'services.query:app.tasks/task.list@1',
                            'services.command:app.tasks/task.create@1'],
            'dependencies': [{'moduleId': 'app.tasks', 'version': '^1.5.1'}],
            'description': '仅通过任务服务添加带验收标记的示例，不修改已有任务。',
            'author': 'Local verification',
        },
        'entryPoint': 'main.js',
        'pages': [{'id': f'{MODULE_ID}.home', 'title': '规划视觉验收数据',
                   'handler': 'render',
                   'entry': {'id': f'{MODULE_ID}.home', 'opening': 'workspace',
                             'placement': 'main', 'order': 999}}],
        'collections': [],
        'services': [{'id': 'fixture.seed', 'major': 1, 'handler': 'seed',
                      'kind': 'command', 'input': {'type': 'object'},
                      'output': {'type': 'object'}}],
    }


SOURCE = """import {services,ui} from '@xudian/sdk';
import fixtures from './fixtures.js';
const ref=id=>({moduleId:'app.tasks',serviceId:id,majorVersion:1});
async function rows(){
 const values=[];
 for(let offset=0;;offset+=1000){
  const page=await services.query(ref('task.list'),{view:'raw',offset,limit:1000});
  values.push(...page);if(page.length<1000)return values;
  if(values.length>=20000)throw Error('任务数量过多，验收数据未创建');
 }
}
export async function seed(){
 const previous=await rows(),created=[];
 for(const input of fixtures){
  // A matching marker remains authoritative even after a task is edited,
  // completed or removed. Repeated acceptance must not create duplicates.
  if(previous.some(t=>t.notes===input.notes))continue;
  const value=await services.prepare(ref('task.create'),input);
  created.push(value.id);
 }
 return {writes:[],events:[],result:{created:created.length,ids:created}};
}
export async function render({state={},event}={}){
 state={...state};
 try{
  if(event?.type==='seed'){
   const plan=await services.prepare({moduleId:'app.verify.planner',serviceId:'fixture.seed',majorVersion:1},{});
   if(await ui.review(plan.planId)){
    const value=await services.commit(plan.planId);
    state.message=`已添加${value.created}项验收任务，已有标记任务保持不变`;
   }
  }
 }catch(error){state.message=String(error);}
 const existing=await rows();
 const own=existing.filter(t=>fixtures.some(f=>f.notes===t.notes));
 return {state,tree:{type:'column',children:[
  {type:'text',text:'通过真实任务服务添加14项视觉验收任务；仅增加带标记的数据，请在审核页确认。'},
  {type:'text',text:`已存在${own.length}/14项；日期${fixtures[0].notes.split(':')[1]}；时区Asia/Shanghai。`},
  ...(state.message?[{type:'text',text:state.message}]:[]),
  {type:'button',text:'创建缺少的验收任务',event:{type:'seed'}},
  ...own.map(t=>({type:'listTile',title:t.title,subtitle:t.plannedStartAt?`${t.plannedStartAt}—${t.plannedEndAt}`:t.dueDate?`${t.dueDate}截止`:`耗时${t.estimatedMinutes}分钟`}))
 ]}};
}
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--start-date', default='2026-10-15',
                        help='First visible day; defaults to the v4 proposal date')
    parser.add_argument('--output', type=Path,
                        default=ROOT / 'dist/verification/planner-fixture')
    args = parser.parse_args()
    values = fixtures(args.start_date)
    source = args.output / 'source'
    source.mkdir(parents=True, exist_ok=True)
    (source / 'module.json').write_text(json.dumps(definition(), ensure_ascii=False, indent=2) + '\n')
    (source / 'fixtures.js').write_text('export default ' + json.dumps(values, ensure_ascii=False, indent=2) + ';\n')
    (source / 'main.js').write_text(SOURCE)
    destination = args.output / f'{MODULE_ID}-{VERSION}.xmodule'
    digest = pack(source, destination)
    receipt = {'id': MODULE_ID, 'name': '规划视觉验收数据', 'version': VERSION,
               'sha256': digest, 'package': str(destination),
               'startDate': args.start_date, 'taskCount': len(values),
               'expectedReportGapsMinutes': [25, 35],
               'expectedShortTaskTotalMinutes': 10,
               'note': 'Only packaged; not installed or executed on a device.'}
    (args.output / 'fixture-package.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
