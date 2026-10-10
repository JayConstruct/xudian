#!/usr/bin/env python3
"""Check production imports, business table access and packaged defaults."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LIB = ROOT / 'client/lib'
seen, pending = set(), [LIB / 'main.dart']
violations = []
while pending:
    path = pending.pop().resolve()
    if path in seen or not path.exists():
        continue
    seen.add(path)
    source = path.read_text()
    relative = path.relative_to(LIB).as_posix()
    if re.search(r'features/(tasks|projects|ai|declarative_runtime|module_manager)/', relative):
        violations.append(f'Legacy business runtime reachable: {relative}')
    if relative not in {'core/module_host/legacy_migration.dart', 'core/module_host/legacy_converter.dart'} and re.search(r'''['"]app\.(tasks|ai)(?:[.'"])''', source):
        violations.append(f'Business module identity special case: {relative}')
    for imported in re.findall(r"(?:import|export)\s+['\"]([^'\"]+)['\"]", source):
        if imported.startswith('package:task_app/'):
            pending.append(LIB / imported.removeprefix('package:task_app/'))
        elif ':' not in imported:
            pending.append(path.parent / imported)
    if relative not in {'data/app_database.dart','data/app_database.g.dart','core/module_host/legacy_migration.dart'}:
        if re.search(r'\bdb\.(tasks|projects|labels|taskLabels|fieldDefinitions|fieldValues|ruleExecutions|moduleInstallations|moduleVersions)\b', source):
            violations.append(f'Legacy business table reachable: {relative}')
        if re.search(r'\b(?:FROM|INTO|UPDATE)\s+(?:tasks|projects|labels|task_labels|field_values|rule_executions)\b', source, re.I):
            violations.append(f'Legacy business SQL reachable: {relative}')
catalog = json.loads((ROOT / 'client/assets/modules/catalog.json').read_text())
if any(row['id'] == 'app.schedule' for row in catalog):
    violations.append('Schedule must be distributed independently')
if list((ROOT / 'client/assets').rglob('*schedule*.xmodule')):
    violations.append('Schedule package found in default assets')
if violations:
    raise SystemExit('\n'.join(violations))
print(f'Production architecture checked: {len(seen)} Dart files; no legacy business runtime or schedule asset.')
