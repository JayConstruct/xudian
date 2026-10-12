#!/usr/bin/env python3
"""Check production imports, business table access and packaged defaults."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LEGACY_ARCHIVES = {
    'core/module_host/legacy_migration.dart',
    'core/module_host/legacy_data_migration.dart',
    'core/module_host/legacy_converter.dart',
}


def business_identity_pattern(root):
    identities = {'app.tasks', 'app.ai'}
    for path in (root / 'packages/modules').glob('*/module.json'):
        manifest = json.loads(path.read_text())['manifest']
        if manifest.get('kind') != 'uiPack' and not manifest['id'].startswith('app.ui.'):
            identities.add(manifest['id'])
    choices = '|'.join(re.escape(identity) for identity in sorted(identities))
    return re.compile(r'''['"](?:''' + choices + r''')(?:[.'"])''')


def imports(source):
    return re.findall(r"(?:import|export)\s+['\"]([^'\"]+)['\"]", source)


def local_import(lib, path, imported):
    if imported.startswith('package:task_app/'):
        return (lib / imported.removeprefix('package:task_app/')).resolve()
    if ':' not in imported:
        return (path.parent / imported).resolve()
    return None


def check_layers(lib):
    """Keep the headless runtime and shared UI independent of App assembly."""
    lib = lib.resolve()
    violations = []
    pending = [lib / 'core/module_host/module_host.dart']
    seen = set()
    while pending:
        path = pending.pop().resolve()
        if path in seen or not path.exists():
            continue
        seen.add(path)
        relative = path.relative_to(lib).as_posix()
        for imported in imports(path.read_text()):
            target = local_import(lib, path, imported)
            if imported.startswith('package:flutter/'):
                violations.append(f'Flutter imported by headless runtime: {relative}')
            if target is not None:
                destination = target.relative_to(lib).as_posix()
                if destination.startswith(('app/', 'features/')) or (
                    destination.startswith('core/ui/') and
                    destination != 'core/ui/ui_pack.dart'
                ):
                    violations.append(f'UI imported by headless runtime: {relative} -> {destination}')
                pending.append(target)
    for path in (lib / 'core/ui').glob('*.dart'):
        for imported in imports(path.read_text()):
            target = local_import(lib, path, imported)
            if target is not None and target.is_relative_to(lib / 'app'):
                violations.append(f'Shared UI depends on App assembly: {path.relative_to(lib)}')
    # Theme constants, motion and icons are defaults; they must not resolve the
    # recipe system that consumes them, even through an intermediate file.
    pending = [lib / 'core/ui' / name for name in
               ('ui_design.dart', 'ui_motion.dart', 'ui_icons.dart')]
    seen = set()
    while pending:
        path = pending.pop().resolve()
        if path in seen or not path.exists():
            continue
        seen.add(path)
        for imported in imports(path.read_text()):
            target = local_import(lib, path, imported)
            if target is not None:
                if target.name in {'ui_component.dart', 'ui_surfaces.dart', 'native_ui.dart'}:
                    violations.append(f'Visual foundation depends on UI rendering: {path.relative_to(lib)}')
                pending.append(target)
    return violations


def check_architecture(root=ROOT):
    lib = root / 'client/lib'
    business_identities = business_identity_pattern(root)
    seen, pending = set(), [lib / 'main.dart']
    violations = []
    while pending:
        path = pending.pop().resolve()
        if path in seen or not path.exists():
            continue
        seen.add(path)
        source = path.read_text()
        relative = path.relative_to(lib).as_posix()
        if re.search(r'features/(tasks|projects|ai|declarative_runtime|module_manager)/', relative):
            violations.append(f'Legacy business runtime reachable: {relative}')
        if relative not in LEGACY_ARCHIVES and business_identities.search(source):
            violations.append(f'Business module identity special case: {relative}')
        for imported in imports(source):
            if imported.startswith('package:task_app/'):
                pending.append(lib / imported.removeprefix('package:task_app/'))
            elif ':' not in imported:
                pending.append(path.parent / imported)
        if relative not in LEGACY_ARCHIVES | {'data/app_database.dart', 'data/app_database.g.dart'}:
            if re.search(r'\bdb\.(tasks|projects|labels|taskLabels|fieldDefinitions|fieldValues|ruleExecutions|moduleInstallations|moduleVersions)\b', source):
                violations.append(f'Legacy business table reachable: {relative}')
            if re.search(r'\b(?:FROM|INTO|UPDATE)\s+(?:tasks|projects|labels|task_labels|field_values|rule_executions)\b', source, re.I):
                violations.append(f'Legacy business SQL reachable: {relative}')
    catalog = json.loads((root / 'client/assets/modules/catalog.json').read_text())
    if any(row['id'] == 'app.schedule' for row in catalog):
        violations.append('Schedule must be distributed independently')
    if list((root / 'client/assets').rglob('*schedule*.xmodule')):
        violations.append('Schedule package found in default assets')
    violations.extend(check_layers(lib))
    if violations:
        raise SystemExit('\n'.join(violations))
    print(f'Production architecture checked: {len(seen)} Dart files; business, runtime and UI boundaries intact.')


if __name__ == '__main__':
    check_architecture()
