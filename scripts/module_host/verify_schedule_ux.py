#!/usr/bin/env python3
"""Read-only UX acceptance of an installed schedule 1.2.0 on the emulator.

Install the release APK and review-import app.schedule.xmodule first. This
script opens pages, cancels selectors and restarts the app; it never saves data.
Previously exported before/after snapshots are compared when present.
"""
import hashlib
import json
from verify_emulator import Emulator, OUT, ROOT


def main():
    e = Emulator('emulator-5554')
    apk = ROOT / 'client/build/app/outputs/flutter-apk/app-release.apk'
    expected = hashlib.sha256(apk.read_bytes()).hexdigest()
    assert e.installed_digest() == expected
    e.home()
    e.manager()
    assert any('app.schedule @ 1.2.0' in e.label(n) for n in e.nodes())
    e.home()
    e.tap('课表')
    labels = [e.label(n) for n in e.nodes()]
    assert labels.count('第 1 周') == 1
    assert labels.count('打开设置') == 1
    assert labels.count('页面菜单') == 1
    assert '切换课表' not in labels  # No second module toolbar.
    assert any('高等数学' in label for label in labels)
    e.record('android-schedule-ux-home')
    e.tap('第 1 周')
    assert any(e.label(n) == '选择教学周' for n in e.nodes())
    e.record('android-schedule-ux-week-selector')
    e.tap('取消')
    e.tap('页面菜单')
    labels = [e.label(n) for n in e.nodes()]
    assert all(label in labels for label in ['回到本周', '今日课程', '课表设置', 'AI 助手'])
    e.record('android-schedule-ux-menu')
    e.adb('shell', 'input', 'keyevent', '4')
    e.tap('高等数学', contains=True)
    nodes = e.nodes()
    labels = [e.label(n) for n in nodes]
    assert any('教学楼101' in label for label in labels)
    assert any('示例教师' in label for label in labels)
    assert any('单次调课' in label for label in labels)
    assert not any(n.get('class') == 'android.widget.EditText' for n in nodes)
    e.record('android-schedule-ux-detail')
    e.adb('shell', 'input', 'keyevent', '4')
    e.tap('打开设置')
    e.tap('课表设置')
    labels = [e.label(n) for n in e.nodes()]
    assert all(label in labels for label in ['概览', '课表配置', '课程与调课', '数据管理'])
    assert any('12 个节次' in label for label in labels)
    assert any('1 门课程' in label for label in labels)
    e.record('android-schedule-ux-settings')
    e.tap('作息设置', contains=True)
    labels = [e.label(n) for n in e.nodes()]
    assert any('12 个节次' in label for label in labels)
    assert any('08:55' in label for label in labels)
    assert '保存作息设置' not in labels  # No edits => no dirty save footer.
    e.record('android-schedule-ux-periods')
    e.home()
    e.adb('shell', 'am', 'force-stop', 'dev.taskapp.task_app')
    e.adb('shell', 'am', 'start', '-n', 'dev.taskapp.task_app/.MainActivity')
    e.tap('课表')
    labels = [e.label(n) for n in e.nodes()]
    assert labels.count('第 1 周') == 1
    assert any('高等数学' in label for label in labels)
    e.record('android-schedule-ux-restart')
    assert e.installed_digest() == expected
    result = {'apkSha256': expected, 'scheduleVersion': '1.2.0',
              'singleHeader': True, 'protectedSettings': True,
              'groupedSettings': True, 'readOnlyCourseDetail': True,
              'periods': 12, 'retainedCourseAfterRestart': True,
              'apkUnchangedDuringVerification': True}
    if (OUT / 'schedule-ux-before.json').exists() and (OUT / 'schedule-ux-after.json').exists():
        before = json.loads((OUT / 'schedule-ux-before.json').read_text())
        after = json.loads((OUT / 'schedule-ux-after.json').read_text())
        for key in ['datasetId', 'courses', 'meetings', 'occurrenceChanges']:
            assert before[key] == after[key], key
        assert after['timetable']['periods'][:2] == before['timetable']['periods']
        assert len(after['timetable']['periods']) == 12
        assert {k:v for k,v in before['timetable'].items() if k != 'periods'} == {
            k:v for k,v in after['timetable'].items() if k != 'periods'}
        result['exportedDataComparison'] = 'only 10 appended periods; original IDs and all course/change data preserved'
    (OUT / 'schedule-ux-emulator.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
