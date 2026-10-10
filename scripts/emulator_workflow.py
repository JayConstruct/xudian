"""Build-input fingerprints and regression selection for emulator updates."""
import hashlib
import json
from pathlib import Path

SMOKE_TESTS = ['test/host_ui_test.dart', 'test/ui_pack_chrome_test.dart']
SKIP_PARTS = {'build', '.gradle', '.dart_tool', '__pycache__'}
SKIP_NAMES = {'local.properties', 'GeneratedPluginRegistrant.java'}


def snapshot(root):
    files = []
    for folder in ['client/lib', 'client/assets', 'client/android']:
        directory = root / folder
        if directory.exists():
            files.extend(p for p in directory.rglob('*') if p.is_file()
                         and not SKIP_PARTS.intersection(p.relative_to(directory).parts)
                         and p.name not in SKIP_NAMES)
    for name in ['client/pubspec.yaml', 'client/pubspec.lock', 'client/.flutter-plugins-dependencies',
                 '.tools/flutter/bin/cache/flutter.version.json', '.tools/flutter/bin/cache/engine.stamp']:
        path = root / name
        if path.is_file():
            files.append(path)
    return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(set(files))}


def fingerprint(inputs):
    return hashlib.sha256(json.dumps(inputs, sort_keys=True).encode()).hexdigest()


def changed_files(before, after):
    return sorted(name for name in before.keys() | after.keys() if before.get(name) != after.get(name))


def select_tests(changes, modules=(), *, first_run=False):
    """None means a full suite; otherwise return a bounded regression list."""
    tests = set(SMOKE_TESTS)
    if first_run:
        changes = []
    critical = ('client/pubspec.', 'client/lib/data/', 'client/lib/core/modules/',
                'client/lib/core/module_host/module_host.dart',
                'client/lib/core/module_host/collection_store.dart',
                'client/lib/core/module_host/module_package.dart')
    if any(name.startswith(critical) for name in changes):
        return None
    if any(name.startswith(('client/lib/app/', 'client/lib/core/ui/')) for name in changes):
        tests.update(['test/schedule_layout_test.dart', 'test/ui_pack_script_page_test.dart'])
    if any(name.startswith('client/lib/core/module_host/') for name in changes):
        tests.update(['test/schedule_layout_test.dart', 'test/ui_pack_script_page_test.dart',
                      'test/shiguang_school_picker_test.dart'])
    if any(name.startswith('client/lib/features/settings/') for name in changes):
        tests.add('test/settings_test.dart')
    if any(name.startswith(('client/lib/features/tasks/', 'client/lib/features/ai/')) for name in changes):
        return None
    if any(name.startswith('client/android/') for name in changes):
        tests.add('test/host_browser_test.dart')
    for module in modules:
        if module == 'app.schedule':
            tests.update(['test/schedule_layout_test.dart', 'test/schedule_ux_test.dart'])
        elif module == 'app.import.shiguang':
            tests.update(['test/shiguang_school_picker_test.dart', 'test/host_browser_test.dart'])
        else:
            return None
    return sorted(tests)


def checks_fingerprint(root, inputs, tests):
    extra = {}
    candidates = list((root / 'client/test').rglob('*')) if tests is None else [root / 'client' / name for name in tests]
    # Fixtures and common test helpers can affect selected tests too.
    candidates += list((root / 'client/test/fixtures').rglob('*'))
    candidates += list((root / 'client/test/support').rglob('*'))
    # Tests may import another test's fixtures; track the entire test source tree.
    candidates += list((root / 'client/test').rglob('*.dart'))
    candidates += [root / 'scripts/module_host/check_architecture.py',
                   root / 'scripts/check_repository.py',
                   root / 'scripts/module_host/build_packages.py',
                   root / 'client/analysis_options.yaml',
                   root / 'scripts/update_emulator.py', Path(__file__)]
    for path in sorted(set(candidates)):
        if path.is_file():
            extra[str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
    return fingerprint({'inputs': inputs, 'testSources': extra, 'selectedTests': tests})


def reusable(cache, inputs_digest, mode, installed_version, root):
    if cache.get('fingerprint') != inputs_digest or cache.get('mode') != mode:
        return False
    if cache.get('versionCode', 0) < installed_version:
        return False
    path = root / cache.get('apk', '')
    return path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == cache.get('apkSha256')
