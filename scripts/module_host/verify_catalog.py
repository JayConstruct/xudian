#!/usr/bin/env python3
"""Repeatable, read-only storefront acceptance; preserves installed modules and data."""
import argparse
import datetime
import json
from pathlib import Path
import re
import sys
import time

try:
    from . import verify_emulator
except ImportError:
    import verify_emulator

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from emulator_workflow import snapshot, fingerprint


def texts(node):
    return tuple(node.get(key, '') for key in ('text', 'content-desc', 'hint'))


def find_node(nodes, label, *, contains=False, button=False):
    matches = [node for node in nodes if any(
        label in text if contains else label == text for text in texts(node))]
    matches = [node for node in matches if node.get('enabled') != 'false'
               and area(node) > 0]
    if button:
        # Android's full-screen dismiss barrier is also labelled "关闭".
        matches = [node for node in matches if node.get('class') == 'android.widget.Button']
    if not matches:
        return None
    return min(matches, key=area) if button else matches[-1]


def area(node):
    left, top, right, bottom = verify_emulator.Emulator.bounds(node)
    return max(0, right - left) * max(0, bottom - top)


class CatalogAcceptance:
    def __init__(self, emulator, output, module, *, timeout=45):
        self.emulator, self.output, self.module = emulator, output, module
        self.timeout = timeout
        self.steps = []
        self.settings_open = False

    def wait(self, predicate, description):
        deadline = time.monotonic() + self.timeout
        while True:
            nodes = self.emulator.nodes()
            if predicate(nodes):
                return nodes
            if time.monotonic() >= deadline:
                raise RuntimeError('等待失败：' + description)
            time.sleep(.15)

    def wait_label(self, label, *, contains=False):
        return self.wait(lambda nodes: find_node(nodes, label, contains=contains) is not None, label)

    def tap(self, label, *, contains=False, button=False):
        node = find_node(self.emulator.snapshot().nodes, label, contains=contains, button=button)
        if node is None:
            raise RuntimeError('找不到可操作控件：' + label)
        self.emulator.tap_node(node)

    def back(self):
        self.emulator.adb('shell', 'input', 'keyevent', '4')

    def step(self, name, action):
        started = time.monotonic()
        action()
        self.steps.append({'name': name, 'seconds': round(time.monotonic() - started, 3)})
        print(name, flush=True)

    @property
    def card(self):
        return f'查看 {self.module["name"]} 详情'

    def open(self):
        self.emulator.home()
        self.emulator.open_settings()
        self.wait_label('模块与连接', contains=True)
        self.tap('模块与连接', contains=True)
        self.wait_label('模块管理与恢复', contains=True)
        self.tap('模块商店', contains=True)
        self.wait_label(self.card, contains=True)
        self.settings_open = False

    def details(self):
        for system_back in (False, True):
            self.tap(self.card, contains=True)
            self.wait(lambda nodes: any(self.module['id'] in texts(node)
                      or f'模块 ID：{self.module["id"]}' in texts(node) for node in nodes), '模块详情')
            if not system_back:
                self.emulator.record('details')
                self.tap('关闭', button=True)
            else:
                self.back()
            self.wait_label(self.card, contains=True)

    def search(self):
        self.tap('搜索名称、作用、作者或模块 ID')
        self.emulator.adb('shell', 'input', 'text', self.module['id'])
        self.back()
        self.wait_label('找到 1 个模块', contains=True)
        self.tap('清空搜索')
        self.wait_label(self.card, contains=True)

    def filters(self):
        self.tap('状态：全部')
        self.wait_label('已安装')
        self.tap('已安装')
        self.wait_label('状态：已安装')
        self.tap('状态：已安装')
        self.wait_label('全部')
        self.tap('全部')
        self.wait_label('状态：全部')

    def scroll_to(self, label, *, down=True):
        previous = None
        for _ in range(10):
            snap = self.emulator.snapshot(force=True)
            node = find_node(snap.nodes, label, contains=True)
            if node is not None:
                return node
            signature = [(texts(node), node.get('bounds')) for node in snap.nodes]
            if signature == previous:
                break
            previous = signature
            scrollables = [node for node in snap.nodes if node.get('scrollable') == 'true']
            if not scrollables:
                break
            left, top, right, bottom = self.emulator.bounds(max(scrollables, key=area))
            x = (left + right) // 2
            upper, lower = int(top + (bottom - top) * .2), int(top + (bottom - top) * .8)
            start, end = (lower, upper) if down else (upper, lower)
            self.emulator.adb('shell', 'input', 'swipe', str(x), str(start), str(x), str(end), '200')
        raise RuntimeError('滚动后找不到：' + label)

    def set_offline(self, enabled):
        if not self.settings_open:
            self.emulator.tap_node(self.scroll_to('商店设置'))
            self.settings_open = True
        node = self.scroll_to('离线浏览缓存')
        if node.get('checkable') != 'true':
            raise RuntimeError('无法读取离线开关状态；未盲目切换')
        if (node.get('checked') == 'true') != enabled:
            self.emulator.tap_node(node)
        self.scroll_to('搜索名称、作用、作者或模块 ID', down=False)
        self.wait(lambda nodes: (find_node(nodes, '正在浏览缓存', contains=True) is not None) == enabled
                  and find_node(nodes, self.card, contains=True) is not None
                  and find_node(nodes, '刷新 / 重试') is not None, '离线缓存' if enabled else '恢复在线')

    def offline(self):
        self.set_offline(True)
        self.emulator.record('offline')
        self.details()
        self.set_offline(False)
        self.emulator.record('online-restored')

    def reopen(self):
        # A keyboard can consume the first Back. Require the actual parent page.
        for _ in range(3):
            self.back()
            if find_node(self.emulator.nodes(), '模块管理与恢复', contains=True) is not None:
                break
        else:
            raise RuntimeError('返回未到达模块与连接设置')
        self.tap('模块商店', contains=True)
        self.wait_label(self.card, contains=True)
        self.emulator.record('reopened')
        self.emulator.home()

    def cold_start(self):
        self.emulator.adb('shell', 'am', 'force-stop', 'dev.taskapp.task_app')
        result = self.emulator.adb('shell', 'am', 'start', '-W', '-n', 'dev.taskapp.task_app/.MainActivity')
        if 'Status: ok' not in result:
            raise RuntimeError('Android 未确认应用冷启动成功')
        self.wait_label('页面菜单')
        self.emulator.record('cold-start')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', default='emulator-5554')
    parser.add_argument('--adb-host', default='127.0.0.1')
    parser.add_argument('--adb-port', type=int, default=5037)
    parser.add_argument('--module', default='app.schedule')
    parser.add_argument('--offline', action='store_true', help='加验离线缓存和恢复在线')
    parser.add_argument('--cold-start', action='store_true', help='加验停止应用进程后重新启动；不重启模拟器')
    parser.add_argument('--build-report', type=Path, default=ROOT / '.cache/emulator-update/latest-success.json')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args(argv)
    catalog = json.loads((ROOT / 'packages/catalog/catalog.json').read_text())
    module = next((item for item in catalog['modules'] if item['id'] == args.module), None)
    if module is None or not re.fullmatch(r'[a-z][a-z0-9_.-]*', args.module):
        parser.error('目录未收录模块：' + args.module)
    phases = ['打开商店', '详情关闭、返回与重开', '搜索并清空', '筛选并恢复']
    if args.offline:
        phases.append('离线缓存与恢复在线')
    phases.append('返回上级设置并再次打开')
    if args.cold_start:
        phases.append('应用冷启动')
    if args.dry_run:
        print(json.dumps({'module': args.module, 'phases': phases}, ensure_ascii=False, indent=2))
        return 0
    output = args.output or ROOT / '.cache/emulator-update/catalog-acceptance' / datetime.datetime.now(
        datetime.timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
    output.mkdir(parents=True, exist_ok=True)
    if (output / 'results.json').exists():
        parser.error('结果目录已有报告，请使用新目录：' + str(output))
    verify_emulator.OUT = output
    emulator = verify_emulator.Emulator(args.serial, adb_host=args.adb_host, adb_port=args.adb_port)
    flow = CatalogAcceptance(emulator, output, module)
    report = {'completed': False, 'steps': flow.steps, 'modifiedBusinessRecords': False}
    started = time.monotonic()
    try:
        build = json.loads(args.build_report.read_text())
        info = emulator.adb('shell', 'dumpsys', 'package', 'dev.taskapp.task_app')
        version = re.search(r'\bversionName=(\S+)', info)[1]
        code = int(re.search(r'\bversionCode=(\d+)', info)[1])
        digest = emulator.installed_digest()
        if (not build.get('completed') or digest != build.get('installedApkSha256')
                or code != build.get('installedVersionCode')
                or fingerprint(snapshot(ROOT)) != build.get('sourceFingerprint')):
            raise RuntimeError('设备 APK、成功更新记录或当前源码指纹不一致；请先更新模拟器')
        report.update(versionName=version, versionCode=code, installedApkSha256=digest,
                      sourceFingerprint=build['sourceFingerprint'])
        actions = [flow.open, flow.details, flow.search, flow.filters]
        if args.offline:
            actions.append(flow.offline)
        actions.append(flow.reopen)
        if args.cold_start:
            actions.append(flow.cold_start)
        for name, action in zip(phases, actions):
            flow.step(name, action)
        report['completed'] = True
    except Exception as error:
        report['error'] = str(error)
        raise
    finally:
        report['seconds'] = round(time.monotonic() - started, 3)
        (output / 'results.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
        print('验收记录：' + str(output), flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
