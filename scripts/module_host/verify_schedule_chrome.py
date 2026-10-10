#!/usr/bin/env python3
"""Read-only gesture acceptance after installing schedule 1.3.0/build23."""
import hashlib
import json
from verify_emulator import Emulator, OUT, ROOT


def labels(e):
    return [e.label(n) for n in e.nodes()]


def main():
    e = Emulator('emulator-5554')
    apk = ROOT / 'client/build/app/outputs/flutter-apk/app-release.apk'
    digest = hashlib.sha256(apk.read_bytes()).hexdigest()
    assert e.installed_digest() == digest
    e.home()
    e.manager()
    assert any('app.schedule @ 1.3.0' in label for label in labels(e))
    e.home()
    e.tap('课表')
    assert '打开设置' in labels(e)
    e.record('android-schedule-chrome-expanded')
    bounds = [e.bounds(n) for n in e.nodes()]
    width, height = max(b[2] for b in bounds), max(b[3] for b in bounds)
    x = width // 2
    # Horizontal date scrolling must leave the host controls visible.
    e.adb('shell', 'input', 'swipe', str(int(width*.8)), str(int(height*.4)),
          str(int(width*.2)), str(int(height*.4)), '500')
    assert '打开设置' in labels(e)
    e.adb('shell', 'input', 'swipe', str(int(width*.2)), str(int(height*.4)),
          str(int(width*.8)), str(int(height*.4)), '500')
    e.adb('shell', 'input', 'swipe', str(x), str(int(height*.73)),
          str(x), str(int(height*.35)), '700')
    hidden = labels(e)
    assert '打开设置' not in hidden, hidden
    assert '展开工具栏' in hidden, hidden
    assert '今天' not in hidden, 'Hidden navigation must not expose accessibility actions'
    e.record('android-schedule-chrome-collapsed')
    # Upward content browsing (finger down) restores both host controls.
    e.adb('shell', 'input', 'swipe', str(x), str(int(height*.35)),
          str(x), str(int(height*.52)), '600')
    restored = labels(e)
    assert '打开设置' in restored and '今天' in restored, restored
    e.record('android-schedule-chrome-scroll-restored')
    e.adb('shell', 'input', 'swipe', str(x), str(int(height*.73)),
          str(x), str(int(height*.35)), '700')
    assert '展开工具栏' in labels(e)
    e.tap('展开工具栏')
    assert '打开设置' in labels(e)
    e.record('android-schedule-chrome-button-restored')
    e.tap('打开设置')
    assert '模块管理与恢复' in labels(e)
    e.home()
    e.adb('shell', 'am', 'force-stop', 'dev.taskapp.task_app')
    e.adb('shell', 'am', 'start', '-n', 'dev.taskapp.task_app/.MainActivity')
    e.tap('课表')
    assert '打开设置' in labels(e)
    e.record('android-schedule-chrome-restart')
    assert e.installed_digest() == digest
    result = {'clientBuild':23, 'scheduleVersion':'1.3.0', 'apkSha256':digest,
              'horizontalKeepsControls':True, 'downwardCollapsesHeaderAndDock':True,
              'hiddenDockAccessibilityRemoved':True, 'upwardRestoresControls':True,
              'restoreButtonWorks':True, 'settingsRecoveryAccessible':True,
              'restartRestoresControls':True, 'apkUnchanged':True}
    (OUT/'schedule-chrome-emulator.json').write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
