#!/usr/bin/env python3
"""Select affected checks and deduplicate exact main/tag revisions."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time

from validate_app_release import validate_release


def github_json(path):
    result = subprocess.run(['gh', 'api', path], check=True, capture_output=True,
                            text=True, timeout=20)
    return json.loads(result.stdout)


def validation_mode(paths):
    """Unknown and build-control changes retain complete Android validation."""
    if not paths:
        return 'full'
    mode = 'tools'
    build_controls = {'scripts/plan_android_ci.py', 'scripts/update_emulator.py',
                      'scripts/update-emulator.sh', 'scripts/emulator_workflow.py',
                      'scripts/module_host/build_packages.py'}
    for name in paths:
        if not isinstance(name, str) or not name or name.startswith('/') or '..' in name.split('/'):
            return 'full'
        if name in build_controls or name.startswith(('.github/', 'packages/xquickjs/')):
            return 'full'
        if name.startswith(('client/test/', 'packages/modules/', 'module-index/',
                            'releases/modules/', 'packages/catalog/')):
            mode = 'tests'
        elif name.startswith('client/') and name != 'client/README.md':
            return 'full'
        elif not (name.endswith('.md') or name.startswith(('docs/', 'scripts/')) or name == '.gitignore'):
            return 'full'
    return mode


def affected_mode(event, ref, sha, repository, load=github_json):
    """Compare against successful checks, including changes in failed pushes."""
    if event != 'push' or ref != 'refs/heads/main':
        return 'full'
    try:
        runs = load(f'repos/{repository}/actions/workflows/android.yml/runs'
                    '?event=push&status=success&per_page=20')['workflow_runs']
        verified = [run for run in runs if run['event'] == 'push'
                    and run['status'] == 'completed' and run['conclusion'] == 'success'
                    and (run['head_branch'] == 'main' or run['head_branch'].startswith('v'))
                    and re.fullmatch(r'[0-9a-f]{40}', run['head_sha'])]
        baseline = max(verified, key=lambda run: run['id'], default=None)
        if baseline is None:
            return 'full'
        before = baseline['head_sha']
        data = load(f'repos/{repository}/compare/{before}...{sha}?per_page=1')
        files = data['files']
        # Compare returns at most 300 files. At the limit completeness is
        # unproven; a rename must account for both the old and new location.
        if (data['status'] != 'ahead' or data['base_commit']['sha'] != before
                or data['merge_base_commit']['sha'] != before
                or not isinstance(files, list) or not 0 < len(files) < 300):
            return 'full'
        paths = []
        for item in files:
            paths.append(item['filename'])
            if item.get('status') == 'renamed':
                paths.append(item['previous_filename'])
        return validation_mode(paths)
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError):
        print('Changed paths could not be confirmed; running full Android checks.')
        return 'full'


def delegate_run(event, ref, sha, repository, pubspec, load=github_json):
    """Return a matching tag run, or 0 to perform a fresh complete validation."""
    if event != 'push' or ref != 'refs/heads/main':
        return 0
    try:
        version = re.search(r'^version:\s*([^\s#]+)', pubspec, re.MULTILINE)[1]
        tag = 'v' + version.split('+')[0]
        validate_release(tag, pubspec)
        prefix = f'repos/{repository}'
        target = load(f'{prefix}/git/ref/tags/{tag}')['object']
        for _ in range(5):
            if target['type'] != 'tag':
                break
            target = load(f"{prefix}/git/tags/{target['sha']}")['object']
        if target['type'] != 'commit' or target['sha'] != sha:
            return 0
        runs = load(f'{prefix}/actions/workflows/android.yml/runs'
                    f'?head_sha={sha}&event=push&per_page=100')['workflow_runs']
        matching = [run for run in runs if run['head_sha'] == sha
                    and run['head_branch'] == tag and run['event'] == 'push']
        latest = max(matching, key=lambda run: run['id'], default=None)
        if latest is None:
            return 0
        if (latest['status'] in {'queued', 'in_progress', 'waiting', 'pending', 'requested'}
                or latest['status'] == 'completed' and latest['conclusion'] == 'success'):
            return max(0, int(latest['id']))
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError):
        # API errors, absent tags, registration races and malformed responses
        # always fall back to full checks, never an unchecked green status.
        print('Tag run could not be confirmed; running full Android checks.')
    return 0


def delegated_result(run, jobs, sha):
    if run['head_sha'] != sha:
        raise ValueError('Delegated run source revision changed')
    for job in jobs['jobs']:
        if job['name'] == 'android' and job['status'] == 'completed':
            if job['conclusion'] != 'success':
                raise ValueError('Delegated Android checks failed or were cancelled')
            return True
    if run['status'] == 'completed':
        raise ValueError('Delegated run ended without successful Android checks')
    return False


def wait_for_checks(run_id, repository, sha, load=github_json, *, timeout=2100):
    prefix = f'repos/{repository}/actions/runs/{run_id}'
    deadline = time.monotonic() + timeout
    print(f'Waiting for https://github.com/{repository}/actions/runs/{run_id}', flush=True)
    while time.monotonic() < deadline:
        try:
            run = load(prefix)
            jobs = load(prefix + '/jobs?filter=latest&per_page=100')
        except (OSError, subprocess.SubprocessError):
            print('GitHub status temporarily unavailable; retrying.', flush=True)
        else:
            if delegated_result(run, jobs, sha):
                print('Matching tag Android checks passed.', flush=True)
                return
        time.sleep(20)
    raise TimeoutError('Timed out waiting for matching tag Android checks')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wait-for-run', type=int)
    args = parser.parse_args()
    repository = os.environ['GITHUB_REPOSITORY']
    sha = os.environ['GITHUB_SHA']
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
        raise SystemExit('Invalid GitHub repository')
    if not re.fullmatch(r'[0-9a-f]{40}', sha):
        raise SystemExit('Invalid source revision')
    if args.wait_for_run is not None:
        if args.wait_for_run <= 0:
            raise SystemExit('Missing delegated workflow run')
        wait_for_checks(args.wait_for_run, repository, sha)
        return
    run_id = delegate_run(os.environ['GITHUB_EVENT_NAME'], os.environ['GITHUB_REF'],
                          sha, repository, Path('client/pubspec.yaml').read_text())
    mode = 'delegate' if run_id else 'full'
    if not run_id:
        mode = affected_mode(os.environ['GITHUB_EVENT_NAME'], os.environ['GITHUB_REF'],
                             sha, repository)
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        output.write(f'run_android={str(not run_id).lower()}\ndelegate_run={run_id}\n'
                     f'validation_mode={mode}\n'
                     f'run_flutter={str(mode in {"full", "tests"}).lower()}\n'
                     f'run_apk={str(mode == "full").lower()}\n')
    print(f'Validation mode: {mode}' if not run_id else f'Using matching tag run {run_id}')


if __name__ == '__main__':
    main()
