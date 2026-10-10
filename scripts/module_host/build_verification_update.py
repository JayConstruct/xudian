#!/usr/bin/env python3
"""Build a reproducible, local schedule update for unchanged-client acceptance."""
import json
import pathlib
import tempfile
import zipfile
from build_packages import ROOT, pack

def main():
    with tempfile.TemporaryDirectory(prefix='schedule-verification-') as folder:
        target = pathlib.Path(folder)
        # Preserve the exact source of the original acceptance demonstration.
        # The current development package has a newer page layout/API range.
        with zipfile.ZipFile(ROOT / 'dist/verification/app.schedule-1.0.0.xmodule') as original:
            for name in original.namelist():
                if name != 'package.json':
                    destination = target / name
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    destination.write_bytes(original.read(name))
        definition = json.loads((target / 'module.json').read_text())
        definition['manifest']['version'] = '1.0.1'
        definition['services'].append({
            'id': 'schedule.query.statistics', 'major': 1, 'handler': 'statistics',
            'kind': 'query', 'input': {'type': 'object'}, 'output': {'type': 'object'},
            'tool': {'description': '查询课表课程数量'},
        })
        (target / 'module.json').write_text(json.dumps(definition, ensure_ascii=False, indent=2)+'\n')
        script = (target / 'main.js').read_text()
        script = script.replace("  if(!t) { children.push", "  children.push(text('脚本更新新增统计：'+(await statistics({timetableId:t?.id})).courses+' 门课程'));\n  if(!t) { children.push")
        script += "\nexport async function statistics({timetableId}) { const courses=await data.query('courses');return {courses:courses.filter(c=>c.timetableId===timetableId).length};}\n"
        (target / 'main.js').write_text(script)
        destination = ROOT / 'dist/verification/app.schedule-1.0.1.xmodule'
        print(pack(target, destination), destination)

if __name__ == '__main__':
    main()
