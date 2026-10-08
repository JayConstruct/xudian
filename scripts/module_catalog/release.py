#!/usr/bin/env python3
"""Publish prepared author assets without replacing a release, tag, or package."""
import argparse
import json
import pathlib
import shutil
import subprocess
import tempfile
import urllib.parse
import zipfile

from catalog import repository_name, require, validate_catalog, validate_index, validate_package

ROOT = pathlib.Path(__file__).resolve().parents[2]


def prepared_assets(catalog_path, index_dir, package_dir, repository, tag, expected_count=None):
    catalog = validate_catalog(json.loads(catalog_path.read_text()))
    assets = {}
    for entry in catalog['modules']:
        if entry['repository'] != repository:
            continue
        index = validate_index(json.loads((index_dir / f'{entry["id"]}.json').read_text()), entry)
        for release in index['versions']:
            parts = urllib.parse.urlsplit(release['url']).path.split('/')
            if parts[-2] != tag:
                continue
            name = parts[-1]
            require(name not in assets, f'Duplicate release asset: {name}')
            data = (package_dir / name).read_bytes()
            validate_package(data, release)
            assets[name] = release
    require(assets, f'No prepared assets for {repository} tag {tag}')
    require(set(assets) == {path.name for path in package_dir.glob('*.xmodule')},
            'Prepared directory must contain exactly the packages indexed for this release tag')
    if expected_count is not None:
        require(len(assets) == expected_count, f'Expected {expected_count} assets, found {len(assets)}')
    return assets


def gh(arguments, allow_missing=False):
    result = subprocess.run(['gh', *arguments], capture_output=True, text=True)
    if result.returncode:
        if allow_missing and 'HTTP 404' in result.stderr:
            return None
        raise ValueError(f'GitHub command failed: {result.stderr.strip() or result.stdout.strip()}. '
                         'Check network access, gh auth login, repository access, and contents:write permissions.')
    return result.stdout


def verify_remote_assets(repository, tag, release, assets):
    names = [asset['name'] for asset in release['assets']]
    require(len(names) == len(set(names)), 'Existing Release has duplicate asset names')
    require(set(names) <= set(assets), 'Existing Release contains unexpected assets; refusing to change it')
    with tempfile.TemporaryDirectory() as folder:
        if names:
            gh(['release', 'download', tag, '--repo', repository, '--dir', folder])
        for name in names:
            data = (pathlib.Path(folder) / name).read_bytes()
            # Check package identity and service metadata in addition to the digest.
            validate_package(data, assets[name])
    return set(assets) - set(names)


def publish(repository, tag, package_dir, assets, title, notes):
    require(shutil.which('gh') is not None,
            'GitHub CLI (gh) is missing. Install it from https://cli.github.com/, then run '
            'gh auth login. In GitHub Actions set GH_TOKEN to the repository GITHUB_TOKEN.')
    repo = json.loads(gh(['api', f'repos/{repository}']))
    require(repo.get('private') is False,
            f'{repository} must be public so clients can anonymously download indexes and packages. '
            'Make the author repository public or review a move to a public publishing repository first.')
    tag_ref = json.loads(gh(['api', f'repos/{repository}/git/ref/tags/{tag}']))
    marker = f'<!-- xudian-module-release-ref:{tag_ref["object"]["sha"]} -->'
    endpoint = f'repos/{repository}/releases/tags/{tag}'
    existing = gh(['api', endpoint], allow_missing=True)
    if existing is None:
        gh(['release', 'create', tag, *[str(package_dir / name) for name in sorted(assets)],
            '--repo', repository, '--verify-tag', '--draft', '--title', title,
            '--notes', f'{notes}\n\n{marker}'])
        existing = gh(['api', endpoint])
    release = json.loads(existing)
    require(marker in (release.get('body') or ''),
            'Release tag identity is unverified or changed; refusing to modify the existing Release')
    missing = verify_remote_assets(repository, tag, release, assets)
    if missing:
        require(release.get('draft') is True,
                'Published Release is missing indexed packages; refusing to modify it')
        gh(['release', 'upload', tag, *[str(package_dir / name) for name in sorted(missing)],
            '--repo', repository])
        release = json.loads(gh(['api', endpoint]))
        require(not verify_remote_assets(repository, tag, release, assets), 'Release upload is incomplete')
    # Recheck the remote tag before publishing, without ever changing it.
    current_ref = json.loads(gh(['api', f'repos/{repository}/git/ref/tags/{tag}']))
    require(current_ref['object']['sha'] == tag_ref['object']['sha'], 'Tag changed during publication')
    if release.get('draft') is True:
        gh(['release', 'edit', tag, '--repo', repository, '--draft=false'])
    return release.get('html_url') or f'https://github.com/{repository}/releases/tag/{tag}'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', default='JayConstruct/xudian')
    parser.add_argument('--tag', required=True)
    parser.add_argument('--catalog', type=pathlib.Path, default=ROOT / 'packages/catalog/catalog.json')
    parser.add_argument('--index-dir', type=pathlib.Path, default=ROOT / 'module-index')
    parser.add_argument('--package-dir', type=pathlib.Path, default=ROOT / 'dist/module-releases')
    parser.add_argument('--expected-count', type=int)
    parser.add_argument('--title', default='模块目录首批模块')
    parser.add_argument('--notes', default='为模块增加作用与作者说明；新旧版本资产保持不可变。未签名包经客户端确认后安装。')
    args = parser.parse_args()
    try:
        repository = repository_name(args.repository)
        require(args.tag and args.tag not in ('.', '..') and urllib.parse.quote(args.tag, safe='-_.') == args.tag,
                'Release tag must be a URL-safe name')
        assets = prepared_assets(args.catalog, args.index_dir, args.package_dir, repository,
                                 args.tag, args.expected_count)
        url = publish(repository, args.tag, args.package_dir, assets, args.title, args.notes)
    except (ValueError, OSError, KeyError, TypeError, zipfile.BadZipFile) as error:
        parser.exit(1, f'Release publication failed: {error}\n')
    print(f'Published and verified {len(assets)} immutable unsigned assets: {url}')


if __name__ == '__main__':
    main()
