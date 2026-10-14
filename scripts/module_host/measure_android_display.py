#!/usr/bin/env python3
"""Read Android display settings without changing devices or application data."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess


def parse_size(text):
    values = {}
    for kind, width, height in re.findall(
            r'(Physical|Override) size:\s*(\d+)x(\d+)', text):
        if int(width) > 0 and int(height) > 0:
            values[kind.lower()] = {'width': int(width), 'height': int(height)}
    return values


def parse_density(text):
    return {kind.lower(): int(value) for kind, value in re.findall(
        r'(Physical|Override) density:\s*(\d+)', text) if int(value) > 0}


def app_configuration(text, package):
    """Return only the target application's configuration, never other apps."""
    active = False
    for line in text.splitlines():
        if 'packageName=' in line:
            active = f'packageName={package} ' in line or line.strip() == f'packageName={package}'
        if active and 'CurrentConfiguration=' in line:
            fields = {}
            for name, pattern in {
                'logicalWidthDp': r'\bw(\d+)dp\b',
                'logicalHeightDp': r'\bh(\d+)dp\b',
                'densityDpi': r'\b(\d+)dpi\b',
                'smallestWidthDp': r'\bsw(\d+)dp\b',
            }.items():
                match = re.search(pattern, line)
                if match:
                    fields[name] = int(match[1])
            return fields or None
        if active and re.search(r'\* Hist|\* Task', line):
            active = False
    return None


def collect(command, package, run=subprocess.run):
    errors = []

    def read(key, *arguments):
        try:
            result = run(command + ['shell', *arguments], capture_output=True,
                         text=True, check=True, timeout=20)
            return result.stdout.strip()
        except (subprocess.SubprocessError, OSError):
            # Do not embed raw dumps or process errors with arbitrary device data.
            errors.append(key)
            return ''

    sizes = parse_size(read('screenSize', 'wm', 'size'))
    densities = parse_density(read('density', 'wm', 'density'))
    font = read('fontScale', 'settings', 'get', 'system', 'font_scale')
    try:
        font_scale = float(font)
        if not 0 < font_scale < float('inf'):
            font_scale = None
    except ValueError:
        font_scale = None
    effective_size = sizes.get('override', sizes.get('physical'))
    effective_density = densities.get('override', densities.get('physical'))
    estimate = None
    if effective_size and effective_density:
        estimate = {name: round(value * 160 / effective_density, 3)
                    for name, value in effective_size.items()}
    result = {
        'schemaVersion': 1,
        'collectedAtUtc': datetime.now(timezone.utc).isoformat(),
        'model': read('model', 'getprop', 'ro.product.model') or None,
        'android': read('android', 'getprop', 'ro.build.version.release') or None,
        'abi': read('abi', 'getprop', 'ro.product.cpu.abi') or None,
        'systemTimezone': read('timezone', 'getprop', 'persist.sys.timezone') or None,
        'screenPixels': sizes,
        'densityDpi': densities,
        'systemFontScale': font_scale,
        'estimatedPixelRatio': effective_density / 160 if effective_density else None,
        'estimatedLogicalDisplay': estimate,
        'androidAppConfiguration': app_configuration(
            read('appConfiguration', 'dumpsys', 'activity', 'activities'), package),
        'flutterView': None,
        'measurementNotes': [
            'Android estimates are not measurements of the Flutter view.',
            'System font_scale is not the nonlinear Flutter TextScaler mapping.',
            'Read the in-app display diagnostics for actual view, safe area and text samples.',
        ],
        'failedReads': errors,
        'deviceSettingsChanged': False,
    }
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--adb-host', default=os.environ.get('XUDIAN_ADB_HOST', '127.0.0.1'))
    parser.add_argument('--adb-port', type=int, default=int(os.environ.get('XUDIAN_ADB_PORT', '5037')))
    parser.add_argument('--package', default='dev.taskapp.task_app')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not 1 <= args.adb_port <= 65535 or not re.fullmatch(r'[A-Za-z][\w]*(?:\.[A-Za-z][\w]*)+', args.package):
        parser.error('Invalid ADB port or Android package')
    result = collect(['adb', '-H', args.adb_host, '-P', str(args.adb_port), '-s', args.serial], args.package)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(f'Display report: {args.output}; failed reads: {len(result["failedReads"])}')
    return 1 if result['failedReads'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
