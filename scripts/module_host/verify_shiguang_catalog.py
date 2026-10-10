#!/usr/bin/env python3
"""Real Android school picker + unchanged warehouse adapter on mock data.

Optional --install installs only the module. No fixture courses are committed.
Uses the existing client and preserves application data.
"""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import hashlib
import json
import threading

from verify_emulator import Emulator, ROOT, OUT
from verify_shiguang_browser import enter_url, expect_load, labels
from verify_shiguang_hierarchy import import_home


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--install', action='store_true')
    args = parser.parse_args()
    e = Emulator('emulator-5554')
    version = json.loads((ROOT/'packages/modules/app.import.shiguang/module.json').read_text())['manifest']['version']
    package = ROOT / 'dist/modules/app.import.shiguang.xmodule'
    before = e.installed_digest()
    reverse_added = False
    server = ThreadingHTTPServer(('127.0.0.1', 8189), partial(
        SimpleHTTPRequestHandler, directory=str(ROOT/'client/test/fixtures')))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        if args.install:
            name = f'app.import.shiguang-{version}.xmodule'
            e.adb('push', str(package), '/sdcard/Download/'+name)
            e.home(); e.manager(); e.tap('导入 .xmodule'); e.tap(name)
            assert '新增权限：无' in labels(e)
            e.record('android-shiguang-1.2-upgrade-review')
            e.tap('确认安装')
            assert any(f'{version} · 已启用' in label for label in labels(e)), labels(e)
        e.home(); e.open_settings(); e.tap('拾光教务导入')
        import_home(e)
        e.tap('按学校导入', contains=True)
        e.record('android-shiguang-school-catalog')
        inputs = [n for n in e.nodes() if n.get('class') == 'android.widget.EditText']
        e.tap_node(inputs[0]); e.nodes()  # settle the native text input connection
        e.adb('shell', 'input', 'text', 'YXHMC')
        e.adb('shell', 'input', 'keyevent', 'KEYCODE_SPACE')
        e.nodes()
        e.adb('shell', 'input', 'keyevent', '4')
        assert any('找到 1 所学校' in label for label in labels(e)), labels(e)
        e.record('android-shiguang-school-search')
        e.tap('银杏', contains=True)
        assert any('gingkoc.edu.cn' in label for label in labels(e)), labels(e)
        e.record('android-shiguang-school-selected')
        e.adb('reverse', 'tcp:8189', 'tcp:8189')
        reverse_added = True
        fixture = 'http://127.0.0.1:8189/shiguang_warehouse_capture.html'
        enter_url(e, fixture); e.tap('打开教务浏览器')
        expect_load(e, '页面已加载')
        e.tap('执行采集'); e.tap('确定')  # adapter announcement
        assert any('选择学年' in label for label in labels(e)), labels(e)
        e.record('android-shiguang-warehouse-year-prompt')
        e.tap('确定')  # default four-digit year; named validator returns false
        assert any('选择学期' in label for label in labels(e)), labels(e)
        e.tap('确定')  # one-based choice defaults to first semester
        assert '选择导入目标' in labels(e), labels(e)
        e.tap('继续')
        assert '确认来源与学期配置' in labels(e), labels(e)
        e.record('android-shiguang-warehouse-captured-config')
        e.tap('取消')
        # The Flutter URL field regains focus when native dialogs close. ESC
        # does not dismiss this Gboard version; Back closes the IME.
        if 'mInputShown=true' in e.adb('shell', 'dumpsys', 'input_method'):
            e.adb('shell', 'input', 'keyevent', '4')
        if not any('已取消导入配置' in label for label in labels(e)):
            e.adb('shell', 'input', 'swipe', '540', '1600', '540', '550', '350')
        assert any('已取消导入配置' in label for label in labels(e)), labels(e)
        assert '预览实际变更' not in labels(e)
        e.record('android-shiguang-warehouse-cancelled')
        report = {
            'device': 'emulator-5554', 'moduleVersion': version,
            'installedApkUnchangedDuringModuleUpdate': before == e.installed_digest(),
            'packageSha256': hashlib.sha256(package.read_bytes()).hexdigest(),
            'schoolSearchVerified': True, 'loginUrlReplaced': True,
            'unchangedOfficialAdapter': 'YXHMC', 'nativeNamedValidatorVerified': True,
            'fixture': 'client/test/fixtures/shiguang_warehouse_capture.html',
            'fetchMocked': True, 'realSchoolLoginVerified': False,
            'captureReturnedToConfiguration': True, 'capturedCoursesCommitted': False,
            'configurationCancellationVerified': True,
        }
        (OUT/'shiguang-warehouse-emulator.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
        print(json.dumps(report, ensure_ascii=False, indent=2))
    except Exception:
        print('Visible UI:', labels(e), flush=True)
        e.record('android-shiguang-warehouse-debug')
        raise
    finally:
        if reverse_added:
            e.adb('reverse', '--remove', 'tcp:8189')
        server.shutdown(); server.server_close()


if __name__ == '__main__':
    main()
