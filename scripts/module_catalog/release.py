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


def _selected_assets(catalog_path, index_dir, package_dir, repository, tag, expected_count):
    repository_name(repository)
    require(tag and tag not in ('.', '..') and urllib.parse.quote(tag, safe='-_.') == tag,
            'Release tag must be a URL-safe name')
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
            assets[name] = (release, data)
    require(assets, f'No prepared assets for {repository} tag {tag}')
    if expected_count is not None:
        require(len(assets) == expected_count, f'Expected {expected_count} assets, found {len(assets)}')
    return assets


def prepared_assets(catalog_path, index_dir, package_dir, repository, tag, expected_count=None):
    selected = _selected_assets(catalog_path, index_dir, package_dir, repository, tag, expected_count)
    require(set(selected) == {path.name for path in package_dir.glob('*.xmodule')},
            'Prepared directory must contain exactly the packages indexed for this release tag')
    return {name: release for name, (release, _) in selected.items()}


def stage_assets(catalog_path, index_dir, source_dir, repository, tag, destination, expected_count=None):
    """Validate the complete tag selection before writing an exact immutable staging set."""
    selected = _selected_assets(catalog_path, index_dir, source_dir, repository, tag, expected_count)
    require(not destination.is_symlink(), 'Staging destination must not be a symlink')
    if destination.exists():
        require(destination.is_dir(), 'Staging destination must be a directory')
        for path in destination.iterdir():
            require(path.name in selected and path.is_file() and not path.is_symlink(),
                    f'Staging directory contains unexpected content: {path.name}')
            require(path.read_bytes() == selected[path.name][1],
                    f'Staged asset is immutable and differs from the index: {path.name}')
    # Keep validated bytes in memory, so a changing source cannot introduce
    # unchecked bytes between validation and copying. Check all destinations
    # before writing any missing asset, and never overwrite an existing file.
    destination.mkdir(parents=True, exist_ok=True)
    for name, (_, data) in selected.items():
        target = destination / name
        if not target.exists():
            with target.open('xb') as stream:
                stream.write(data)
    return prepared_assets(catalog_path, index_dir, destination, repository, tag, expected_count)


def gh(arguments, *, binary=False):
    result = subprocess.run(['gh', *arguments], capture_output=True, text=not binary)
    if result.returncode:
        error = result.stderr.strip() or result.stdout.strip()
        if isinstance(error, bytes):
            error = error.decode('utf-8', errors='replace')
        raise ValueError(f'GitHub command failed: {error}. '
                         'Check network access, gh auth login, repository access, and contents:write permissions.')
    return result.stdout


def find_release(repository, tag):
    # The by-tag REST endpoint returns published releases only. Drafts keep their
    # pending tag_name and must be found in the authenticated, paginated list.
    pages = json.loads(gh(['api', f'repos/{repository}/releases?per_page=100',
                          '--paginate', '--slurp']))
    matches = [release for page in pages for release in page if release.get('tag_name') == tag]
    require(len(matches) <= 1, f'Multiple Releases have pending tag {tag}; refusing ambiguous publication')
    if not matches:
        return None
    release = json.loads(gh(['api', f'repos/{repository}/releases/{matches[0]["id"]}']))
    require(release.get('tag_name') == tag, 'Release pending tag changed during lookup')
    return release


def verify_remote_assets(repository, tag, release, assets):
    names = [asset['name'] for asset in release['assets']]
    require(len(names) == len(set(names)), 'Existing Release has duplicate asset names')
    require(set(names) <= set(assets), 'Existing Release contains unexpected assets; refusing to change it')
    for asset in release['assets']:
        # Draft tag lookups can lag behind creation. Resolve each immutable asset
        # by its authenticated API ID and preserve the ZIP's binary bytes.
        data = gh(['api', f'repos/{repository}/releases/assets/{asset["id"]}',
                   '-H', 'Accept: application/octet-stream'], binary=True)
        validate_package(data, assets[asset['name']])
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
    release = find_release(repository, tag)
    if release is None:
        # Use the create response directly: the release list may not yet contain
        # this draft, and a second tag lookup could create an ambiguous duplicate.
        release = json.loads(gh(['api', f'repos/{repository}/releases', '--method', 'POST',
                                 '-f', f'tag_name={tag}', '-F', 'draft=true',
                                 '-f', f'name={title}', '-f', f'body={notes}\n\n{marker}']))
        require(release.get('draft') is True and release.get('tag_name') == tag,
                'Release creation did not return the expected draft')
    endpoint = f'repos/{repository}/releases/{release["id"]}'
    require(marker in (release.get('body') or ''),
            'Release tag identity is unverified or changed; refusing to modify the existing Release')
    missing = verify_remote_assets(repository, tag, release, assets)
    if missing:
        require(release.get('draft') is True,
                'Published Release is missing indexed packages; refusing to modify it')
        for name in sorted(missing):
            upload_url = (f'https://uploads.github.com/repos/{repository}/releases/{release["id"]}'
                          f'/assets?name={urllib.parse.quote(name, safe="")}')
            gh(['api', upload_url, '--method', 'POST', '-H', 'Content-Type: application/octet-stream',
                '--input', str(package_dir / name)])
        release = json.loads(gh(['api', endpoint]))
        require(not verify_remote_assets(repository, tag, release, assets), 'Release upload is incomplete')
    # Recheck the remote tag before publishing, without ever changing it.
    current_ref = json.loads(gh(['api', f'repos/{repository}/git/ref/tags/{tag}']))
    require(current_ref['object']['sha'] == tag_ref['object']['sha'], 'Tag changed during publication')
    if release.get('draft') is True:
        release = json.loads(gh(['api', endpoint, '--method', 'PATCH', '-F', 'draft=false']))
        require(release.get('draft') is False and release.get('tag_name') == tag,
                'Release publication did not complete for the expected tag')
    return release.get('html_url') or f'https://github.com/{repository}/releases/tag/{tag}'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', default='JayConstruct/xudian')
    parser.add_argument('--tag', required=True)
    parser.add_argument('--catalog', type=pathlib.Path, default=ROOT / 'packages/catalog/catalog.json')
    parser.add_argument('--index-dir', type=pathlib.Path, default=ROOT / 'module-index')
    parser.add_argument('--package-dir', type=pathlib.Path, default=ROOT / 'releases/modules')
    parser.add_argument('--stage-dir', type=pathlib.Path,
                        help='Prepare and verify only this tag in this directory; do not contact GitHub')
    parser.add_argument('--expected-count', type=int)
    parser.add_argument('--title', default='序点模块发布')
    parser.add_argument('--notes', default='本 Release 提供当前 tag 的不可变模块包，源码与版本索引保存在同一 tag。安装前由客户端核验包身份、摘要、依赖、权限与签名状态。客户端 APK 由 Android Actions 工作流构建。')
    args = parser.parse_args()
    try:
        repository = repository_name(args.repository)
        require(args.tag and args.tag not in ('.', '..') and urllib.parse.quote(args.tag, safe='-_.') == args.tag,
                'Release tag must be a URL-safe name')
        if args.stage_dir is not None:
            assets = stage_assets(args.catalog, args.index_dir, args.package_dir, repository,
                                  args.tag, args.stage_dir, args.expected_count)
            print(f'Prepared and verified {len(assets)} assets for {args.tag}: {args.stage_dir}')
            return
        with tempfile.TemporaryDirectory(prefix='xudian-module-release-') as temporary:
            package_dir = pathlib.Path(temporary)
            assets = stage_assets(args.catalog, args.index_dir, args.package_dir, repository,
                                  args.tag, package_dir, args.expected_count)
            url = publish(repository, args.tag, package_dir, assets, args.title, args.notes)
    except (ValueError, OSError, KeyError, TypeError, zipfile.BadZipFile) as error:
        parser.exit(1, f'Release publication failed: {error}\n')
    print(f'Published and verified {len(assets)} immutable unsigned assets: {url}')


if __name__ == '__main__':
    main()
