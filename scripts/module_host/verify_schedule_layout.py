#!/usr/bin/env python3
"""Review-install the schedule layout package and verify real emulator navigation."""
import argparse
import json
from verify_emulator import Emulator, OUT


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--installed', action='store_true', help='Verify an already installed 1.1.0 package')
    args = parser.parse_args()
    emulator = Emulator('emulator-5554')
    apk_before = emulator.installed_digest()
    emulator.manager()
    if args.installed:
        assert any('app.schedule @ 1.1.0' in emulator.label(n) for n in emulator.nodes())
    else:
        emulator.tap('导入 .xmodule')
        nodes = emulator.nodes()
        name = 'app.schedule-1.1.0.xmodule'
        if not any(emulator.label(n) == name for n in nodes):
            emulator.tap_node(emulator.find(nodes, '显示根目录'))
            emulator.tap('下载')
            nodes = emulator.nodes()
        if any(emulator.label(n) == '列表视图' for n in nodes):
            emulator.tap_node(emulator.find(nodes, '列表视图'))
        emulator.tap(name)
        emulator.tap('确认')
    emulator.home()
    emulator.tap('课表')
    labels = [emulator.label(n) for n in emulator.nodes()]
    assert any('第 1 周' in label for label in labels), labels
    assert not any(label in ['新建课表', 'JSON 导入', 'JSON 导出', '课程管理', '作息设置'] for label in labels)
    assert any('高等数学' in label for label in labels)
    week_button = emulator.find(emulator.nodes(), '第 1 周')
    _, top, _, bottom = emulator.bounds(week_button)
    assert bottom - top < 250, 'Week selector must have its own accessibility bounds'
    emulator.tap_node(week_button)
    assert any(emulator.label(n) == '选择教学周' for n in emulator.nodes())
    emulator.record('android-schedule-week-selector')
    emulator.tap('取消')
    emulator.record('android-schedule-reference-layout')
    emulator.tap('打开设置')
    emulator.tap('课表设置')
    labels = [emulator.label(n) for n in emulator.nodes()]
    assert all(label in labels for label in ['学期设置', '作息设置', '课程管理', '调课记录', '导入与备份', '课表管理', '今日课程'])
    emulator.record('android-schedule-settings')
    for title, name, expected in [
        ('学期设置', 'android-schedule-semester', '保存学期设置'),
        ('作息设置', 'android-schedule-periods', '保存作息设置'),
        ('导入与备份', 'android-schedule-imports', 'JSON 导入'),
    ]:
        emulator.tap(title)
        assert any(emulator.label(n) == expected for n in emulator.nodes())
        emulator.record(name)
        emulator.adb('shell', 'input', 'keyevent', '4')
    emulator.home()
    emulator.adb('shell', 'am', 'force-stop', 'dev.taskapp.task_app')
    emulator.adb('shell', 'am', 'start', '-n', 'dev.taskapp.task_app/.MainActivity')
    emulator.tap('课表')
    labels = [emulator.label(n) for n in emulator.nodes()]
    assert any('高等数学' in label for label in labels)
    assert any('第 1 周' in label for label in labels)
    emulator.record('android-schedule-layout-restart')
    assert emulator.installed_digest() == apk_before
    result = {'installedApkSha256Before': apk_before,
              'installedApkSha256After': apk_before,
              'scheduleVersion': '1.1.0', 'settingsSubpages': 'verified',
              'weekSelectorAccessibility': 'verified',
              'retainedCourseAfterRestart': 'verified'}
    (OUT / 'schedule-layout-emulator.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
