#!/usr/bin/env python3
"""Manage shallow UI drafts and legacy batches; see design/README.md."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import sys
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
DESIGNS = ROOT / 'dist/design'
UI_DESIGNS = ROOT / 'design'
SECTIONS = ('references', 'drafts', 'selected', 'notes')
IMAGES = {'.png', '.jpg', '.jpeg', '.webp', '.gif'}
PAGE_CATEGORIES = ('日程与任务', '课表与教务', '项目推进', '模块管理', 'AI 助手', '应用设置', '全局与通用')
PAGE_ALIASES = {
    'ui-01': 'schedule-home', 'ui-02': 'planner', 'ui-03': 'new-task',
    'ui-04': 'batch-tasks', 'ui-05': 'planning-preview', 'ui-06': 'task-details',
    'ui-07': 'task-history', 'ui-08': 'timetable', 'ui-09': 'courses',
    'ui-10': 'timetable-settings', 'ui-11': 'course-import', 'ui-12': 'ai-chat',
    'ui-13': 'model-connections', 'ui-14': 'module-store', 'ui-15': 'module-details',
    'ui-16': 'module-install', 'ui-17': 'module-manager', 'ui-18': 'module-permissions',
    'ui-19': 'data-recovery', 'ui-20': 'settings', 'ui-21': 'appearance',
    'ui-22': 'app-updates', 'ui-23': 'projects',
}


def timestamp():
    return datetime.now(ZoneInfo('Asia/Shanghai'))


def plain_path(value):
    candidate = Path(value).absolute()
    if any(parent.is_symlink() for parent in [candidate, *candidate.parents]):
        raise ValueError('设计批次不能经过符号链接')
    return candidate.resolve()


def flat_area(topic):
    name = PAGE_ALIASES.get(topic, topic)
    if (name == 'screens' or name.startswith('ui-')
            or not re.fullmatch(r'[a-z][a-z0-9]*(?:-[a-z0-9]+)*', name)):
        raise ValueError('浅层主题须使用功能名称，例如 settings')
    return UI_DESIGNS / name


def batch_path(value):
    path = Path(value).absolute()
    area = path.parent.parent
    # Moved pages can retain this exact relative link for old review URLs.
    if (area.parent == UI_DESIGNS / 'screens' and area.name in PAGE_ALIASES
            and path.parent.name == '.batches' and area.is_symlink()
            and area.readlink() in (Path('..') / area.name, Path('..') / PAGE_ALIASES[area.name])):
        plain_path(area.parent)
        path = UI_DESIGNS / area.readlink().name / path.parent.name / path.name
    path = plain_path(path)
    base = DESIGNS.resolve()
    if path.is_relative_to(base) and len(path.relative_to(base).parts) == 2:
        return path
    ui_base = UI_DESIGNS.resolve()
    if path.is_relative_to(ui_base):
        parts = path.relative_to(ui_base).parts
        if len(parts) == 3 and parts[1] == '.batches':
            area = ui_base / parts[0] if parts[0] in PAGE_ALIASES else flat_area(parts[0])
        elif (len(parts) == 4 and parts[0] == 'screens'
              and parts[2] == '.batches' and parts[1] in PAGE_ALIASES):
            # Older workspaces may still have physical page directories here.
            area = ui_base / 'screens' / parts[1]
        else:
            raise ValueError('页面和风格批次位于 design/<功能名>/.batches/ 下')
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
        'schemaVersion': 2, 'layout': 'flat', 'topic': area.name,
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


def new_batch(topic, brief, *, page=False):
    if not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', topic):
        raise ValueError('主题使用小写英文、数字和短横线，例如 planner-cancellation')
    if not brief.strip():
        raise ValueError('需求说明不能为空')
    if page or topic == 'styles' or topic.startswith('ui-'):
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
    area = batch.parent.parent
    prefix = batch.name + '-'
    if (manifest.get('layout') != 'flat' or manifest.get('batch') != batch.name
            or manifest.get('topic') != area.name or not manifest.get('brief')
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
        if not batch.is_relative_to(UI_DESIGNS.resolve()):
            raise ValueError('浅层清单仅接受 design/ 下的批次')
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


def read_page_catalog(file):
    """Read the editable page table. Image paths in its Markdown links are relative to it."""
    root = file.parent.parent.resolve()
    image_roots = (root / 'design', root / 'dist/design', root / 'docs/design')
    pages = []
    names = set()
    for number, line in enumerate(file.read_text(encoding='utf-8').splitlines(), 1):
        if not line.startswith('|') or line.startswith(('| 功能分类 |', '| --- |')):
            continue
        cells = [cell.strip() for cell in line.strip('|').split('|')]
        location = f'{file.name}:{number}'
        if len(cells) != 6 or not all(cells):
            raise ValueError(f'{location} 每行须填写六列，别名、设计稿和待完善项为空时用 —')
        category, page_id, name, aliases, links, pending = cells
        if category not in PAGE_CATEGORIES:
            raise ValueError(f'{location} 未知功能分类：{category}。可用分类：{"、".join(PAGE_CATEGORIES)}')
        if not re.fullmatch(r'[a-z][a-z0-9]*(?:-[a-z0-9]+)*', page_id):
            raise ValueError(f'{location} 页面标识须使用英文小写和连字符')
        aliases = [] if aliases == '—' else [a.strip() for a in aliases.split('、')]
        for key in (page_id, name, *aliases):
            if not key or key.casefold() in names:
                raise ValueError(f'{location} 页面标识、名称或别名重复或为空：{key}')
            names.add(key.casefold())
        images = []
        labels = set()
        if links != '—':
            for link in links.split('<br>'):
                match = re.fullmatch(r'\[([^\[\]]+)\]\(([^\s()]+)\)', link.strip())
                if not match:
                    raise ValueError(f'{location} 设计稿须使用 [状态](相对图片路径)')
                label, target = match.groups()
                path = (file.parent / target).resolve()
                if (Path(target).is_absolute() or path.suffix.lower() not in IMAGES
                        or not any(path.is_relative_to(base) for base in image_roots)):
                    raise ValueError(f'{location} 无效的设计稿路径：{target}')
                if label in labels:
                    raise ValueError(f'{location} 同一页面有重复的状态名称：{label}')
                labels.add(label)
                images.append({'state': label, 'path': path.relative_to(root).as_posix(),
                               'available': path.is_file()})
        if not images and pending == '—':
            raise ValueError(f'{location} 未关联图片的页面须记录待完善项')
        pages.append({'id': page_id, 'name': name, 'category': category, 'aliases': aliases, 'images': images,
                      'pending': None if pending == '—' else pending})
    if not pages:
        raise ValueError('页面映射表为空')
    return pages


def query_pages(pages, terms, pending, *, category=None):
    if category is not None:
        pages = [page for page in pages if page['category'] == category]
    found = {}
    missing = []
    for term in terms:
        key = term.strip().casefold()
        key = PAGE_ALIASES.get(key, key)
        exact, partial = [], []
        for page in pages:
            names = [value.casefold() for value in (page['id'], page['name'], *page['aliases'])]
            if key in names:
                exact.append(page)
            elif key and any(key in value for value in names):
                partial.append(page)
        matches = exact or partial
        if not matches:
            missing.append(term)
        found.update((page['id'], page) for page in matches)
    results = found.values() if terms else pages
    return [page for page in results if not pending or page['pending']], missing


def print_page_results(pages):
    if not pages:
        print('没有符合条件的页面。')
    for page in pages:
        print(f'{page["name"]} ({page["id"]}) · {page["category"]}')
        for image in page['images']:
            availability = '' if image['available'] else '（本机缺图）'
            print(f'  {image["state"]}  {image["path"]}{availability}')
        if not page['images']:
            print('  尚未关联设计稿')
        if page['pending']:
            print(f'  待完善：{page["pending"]}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    new = commands.add_parser('new', help='创建一个独立设计批次')
    new.add_argument('topic')
    new.add_argument('--page', action='store_true', help='按功能名称创建页面设计批次')
    new.add_argument('--brief', required=True)
    query = commands.add_parser('query', help='按页面名、别名或标识查询设计稿')
    query.add_argument('names', nargs='*', help='可传多个名称；省略时列出全部页面')
    query.add_argument('--category', choices=PAGE_CATEGORIES, help='在指定功能分类中查询')
    query.add_argument('--pending', action='store_true', help='只列出已登记待完善项的页面')
    query.add_argument('--json', action='store_true', help='输出 JSON 数组')
    for command in ('index', 'check'):
        sub = commands.add_parser(command, help='更新摘要清单' if command == 'index' else '只读校验批次和摘要')
        sub.add_argument('batch', type=Path)
    args = parser.parse_args()
    try:
        if args.command == 'query':
            pages = read_page_catalog(UI_DESIGNS / 'PAGES.md')
            results, missing = query_pages(pages, args.names, args.pending, category=args.category)
            if args.json:
                print(json.dumps(results, ensure_ascii=False, indent=2))
            else:
                print_page_results(results)
            if missing:
                scope = f'在「{args.category}」中' if args.category else ''
                print(scope + '未找到页面：' + '、'.join(missing), file=sys.stderr)
                return 1
            return
        if args.command == 'new':
            print(new_batch(args.topic, args.brief, page=args.page).relative_to(ROOT))
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
    sys.exit(main())
