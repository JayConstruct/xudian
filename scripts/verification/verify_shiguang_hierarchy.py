#!/usr/bin/env python3
"""Read-only Android acceptance of import categories and attribution pages.

Requires the updated module to be installed. Keeps all existing course data.
"""
import hashlib
import json
import re
from scripts.module_host.emulator_ui import Emulator, ROOT, OUT

BACK_LABELS = {'Back', '返回', '返回按钮'}


def labels(e):
    return [e.label(n) for n in e.nodes() if e.label(n)]


def toolbar_back(e):
    node = next(n for n in e.nodes() if e.label(n) in BACK_LABELS)
    e.tap_node(node)


def installation(e):
    package = ROOT/'dist/modules/app.import.shiguang.xmodule'
    manifest = ROOT/'packages/modules/app.import.shiguang/module.json'
    info = e.adb('shell', 'dumpsys', 'package', 'dev.taskapp.task_app')
    return {
        'moduleVersion': json.loads(manifest.read_text())['manifest']['version'],
        'clientBuild': int(re.search(r'\bversionCode=(\d+)', info)[1]),
        'apkSha256': e.installed_digest(),
        'modulePackageSha256': hashlib.sha256(package.read_bytes()).hexdigest(),
    }


def import_home(e):
    for _ in range(8):
        current = labels(e)
        if ('拾光教务导入' in current and
                any('按学校导入' in label for label in current) and
                any('粘贴学校脚本' in label for label in current)):
            return
        if BACK_LABELS.intersection(current):
            toolbar_back(e)
        elif '取消' in current:
            e.tap('取消')
        else:
            e.adb('shell', 'input', 'swipe', '700', '500', '700', '1800', '500')
    raise AssertionError(f'未找到拾光教务导入首页：{labels(e)}')


def search(e, value):
    node = next(n for n in e.nodes() if n.get('class') == 'android.widget.EditText')
    e.tap_node(node)
    e.nodes()
    e.adb('shell', 'input', 'text', value)
    e.adb('shell', 'input', 'keyevent', 'KEYCODE_SPACE')
    e.nodes()
    if 'mInputShown=true' in e.adb('shell', 'dumpsys', 'input_method'):
        e.adb('shell', 'input', 'keyevent', '4')


def main():
    e = Emulator('emulator-5554')
    apk = e.installed_digest()
    e.home(); e.open_settings(); e.tap('拾光教务导入')
    import_home(e)
    e.record('android-shiguang-home')
    e.tap('按学校导入', contains=True); search(e, 'AUFE')
    current = labels(e)
    assert '1 所学校' in current, current
    assert any('安徽财经大学' in label and '2 个导入入口' in label for label in current), current
    assert not any('进入教务系统后点击开始导入' in label for label in current), current
    e.record('android-shiguang-schools')
    e.tap('安徽财经大学', contains=True)
    current = labels(e)
    assert any('安徽财经大学校内入口' in label for label in current), current
    assert any('安徽财经大学Webvpn入口' in label for label in current), current
    assert any('进入教务系统后点击开始导入' in label for label in current), current
    e.record('android-shiguang-school-detail')
    import_home(e); e.tap('按学校导入', contains=True); search(e, 'ZZZZZ')
    assert '没有找到学校' in labels(e)
    e.record('android-shiguang-school-empty')
    e.tap('通用系统导入', contains=True)
    current = labels(e)
    assert all(name in current for name in ['正方教务', '青果教务', 'URP 教务', '超星教务系统']), current
    e.record('android-shiguang-general')
    import_home(e); e.tap('关于与致谢', contains=True)
    e.record('android-shiguang-about')
    for label, url in [
        ('拾光学校适配脚本仓库', 'https://github.com/ShiGuangSchedule/shiguang_warehouse'),
        ('拾光课表项目', 'https://github.com/ShiGuangSchedule/shiguangschedule'),
    ]:
        e.tap(label, contains=True)
        e.wait_for(url, contains=True)
        toolbar_back(e)
    e.tap('MIT 开源许可', contains=True)
    current = labels(e)
    assert any('星河欲转' in label for label in current), current
    assert any('MIT License' in label for label in current), current
    e.record('android-shiguang-credits-license')
    assert apk == e.installed_digest()
    result = {**installation(e),'apkUnchanged':True,
              'schoolGroupingVerified':True,'descriptionsOnlyInDetails':True,
              'multipleSchoolEntriesVerified':True,'noResultsGenericFallbackVerified':True,
              'fourGeneralSystemsVerified':True,'repositoryAddressesAndCreditsVerified':True,
              'coursesWritten':False,'fixtureBrowserNotExecuted':True}
    (OUT/'shiguang-hierarchy-emulator.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(result,ensure_ascii=False,indent=2))
    import_home(e)


if __name__ == '__main__':
    main()
