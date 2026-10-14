#!/usr/bin/env python3
"""Pack selected modules and install through the host's reviewed import UI."""
import json
from pathlib import Path
import re

try:
    from .build_packages import pack
except ImportError:
    from build_packages import pack

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = 'dev.taskapp.task_app'


def prepare_modules(module_ids, output_dir):
    """Validate every selected source before writing packages or touching a device."""
    base = (ROOT / 'packages/modules').resolve()
    prepared = []
    for module_id in dict.fromkeys(module_ids):
        if not isinstance(module_id, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', module_id):
            raise ValueError(f'无效模块 ID：{module_id}')
        folder = (base / module_id).resolve()
        if folder.parent != base or not folder.is_dir():
            raise ValueError(f'模块不存在或路径越界：{module_id}')
        for source in folder.rglob('*'):
            if source.is_symlink():
                raise ValueError(f'模块源文件不接受符号链接：{source}')
        definition = json.loads((folder / 'module.json').read_text())
        manifest = definition.get('manifest', {})
        version = manifest.get('version')
        if manifest.get('id') != module_id:
            raise ValueError(f'目录与 manifest.id 不一致：{module_id}')
        if not isinstance(version, str) or not re.fullmatch(r'\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)*', version):
            raise ValueError(f'模块版本无效：{module_id}')
        if definition.get('formatVersion') != 3 or not isinstance(manifest.get('name'), str) or not manifest['name']:
            raise ValueError(f'模块定义无效：{module_id}')
        prepared.append((folder, manifest))
    result = []
    for folder, manifest in prepared:
        destination = Path(output_dir) / f'{manifest["id"]}-{manifest["version"]}.xmodule'
        digest = pack(folder, destination)
        result.append({'id': manifest['id'], 'name': manifest['name'], 'version': manifest['version'],
                       'sha256': digest, 'package': str(destination)})
    return result


def _labels(emulator, nodes):
    return [emulator.label(node) for node in nodes if emulator.label(node)]


def _find(emulator, nodes, labels):
    for label in labels:
        found = [node for node in nodes if emulator.label(node) == label]
        if found:
            return found[-1]
    return None


def _check_host_error(labels):
    for label in labels:
        if re.search(r'^(?:Bad state:|[A-Za-z]+(?:Error|Exception):)', label):
            raise RuntimeError('宿主拒绝模块导入：' + label)


def _swipe(emulator, nodes, *, down=True):
    rectangles = []
    scrollables = []
    for node in nodes:
        raw = node.get('bounds', '')
        match = re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', raw)
        if match:
            rectangle = tuple(map(int, match.groups()))
            if rectangle[2] > rectangle[0] and rectangle[3] > rectangle[1]:
                rectangles.append(rectangle)
                if node.get('scrollable') == 'true':
                    scrollables.append(rectangle)
    if not rectangles:
        raise RuntimeError('无法读取当前 UI 屏幕尺寸；不会使用固定坐标滚动')
    if scrollables:
        left, top, right, bottom = max(
            scrollables, key=lambda r: (r[2] - r[0]) * (r[3] - r[1]))
    else:
        left, top = 0, 0
        right = max(r[2] for r in rectangles)
        bottom = max(r[3] for r in rectangles)
    x = (left + right) // 2
    upper = int(top + (bottom - top) * .35)
    lower = int(top + (bottom - top) * .65)
    start, end = (lower, upper) if down else (upper, lower)
    emulator.adb('shell', 'input', 'swipe', str(x), str(start), str(x), str(end), '250')


def _permission_values(fields, prefix):
    values = {line.removeprefix(prefix) for line in fields if line.startswith(prefix)}
    if len(values) != 1:
        raise RuntimeError('新增权限或完整权限字段缺失/归属不明确；不会确认：' + str(values))
    value = next(iter(values))
    if value == '无':
        return set()
    tokens = value.split('、')
    if any(not token or any(char.isspace() for char in token) or '…' in token
           or '...' in token or token == '无' for token in tokens):
        raise RuntimeError('新增权限或完整权限字段不完整；不会确认：' + value)
    return set(tokens)


def _permission_authorization(permissions):
    if (not isinstance(permissions, (set, frozenset))
            or any(not isinstance(value, str) or not value or value == '无'
                   or any(char.isspace() for char in value) or '、' in value
                   or '…' in value or '...' in value for value in permissions)):
        raise ValueError('allowed_added_permissions 必须是明确的完整权限标识集合')
    return frozenset(permissions)


def _review_lines(emulator, nodes):
    permission_prefixes = ('新增权限：', '全部权限：', '新增权限标识：', '全部权限标识：')
    lines = []
    for label in _labels(emulator, nodes):
        if label.startswith(permission_prefixes) and len(label.splitlines()) != 1:
            raise RuntimeError('权限字段含换行或未知合并结构；不会截断后确认')
        for line in label.splitlines():
            # Whitespace is part of a permission identifier; never silently
            # normalize an unrecognized permission into an authorized one.
            lines.append(line if line.startswith(permission_prefixes) else line.strip())
    return lines


def _drawer_nodes(emulator, nodes):
    for node in nodes:
        resource = node.get('resource-id', '').split('/')[-1]
        if resource in ('roots_list', 'container_roots', 'drawer_roots'):
            return list(node.iter())
    labels = _labels(emulator, nodes)
    if (any(label in labels for label in ('打开文档', 'Open from'))
            and any(label in labels for label in ('最近', 'Recent', '最近使用'))
            and any(label in labels for label in ('下载', 'Downloads', 'Download'))):
        return nodes
    return None


def _select_download_root(emulator, nodes):
    drawer = _drawer_nodes(emulator, nodes)
    scope = nodes if drawer is None else drawer
    candidates = [node for node in scope
                  if emulator.label(node) in ('下载', 'Downloads', 'Download')]
    selected = [node for node in candidates if node.get('selected') == 'true']
    if selected:
        candidates = selected
    if len(candidates) != 1:
        raise RuntimeError('文件选择器下载根目录缺失或归属不明确；不会点击背后文件')
    emulator.tap_node(candidates[0])
    for _ in range(12):
        nodes = emulator.nodes()
        if _drawer_nodes(emulator, nodes) is None:
            return nodes
    breadcrumbs = [emulator.label(node) for node in nodes
                   if node.get('resource-id', '').split('/')[-1] == 'breadcrumb_text']
    if (len(breadcrumbs) == 1 and breadcrumbs[0] in ('下载', 'Downloads', 'Download')
            and _drawer_nodes(emulator, nodes) is not None):
        # Some DocumentsUI versions retain an already-selected root's drawer.
        # BACK is safe only with both the open drawer and Download breadcrumb
        # proved; never use it to recover an unknown picker or another route.
        emulator.adb('shell', 'input', 'keyevent', '4')
        for _ in range(12):
            nodes = emulator.nodes()
            if _drawer_nodes(emulator, nodes) is None:
                return nodes
    raise RuntimeError('文件选择器根目录抽屉未关闭；不会点击背后文件')


def _scroll_to_top(emulator, nodes, *, description='审核内容'):
    """Return to a stable start before collecting identity and overlapping fields."""
    previous = None
    stable = 0
    for _ in range(40):
        labels = _labels(emulator, nodes)
        _check_host_error(labels)
        stable = stable + 1 if labels == previous else 0
        if stable >= 2:
            return nodes
        previous = labels
        _swipe(emulator, nodes, down=False)
        nodes = emulator.nodes()
    raise RuntimeError(description + '无法返回稳定顶部；不会继续')


def _select_download(emulator, filename):
    nodes = emulator.nodes()
    if _drawer_nodes(emulator, nodes) is not None:
        nodes = _select_download_root(emulator, nodes)
    target = _find(emulator, nodes, [filename])
    if target is not None:
        emulator.tap_node(target)
        return
    # DocumentsUI may retain another location and/or its grid presentation.
    listing = _find(emulator, nodes, ['列表视图', 'List view'])
    if listing is not None:
        emulator.tap_node(listing)
        nodes = emulator.nodes()
        target = _find(emulator, nodes, [filename])
    if target is None:
        roots = _find(emulator, nodes, ['显示根目录', 'Show roots'])
        if roots is not None:
            emulator.tap_node(roots)
            nodes = emulator.nodes()
        nodes = _select_download_root(emulator, nodes)
        listing = _find(emulator, nodes, ['列表视图', 'List view'])
        if listing is not None:
            emulator.tap_node(listing)
            nodes = emulator.nodes()
        target = _find(emulator, nodes, [filename])
    # The newest download can be below the visible viewport.
    for _ in range(8):
        if target is not None:
            emulator.tap_node(target)
            return
        _swipe(emulator, nodes)
        nodes = emulator.nodes()
        target = _find(emulator, nodes, [filename])
    raise RuntimeError('下载目录找不到模块包：' + filename)


def _confirm_review(emulator, module, *, allowed_added_permissions=frozenset()):
    allowed = _permission_authorization(allowed_added_permissions)
    for _ in range(8):
        nodes = emulator.nodes()
        labels = _labels(emulator, nodes)
        _check_host_error(labels)
        if '所需模块已经安装并启用' in labels:
            return False
        if '确认模块安装计划' in labels:
            break
    else:
        raise RuntimeError('宿主未显示安装审核；不会确认：' + str(labels))
    lines = _review_lines(emulator, nodes)
    if '你选择的模块' in lines:
        plan_count = None
        for _ in range(24):
            labels = _labels(emulator, nodes)
            _check_host_error(labels)
            lines = _review_lines(emulator, nodes)
            for line in lines:
                if re.fullmatch(r'(?:安装|升级|启用|继续使用) \d+ 个(?:，(?:安装|升级|启用|继续使用) \d+ 个)*', line):
                    plan_count = sum(int(value) for value in re.findall(r'(\d+) 个', line))
            expand = next((node for node in nodes
                           if '技术详情与完整计划' in emulator.label(node)
                           and node.get('enabled') != 'false'), None)
            if expand is not None:
                if not plan_count:
                    raise RuntimeError('无法核对完整计划模块数量；不会确认')
                emulator.tap_node(expand)
                nodes = emulator.nodes()
                break
            _swipe(emulator, nodes)
            nodes = emulator.nodes()
        else:
            raise RuntimeError('审核页缺少技术详情与完整计划；不会确认')
        nodes = _scroll_to_top(emulator, nodes)
        sections = {}
        scan = []
        previous_lines = set()
        for index in range(80):
            lines = _review_lines(emulator, nodes)
            _check_host_error(lines)
            active = None
            recovered = set()
            for line in lines:
                if re.match(r'^\d+\. ', line):
                    active = None
                elif line.startswith('模块标识：'):
                    active = line.removeprefix('模块标识：')
                    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', active):
                        raise RuntimeError('完整计划模块标识无效；不会确认')
                    sections.setdefault(active, set())
                elif active is None:
                    owners = [identity for identity, fields in sections.items() if line in fields]
                    if len(owners) == 1:
                        active = owners[0]
                        recovered.add(active)
                if active:
                    sections[active].add(line)
            scan.append({'index': index, 'moduleIds': sorted(sections),
                         'overlapFieldCount': len(set(lines) & previous_lines),
                         'recoveredModuleIds': sorted(recovered)})
            previous_lines = set(lines)
            complete = len(sections) == plan_count and all(
                any(line.startswith('新增权限标识：') for line in fields)
                and any(line.startswith('全部权限标识：') for line in fields)
                and any(re.fullmatch(r'SHA-256：[0-9a-f]{64}', line) for line in fields)
                and any(re.fullmatch(r'(?:安装并启用|启用|继续使用) · [^\s]+(?:（无需安装）)?|升级并启用 · [^\s]+ → [^\s]+', line)
                        for line in fields)
                for fields in sections.values())
            if complete:
                break
            _swipe(emulator, nodes)
            nodes = emulator.nodes()
        else:
            raise RuntimeError('完整计划标识、版本、摘要或新增权限不完整；不会确认')
        fields = sections.get(module['id'], set())
        versions = set()
        for line in fields:
            match = re.fullmatch(r'(?:安装并启用|启用|继续使用) · ([^\s]+?)(?:（无需安装）)?|升级并启用 · [^\s]+ → ([^\s]+)', line)
            if match:
                versions.add(match[1] or match[2])
        digests = {line.removeprefix('SHA-256：') for line in fields if line.startswith('SHA-256：')}
        if versions != {module['version']} or digests != {module['sha256']}:
            raise RuntimeError('审核模块 ID、版本或摘要与打包结果不一致；不会确认')
        for fields in sections.values():
            added = _permission_values(fields, '新增权限标识：')
            all_permissions = _permission_values(fields, '全部权限标识：')
            if not added.issubset(all_permissions) or not added.issubset(allowed):
                raise RuntimeError('模块存在未授权新增权限或权限字段不一致；不会确认：' + str(sorted(added)))
        module['reviewScan'] = scan
    else:
        added = _permission_values(set(lines), '新增权限：')
        if not added.issubset(allowed):
            raise RuntimeError('模块存在未授权新增权限；不会确认：' + str(sorted(added)))
        if f'{module["name"]} · {module["version"]}' not in lines or f'SHA-256：{module["sha256"]}' not in lines:
            raise RuntimeError('审核模块版本或摘要与打包结果不一致；不会确认')
    button = _find(emulator, nodes, ['确认安装'])
    for _ in range(8):
        if button is not None:
            break
        _swipe(emulator, nodes)
        nodes = emulator.nodes()
        _check_host_error(_labels(emulator, nodes))
        button = _find(emulator, nodes, ['确认安装'])
    if button is None:
        raise RuntimeError('审核页缺少确认安装按钮')
    emulator.tap_node(button)
    return True


def _verify_installed(emulator, module):
    for _ in range(8):
        nodes = emulator.nodes()
        if _find(emulator, nodes, ['模块管理']) is not None:
            break
    else:
        raise RuntimeError('安装后未返回模块管理')
    nodes = _scroll_to_top(emulator, nodes, description='模块管理列表')
    for _ in range(10):
        # A ListTile's merged accessibility node contains name and version together.
        rows = [emulator.label(node) for node in nodes]
        _check_host_error(rows)
        matches = [node for node in nodes
                   if module['name'] in emulator.label(node).splitlines()
                   and f'{module["version"]} · 已启用' in emulator.label(node).splitlines()]
        if matches:
            return matches[-1]
        _swipe(emulator, nodes)
        nodes = emulator.nodes()
    raise RuntimeError(f'安装后未核对到 {module["id"]} {module["version"]} 已启用')


def _verify_same_package(emulator, module, row):
    """Host skips same-version imports; inspect its actual stored package digest."""
    emulator.tap_node(row)
    for _ in range(5):
        nodes = emulator.nodes()
        labels = _labels(emulator, nodes)
        _check_host_error(labels)
        if _find(emulator, nodes, ['关闭']) is not None:
            break
    else:
        raise RuntimeError('无法打开已安装模块详情；不会将同版本导入报告为成功')
    fields = {}
    for _ in range(8):
        lines = [line.strip() for label in _labels(emulator, nodes) for line in label.splitlines()]
        for i, line in enumerate(lines[:-1]):
            if line in ('模块 ID', '版本与状态', 'SHA-256'):
                fields[line] = lines[i + 1]
        digest = fields.get('SHA-256', '')
        if re.fullmatch(r'[0-9a-f]{64}', digest):
            if (fields.get('模块 ID') != module['id']
                    or fields.get('版本与状态') != f'{module["version"]} · 已启用'):
                raise RuntimeError('已安装模块详情的 ID 或版本不一致；不会报告成功')
            if digest != module['sha256']:
                raise RuntimeError(f'{module["id"]} {module["version"]} 已安装包与当前源码摘要不同；'
                                   '请提升 module.json 中的模块版本号后重试，同版本源码不可覆盖')
            close = _find(emulator, nodes, ['关闭'])
            if close is None:
                raise RuntimeError('已安装模块详情缺少关闭按钮')
            emulator.tap_node(close)
            module['installedSha256'] = digest
            return
        _swipe(emulator, nodes)
        nodes = emulator.nodes()
    raise RuntimeError('无法读取已安装模块 SHA-256；不会将同版本导入报告为成功')


def update_modules(module_ids, emulator, output_dir, *, allowed_added_permissions=frozenset()):
    """Update only named modules; preserve data and stop at newly requested permissions."""
    allowed = _permission_authorization(allowed_added_permissions)
    modules = prepare_modules(module_ids, output_dir)
    if not modules:
        return []
    emulator.adb('shell', 'am', 'start', '-W', '-n', f'{PACKAGE}/.MainActivity')
    for _ in range(10):
        labels = _labels(emulator, emulator.nodes())
        if any(label in labels for label in ['页面菜单', '打开设置', '模块管理', '打开设置并恢复模块']):
            break
    else:
        raise RuntimeError('App 启动后未就绪')
    for module in modules:
        filename = Path(module['package']).name
        emulator.adb('push', module['package'], '/sdcard/Download/' + filename)
        emulator.manager()
        nodes = emulator.nodes()
        # manager() taps the route; its first accessibility snapshot can still
        # describe the settings page while the transition is completing.
        for _ in range(4):
            if (_find(emulator, nodes, ['模块管理']) is not None
                    and _find(emulator, nodes, ['导入 .xmodule']) is not None):
                break
            nodes = emulator.nodes()
        for _ in range(10):
            button = _find(emulator, nodes, ['导入 .xmodule'])
            if button is not None:
                break
            _swipe(emulator, nodes, down=False)
            nodes = emulator.nodes()
        else:
            raise RuntimeError('模块管理中找不到导入按钮：' + str(_labels(emulator, nodes)))
        emulator.tap_node(button)
        _select_download(emulator, filename)
        changed = _confirm_review(emulator, module, allowed_added_permissions=allowed)
        row = _verify_installed(emulator, module)
        if not changed:
            _verify_same_package(emulator, module, row)
        module['status'] = 'installed' if changed else 'already-installed'
        action = '模块安装完成' if changed else '模块同版本已复用，未重新安装'
        print(f'{action}：{module["id"]} {module["version"]}；包 SHA-256 {module["sha256"]}', flush=True)
    return modules
