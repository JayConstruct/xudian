#!/usr/bin/env python3
"""Manage shallow UI drafts and legacy batches; see docs/DESIGN_ARTIFACTS.md."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
DESIGNS = ROOT / 'dist/design'
UI_DESIGNS = ROOT / 'design'
SECTIONS = ('references', 'drafts', 'selected', 'notes')
IMAGES = {'.png', '.jpg', '.jpeg', '.webp', '.gif'}


def timestamp():
    return datetime.now(ZoneInfo('Asia/Shanghai'))


def plain_path(value):
    candidate = Path(value).absolute()
    if any(parent.is_symlink() for parent in [candidate, *candidate.parents]):
        raise ValueError('设计批次不能经过符号链接')
    return candidate.resolve()


def flat_area(topic):
    if topic == 'styles':
        return UI_DESIGNS / 'styles'
    if isinstance(topic, str) and re.fullmatch(r'ui-(?:0[1-9]|1[0-9]|2[0-2])', topic):
        return UI_DESIGNS / 'screens' / topic
    raise ValueError('浅层主题只接受 styles 或 ui-01 至 ui-22')


def batch_path(value):
    path = plain_path(value)
    base = DESIGNS.resolve()
    if path.is_relative_to(base) and len(path.relative_to(base).parts) == 2:
        return path
    ui_base = UI_DESIGNS.resolve()
    if path.is_relative_to(ui_base):
        parts = path.relative_to(ui_base).parts
        if len(parts) == 3 and parts[:2] == ('styles', '.batches'):
            area = flat_area('styles')
        elif (len(parts) == 4 and parts[0] == 'screens'
              and parts[2] == '.batches'):
            area = flat_area(parts[1])
        else:
            raise ValueError('浅层批次位于 design/styles 或 design/screens/ui-XX 的 .batches/ 下')
        if (path.parent != area.resolve() / '.batches'
                or not re.fullmatch(r'\d{8}-\d{6}-\d{6}', path.name)):
            raise ValueError('浅层批次路径或时间编号不正确')
        return path
    raise ValueError('批次须位于 design/ 的 .batches/ 或 dist/design/<topic>/<batch>/')


def new_flat_batch(topic, brief):
    now = timestamp()
    area = flat_area(topic)
    batch = area / '.batches' / now.strftime('%Y%m%d-%H%M%S-%f')
    batch_path(batch)
    batch.mkdir(parents=True, exist_ok=False)
    for section in ('references', 'notes'):
        (batch / section).mkdir()
    manifest = {
        'schemaVersion': 2, 'layout': 'flat', 'topic': topic,
        'batch': batch.name, 'createdAt': now.isoformat(), 'brief': brief,
        'artifactDirectory': area.relative_to(ROOT).as_posix(),
        'filePrefix': batch.name + '-', 'status': 'draft', 'tool': '未记录',
        'references': [], 'selection': None, 'files': [],
    }
    (batch / 'manifest.json').write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    (batch / 'README.md').write_text(
        f'# {brief}\n\n'
        f'原图和完整同名提示词直接放在 {manifest["artifactDirectory"]}/。\n'
        f'文件名须以 {manifest["filePrefix"]} 开头，例如 '
        f'{manifest["filePrefix"]}style-a-v01.png。\n\n'
        '本目录只存清单、references/ 和 notes/。原图不再套 drafts/。\n'
        'selection 记录 source（原图文件名）和 reason，不复制或覆盖原图。\n'
        '填写实际工具和来源后运行 index，再运行 check；批次只索引自己的文件。\n')
    return batch


def new_batch(topic, brief):
    if not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', topic):
        raise ValueError('主题使用小写英文、数字和短横线，例如 planner-cancellation')
    if not brief.strip():
        raise ValueError('需求说明不能为空')
    if topic == 'styles' or topic.startswith('ui-'):
        return new_flat_batch(topic, brief)
    now = timestamp()
    batch = DESIGNS / topic / now.strftime('%Y%m%d-%H%M%S-%f')
    batch_path(batch)
    batch.mkdir(parents=True, exist_ok=False)
    for section in SECTIONS:
        (batch / section).mkdir()
    manifest = {
        'schemaVersion': 1, 'topic': topic, 'batch': batch.name,
        'createdAt': now.isoformat(), 'brief': brief,
        'status': 'draft', 'tool': '未记录', 'legacy': False,
        'references': [], 'selection': None, 'files': [],
    }
    (batch / 'manifest.json').write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    (batch / 'README.md').write_text(
        f'# {brief}\n\n'
        '- references/：输入图片、真实截图及来源说明。\n'
        '- drafts/：v01.png、v01.prompt.txt；每次修改另增版本。\n'
        '- selected/：选定稿的副本；在 manifest.json 记录原稿路径。\n'
        '- notes/：需求、比较和决策；不得把视觉稿标记为已实现。\n\n'
        '保存每版完整提示词，在 manifest.json 填写实际工具、参考来源与选择原因。'
        '完成后运行 python3 scripts/design_artifacts.py index <本目录>，'
        '再运行 check <本目录>。\n')
    return batch


def inspect_flat_batch(batch, manifest):
    area = plain_path(flat_area(manifest.get('topic', '')))
    prefix = batch.name + '-'
    if (manifest.get('layout') != 'flat' or manifest.get('batch') != batch.name
            or batch.parent != area / '.batches' or not manifest.get('brief')
            or manifest.get('artifactDirectory') != area.relative_to(ROOT).as_posix()
            or manifest.get('filePrefix') != prefix):
        raise ValueError('浅层清单的主题、目录、批次、前缀或需求不正确')
    files = []
    def add(path):
        path = plain_path(path)
        files.append({'path': path.relative_to(area).as_posix(),
                      'bytes': path.stat().st_size,
                      'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    for path in sorted(area.iterdir()):
        if not path.name.startswith(prefix):
            continue
        plain_path(path)
        if not path.is_file():
            raise ValueError('浅层原稿必须是普通文件：' + str(path))
        if path.suffix.lower() in IMAGES:
            if not re.fullmatch(re.escape(prefix) + r'[a-z0-9]+(?:-[a-z0-9]+)*-v\d{2,}', path.stem):
                raise ValueError('原图文件名须含批次前缀、英文说明及 -v01 等版本：' + path.name)
            prompt = path.with_suffix('.prompt.txt')
            plain_path(prompt)
            if not prompt.is_file() or not prompt.read_text().strip():
                raise ValueError('缺少该版本的完整提示词：' + str(prompt))
        add(path)
    for section in ('references', 'notes'):
        directory = batch / section
        plain_path(directory)
        if not directory.is_dir():
            raise ValueError('缺少普通目录：' + str(directory))
        for path in sorted(directory.rglob('*')):
            plain_path(path)
            if path.is_file():
                add(path)
    images = {f['path']: f for f in files if not f['path'].startswith('.batches/')
              and Path(f['path']).suffix.lower() in IMAGES}
    if images and manifest.get('tool') in (None, '', '未记录'):
        raise ValueError('新增图片后须在 manifest.json 记录实际工具或制作方式')
    if manifest.get('status') not in ('draft', 'selected'):
        raise ValueError('浅层批次状态须为 draft 或 selected')
    selection = manifest.get('selection')
    choices = selection if isinstance(selection, list) else [selection] if selection else []
    selected = []
    for choice in choices:
        if (not isinstance(choice, dict) or not choice.get('reason')
                or choice.get('source') not in images):
            raise ValueError('选定稿须为本批次原图文件名，并记录选择原因')
        selected.append(choice['source'])
    if len(set(selected)) != len(selected):
        raise ValueError('选定稿不能重复')
    if bool(choices) != (manifest.get('status') == 'selected'):
        raise ValueError('selected 状态与 selection 记录须一致')
    return manifest, sorted(files, key=lambda item: item['path'])


def inspect_batch(batch):
    batch = batch_path(batch)
    manifest = json.loads(plain_path(batch / 'manifest.json').read_text())
    if manifest.get('schemaVersion') == 2:
        return inspect_flat_batch(batch, manifest)
    if not batch.is_relative_to(DESIGNS.resolve()):
        raise ValueError('旧版清单仅接受 dist/design/ 历史批次')
    if (manifest.get('schemaVersion') != 1 or manifest.get('topic') != batch.parent.name
            or manifest.get('batch') != batch.name or not manifest.get('brief')):
        raise ValueError('manifest.json 的版本、主题、批次或需求不完整')
    files = []
    for section in SECTIONS:
        directory = batch / section
        if not directory.is_dir() or directory.is_symlink():
            raise ValueError(f'缺少普通目录：{section}/')
        for path in sorted(directory.rglob('*')):
            if path.is_symlink():
                raise ValueError(f'批次内不能包含符号链接：{path}')
            if not path.is_file():
                continue
            if (section == 'drafts' and path.suffix.lower() in IMAGES
                    and not manifest.get('legacy')):
                prompt = path.with_suffix('.prompt.txt')
                if not prompt.is_file() or not prompt.read_text().strip():
                    raise ValueError(f'缺少该版本的完整提示词：{prompt}')
            files.append({'path': path.relative_to(batch).as_posix(),
                          'bytes': path.stat().st_size,
                          'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    if not manifest.get('legacy'):
        images = [f for f in files if Path(f['path']).suffix.lower() in IMAGES]
        if images and manifest.get('tool') in (None, '', '未记录'):
            raise ValueError('新增图片后须在 manifest.json 记录实际工具或制作方式')
        selected = [f for f in images if f['path'].startswith('selected/')]
        if selected:
            selection = manifest.get('selection')
            choices = selection if isinstance(selection, list) else [selection]
            by_path = {f['path']: f for f in files}
            recorded = []
            for choice in choices:
                if not isinstance(choice, dict) or not choice.get('reason'):
                    raise ValueError('每张选定稿须记录 selection.source、file 和 reason')
                source = by_path.get(choice.get('source'))
                target = by_path.get(choice.get('file'))
                if (not source or not target or not source['path'].startswith('drafts/')
                        or not target['path'].startswith('selected/')
                        or source['sha256'] != target['sha256']):
                    raise ValueError('选定稿须为原稿的完整副本，且与 selection 路径一致')
                recorded.append(target['path'])
            if sorted(recorded) != sorted(f['path'] for f in selected):
                raise ValueError('selection 须逐一覆盖选定稿，不重复或遗漏')
    return manifest, files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    new = commands.add_parser('new', help='创建一个独立设计批次')
    new.add_argument('topic')
    new.add_argument('--brief', required=True)
    for command in ('index', 'check'):
        sub = commands.add_parser(command, help='更新摘要清单' if command == 'index' else '只读校验批次和摘要')
        sub.add_argument('batch', type=Path)
    args = parser.parse_args()
    try:
        if args.command == 'new':
            print(new_batch(args.topic, args.brief).relative_to(ROOT))
            return
        batch = batch_path(args.batch)
        manifest, files = inspect_batch(batch)
        if args.command == 'index':
            manifest['files'] = files
            manifest['indexedAt'] = timestamp().isoformat()
            (batch / 'manifest.json').write_text(
                json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
        elif manifest.get('files') != files:
            raise ValueError('文件或摘要与清单不一致；核对变更后重新执行 index')
        print(f'{args.command}: {batch.relative_to(ROOT)} ({len(files)} files)')
    except (OSError, ValueError, KeyError) as error:
        parser.exit(1, f'{error}\n')


if __name__ == '__main__':
    main()
