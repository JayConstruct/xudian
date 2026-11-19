#!/usr/bin/env python3
"""UI acceptance on a connected emulator; retains all module data.

Usage: --record-update performs reviewed rollback/update of app.schedule.
The verification update adds a statistics service using only JavaScript.
"""
import argparse
import hashlib
import json

from scripts.module_host.emulator_ui import Emulator, OUT, ROOT


class ScheduleUpdateEmulator(Emulator):
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
    emulator = ScheduleUpdateEmulator(args.serial)
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
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'android-final-update.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))

if __name__ == '__main__':
    main()
