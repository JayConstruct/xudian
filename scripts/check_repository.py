#!/usr/bin/env python3
"""Check repository boundaries and the files actually bundled into the APK."""
import argparse
import importlib.util
import json
from pathlib import Path, PurePosixPath
import subprocess
import urllib.parse
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('bundle_packer', ROOT / 'scripts/module_host/build_packages.py')
packer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packer)
LOCAL_DIRECTORIES = {
    '.tools', '.cache', '.aws', '.codex', '.agents', '.dart_tool', '.gradle',
    '.idea', '.vscode', '__pycache__', '.pytest_cache', 'node_modules', 'build',
}
LOCAL_SUFFIXES = {
    '.apk', '.aab', '.apks', '.idsig', '.log', '.pyc', '.pyo', '.keystore',
    '.jks', '.p12', '.pfx', '.db', '.sqlite', '.sqlite3',
}


def local_only(name):
    path = PurePosixPath(name)
    return (bool(LOCAL_DIRECTORIES.intersection(path.parts))
            or path.parts[0] in {'dist', 'tmp', 'coverage'}
            or path.suffix in LOCAL_SUFFIXES
            or path.name in {'local.properties', 'key.properties', '.DS_Store', 'Thumbs.db'}
            or path.name.startswith('.flutter-plugins')
            or (path.name.startswith('.env') and path.name != '.env.example'))


def check_repository(root, tracked):
    errors = []
    for name in tracked:
        if local_only(name):
            errors.append(f'Local-only file is tracked: {name}')

    bundle_dir = root / 'client/assets/modules'
    bundles = json.loads((bundle_dir / 'catalog.json').read_text())
    expected_bundles = {PurePosixPath(entry['asset']).name for entry in bundles}
    # The shared validator checks ZIP payload integrity as well as the public
    # catalog digest. Directory extras are rejected even when Git ignores them.
    try:
        packer.validate_bundle(bundle_dir / 'catalog.json', bundle_dir)
    except (OSError, ValueError, KeyError, TypeError, zipfile.BadZipFile) as error:
        errors.append(f'Invalid bundled catalog: {error}')

    expected_releases = set()
    for file in sorted((root / 'module-index').glob('*.json')):
        index = json.loads(file.read_text())
        for version in index['versions']:
            name = urllib.parse.urlsplit(version['url']).path.split('/')[-1]
            expected = f'{index["moduleId"]}-{version["version"]}.xmodule'
            if name != expected:
                errors.append(f'Release index must pin its module identity and version: {file.name}')
            expected_releases.add(name)
    release_dir = root / 'releases/modules'
    actual_releases = {file.name for file in release_dir.glob('*.xmodule')}
    for name in sorted(expected_releases - actual_releases):
        errors.append(f'Missing indexed release snapshot: {name}')
    for name in sorted(actual_releases - expected_releases):
        errors.append(f'Unreferenced release snapshot: {name}')

    allowed = {f'client/assets/modules/{name}' for name in expected_bundles}
    allowed.update(f'releases/modules/{name}' for name in expected_releases)
    for name in tracked:
        if name.endswith('.xmodule') and name not in allowed:
            errors.append(f'Unreferenced package is tracked: {name}')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    args = parser.parse_args()
    tracked = subprocess.check_output(
        ['git', 'ls-files', '-z'], cwd=args.root).decode().split('\0')[:-1]
    try:
        errors = check_repository(args.root, tracked)
    except (OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        parser.exit(1, f'Repository check failed: {error}\n')
    ignored = subprocess.check_output(
        ['git', 'ls-files', '-ci', '--exclude-standard'], cwd=args.root).decode().splitlines()
    errors.extend(f'Tracked file conflicts with .gitignore: {name}' for name in ignored)
    if errors:
        parser.exit(1, '\n'.join(errors) + '\n')
    print(f'Repository boundaries and pinned assets checked: {len(tracked)} tracked files.')


if __name__ == '__main__':
    main()
