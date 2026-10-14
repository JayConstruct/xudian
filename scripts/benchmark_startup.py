#!/usr/bin/env python3
"""Benchmark installed Android process cold launches without clearing app data."""

import argparse
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys
import time
import uuid


METRICS = ('ThisTime', 'TotalTime', 'WaitTime')
READY_METRIC = 'ActivityCreateToWorkspaceReadyMs'
PACKAGE_PATTERN = r'[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+'
ACTIVITY_PATTERN = r'\.?[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)*'
MODULE_PATTERN = r'[a-z][a-z0-9]*(?:\.[a-z][a-z0-9_-]*)+'
MAXIMUM_PHASE_GROUPS = 96
MAXIMUM_PHASE_INTEGER = (1 << 63) - 1
PHASE_NAMES = frozenset((
    'app.firstFrame', 'app.workspaceReady', 'database.open', 'database.ready', 'host.restore',
    'host.initialize', 'host.restore.packages', 'host.defaults.metadata',
    'host.package.verify', 'host.bundle.verify', 'host.worker.load',
    'shell.restore', 'page.queue', 'page.execute', 'page.firstFrame',
))
PHASE_FIELDS = frozenset(('name', 'count', 'elapsedUs', 'moduleId', 'worker'))


class BenchmarkError(RuntimeError):
    """A launch cannot be accepted as a valid cold-start sample."""


def parse_launch(text):
    """Keep am's raw metrics; ThisTime is absent on some Android versions."""
    fields = {}
    for line in text.splitlines():
        match = re.fullmatch(r'\s*([A-Za-z]+):\s*(.*?)\s*', line)
        if match:
            key, value = match.groups()
            if key in fields:
                raise BenchmarkError(f'Duplicate am field: {key}')
            fields[key] = value
    if fields.get('Status') != 'ok':
        raise BenchmarkError('am start did not report Status: ok')
    if re.search(r'^\s*(Error|Exception|Warning):', text, re.MULTILINE):
        raise BenchmarkError('am start reported an error or warning')
    if fields.get('LaunchState') in ('HOT', 'WARM'):
        raise BenchmarkError('am start reported a warm/hot launch')
    result = {'Status': fields['Status'], 'LaunchState': fields.get('LaunchState')}
    for key in METRICS:
        value = fields.get(key)
        if value is None and key == 'ThisTime':
            result[key] = None
        elif value is None or not re.fullmatch(r'\d+', value):
            raise BenchmarkError(f'Missing or invalid am metric: {key}')
        else:
            result[key] = int(value)
    return result


def percentile(values, percent):
    """Nearest-rank percentile; no interpolation of recorded milliseconds."""
    ordered = sorted(values)
    return ordered[max(0, math.ceil(percent / 100 * len(ordered)) - 1)]


def summarize(samples):
    result = {}
    for key in (*METRICS, READY_METRIC):
        values = [sample[key] for sample in samples if sample.get(key) is not None]
        result[key] = {
            'count': len(values),
            'p50Ms': statistics.median(values) if values else None,
            'p95Ms': percentile(values, 95) if values else None,
            'minMs': min(values) if values else None,
            'maxMs': max(values) if values else None,
        }
    if any('startupPhases' in sample for sample in samples):
        groups = {}
        for sample in samples:
            for phase in sample.get('startupPhases', []):
                key = (phase['name'], phase.get('moduleId'), phase.get('worker'))
                groups.setdefault(key, []).append(phase)
        # Each record is already one launch's aggregate for this exact group.
        # Keep nested spans separate; never sum host/page spans into a total.
        result['startupPhases'] = []
        for key in sorted(groups, key=lambda value: tuple(item or '' for item in value)):
            name, module_id, worker = key
            values = groups[key]
            group = {'name': name, 'sampleCount': len(values)}
            if module_id is not None:
                group['moduleId'] = module_id
            if worker is not None:
                group['worker'] = worker
            for metric in ('elapsedUs', 'count'):
                measurements = [value[metric] for value in values]
                group[metric] = {
                    'p50': statistics.median(measurements),
                    'p95': percentile(measurements, 95),
                    'min': min(measurements),
                    'max': max(measurements),
                }
            result['startupPhases'].append(group)
    return result


def _unique_phase_fields(pairs):
    result = {}
    for name, value in pairs:
        if name in result:
            raise BenchmarkError('Duplicate startup phase field')
        result[name] = value
    return result


def parse_phases(text, launch_token):
    """Return only validated current-launch aggregates and completion status.

    Input is one PID/tag-filtered logcat snapshot, so polling never accumulates
    records twice. No raw line, unrecognized field or launch token is retained.
    """
    phases = []
    groups = set()
    complete = False
    for line in text.splitlines():
        line = re.sub(r'^\s*I/XudianStartupPhases\(\s*\d+\):\s*', '', line).strip()
        token = re.search(r'(?:^|\s)launchToken=([a-f0-9]{32})\s*$', line)
        if token is None:
            if f'launchToken={launch_token}' in line:
                raise BenchmarkError('Invalid startup phase marker format')
            continue
        if token[1] != launch_token:
            continue
        payload = line[:token.start()].strip()
        if payload == 'complete=true':
            if complete:
                raise BenchmarkError('Multiple startup phase completion markers')
            complete = True
            continue
        if complete:
            raise BenchmarkError('Startup phase emitted after completion')
        try:
            phase = json.loads(payload, object_pairs_hook=_unique_phase_fields)
        except (ValueError, RecursionError):
            raise BenchmarkError('Invalid startup phase JSON') from None
        if not isinstance(phase, dict) or not {'name', 'count', 'elapsedUs'} <= phase.keys():
            raise BenchmarkError('Missing startup phase fields')
        if not phase.keys() <= PHASE_FIELDS:
            raise BenchmarkError('Unexpected startup phase fields')
        if not isinstance(phase['name'], str) or phase['name'] not in PHASE_NAMES:
            raise BenchmarkError('Unknown startup phase name')
        for field, minimum in (('count', 1), ('elapsedUs', 0)):
            value = phase[field]
            if type(value) is not int or not minimum <= value <= MAXIMUM_PHASE_INTEGER:
                raise BenchmarkError(f'Invalid startup phase metric: {field}')
        if 'moduleId' in phase and (not isinstance(phase['moduleId'], str) or
                                   not re.fullmatch(MODULE_PATTERN, phase['moduleId'])):
            raise BenchmarkError('Invalid startup phase module ID')
        if 'worker' in phase and phase['worker'] not in ('computation', 'workflow'):
            raise BenchmarkError('Invalid startup phase worker')
        key = (phase['name'], phase.get('moduleId'), phase.get('worker'))
        if key in groups:
            raise BenchmarkError('Duplicate startup phase group')
        groups.add(key)
        if len(groups) > MAXIMUM_PHASE_GROUPS:
            raise BenchmarkError('Too many startup phase groups')
        phases.append(phase)
    return phases, complete


def parse_readiness(text, launch_token=None):
    """Parse only our process-scoped marker; never retain arbitrary log lines."""
    markers = []
    for line in text.splitlines():
        match = re.fullmatch(
            r'\s*(?:I/XudianStartup\(\s*\d+\):\s*)?'
            r'outcome=(ready|restoreError|noWorkspace) workspaceReadyMs=(\d+)'
            r'(?: launchToken=([a-f0-9]{32}))?\s*', line)
        if match and (launch_token is None or match[3] == launch_token):
            markers.append((match[1], int(match[2])))
    if len(markers) > 1:
        raise BenchmarkError('Multiple startup outcomes for the launched process')
    if not markers:
        return None
    outcome, elapsed = markers[0]
    if outcome != 'ready':
        raise BenchmarkError(f'Workspace unavailable: {outcome}')
    return elapsed


def collect(command, package, activity, runs, interval=1.0, check_pid=False,
            run=subprocess.run, sleep=time.sleep, wait_ready=False,
            ready_timeout=30.0, monotonic=time.monotonic,
            token_factory=lambda: uuid.uuid4().hex, capture_phases=False):
    """Force-stop, verify process absence, and launch once per trial."""
    if capture_phases and not wait_ready:
        raise BenchmarkError('Startup phase capture requires workspace readiness')
    diagnostics = {}
    phase = 'forceStop'

    def adb(arguments, allow_absent=False, timeout=60):
        nonlocal diagnostics
        parts = arguments[1:] if arguments[0] == 'shell' else arguments
        operation = ' '.join(parts[:2]) if parts[0] == 'am' else parts[0]
        diagnostics = {'operation': operation, 'exitCode': None,
                       'stdoutPresent': False, 'stderrPresent': False,
                       'timedOut': False, 'timeoutSeconds': timeout}
        try:
            response = run(command + arguments, capture_output=True,
                           text=True, check=False, timeout=timeout)
        except (OSError, subprocess.SubprocessError) as error:
            diagnostics.update({
                'exceptionType': type(error).__name__,
                'timedOut': isinstance(error, subprocess.TimeoutExpired),
                'stdoutPresent': bool(getattr(error, 'stdout', None)),
                'stderrPresent': bool(getattr(error, 'stderr', None)),
            })
            raise BenchmarkError(f'ADB {operation} failed ({type(error).__name__})') from error
        diagnostics.update({'exitCode': response.returncode,
                            'stdoutPresent': bool(response.stdout.strip()),
                            'stderrPresent': bool(response.stderr.strip())})
        if allow_absent and response.returncode == 1 and not response.stdout.strip() and not response.stderr.strip():
            return ''
        if response.returncode != 0 or response.stderr.strip():
            raise BenchmarkError(f'ADB {operation} returned an error')
        return response.stdout.strip()

    def shell(*arguments, allow_absent=False):
        return adb(['shell', *arguments], allow_absent)

    samples = []
    errors = []
    for trial in range(1, runs + 1):
        try:
            phase = 'forceStop'
            stop_output = shell('am', 'force-stop', package)
            if stop_output:
                raise BenchmarkError('am force-stop returned unexpected output')
            # ps also covers package:worker processes; an incomplete/unsupported
            # process listing is rejected instead of claiming a cold launch.
            phase = 'verifyProcessAbsence'
            process_table = shell('ps', '-A', '-o', 'PID,NAME')
            lines = process_table.splitlines()
            if not lines or lines[0].split() != ['PID', 'NAME']:
                raise BenchmarkError('Cannot verify process absence from ps output')
            for line in lines[1:]:
                parts = line.split()
                if len(parts) != 2 or not parts[0].isdigit():
                    raise BenchmarkError('Cannot parse device process listing')
                if parts[1] == package or parts[1].startswith(package + ':'):
                    raise BenchmarkError('Application process still exists after force-stop')
            launch_token = token_factory() if wait_ready else None
            launch_extras = ['--es', 'xudian.benchmark.launchToken', launch_token] if wait_ready else []
            phase = 'launch'
            raw = shell('am', 'start', '-W', '-a', 'android.intent.action.MAIN',
                        '-c', 'android.intent.category.LAUNCHER', '-n', f'{package}/{activity}',
                        *launch_extras)
            sample = {'trial': trial, **parse_launch(raw), 'processAbsentBeforeLaunch': True,
                      'rawAmStart': raw}
            if check_pid or wait_ready:
                phase = 'checkPid'
                pid = shell('pidof', package, allow_absent=True)
                if not pid or any(not item.isdigit() for item in pid.split()):
                    raise BenchmarkError('Application PID missing after launch')
                sample['pidAfterLaunch'] = [int(item) for item in pid.split()]
            if wait_ready:
                phase = 'waitForWorkspaceReady'
                if len(sample['pidAfterLaunch']) != 1:
                    raise BenchmarkError('Readiness requires exactly one main process PID')
                deadline = monotonic() + ready_timeout
                diagnostics = {'operation': 'logcat', 'exitCode': None,
                               'stdoutPresent': False, 'stderrPresent': False,
                               'timedOut': False, 'timeoutSeconds': ready_timeout}
                while True:
                    remaining = deadline - monotonic()
                    if remaining <= 0:
                        diagnostics['timedOut'] = True
                        raise BenchmarkError('Timed out waiting for workspace readiness marker')
                    # Filtering by current main PID prevents previous launches
                    # from satisfying readiness. Logcat is never cleared.
                    logs = adb(['logcat', '-d', '-b', 'main', '-v', 'raw',
                                '--pid', pid, '-s', 'XudianStartup:I', '*:S'],
                               timeout=min(60, remaining))
                    ready_ms = parse_readiness(logs, launch_token)
                    if ready_ms is not None:
                        sample[READY_METRIC] = ready_ms
                        sample['workspaceOutcome'] = 'ready'
                        break
                    if monotonic() >= deadline:
                        diagnostics['timedOut'] = True
                        raise BenchmarkError('Timed out waiting for workspace readiness marker')
                    sleep(min(0.25, max(0, deadline - monotonic())))
                if capture_phases:
                    phase = 'waitForStartupPhases'
                    while True:
                        remaining = deadline - monotonic()
                        if remaining <= 0:
                            diagnostics['timedOut'] = True
                            raise BenchmarkError('Timed out waiting for startup phase completion marker')
                        logs = adb(['logcat', '-d', '-b', 'main', '-v', 'raw',
                                    '--pid', pid, '-s', 'XudianStartupPhases:I', '*:S'],
                                   timeout=min(60, remaining))
                        startup_phases, complete = parse_phases(logs, launch_token)
                        if complete:
                            sample['startupPhases'] = startup_phases
                            break
                        if monotonic() >= deadline:
                            diagnostics['timedOut'] = True
                            raise BenchmarkError('Timed out waiting for startup phase completion marker')
                        sleep(min(0.25, max(0, deadline - monotonic())))
            samples.append(sample)
            if trial < runs and interval:
                sleep(interval)
        except BenchmarkError as error:
            errors.append({'trial': trial, 'phase': phase,
                           'message': str(error), **diagnostics})
            break
    report = {
        'schemaVersion': 2,
        'collectedAtUtc': datetime.now(timezone.utc).isoformat(),
        'measurement': 'Android activity launch / first display proxy (am start -W)',
        'package': package,
        'activity': activity,
        'adbCommand': command,
        'requestedRuns': runs,
        'completedRuns': len(samples),
        'complete': not errors and len(samples) == runs,
        'intervalSeconds': interval,
        'waitForWorkspaceReady': wait_ready,
        'readinessTimeoutSeconds': ready_timeout if wait_ready else None,
        'percentileMethod': 'p50 median; p95 nearest rank',
        'samples': samples,
        'summary': summarize(samples),
        'errors': errors,
        'notes': [
            'Process cold launch with retained application data and filesystem caches.',
            'am metrics are first display proxies; the optional workspace metric starts at Activity.onCreate, not process creation, and is not Android TTFD.',
            'Workspace readiness means an active composed content tree after entrance animation; it does not guarantee all network requests or user actions will succeed.',
            'ThisTime is null when the device does not emit it; it is not inferred from TotalTime.',
            'App force-stop and launch only; no uninstall, data clearing, settings changes or logcat clearing.',
            'Emulator results are local comparisons, not representative real-device performance.',
        ],
    }
    if capture_phases:
        report['captureStartupPhases'] = True
        report['notes'].append(
            'Startup phase records are opt-in validated per-launch aggregates in microseconds; nested and parallel groups must not be added into total launch time.')
    return report


def arguments(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--adb-host', default=os.environ.get('XUDIAN_ADB_HOST', '127.0.0.1'))
    parser.add_argument('--adb-port', type=int, default=os.environ.get('XUDIAN_ADB_PORT', '5037'))
    parser.add_argument('--adb', default='adb', help='ADB executable path')
    parser.add_argument('--package', default='dev.taskapp.task_app')
    parser.add_argument('--activity', default='.MainActivity')
    parser.add_argument('--runs', type=int, default=10)
    parser.add_argument('--interval', type=float, default=1.0, help='Seconds between launches (default: 1)')
    parser.add_argument('--check-pid', action='store_true', help='Require a main process PID after each launch')
    parser.add_argument('--wait-ready', action='store_true', help='Wait for the new APK workspace readiness marker')
    parser.add_argument('--capture-phases', action='store_true', help='Require --wait-ready and an APK built with XUDIAN_CAPTURE_STARTUP; capture validated startup aggregates')
    parser.add_argument('--ready-timeout', type=float, default=30.0, help='Workspace marker timeout in seconds')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(argv)
    if args.capture_phases and not args.wait_ready:
        parser.error('--capture-phases requires --wait-ready')
    if not re.fullmatch(PACKAGE_PATTERN, args.package):
        parser.error('Invalid Android package')
    if not re.fullmatch(ACTIVITY_PATTERN, args.activity):
        parser.error('Activity must be a relative or fully qualified class name')
    if not 1 <= args.adb_port <= 65535:
        parser.error('ADB port must be between 1 and 65535')
    if not 1 <= args.runs <= 1000:
        parser.error('Runs must be between 1 and 1000')
    if not math.isfinite(args.interval) or not 0 <= args.interval <= 60:
        parser.error('Interval must be finite and between 0 and 60 seconds')
    if not math.isfinite(args.ready_timeout) or not 0 < args.ready_timeout <= 120:
        parser.error('Readiness timeout must be finite and between 0 and 120 seconds')
    for name in ('serial', 'adb_host', 'adb'):
        value = getattr(args, name)
        if not value or value.startswith('-') or any(ord(char) < 32 for char in value):
            parser.error(f'Invalid {name}')
    return args


def main(argv=None):
    args = arguments(argv)
    command = [args.adb, '-H', args.adb_host, '-P', str(args.adb_port), '-s', args.serial]
    report = collect(command, args.package, args.activity, args.runs, args.interval, args.check_pid,
                     wait_ready=args.wait_ready, ready_timeout=args.ready_timeout,
                     capture_phases=args.capture_phases)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    metric = report['summary']['TotalTime']
    print(f'Activity launch / first display proxy: {report["completedRuns"]}/{args.runs} runs; '
          f'TotalTime p50={metric["p50Ms"]} ms, p95={metric["p95Ms"]} ms; report: {args.output}')
    for error in report['errors']:
        print(f'Trial {error["trial"]} ({error["phase"]}, {error["operation"]}, '
              f'exitCode={error["exitCode"]}): {error["message"]}', file=sys.stderr)
    return 0 if report['complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
