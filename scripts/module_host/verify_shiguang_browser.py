#!/usr/bin/env python3
"""Emulator acceptance using a local fixture; does not save captured courses.

Requires emulator-5554, new APK and module packages. --install updates the
app and the two modules while preserving existing application data.
"""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import threading

from verify_emulator import Emulator, ROOT, OUT


def labels(e):
    return [e.label(n) for n in e.nodes() if e.label(n)]


def home(e):
    e.home()


def open_importer(e):
    e.open_settings()
    for _ in range(8):
        nodes = e.nodes()
        importers = [n for n in nodes if '拾光教务导入' in e.label(n)]
        if importers:
            e.tap_node(importers[-1])
            e.tap('通用系统导入')
            e.tap('正方', contains=True)
            return
        e.adb('shell', 'input', 'swipe', '540', '1850', '540', '700', '300')
    raise RuntimeError('设置中未找到拾光教务导入')


def import_package(e, name):
    e.manager()
    e.tap('导入 .xmodule')
    e.tap(name)
    e.tap('确认')


def enter_url(e, url):
    inputs = [n for n in e.nodes() if n.get('class') == 'android.widget.EditText']
    e.tap_node(inputs[0])
    e.adb('shell', 'input', 'keyevent', 'KEYCODE_MOVE_END')
    e.adb('shell', 'input', 'keyevent', *(['KEYCODE_DEL'] * min(512, len(inputs[0].get('text', '')) + 1)))
    e.adb('shell', 'input', 'text', url)
    e.adb('shell', 'input', 'keyevent', '111')
    entered = next(n.get('text') for n in e.nodes() if n.get('class') == 'android.widget.EditText')
    assert entered == url, f'地址栏输入被改写：{entered!r} != {url!r}'


def expect_load(e, message, failed=False):
    for _ in range(10):
        nodes = e.nodes()
        if any(message in e.label(n) for n in nodes):
            run = e.find(nodes, '执行采集')
            assert run.get('enabled') == ('false' if failed else 'true')
            # A later onPageFinished must not overwrite a main-frame error.
            assert any(message in label for label in labels(e)), labels(e)
            return
    raise RuntimeError('页面状态未出现：' + message + '; ' + str(labels(e)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--install', action='store_true')
    parser.add_argument('--release', action='store_true', help='Use the release APK for installation')
    parser.add_argument('--public-url', help='Also verify an ordinary public HTTPS page')
    args = parser.parse_args()
    modules = ['app.schedule', 'app.import.shiguang']
    e = Emulator('emulator-5554')
    server = ThreadingHTTPServer(('127.0.0.1', 8188), partial(SimpleHTTPRequestHandler, directory=str(ROOT/'client/test/fixtures')))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        if args.install:
            apk = 'app-release.apk' if args.release else 'app-debug.apk'
            print(e.adb('install', '-r', str(ROOT/'client/build/app/outputs/flutter-apk'/apk)), flush=True)
            for module in modules:
                version = json.loads((ROOT/f'packages/modules/{module}/module.json').read_text())['manifest']['version']
                name = f'{module}-{version}.xmodule'
                e.adb('push', str(ROOT/f'dist/modules/{module}.xmodule'), '/sdcard/Download/'+name)
            e.adb('shell', 'am', 'force-stop', 'dev.taskapp.task_app')
            e.adb('shell', 'am', 'start', '-W', '-n', 'dev.taskapp.task_app/.MainActivity')
            home(e)
            for module in modules:
                e.manager()
                version = json.loads((ROOT/f'packages/modules/{module}/module.json').read_text())['manifest']['version']
                if not any(f'{module} @ {version}' in label for label in labels(e)):
                    import_package(e, f'{module}-{version}.xmodule')
        e.adb('shell', 'am', 'start', '-W', '-n', 'dev.taskapp.task_app/.MainActivity')
        e.adb('reverse', 'tcp:8188', 'tcp:8188')
        home(e)
        open_importer(e)
        fixture_url = 'http://127.0.0.1:8188/zhengfang_capture.html'
        enter_url(e, fixture_url)
        e.tap('打开教务浏览器')
        expect_load(e, '页面已加载')
        if args.public_url:
            enter_url(e, args.public_url)
            e.tap('前往')
            expect_load(e, '页面已加载')
            e.record('android-shiguang-browser-public-page')
        enter_url(e, 'http://127.0.0.1:8188/missing-capture-page')
        e.tap('前往')
        expect_load(e, 'HTTP 404', failed=True)
        # This network uses fake-IP DNS, including for .invalid. An empty label
        # forces a real lookup failure before that wildcard proxy response.
        enter_url(e, 'https://xudian..invalid/')
        e.tap('前往')
        expect_load(e, '无法解析域名', failed=True)
        e.record('android-shiguang-browser-dns-error')
        enter_url(e, fixture_url)
        e.tap('前往')
        expect_load(e, '页面已加载')
        e.record('android-shiguang-browser')
        e.tap('执行采集')
        e.tap('确定')
        assert '选择导入目标' in labels(e), labels(e)
        e.tap('继续')
        assert '确认来源与学期配置' in labels(e), labels(e)
        # Cancel metadata entry: proves the real shipped parser completed and
        # returned to Flutter without committing any captured data.
        e.record('android-shiguang-captured-config')
        e.tap('取消')
        assert any('已取消导入配置' in label for label in labels(e)), labels(e)
        print('Native browser + HTTP/DNS error persistence + recovery + parser + cancellation verified', flush=True)
        OUT.mkdir(exist_ok=True)
        (OUT/'shiguang-browser.json').write_text(json.dumps({
            'device': 'emulator-5554',
            'fixture': 'client/test/fixtures/zhengfang_capture.html',
            'browserCaptureVerified': True, 'cancelVerified': True,
            'httpErrorVerified': True, 'dnsErrorVerified': True,
            'failedPageCaptureDisabled': True, 'loadRecoveryVerified': True,
            'publicPageVerified': args.public_url,
            'builtinGenericZhengfangVerified': True,
            'realSchoolLoginVerified': False, 'capturedCoursesCommitted': False,
        }, ensure_ascii=False, indent=2)+'\n')
    except Exception:
        print('Visible UI:', labels(e), flush=True)
        e.record('android-shiguang-debug')
        raise
    finally:
        e.adb('reverse', '--remove', 'tcp:8188')
        server.shutdown();server.server_close()


if __name__ == '__main__':
    main()
