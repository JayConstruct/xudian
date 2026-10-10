#!/usr/bin/env python3
"""Verify first app installation and reviewed module-store dependency installation.

Use an empty Android user that is already in the foreground. Existing app
installations are refused; this script never clears data or uninstalls the app.
Android shares APK binaries between users, so use a dedicated emulator or the
same APK as any other user's installation. Evidence and a JSON report are kept
on both success and failure. Failed runs retain their app and module data.
--resume continues only a failed first installation proved by this output
directory's report, with the same device/user/APK and no target modules installed.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time
import uuid
import xml.etree.ElementTree as ET

try:
    from .verify_emulator import Emulator, ROOT, UiSnapshot
except ImportError:
    from verify_emulator import Emulator, ROOT, UiSnapshot


PACKAGE = 'dev.taskapp.task_app'
UNSIGNED = '未签名包；摘要验证不代表发布者签名'


class FreshInstallEmulator(Emulator):
    def snapshot(self, *, force=False):
        cached = self._snapshot
        if not force and cached is not None and time.monotonic() - cached.captured_at < self.SNAPSHOT_TTL:
            return cached
        self.invalidate_snapshot()
        # A unique path for every attempt prevents a successful but incomplete
        # dump (or a failed dump) from reusing an earlier screen's XML.
        for attempt in range(4):
            remote = f'/sdcard/xudian-fresh-{uuid.uuid4().hex}.xml'
            try:
                self._read_adb('shell', 'uiautomator', 'dump', remote)
                xml = self._read_adb('shell', 'cat', remote)
                root = ET.fromstring(xml)
                nodes = root.findall('.//node')
                if root.tag != 'hierarchy' or not nodes:
                    raise RuntimeError('uiautomator 未生成有效的当前界面 XML')
                snapshot = UiSnapshot(xml, nodes, time.monotonic())
                self._snapshot = snapshot
                return snapshot
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired,
                    ET.ParseError, RuntimeError) as error:
                self.invalidate_snapshot()
                if attempt == 3:
                    raise
                print(f'当前 UI dump 临时失败，1 秒后重试 {attempt + 1}/3：{error}',
                      file=sys.stderr, flush=True)
                time.sleep(1)
            finally:
                try:
                    self._read_adb('shell', 'rm', '-f', remote)
                except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
                    pass


class FreshInstallVerification:
    def __init__(self, args):
        self.args = args
        self.emulator = FreshInstallEmulator(args.serial, adb_host=args.adb_host,
                                             adb_port=args.adb_port)
        self.output = args.output.resolve()
        self.output.mkdir(parents=True, exist_ok=True)
        self.started = time.monotonic()
        self.ui_started = False
        self.resuming = False
        self.report_file = self.output / ('fresh-install-resume-rejected.json'
                                          if args.resume else 'fresh-install.json')
        self.modules = [
            {'id': 'app.schedule', 'name': '大学课表',
             'version': args.expected_schedule_version},
            {'id': 'app.import.shiguang', 'name': '拾光教务导入兼容',
             'version': args.expected_importer_version},
        ]
        self.report = {
            'status': 'running', 'startedAt': datetime.now(timezone.utc).isoformat(),
            'serial': args.serial, 'androidUser': args.user,
            'adbHost': args.adb_host, 'adbPort': args.adb_port,
            'apk': str(args.apk.resolve()), 'expectedModules': self.modules,
            'steps': [], 'artifacts': [], 'attempt': 1,
        }

    def step(self, name, **evidence):
        self.report['steps'].append({'name': name, 'passed': True, **evidence})
        print(name, flush=True)
        self.write_report()

    def write_report(self):
        self.report['elapsedSeconds'] = round(time.monotonic() - self.started, 2)
        self.report_file.write_text(
            json.dumps(self.report, ensure_ascii=False, indent=2) + '\n',
            encoding='utf-8')

    def record(self, name):
        if self.resuming:
            name = f'attempt-{self.report["attempt"]:02d}-{name}'
        # Capture a screenshot independently, so a failed accessibility dump
        # still leaves useful visual evidence of the failure.
        screenshot = self.emulator.adb('exec-out', 'screencap', '-p', binary=True)
        (self.output / f'{name}.png').write_bytes(screenshot)
        artifact = {'name': name, 'xml': None, 'screenshot': f'{name}.png'}
        self.report['artifacts'].append(artifact)
        snapshot = self.emulator.snapshot(force=True)
        (self.output / f'{name}.xml').write_text(snapshot.xml, encoding='utf-8')
        artifact['xml'] = f'{name}.xml'
        return snapshot.nodes

    def prepare_resume(self):
        previous_file = self.output / 'fresh-install.json'
        if not previous_file.is_file():
            raise RuntimeError('--resume 缺少同一 output 目录的原始 fresh-install.json')
        previous_text = previous_file.read_text(encoding='utf-8')
        previous = json.loads(previous_text)
        proven = {step.get('name'): step for step in previous.get('steps', [])
                  if step.get('passed') is True}
        digest = self.report['apkSha256']
        if (previous.get('status') != 'failed'
                or previous.get('androidUser') != self.args.user
                or previous.get('serial') != self.args.serial
                or previous.get('apkSha256') != digest
                or 'targetUserInitiallyUninstalled' not in proven
                or 'apkFirstInstalled' not in proven
                or proven['apkFirstInstalled'].get('installedApkSha256') != digest):
            raise RuntimeError('--resume 原报告不能证明相同 user/serial/APK 的失败首装；'
                               '拒绝使用已有安装替代从 0 验收')
        if self.installed_apk_digest() != digest:
            raise RuntimeError('--resume 当前已安装 APK 与原首装证据不一致')
        if 'modulesInstalledFromStore' in proven:
            raise RuntimeError('--resume 原报告已证明模块安装完成；'
                               '仅允许恢复模块尚未安装的失败首装')
        attempt = previous.get('attempt', 1)
        if not isinstance(attempt, int) or attempt < 1:
            raise RuntimeError('--resume 原报告 attempt 无效')
        archive = self.output / f'fresh-install-attempt-{attempt:02d}.json'
        if archive.exists() and archive.read_text(encoding='utf-8') != previous_text:
            raise RuntimeError('--resume 上一轮报告归档已存在且内容不同，拒绝覆盖证据')
        archive.write_text(previous_text, encoding='utf-8')
        self.report = previous
        self.report['attempt'] = attempt + 1
        self.report['attemptStartedAt'] = datetime.now(timezone.utc).isoformat()
        self.report['previousFailure'] = previous.get('error')
        self.report['previousAttemptReport'] = archive.name
        self.report['status'] = 'running'
        for key in ('error', 'failureCaptureError', 'failureVisibleLabels'):
            self.report.pop(key, None)
        self.resuming = True
        self.report_file = previous_file
        self.step('resumeOriginalFirstInstallationVerified', installedApkSha256=digest,
                  previousAttemptReport=archive.name)

    def refuse_existing_modules_on_resume(self):
        self.find_scrolling('模块商店', down=False)
        previous_labels = None
        stable = 0
        saw_module = False
        for _ in range(20):
            nodes = self.emulator.nodes()
            self.check_errors(nodes)
            labels = self.labels(nodes)
            for label in labels:
                for module in self.modules:
                    if module['name'] in label.splitlines() or module['id'] in label.splitlines():
                        self.record('resume-refused-existing-module')
                        self.report['resumeExistingModule'] = label
                        raise RuntimeError('--resume 模块管理已有目标模块，拒绝重复安装：' + label)
                if re.search(r'\d+\.\d+\.\d+ · 已启用', label):
                    saw_module = True
            stable = stable + 1 if labels == previous_labels else 0
            if stable >= 2:
                if not saw_module:
                    raise RuntimeError('--resume 未读取到模块管理列表，无法证明目标模块尚未安装')
                self.step('resumeTargetModulesStillUninstalled')
                self.find_scrolling('模块商店', down=False)
                return
            previous_labels = labels
            self.swipe(nodes)
        raise RuntimeError('--resume 无法检查完整模块管理列表，拒绝继续安装')

    def labels(self, nodes):
        return [self.emulator.label(node) for node in nodes
                if self.emulator.label(node)]

    def check_errors(self, nodes):
        for label in self.labels(nodes):
            if re.search(r'^(?:Bad state:|[A-Za-z]+(?:Error|Exception):)', label):
                raise RuntimeError('宿主出现错误：' + label)

    def swipe(self, nodes, *, down=True):
        """Scroll inside the visible scrollable region, using accessibility bounds."""
        rectangles = [self.emulator.bounds(node) for node in nodes
                      if node.get('bounds')]
        width = max((r[2] for r in rectangles), default=0)
        height = max((r[3] for r in rectangles), default=0)
        if width <= 0 or height <= 0:
            raise RuntimeError('无法读取当前屏幕尺寸，不能滚动')
        scrollables = [self.emulator.bounds(node) for node in nodes
                       if node.get('scrollable') == 'true' and node.get('bounds')]
        scrollables = [r for r in scrollables if r[2] > r[0] and r[3] > r[1]]
        if scrollables:
            left, top, right, bottom = max(
                scrollables, key=lambda r: (r[2] - r[0]) * (r[3] - r[1]))
        else:
            left, top, right, bottom = 0, int(height * .18), width, int(height * .88)
        x = (left + right) // 2
        upper = int(top + (bottom - top) * .22)
        lower = int(top + (bottom - top) * .78)
        start, end = (lower, upper) if down else (upper, lower)
        self.emulator.adb('shell', 'input', 'swipe', str(x), str(start),
                          str(x), str(end), '300')

    def find_scrolling(self, label, *, contains=False, attempts=16, down=True):
        for index in range(attempts):
            nodes = self.emulator.nodes()
            self.check_errors(nodes)
            found = [node for node in nodes
                     if (label in self.emulator.label(node) if contains
                         else label == self.emulator.label(node))
                     and node.get('enabled') != 'false']
            if found:
                return found[-1]
            if index < attempts - 1:
                self.swipe(nodes, down=down)
        raise RuntimeError(f'滚动后仍未找到 {label!r}；可见 UI：{self.labels(nodes)}')

    def tap_scrolling(self, label, **kwargs):
        self.emulator.tap_node(self.find_scrolling(label, **kwargs))

    def launch(self, *, restart=False):
        e = self.emulator
        if restart:
            e.adb('shell', 'am', 'force-stop', '--user', str(self.args.user), PACKAGE)
        e.adb('shell', 'am', 'start', '--user', str(self.args.user), '-W',
              '-n', f'{PACKAGE}/.MainActivity')
        e.wait_for('页面菜单', timeout=30)

    def installed_apk_digest(self):
        paths = self.emulator.adb('shell', 'pm', 'path', '--user',
                                  str(self.args.user), PACKAGE).splitlines()
        bases = [line.removeprefix('package:') for line in paths
                 if line.startswith('package:') and line.endswith('/base.apk')]
        if len(bases) != 1:
            raise RuntimeError('无法定位目标 Android user 的已安装 base.apk：' + str(paths))
        digest = self.emulator.adb('shell', 'sha256sum', bases[0]).split()[0]
        if not re.fullmatch(r'[0-9a-f]{64}', digest):
            raise RuntimeError('已安装 APK 的 SHA-256 无效：' + digest)
        return digest

    def manager(self):
        self.emulator.manager()
        self.emulator.wait_for('模块管理', timeout=15)

    def wait_for_store_version(self):
        """Wait for asynchronous indices; periodically refresh stale CDN results."""
        e = self.emulator
        card = self.find_scrolling('拾光教务导入兼容', contains=True)
        started = time.monotonic()
        deadline = started + 120
        next_refresh = started + 18
        stale_seen = False
        observations = []
        refreshes = []
        last_label = e.label(card)
        expected = f'版本：{self.args.expected_importer_version} · 可安装'
        self.report['storeVersionWait'] = {
            'expectedVersion': self.args.expected_importer_version,
            'observations': observations, 'refreshes': refreshes,
        }
        while True:
            nodes = e.nodes()
            self.check_errors(nodes)
            cards = [node for node in nodes
                     if '拾光教务导入兼容' in e.label(node)
                     and '版本：' in e.label(node)]
            if cards:
                card = cards[-1]
                last_label = e.label(card)
                if not observations or observations[-1]['label'] != last_label:
                    observations.append({'elapsedSeconds': round(time.monotonic() - started, 2),
                                         'label': last_label})
                    self.write_report()
                if expected in last_label:
                    self.step('expectedStoreVersionReady',
                              actualVersion=self.args.expected_importer_version,
                              refreshCount=len(refreshes))
                    return card
                match = re.search(r'版本：(\d+\.\d+\.\d+[^\s·]*)', last_label)
                if match:
                    stale_seen = True
                    self.report['storeVersionWait']['actualVersion'] = match[1]
            now = time.monotonic()
            # An initial loading placeholder gets 90 seconds. Once a resolved
            # stale index is observed, allow the complete 120-second CDN window.
            if now >= deadline or (not stale_seen and now - started >= 90):
                self.record('02-store-version-timeout')
                raise RuntimeError(
                    f'商店在等待及重试后未提供预期拾光版本 '
                    f'{self.args.expected_importer_version} · 可安装；'
                    f'实际版本：{self.report["storeVersionWait"].get("actualVersion", "仍未加载")}；'
                    f'最后卡片：{last_label}')
            if stale_seen and now >= next_refresh:
                refresh = [node for node in nodes
                           if e.label(node) in ('刷新 / 重试', '刷新', '重试')
                           and node.get('enabled') == 'true']
                if refresh:
                    self.record(f'02-store-before-refresh-{len(refreshes):02d}')
                    e.tap_node(refresh[0])
                    refreshes.append({'elapsedSeconds': round(time.monotonic() - started, 2)})
                    next_refresh = time.monotonic() + 18
                    self.write_report()
                    print('商店索引尚未到预期版本，已刷新 / 重试', flush=True)
            # Once the card is visible, poll in place instead of scrolling it
            # away while its asynchronously fetched version index settles.
            time.sleep(min(1, max(0, deadline - time.monotonic())))

    def verify_review(self):
        e = self.emulator
        e.wait_for('确认模块安装计划', timeout=120)
        sections = {module['name']: set() for module in self.modules}
        headers = {f"{m['name']} · {m['version']}": m['name'] for m in self.modules}
        active = None
        all_lines = set()
        for index in range(20):
            nodes = self.record(f'03-install-review-{index:02d}')
            self.check_errors(nodes)
            lines = [line.strip() for label in self.labels(nodes)
                     for line in label.splitlines() if line.strip()]
            for line in lines:
                all_lines.add(line)
                if line in headers:
                    active = headers[line]
                if active and (line in headers or line.startswith(
                        ('新增权限：', '全部权限：', 'SHA-256：', '操作：')) or line == UNSIGNED):
                    sections[active].add(line)
            complete = all(
                f"{m['name']} · {m['version']}" in sections[m['name']]
                and UNSIGNED in sections[m['name']]
                and '操作：安装并启用' in sections[m['name']]
                and any(line.startswith('新增权限：') for line in sections[m['name']])
                and any(line.startswith('全部权限：') for line in sections[m['name']])
                and any(re.fullmatch(r'SHA-256：[0-9a-f]{64}', line)
                        for line in sections[m['name']])
                for m in self.modules)
            if complete:
                break
            self.swipe(nodes)
        else:
            raise RuntimeError('依赖审核缺少预期模块、版本、未签名提示、权限或 SHA-256；'
                               '不会确认安装：' + str({k: sorted(v) for k, v in sections.items()}))
        reviews = []
        for module in self.modules:
            fields = sections[module['name']]
            digests = [line.removeprefix('SHA-256：') for line in fields
                       if re.fullmatch(r'SHA-256：[0-9a-f]{64}', line)]
            if len(digests) != 1:
                raise RuntimeError('模块审核摘要归属不明确；不会确认安装：' + str(fields))
            reviews.append({**module, 'sha256': digests[0], 'unsigned': True,
                            'newPermissions': sorted(line for line in fields
                                                     if line.startswith('新增权限：')),
                            'allPermissions': sorted(line for line in fields
                                                     if line.startswith('全部权限：'))})
        if len({review['sha256'] for review in reviews}) != len(self.modules):
            raise RuntimeError('两个模块的审核摘要相同；不会确认安装')
        self.step('dependencyReviewVerified', modules=reviews,
                  visibleReviewLines=sorted(all_lines))
        e.tap_node(self.find_scrolling('确认安装', attempts=2))
        e.wait_for('模块安装完成', timeout=90, contains=True)
        self.record('04-store-install-complete')
        self.step('modulesInstalledFromStore')

    def verify_enabled(self, stage):
        self.manager()
        self.find_scrolling('模块商店', down=False)
        remaining = {m['name']: m for m in self.modules}
        observed = {}
        # Start at the top even if the manager retained its previous position.
        for index in range(16):
            nodes = self.emulator.nodes()
            self.check_errors(nodes)
            for node in nodes:
                label = self.emulator.label(node)
                for name, module in list(remaining.items()):
                    if (name in label.splitlines()
                            and f"{module['version']} · 已启用" in label.splitlines()):
                        observed[module['id']] = label
                        del remaining[name]
            self.record(f'{stage}-manager-{index:02d}')
            if not remaining:
                self.step(stage, moduleRows=observed)
                return
            self.swipe(nodes)
        raise RuntimeError('模块管理未核对到预期版本已启用：' + str(remaining))

    def run(self):
        args, e = self.args, self.emulator
        if not args.apk.is_file():
            raise RuntimeError('APK 文件不存在：' + str(args.apk))
        self.report['apkSha256'] = hashlib.sha256(args.apk.read_bytes()).hexdigest()
        installed = e.adb('shell', 'pm', 'list', 'packages', '--user', str(args.user), PACKAGE)
        app_installed = f'package:{PACKAGE}' in installed.splitlines()
        if app_installed and not args.resume:
            raise RuntimeError(f'Android user {args.user} 已安装 {PACKAGE}；拒绝覆盖或清数据。'
                               '请使用未安装本 App 的独立模拟器或 Android user。')
        current = e.adb('shell', 'am', 'get-current-user').strip()
        if current != str(args.user):
            raise RuntimeError(f'当前前台 Android user 为 {current}，不是 {args.user}；'
                               '请先切换目标 user 后重试，避免验证错误用户的 UI。')
        if args.resume:
            if not app_installed:
                raise RuntimeError('--resume 目标 user 的原首装 App 已不存在，拒绝重新安装替代原证据')
            self.prepare_resume()
        else:
            self.step('targetUserInitiallyUninstalled', packageList=installed.strip())
            install = e.adb('install', '--user', str(args.user), '-r', str(args.apk.resolve()))
            if 'Success' not in install:
                raise RuntimeError('首次 APK 安装未成功：' + install)
            digest = self.installed_apk_digest()
            if digest != self.report['apkSha256']:
                raise RuntimeError('首装 APK 摘要与指定文件不一致')
            self.step('apkFirstInstalled', adbOutput=install.strip(), installedApkSha256=digest)
        self.ui_started = True
        e.adb('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP')
        e.adb('shell', 'wm', 'dismiss-keyguard')
        self.launch(restart=self.resuming)
        e.wait_for('暂无今天待办或逾期任务', timeout=30, contains=True)
        self.record('resume-today-empty' if self.resuming else '01-today-empty')
        self.step('resumeTodayEmptyVerified' if self.resuming else 'initialTodayEmpty')
        self.manager()
        self.record('resume-manager-before-install' if self.resuming else '01-initial-module-manager')
        if self.resuming:
            self.refuse_existing_modules_on_resume()
        self.tap_scrolling('模块商店')
        e.wait_for('模块商店', timeout=30)
        card = self.wait_for_store_version()
        self.record('02-store-importer')
        e.tap_node(card)
        self.tap_scrolling('解析依赖并安装')
        self.verify_review()
        e.home()
        self.verify_enabled('05-modules-enabled')
        self.launch(restart=True)
        self.verify_enabled('06-modules-enabled-after-restart')
        e.home()
        self.tap_scrolling('课表')
        e.wait_for('创建课表或导入 JSON 备份后开始使用', timeout=30, contains=True)
        self.record('07-schedule-opened')
        self.step('scheduleOpenedAfterRestart')
        e.home()
        e.open_settings()
        nodes = e.nodes()
        if not any('拾光教务导入' in label for label in self.labels(nodes)):
            self.tap_scrolling('模块与连接', contains=True)
        self.tap_scrolling('拾光教务导入', contains=True)
        e.wait_for('按学校导入', timeout=30, contains=True)
        self.record('08-importer-settings-opened')
        self.step('importerSettingsOpenedAfterRestart')
        if hashlib.sha256(args.apk.read_bytes()).hexdigest() != self.report['apkSha256']:
            raise RuntimeError('验收期间本地 APK 文件发生变化')
        digest = self.installed_apk_digest()
        if digest != self.report['apkSha256']:
            raise RuntimeError('安装模块后已安装 APK 摘要发生变化')
        self.step('installedApkUnchangedDuringModuleInstallation', installedApkSha256=digest)
        self.report['status'] = 'passed'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--user', type=int, default=0)
    parser.add_argument('--serial', default='emulator-5554')
    parser.add_argument('--adb-host', default='127.0.0.1')
    parser.add_argument('--adb-port', default='5037')
    parser.add_argument('--output', type=Path, default=ROOT / 'dist/verification/fresh-install')
    parser.add_argument('--expected-schedule-version', default='1.7.0')
    parser.add_argument('--expected-importer-version', default='1.4.0')
    parser.add_argument('--resume', action='store_true',
                        help='Resume a failed first install proved by this output directory, before module installation')
    args = parser.parse_args()
    if args.user < 0:
        parser.error('--user must be nonnegative')
    verification = FreshInstallVerification(args)
    try:
        verification.run()
    except Exception as error:
        verification.report['status'] = 'failed'
        verification.report['error'] = f'{type(error).__name__}: {error}'
        if verification.ui_started:
            try:
                nodes = verification.record('failure-ui')
                verification.report['failureVisibleLabels'] = verification.labels(nodes)
            except Exception as capture_error:
                verification.report['failureCaptureError'] = str(capture_error)
        print(verification.report['error'], file=sys.stderr, flush=True)
    finally:
        verification.write_report()
        print('Report:', verification.report_file, flush=True)
    return 0 if verification.report['status'] == 'passed' else 1


if __name__ == '__main__':
    sys.exit(main())
