#!/usr/bin/env python3
"""UI acceptance on a connected emulator; retains all module data.

Usage: --record-update performs reviewed rollback/update of app.schedule.
The verification update adds a statistics service using only JavaScript.
"""
import argparse
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import subprocess
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'dist/verification'

@dataclass(frozen=True)
class UiSnapshot:
    xml: str
    nodes: list
    captured_at: float

class Emulator:
    SNAPSHOT_TTL = 0.25

    def __init__(self, serial, *, adb_host='127.0.0.1', adb_port='5037'):
        self.command = ['adb', '-H', adb_host, '-P', str(adb_port), '-s', serial]
        self._snapshot = None

    def invalidate_snapshot(self):
        """Also call after UI changes made by an external adb process."""
        self._snapshot = None

    def _read_adb(self, *args, binary=False):
        result = subprocess.run(self.command + list(args), capture_output=True, check=True, timeout=30)
        return result.stdout if binary else result.stdout.decode(errors='replace')

    def adb(self, *args, binary=False):
        # Public commands can contain arbitrary shell input, installs or activity
        # launches. Invalidate before executing, including commands that fail.
        self.invalidate_snapshot()
        return self._read_adb(*args, binary=binary)
    def installed_digest(self):
        paths = self.adb('shell', 'pm', 'path', 'dev.taskapp.task_app').splitlines()
        base = next(p.removeprefix('package:') for p in paths if p.endswith('/base.apk'))
        return self.adb('shell', 'sha256sum', base).split()[0]
    def snapshot(self, *, force=False):
        """Reuse only immediate reads; force a new dump for polls and recordings."""
        cached = self._snapshot
        if not force and cached is not None and time.monotonic() - cached.captured_at < self.SNAPSHOT_TTL:
            return cached
        self.invalidate_snapshot()
        self._read_adb('shell', 'uiautomator', 'dump', '/sdcard/xudian-ui.xml')
        xml = self._read_adb('shell', 'cat', '/sdcard/xudian-ui.xml')
        snapshot = UiSnapshot(xml, ET.fromstring(xml).findall('.//node'), time.monotonic())
        self._snapshot = snapshot
        return snapshot

    def nodes(self):
        # Existing acceptance scripts use repeated calls to await transitions.
        return self.snapshot(force=True).nodes
    @staticmethod
    def label(node):
        return node.get('text') or node.get('content-desc') or ''
    @staticmethod
    def bounds(node):
        return list(map(int, node.get('bounds').replace('][', ',').strip('[]').split(',')))
    def find(self, nodes, label, contains=False):
        found = [n for n in nodes if (label in self.label(n) if contains else self.label(n) == label)]
        if not found:
            raise RuntimeError('UI item missing: ' + label + '; visible: ' + str([self.label(n) for n in nodes if self.label(n)]))
        return found[-1]
    def tap_node(self, node):
        x, y, xx, yy = self.bounds(node)
        self.adb('shell', 'input', 'tap', str((x + xx)//2), str((y + yy)//2))
    def tap(self, label, contains=False):
        self.tap_node(self.find(self.snapshot().nodes, label, contains))

    def wait_for(self, label, timeout=10, contains=False):
        deadline = time.monotonic() + timeout
        while True:
            nodes = self.nodes()
            found = [n for n in nodes if (label in self.label(n) if contains else self.label(n) == label)]
            if found:
                return found[-1]
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                self.find(nodes, label, contains)
            time.sleep(min(0.2, remaining))

    def record(self, name):
        OUT.mkdir(parents=True, exist_ok=True)
        # Wait for accessibility to settle before capturing route animations.
        snapshot = self.snapshot(force=True)
        screenshot = self._read_adb('exec-out', 'screencap', '-p', binary=True)
        (OUT / (name + '.png')).write_bytes(screenshot)
        (OUT / (name + '.xml')).write_text(snapshot.xml)
        print(name, flush=True)
    def open_settings(self):
        nodes = self.nodes()
        recovery = [n for n in nodes if self.label(n) == '打开设置并恢复模块']
        direct = [n for n in nodes if self.label(n) == '打开设置']
        if recovery or direct:
            self.tap_node((recovery or direct)[-1])
        else:
            self.tap_node(self.find(nodes, '页面菜单'))
            self.tap('设置')
    def manager(self):
        nodes = self.nodes()
        if any(self.label(n) == '模块管理' for n in nodes): return
        if not any('模块管理与恢复' in self.label(n) or '模块与连接' in self.label(n) for n in nodes):
            self.open_settings()
            nodes = self.nodes()
        categories = [n for n in nodes if '模块与连接' in self.label(n)]
        if categories: self.tap_node(categories[-1])
        self.tap('模块管理与恢复', contains=True)
    def home(self):
        for _ in range(6):
            nodes = self.nodes()
            if any(self.label(n) in ['没有可用工作区', '打开设置', '页面菜单'] for n in nodes): return
            self.adb('shell', 'input', 'keyevent', '4')
        raise RuntimeError('Home did not appear')
    def schedule_menu(self):
        self.manager()
        nodes = self.nodes()
        row = self.find(nodes, 'app.schedule @', contains=True)
        _, y, _, yy = self.bounds(row)
        self.adb('shell', 'input', 'tap', '929', str((y + yy)//2))
    def update(self):
        self.schedule_menu(); self.tap('版本与回退'); self.tap('1.0.0 ·', contains=True); self.tap('确认')
        self.home(); self.tap('课表')
        assert not any('脚本更新新增统计' in self.label(n) for n in self.nodes())
        self.record('android-schedule-original-final')
        self.manager(); self.tap('导入 .xmodule')
        nodes = self.nodes()
        if not any(self.label(n) == 'app.schedule-1.0.1.xmodule' for n in nodes):
            self.tap_node(self.find(nodes, '显示根目录')); self.tap('下载'); nodes = self.nodes()
        if any(self.label(n) == '列表视图' for n in nodes):
            self.tap_node(self.find(nodes, '列表视图')); nodes = self.nodes()
        self.tap_node(self.find(nodes, 'app.schedule-1.0.1.xmodule'))
        self.tap('确认'); self.home(); self.tap('课表')
        assert any('脚本更新新增统计：1 门课程' in self.label(n) for n in self.nodes())
        self.record('android-schedule-script-update')
        self.adb('shell', 'am', 'force-stop', 'dev.taskapp.task_app')
        self.adb('shell', 'am', 'start', '-n', 'dev.taskapp.task_app/.MainActivity')
        self.tap('课表')
        assert any('脚本更新新增统计：1 门课程' in self.label(n) for n in self.nodes())
        self.record('android-schedule-update-restart')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--serial', default='emulator-5554')
    parser.add_argument('--record-update', action='store_true')
    args = parser.parse_args()
    emulator = Emulator(args.serial)
    apk = ROOT / 'client/build/app/outputs/flutter-apk/app-release.apk'
    before = hashlib.sha256(apk.read_bytes()).hexdigest()
    installed_before = emulator.installed_digest()
    assert installed_before == before, 'Installed APK differs from the delivery APK'
    if args.record_update:
        emulator.update()
    assert hashlib.sha256(apk.read_bytes()).hexdigest() == before
    installed_after = emulator.installed_digest()
    assert installed_after == installed_before
    result = {'apkSha256Before': before, 'apkSha256After': before,
              'installedApkSha256Before': installed_before,
              'installedApkSha256After': installed_after,
              'scriptUpdateAndRestartVerified': args.record_update}
    OUT.mkdir(exist_ok=True)
    (OUT / 'android-final-update.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))

if __name__ == '__main__':
    main()
