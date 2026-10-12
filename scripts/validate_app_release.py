#!/usr/bin/env python3
"""Verify an app release tag matches the version embedded in the client."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def validate_release(tag, pubspec):
    number = r'(?:0|[1-9][0-9]*)'
    stable = rf'{number}\.{number}\.{number}'
    version = stable + rf'(?:-(?:alpha|beta|rc)\.{number})?'
    if not re.fullmatch('v' + version, tag):
        raise ValueError('App tag must be vMAJOR.MINOR.PATCH, optionally with -alpha.N, -beta.N or -rc.N.')
    match = re.search(r'^version:\s*([^\s#]+)', pubspec, re.MULTILINE)
    if not match or not re.fullmatch(version + r'(?:\+[0-9]+)?', match[1]):
        raise ValueError('pubspec.yaml must declare a supported app release version.')
    if tag[1:] != match[1].split('+')[0]:
        raise ValueError('App release tag must match client/pubspec.yaml version.')


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: validate_app_release.py vMAJOR.MINOR.PATCH[-beta.N]')
    try:
        validate_release(sys.argv[1], (ROOT / 'client/pubspec.yaml').read_text())
    except ValueError as error:
        raise SystemExit(str(error)) from error
    print(f'App release validated: {sys.argv[1]}')


if __name__ == '__main__':
    main()
