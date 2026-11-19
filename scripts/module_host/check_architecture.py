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


def dart_tokens(source):
    """Read directive tokens without treating comments or string bodies as code."""
    offset = 0
    while offset < len(source):
        char = source[offset]
        if char.isspace():
            offset += 1
        elif source.startswith('//', offset):
            end = source.find('\n', offset)
            offset = len(source) if end < 0 else end + 1
        elif source.startswith('/*', offset):
            # Dart permits nested block comments.
            depth = 1
            offset += 2
            while offset < len(source) and depth:
                if source.startswith('/*', offset):
                    depth += 1
                    offset += 2
                elif source.startswith('*/', offset):
                    depth -= 1
                    offset += 2
                else:
                    offset += 1
        elif char in "'\"" or (char == 'r' and source[offset + 1:offset + 2] in ("'", '"')):
            raw = char == 'r'
            if raw:
                offset += 1
            quote = source[offset]
            delimiter = quote * (3 if source.startswith(quote * 3, offset) else 1)
            offset += len(delimiter)
            start = offset
            while offset < len(source) and not source.startswith(delimiter, offset):
                offset += 2 if not raw and source[offset] == '\\' else 1
            yield 'string', source[start:offset]
            offset += len(delimiter)
        elif char.isalpha() or char in '_$':
            start = offset
            offset += 1
            while offset < len(source) and (source[offset].isalnum() or source[offset] in '_$'):
                offset += 1
            yield 'word', source[start:offset]
        else:
            offset += 1
            yield 'symbol', char


def directives(source):
    """Yield import/export/part URIs from the library directive preamble.

    A `part of` URI names the owning library, not another dependency. Stop at
    the first declaration so source examples in later strings cannot add edges.
    Flutter analyze remains responsible for Dart syntax and URI validity.
    """
    tokens = iter(dart_tokens(source))
    token = next(tokens, None)
    while token is not None:
        # Metadata may precede a library directive. Consume its qualified name
        # and optional argument list, without inspecting strings as directives.
        if token == ('symbol', '@'):
            token = next(tokens, None)
            if token and token[0] == 'word':
                token = next(tokens, None)
            while token == ('symbol', '.'):
                token = next(tokens, None)
                if token and token[0] == 'word':
                    token = next(tokens, None)
            if token == ('symbol', '('):
                depth = 1
                while depth and (token := next(tokens, None)) is not None:
                    if token == ('symbol', '('):
                        depth += 1
                    elif token == ('symbol', ')'):
                        depth -= 1
                token = next(tokens, None)
            continue
        if token[0] != 'word' or token[1] not in {'library', 'import', 'export', 'part'}:
            break
        kind = token[1]
        token = next(tokens, None)
        if kind != 'library' and token and token[0] == 'string':
            yield kind, token[1]
        # Conditional imports/exports are dependencies on every platform, not
        # just the first URI. Strings inside the condition are not URIs.
        while token is not None and token != ('symbol', ';'):
            if kind in {'import', 'export'} and token == ('word', 'if'):
                token = next(tokens, None)
                depth = 0
                while token is not None:
                    if token == ('symbol', '('):
                        depth += 1
                    elif token == ('symbol', ')'):
                        depth -= 1
                        if depth == 0:
                            token = next(tokens, None)
                            if token and token[0] == 'string':
                                yield kind, token[1]
                            break
                    token = next(tokens, None)
            token = next(tokens, None)
        token = next(tokens, None)


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
        for _, imported in directives(path.read_text()):
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
    pending = list((lib / 'core/ui').glob('*.dart'))
    seen = set()
    while pending:
        path = pending.pop().resolve()
        if path in seen or not path.exists():
            continue
        seen.add(path)
        for kind, imported in directives(path.read_text()):
            target = local_import(lib, path, imported)
            if target is not None and target.is_relative_to(lib / 'app'):
                violations.append(f'Shared UI depends on App assembly: {path.relative_to(lib)}')
            # Parts belong to this library even when stored in a subdirectory.
            if kind == 'part' and target is not None:
                pending.append(target)
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
        for _, imported in directives(path.read_text()):
            target = local_import(lib, path, imported)
            if target is not None:
                if target.name in {'ui_component.dart', 'ui_surfaces.dart', 'native_ui.dart'}:
                    violations.append(f'Visual foundation depends on UI rendering: {path.relative_to(lib)}')
                pending.append(target)
    return violations


BUSINESS_FIELDS = {'plannedStartAt', 'plannedEndAt', 'plannedTimezone',
                   'completedAt', 'archivedAt', 'executionExpiresOn'}


def check_business_semantics(relative, source):
    if relative in LEGACY_ARCHIVES:
        return []
    if not relative.startswith(('core/module_host/', 'core/ui/', 'app/')):
        return []
    tokens = list(dart_tokens(source))
    violations = []
    for index, token in enumerate(tokens):
        if (token[0] == 'string' and token[1] in BUSINESS_FIELDS and index > 0
                and tokens[index - 1] == ('symbol', '[')
                and index + 1 < len(tokens) and tokens[index + 1] == ('symbol', ']')):
            violations.append(f'Business record field outside transaction policy: {relative}: {token[1]}')
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
        violations.extend(check_business_semantics(relative, source))
        if relative.startswith('legacy/') or re.search(
                r'features/(tasks|projects|ai|declarative_runtime|module_manager)/', relative):
            violations.append(f'Legacy business runtime reachable: {relative}')
        if relative not in LEGACY_ARCHIVES and business_identities.search(source):
            violations.append(f'Business module identity special case: {relative}')
        for _, imported in directives(source):
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
