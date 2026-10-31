#!/usr/bin/env python3
"""Check published Markdown files, images, local anchors and the SDK API version.

Uses only the standard library. External URLs are not fetched. Explicit local
artifact directories are skipped unless --check-local is requested.
"""
import argparse
from collections import Counter
import html
import json
import os
from pathlib import Path
import re
import subprocess
import unicodedata
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]


def without_code(text, *, inline=True):
    """Mask code, keeping character offsets and newlines for diagnostics."""
    lines = []
    fence = None
    for line in text.splitlines(keepends=True):
        marker = re.match(r'^\s{0,3}(`{3,}|~{3,})', line)
        inside = fence is not None
        if marker:
            token = marker[1]
            if fence is None:
                fence = token
            elif token[0] == fence[0] and len(token) >= len(fence) and not line[marker.end():].strip():
                fence = None
        if inside or marker:
            line = re.sub(r'[^\n\r]', ' ', line)
        lines.append(line)
    text = ''.join(lines)
    if inline:
        text = re.sub(r'(`+)(?!`)([\s\S]*?)(?<!`)\1(?!`)',
                      lambda m: re.sub(r'[^\n\r]', ' ', m[0]), text)
    return text


def heading_slug(text):
    text = re.sub(r'!?\[([^\]]+)\]\([^)]+\)', r'\1', text)
    text = html.unescape(re.sub(r'<[^>]+>', '', text)).strip().lower()
    return ''.join(c for c in text if c in '_- ' or
                   unicodedata.category(c)[0] in 'LMN').replace(' ', '-')


def markdown_anchors(text):
    anchors = set()
    counts = Counter()
    text = without_code(text, inline=False)
    anchors.update(re.findall(r'<a\s+(?:id|name)=["\']([^"\']+)["\']', text))
    lines = text.splitlines()
    for index, line in enumerate(lines):
        heading = re.match(r'^\s{0,3}#{1,6}\s+(.+?)\s*#*$', line)
        title = heading[1] if heading else None
        if title is None and index + 1 < len(lines) and line.strip():
            if re.fullmatch(r'\s{0,3}(?:=+|-+)\s*', lines[index + 1]):
                title = line.strip()
        if title is not None:
            slug = heading_slug(title)
            anchors.add(slug + (f'-{counts[slug]}' if counts[slug] else ''))
            counts[slug] += 1
    return anchors


def closing_bracket(text, start):
    depth = 1
    index = start + 1
    while index < len(text):
        if text[index] == '\\':
            index += 2
            continue
        if text[index] == '[':
            depth += 1
        elif text[index] == ']':
            depth -= 1
            if depth == 0:
                return index
        index += 1
    return None


def destination(text, start):
    index = start
    while index < len(text) and text[index].isspace():
        index += 1
    if index < len(text) and text[index] == '<':
        end = text.find('>', index + 1)
        return (text[index + 1:end], end + 1) if end != -1 else (None, start)
    begin = index
    depth = 0
    while index < len(text):
        char = text[index]
        if char == '\\' and index + 1 < len(text):
            index += 2
            continue
        if char.isspace() or (char == ')' and depth == 0):
            break
        if char == '(':
            depth += 1
        elif char == ')':
            depth -= 1
        index += 1
    return text[begin:index], index


def markdown_links(text):
    """Yield (target, line) for inline, image and reference-style links."""
    text = without_code(text)
    definitions = {}
    label_key = lambda value: ' '.join(value.split()).casefold()
    definition_pattern = r'^\s{0,3}\[([^\]\n]+)\]:[^\n]*$'
    for match in re.finditer(definition_pattern, text, re.MULTILINE):
        target, _ = destination(match[0], match[0].index(':') + 1)
        definitions[label_key(match[1])] = target
    text = re.sub(definition_pattern, lambda m: re.sub(r'[^\n\r]', ' ', m[0]),
                  text, flags=re.MULTILINE)
    index = 0
    while index < len(text):
        begin = text.find('[', index)
        if begin == -1:
            break
        index = begin + 1
        if begin and text[begin - 1] == '\\':
            continue
        end = closing_bracket(text, begin)
        if end is None:
            continue
        label = text[begin + 1:end]
        target = None
        index = end + 1
        if index < len(text) and text[index] == '(':
            target, after = destination(text, index + 1)
            # Optional title is not part of the destination.
            suffix = re.match(r'\s*(?:"[^"\n]*"|\'[^\'\n]*\')?\s*\)', text[after:])
            if not suffix:
                target = None
            else:
                index = after + suffix.end()
        elif index < len(text) and text[index] == '[':
            ref_end = closing_bracket(text, index)
            if ref_end is not None:
                target = definitions.get(label_key(text[index + 1:ref_end] or label))
                index = ref_end + 1
        else:
            target = definitions.get(label_key(label))
        if target is not None:
            target = html.unescape(re.sub(r'\\([\\()[\] <>])', r'\1', target))
            yield target, text.count('\n', 0, begin) + 1


def local_artifact(name, published):
    if name in published:
        return False
    parts = Path(name).parts
    return (bool(parts) and parts[0] in {'.cache', '.tools', 'dist', 'tmp', 'output'}
            or bool({'build', '.dart_tool', '.gradle'}.intersection(parts))
            or (len(parts) >= 3 and parts[:2] in {
                ('design', 'styles'), ('design', 'screens')}
                and parts[2:] != ('README.md',)))


def check_documents(root, published, *, check_local=False):
    root = root.resolve()
    published = set(published)
    errors = []
    checked = skipped = documents = 0
    anchors = {}
    for name in sorted(published):
        source = root / name
        if source.suffix.lower() != '.md' or not source.is_file():
            continue
        if not source.resolve().is_relative_to(root):
            errors.append(f'{name}: document resolves outside the repository')
            continue
        documents += 1
        for ref, line in markdown_links(source.read_text(encoding='utf-8')):
            if re.match(r'^[a-zA-Z][\w+.-]*:', ref) or ref.startswith('//'):
                continue
            location = f'{name}:{line}'
            try:
                link = urlsplit(ref)
            except ValueError:
                errors.append(f'{location}: invalid link {ref!r}')
                continue
            target = Path(os.path.normpath(source.parent / unquote(link.path))) if link.path else source
            if not target.is_relative_to(root) or not target.resolve().is_relative_to(root):
                errors.append(f'{location}: link leaves the repository: {ref}')
                continue
            target_name = target.relative_to(root).as_posix()
            if not check_local and local_artifact(target_name, published):
                skipped += 1
                continue
            checked += 1
            if not target.exists():
                errors.append(f'{location}: missing file: {ref}')
            elif link.fragment and target.suffix.lower() == '.md':
                if target not in anchors:
                    anchors[target] = markdown_anchors(target.read_text(encoding='utf-8'))
                if unquote(link.fragment) not in anchors[target]:
                    errors.append(f'{location}: missing anchor: {ref}')
    api = root / 'client/lib/core/module_host/host_api.dart'
    sdk = root / 'docs/MODULE_SDK.md'
    if api.is_file() and sdk.is_file():
        actual = re.search(r'hostApiVersion\s*=\s*Version\((\d+),\s*(\d+),\s*(\d+)\)', api.read_text())
        declared = re.search(r'当前宿主 API 为 `(\d+)\.(\d+)\.(\d+)`', sdk.read_text())
        if not actual or not declared or actual.groups() != declared.groups():
            errors.append('docs/MODULE_SDK.md: current API must match host_api.dart')
    return {'documents': documents, 'linksChecked': checked,
            'localLinksSkipped': skipped, 'errors': errors}


def published_files(root):
    result = subprocess.check_output(
        ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=root)
    return {name for name in result.decode().split('\0') if name}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--check-local', action='store_true', help='also require local artifact links to exist')
    parser.add_argument('--json', type=Path, help='write a verification report')
    args = parser.parse_args()
    report = check_documents(args.root, published_files(args.root), check_local=args.check_local)
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    if report['errors']:
        parser.exit(1, '\n'.join(report['errors']) + '\n')
    print(f'Documentation checked: {report["documents"]} Markdown files, '
          f'{report["linksChecked"]} links; {report["localLinksSkipped"]} local artifact links skipped.')


if __name__ == '__main__':
    main()
