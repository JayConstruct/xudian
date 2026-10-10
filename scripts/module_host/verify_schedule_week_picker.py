#!/usr/bin/env python3
"""Check the numeric week picker and menu entry, then restore the selected week."""
import argparse
import hashlib
import json

from verify_emulator import Emulator, ROOT, OUT


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--serial', default='emulator-5554')
    args = parser.parse_args()
    emulator = Emulator(args.serial)
    labels = lambda: [emulator.label(n) for n in emulator.nodes()]
    if any(value in labels() for value in ['选择教学周', '切换课表']):
        emulator.tap('取消')
    emulator.home()
    emulator.tap('课表')
    before = labels()
    title = next(value for value in before if value.startswith('第 ') and value.endswith(' 周'))
    original_week = title.split()[1]
    course_labels = [value for value in before if '高等数学' in value]
    emulator.record('android-schedule-week-grid-home')
    emulator.tap(title)
    nodes = emulator.nodes()
    first = emulator.bounds(emulator.find(nodes, '1'))
    second = emulator.bounds(emulator.find(nodes, '2'))
    assert first[1] == second[1] and first[0] < second[0], 'Weeks do not share a row'
    assert not any(emulator.label(n) == '继续' for n in nodes)
    emulator.record('android-schedule-week-grid-picker')
    emulator.tap('取消')
    assert title in labels(), 'Cancel changed the selected week'
    emulator.tap(title)
    target = '2' if original_week != '2' else '1'
    emulator.tap(target)
    selected_title = f'第 {target} 周'
    assert selected_title in labels() and '选择教学周' not in labels()
    emulator.tap(selected_title)
    emulator.tap(original_week)
    assert title in labels()
    emulator.tap('页面菜单')
    assert '切换课表' in labels()
    emulator.record('android-schedule-week-grid-menu')
    emulator.tap('切换课表')
    assert '切换课表' in labels()
    emulator.record('android-schedule-week-grid-switch')
    emulator.tap('取消')
    after = labels()
    assert title in after
    assert all(value in after for value in course_labels), 'Course labels changed'
    emulator.record('android-schedule-week-grid-restored')
    apk = ROOT / 'client/build/app/outputs/flutter-apk/app-x86_64-release.apk'
    digest = hashlib.sha256(apk.read_bytes()).hexdigest()
    assert emulator.installed_digest() == digest
    report = {
        'moduleVersion': '1.7.0',
        'apkSha256': digest,
        'multipleNumbersPerRow': True,
        'selectImmediately': True,
        'cancelPreservesWeek': True,
        'switchTimetableInMenu': True,
        'restoredWeek': original_week,
        'courseLabelsPreserved': course_labels,
    }
    OUT.mkdir(exist_ok=True)
    (OUT / 'schedule-week-grid-emulator.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report, ensure_ascii=False, indent=2), flush=True)


if __name__ == '__main__':
    main()
