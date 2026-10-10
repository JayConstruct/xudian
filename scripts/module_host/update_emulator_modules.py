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


def _select_download(emulator, filename):
    nodes = emulator.nodes()
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
        downloads = _find(emulator, nodes, ['下载', 'Downloads', 'Download'])
        if downloads is None:
            raise RuntimeError('文件选择器没有下载入口：' + str(_labels(emulator, nodes)))
        emulator.tap_node(downloads)
        nodes = emulator.nodes()
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
        emulator.adb('shell', 'input', 'swipe', '500', '1550', '500', '500', '250')
        nodes = emulator.nodes()
        target = _find(emulator, nodes, [filename])
    raise RuntimeError('下载目录找不到模块包：' + filename)


def _confirm_review(emulator, module):
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
    lines = [line.strip() for label in labels for line in label.splitlines()]
    permissions = [line for line in lines if line.startswith('新增权限：')]
    if permissions != ['新增权限：无']:
        raise RuntimeError('模块存在新增权限或无法核对权限，请在当前审核页手动审核：' + str(permissions))
    if f'{module["name"]} · {module["version"]}' not in lines or f'SHA-256：{module["sha256"]}' not in lines:
        raise RuntimeError('审核模块版本或摘要与打包结果不一致；不会确认')
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
    for _ in range(10):
        # A ListTile's merged accessibility node contains name and version together.
        rows = [emulator.label(node) for node in nodes]
        _check_host_error(rows)
        matches = [node for node in nodes
                   if module['name'] in emulator.label(node).splitlines()
                   and f'{module["version"]} · 已启用' in emulator.label(node).splitlines()]
        if matches:
            return matches[-1]
        emulator.adb('shell', 'input', 'swipe', '500', '1550', '500', '500', '250')
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
        emulator.adb('shell', 'input', 'swipe', '500', '1300', '500', '650', '250')
        nodes = emulator.nodes()
    raise RuntimeError('无法读取已安装模块 SHA-256；不会将同版本导入报告为成功')


def update_modules(module_ids, emulator, output_dir):
    """Update only named modules; preserve data and stop at newly requested permissions."""
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
            emulator.adb('shell', 'input', 'swipe', '500', '500', '500', '1550', '250')
            nodes = emulator.nodes()
        else:
            raise RuntimeError('模块管理中找不到导入按钮：' + str(_labels(emulator, nodes)))
        emulator.tap_node(button)
        _select_download(emulator, filename)
        changed = _confirm_review(emulator, module)
        row = _verify_installed(emulator, module)
        if not changed:
            _verify_same_package(emulator, module, row)
        module['status'] = 'installed' if changed else 'already-installed'
        action = '模块安装完成' if changed else '模块同版本已复用，未重新安装'
        print(f'{action}：{module["id"]} {module["version"]}；包 SHA-256 {module["sha256"]}', flush=True)
    # Clear the accessibility-persistent "打开模块" snackbar after batch completion.
    emulator.adb('shell', 'am', 'force-stop', PACKAGE)
    emulator.adb('shell', 'am', 'start', '-W', '-n', f'{PACKAGE}/.MainActivity')
    return modules
