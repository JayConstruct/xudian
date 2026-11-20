#!/usr/bin/env python3
"""Verify unified title/back navigation on Android without writing courses."""
import json

from scripts.module_host.emulator_ui import Emulator, OUT
from .verify_shiguang_hierarchy import BACK_LABELS, import_home, installation, labels, search, toolbar_back


def expect_page(e, title):
    current = labels(e)
    assert title in current, current
    assert sum(label in BACK_LABELS for label in current) == 1, current
    assert not any(label.startswith(('返回导入首页', '返回学校列表', '返回通用系统')) for label in current), current


def main():
    e = Emulator('emulator-5554')
    apk = e.installed_digest()
    e.home(); e.open_settings(); e.tap('拾光教务导入')
    import_home(e)
    expect_page(e, '拾光教务导入')
    e.record('android-shiguang-navigation-home')
    e.tap('按学校导入', contains=True)
    search(e, 'AUFE')
    expect_page(e, '选择学校')
    assert '1 所学校' in labels(e)
    e.record('android-shiguang-navigation-schools')
    e.tap('安徽财经大学', contains=True)
    expect_page(e, '安徽财经大学')
    e.record('android-shiguang-navigation-detail')
    e.adb('shell', 'input', 'swipe', '540', '1750', '540', '550', '450')
    e.tap('关于与致谢', contains=True)
    expect_page(e, '关于与致谢')
    e.record('android-shiguang-navigation-about')
    toolbar_back(e)
    expect_page(e, '安徽财经大学')
    e.adb('shell', 'input', 'keyevent', '4')
    expect_page(e, '选择学校')
    assert '1 所学校' in labels(e)
    toolbar_back(e)
    expect_page(e, '拾光教务导入')
    e.tap('通用系统导入', contains=True)
    expect_page(e, '通用系统导入')
    e.tap('正方教务')
    expect_page(e, '正方教务')
    e.record('android-shiguang-navigation-general-detail')
    e.adb('shell', 'input', 'keyevent', '4')
    expect_page(e, '通用系统导入')
    toolbar_back(e)
    expect_page(e, '拾光教务导入')
    e.adb('shell', 'input', 'keyevent', '4')
    assert '设置' in labels(e)
    e.tap('拾光教务导入')
    import_home(e)
    assert apk == e.installed_digest()
    result = {
        **installation(e),
        'dynamicTitlesVerified': True, 'singleBackButtonVerified': True,
        'toolbarAndAndroidBackVerified': True, 'aboutReturnsToDetail': True,
        'schoolSearchPreserved': True, 'homeBackExitsToSettings': True,
        'reopenedFromSettings': True, 'coursesWritten': False,
    }
    (OUT/'shiguang-navigation-emulator.json').write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result, indent=2), flush=True)


if __name__ == '__main__':
    main()
