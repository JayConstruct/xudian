#!/usr/bin/env python3
"""Prepare deterministic, immutable author release assets and append-only version indexes."""
import argparse
import importlib.util
import json
import pathlib
import urllib.parse
import hashlib
import zipfile

from catalog import validate_catalog, validate_index, validate_package, require

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('module_packer', ROOT / 'scripts/module_host/build_packages.py')
packer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packer)


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode()


def immutable_write(path, data):
    if path.exists():
        require(path.read_bytes() == data, f'Published asset is immutable: {path}; publish a new version')
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)


def prepare(modules, catalog_path, repository, tag, output, index_dir, archive_dirs=()):
    catalog = validate_catalog(json.loads(catalog_path.read_text()))
    require(tag and '/' not in tag and '\\' not in tag and tag not in ('.', '..') and
            urllib.parse.quote(tag, safe='-_.') == tag, 'release tag must be a URL-safe name')
    prepared = []
    for entry in catalog['modules']:
        if entry['repository'] != repository:
            continue
        folder = modules / entry['id']
        require(not any(path.is_symlink() for path in folder.rglob('*')), 'Source packages cannot contain symlinks')
        definition = json.loads((folder / 'module.json').read_text())
        manifest = definition['manifest']
        require(manifest['id'] == entry['id'], 'source module identity mismatch')
        for field in ('name', 'description', 'author'):
            require(manifest.get(field) == entry[field], f'directory {field} differs from package metadata')
        index_path = index_dir / f'{entry["id"]}.json'
        index = json.loads(index_path.read_text()) if index_path.exists() else {
            'indexFormat': 1, 'moduleId': entry['id'], 'repository': repository, 'versions': []}
        require(index.get('repository') == repository, 'publishing repository cannot silently change')
        for archive_dir in archive_dirs:
            for archived in sorted(archive_dir.glob('*.xmodule')):
                data = archived.read_bytes()
                from io import BytesIO
                with zipfile.ZipFile(BytesIO(data)) as archive:
                    archived_definition = json.loads(archive.read('module.json'))
                    archived_package = json.loads(archive.read('package.json'))
                old_manifest = archived_definition['manifest']
                if old_manifest['id'] != entry['id']:
                    continue
                old_version = old_manifest['version']
                old_name = f'{entry["id"]}-{old_version}.xmodule'
                old_release = {'version': old_version, 'manifest': old_manifest,
                               'services': archived_definition.get('services', []),
                               'url': f'https://github.com/{repository}/releases/download/{tag}/{old_name}',
                               'size': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
                               'signature': archived_package.get('signature')}
                prior = next((r for r in index['versions'] if r['version'] == old_version), None)
                if prior:
                    require(prior['sha256'] == old_release['sha256'], f'Archived {entry["id"]} {old_version} changed')
                    old_release = prior
                else:
                    index['versions'].append(old_release)
                validate_package(data, old_release)
                prepared.append((output / old_name, data, None, None))
        existing = next((r for r in index['versions'] if r['version'] == manifest['version']), None)
        asset_name = f'{entry["id"]}-{manifest["version"]}.xmodule'
        asset = output / asset_name
        # Generate to a temporary sibling and compare before touching a published asset.
        import tempfile
        with tempfile.TemporaryDirectory() as temporary:
            candidate = pathlib.Path(temporary) / asset_name
            sha = packer.pack(folder, candidate)
            data = candidate.read_bytes()
        release = {'version': manifest['version'], 'manifest': manifest,
                   'services': definition.get('services', []),
                   'url': f'https://github.com/{repository}/releases/download/{tag}/{asset_name}',
                   'size': len(data), 'sha256': sha, 'signature': None}
        if existing:
            require(existing['sha256'] == sha and existing['manifest'] == manifest and existing['services'] == release['services'],
                    f'{entry["id"]} {manifest["version"]} already published; use a new version')
            release = existing
        else:
            index['versions'].append(release)
        validate_index(index, entry)
        validate_package(data, release)
        prepared.append((asset, data, index_path, json_bytes(index)))
    require(prepared, f'No modules belong to {repository}')
    # Validate every candidate before writing any index.
    for asset, data, _, _ in prepared:
        if asset.exists():
            require(asset.read_bytes() == data, f'Published asset is immutable: {asset}')
    for asset, data, index_path, index_data in prepared:
        immutable_write(asset, data)
        if index_path is not None:
            index_path.parent.mkdir(parents=True, exist_ok=True)
            index_path.write_bytes(index_data)
    return [asset for asset, _, _, _ in prepared]


def bundle_catalog(catalog_path, asset_dir, modules, releases):
    """Pin new assets for existing bundle entries, preserving default flags and old assets."""
    entries = json.loads(catalog_path.read_text())
    updates = []
    for entry in entries:
        manifest = json.loads((modules / entry['id'] / 'module.json').read_text())['manifest']
        name = f'{entry["id"]}-{manifest["version"]}.xmodule'
        data = (releases / name).read_bytes()
        destination = asset_dir / name
        if destination.exists():
            require(destination.read_bytes() == data, f'Bundled asset is immutable: {destination}')
        updated = dict(entry, asset=f'assets/modules/{name}', sha256=hashlib.sha256(data).hexdigest())
        updates.append((destination, data, updated))
    for destination, data, _ in updates:
        immutable_write(destination, data)
    catalog_path.write_bytes(json_bytes([updated for _, _, updated in updates]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--modules', type=pathlib.Path, default=ROOT / 'packages/modules')
    parser.add_argument('--catalog', type=pathlib.Path, default=ROOT / 'packages/catalog/catalog.json')
    parser.add_argument('--repository', default='JayConstruct/xudian')
    parser.add_argument('--tag', required=True)
    parser.add_argument('--output', type=pathlib.Path, default=ROOT / 'dist/module-releases')
    parser.add_argument('--index-dir', type=pathlib.Path, default=ROOT / 'module-index')
    parser.add_argument('--archive-dir', type=pathlib.Path, action='append', default=[],
                        help='Include byte-identical historical packages, never rewrite their metadata (repeatable)')
    parser.add_argument('--bundle-catalog', type=pathlib.Path,
                        help='Pin existing client bundle entries to new versioned assets without overwriting old packages')
    args = parser.parse_args()
    try:
        assets = prepare(args.modules, args.catalog, args.repository, args.tag, args.output, args.index_dir, args.archive_dir)
        if args.bundle_catalog:
            bundle_catalog(args.bundle_catalog, args.bundle_catalog.parent, args.modules, args.output)
    except (ValueError, OSError, KeyError, TypeError) as error:
        parser.exit(1, f'Release preparation failed: {error}\n')
    for asset in assets:
        print(asset)
    print('Unsigned releases prepared; SHA-256 proves integrity, not publisher authentication.')


if __name__ == '__main__':
    main()
