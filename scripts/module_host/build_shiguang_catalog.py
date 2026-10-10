#!/usr/bin/env python3
"""Bundle a pinned official warehouse checkout without executing its scripts.

Requires PyYAML. Sources remain text inside ESM data bundles; only the selected
adapter runs in the user-operated browser, never in the module worker.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

import yaml

ROOT = Path(__file__).resolve().parents[2]
DESTINATION = ROOT / 'packages/modules/app.import.shiguang/warehouse'
METHODS = {
    'showAlert', 'showPrompt', 'showSingleSelection', 'showToast',
    'saveImportedCourses', 'savePresetTimeSlots', 'saveCourseConfig',
    'saveComboSchedule', 'notifyTaskCompletion',
}


def encode(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':'))


def build(checkout, revision):
    actual = subprocess.check_output(
        ['git', '-C', str(checkout), 'rev-parse', 'HEAD'], text=True,
    ).strip()
    if actual != revision:
        raise ValueError('Checkout does not match the pinned revision')
    subprocess.run(['git', '-C', str(checkout), 'diff', '--exit-code', 'HEAD'], check=True)
    schools = yaml.safe_load((checkout / 'index/root_index.yaml').read_text())['schools']
    adapters, batches, batch = [], [], {}
    seen = set()
    for school in sorted(schools, key=lambda s: (s['initial'], s['name'], s['id'])):
        # These are demos, test placeholders and converters for other apps.
        if school['id'] == 'GLOBAL_TOOLS':
            continue
        folder = checkout / 'resources' / school['resource_folder']
        for item in yaml.safe_load((folder / 'adapters.yaml').read_text())['adapters']:
            source = (folder / item['asset_js_path']).resolve()
            if not source.is_relative_to(folder.resolve()) or not source.is_file():
                raise ValueError(f'Missing or unsafe script: {item["adapter_id"]}')
            raw = source.read_bytes()
            script = raw.decode('utf-8-sig')
            adapter_id = item['adapter_id']
            if adapter_id in seen:
                raise ValueError(f'Duplicate adapter id: {adapter_id}')
            seen.add(adapter_id)
            if len(encode({**batch, adapter_id: script}).encode()) > 900_000 and batch:
                batches.append(batch)
                batch = {}
            batch[adapter_id] = script
            methods = sorted(set(re.findall(
                r'(?:shiguangBridgePromise|AndroidBridgePromise|shiguangBridge|AndroidBridge)\s*\.\s*(\w+)',
                script,
            )))
            features = []
            if re.search(r'customStartTime|["\']?isCustomTime["\']?\s*:\s*true', script):
                features.append('customTime')
            if 'saveComboSchedule' in script:
                features.append('comboSchedule')
            if re.search(r'jQuery|\$\(', script):
                features.append('jquery')
            adapters.append({
                'id': adapter_id, 'schoolId': school['id'], 'school': school['name'],
                'name': item['adapter_name'], 'category': item['category'],
                'url': item['import_url'] or '', 'maintainer': item['maintainer'],
                'description': item['description'], 'features': features,
                'path': source.relative_to(checkout).as_posix(),
                'sha256': hashlib.sha256(raw).hexdigest(),
                'methods': methods, 'unsupportedMethods': sorted(set(methods) - METHODS),
                'bundle': len(batches),
            })
    if batch:
        batches.append(batch)
    DESTINATION.mkdir(parents=True, exist_ok=True)
    for old in DESTINATION.glob('scripts-*.js'):
        old.unlink()
    for index, contents in enumerate(batches):
        (DESTINATION / f'scripts-{index}.js').write_text(
            '// Generated from the pinned official warehouse; preserve source attribution.\n'
            + 'export default ' + encode(contents) + ';\n', encoding='utf-8',
        )
    metadata = {
        'repository': 'https://github.com/ShiGuangSchedule/shiguang_warehouse',
        'revision': revision, 'schools': len({a['schoolId'] for a in adapters}),
        'adapters': len(adapters), 'uniqueScripts': len({a['path'] for a in adapters}),
        'excluded': ['GLOBAL_TOOLS demos and external-app utilities'],
    }
    (DESTINATION / 'catalog.js').write_text(
        '// Generated metadata. Script text is loaded only on selection.\n'
        + 'export const snapshot=' + encode(metadata) + ';\n'
        + 'export const adapters=' + encode(adapters) + ';\n'
        + 'const bundles=[' + ','.join(
            f"()=>import('./scripts-{i}.js')" for i in range(len(batches))
        ) + '];\n'
        + "export async function loadAdapter(id){const adapter=adapters.find(a=>a.id===id);"
        + "if(!adapter)throw new Error('学校脚本不存在，请重新选择');"
        + "const sources=(await bundles[adapter.bundle]()).default;"
        + "return {...adapter,script:sources[id]};}\n", encoding='utf-8',
    )
    (DESTINATION / 'LICENSE.txt').write_bytes((checkout / 'LICENSE').read_bytes())
    (DESTINATION / 'snapshot.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({**metadata, 'bundles': len(batches)}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('checkout', type=Path)
    parser.add_argument('--revision', required=True)
    args = parser.parse_args()
    build(args.checkout, args.revision)
