#!/usr/bin/env python3
"""Read-only Android acceptance of import categories and attribution pages.

Requires the updated module to be installed. Keeps all existing course data.
"""
import hashlib
import json
from verify_emulator import Emulator, ROOT, OUT


def labels(e):
    return [e.label(n) for n in e.nodes() if e.label(n)]


def import_home(e):
    for _ in range(4):
        current = labels(e)
        if '导入课表' in current: return
        for label in ['返回学校列表', '返回通用系统', '返回导入首页']:
            if label in current:
                e.tap(label)
                break
        else:
            e.adb('shell', 'input', 'swipe', '700', '500', '700', '1800', '500')
    assert '导入课表' in labels(e)


def search(e, value):
    node = next(n for n in e.nodes() if n.get('class') == 'android.widget.EditText')
    e.tap_node(node); e.nodes()
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
    e.record('android-shiguang-1.3-home')
    e.tap('按学校导入', contains=True); search(e, 'AUFE')
    current = labels(e)
    assert any('找到 1 所学校' in label for label in current), current
    assert any('安徽财经大学' in label and '2 个导入入口' in label for label in current), current
    assert not any('进入教务系统后点击开始导入' in label for label in current), current
    e.record('android-shiguang-1.3-schools')
    e.tap('安徽财经大学', contains=True)
    current = labels(e)
    assert any('安徽财经大学校内入口' in label for label in current), current
    assert any('安徽财经大学Webvpn入口' in label for label in current), current
    assert any('进入教务系统后点击开始导入' in label for label in current), current
    e.record('android-shiguang-1.3-school-detail')
    import_home(e); e.tap('按学校导入', contains=True); search(e, 'ZZZZZ')
    assert '没有找到学校' in labels(e)
    e.record('android-shiguang-1.3-school-empty')
    e.tap('尝试通用系统导入')
    current = labels(e)
    assert all(name in current for name in ['正方教务', '青果教务', 'URP教务', '超星教务系统']), current
    e.record('android-shiguang-1.3-general')
    e.tap('返回导入首页'); e.tap('关于与致谢', contains=True)
    current = labels(e)
    assert 'https://github.com/ShiGuangSchedule/shiguang_warehouse' in current, current
    assert 'https://github.com/ShiGuangSchedule/shiguangschedule' in current, current
    e.record('android-shiguang-1.3-about')
    e.adb('shell', 'input', 'swipe', '700', '1800', '700', '650', '500')
    current = labels(e)
    assert any('星河欲转' in label for label in current), current
    assert any('MIT License' in label for label in current), current
    e.record('android-shiguang-1.3-credits-license')
    assert apk == e.installed_digest()
    package = ROOT/'dist/modules/app.import.shiguang.xmodule'
    version = json.loads((ROOT/'packages/modules/app.import.shiguang/module.json').read_text())['manifest']['version']
    result = {'moduleVersion':version,'clientBuild':36,'apkUnchanged':True,
              'moduleSha256':hashlib.sha256(package.read_bytes()).hexdigest(),
              'schoolGroupingVerified':True,'descriptionsOnlyInDetails':True,
              'multipleSchoolEntriesVerified':True,'noResultsGenericFallbackVerified':True,
              'fourGeneralSystemsVerified':True,'repositoryAddressesAndCreditsVerified':True,
              'coursesWritten':False,'fixtureBrowserNotExecuted':True}
    (OUT/'shiguang-hierarchy-emulator.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(result,ensure_ascii=False,indent=2))
    import_home(e)


if __name__ == '__main__':
    main()
