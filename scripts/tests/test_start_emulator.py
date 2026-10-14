"""Exercise the WSL startup flow with fake external processes."""
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'start-emulator.sh'


class StartEmulatorTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        scripts = self.root / 'scripts'
        scripts.mkdir()
        shutil.copyfile(SCRIPT, scripts / SCRIPT.name)
        (scripts / 'dev-env.sh').write_text('# Test toolchain is provided through PATH.\n')
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=f'{self.bin}:/usr/bin:/bin',
                        START_TEST_ROOT=str(self.root), START_TEST_MODE='new',
                        XUDIAN_ADB_HOST='127.0.0.1', XUDIAN_ADB_PORT='5037')
        self.tool('uname', 'print("6.6.0-microsoft-standard-WSL2")')
        self.tool('powershell.exe', '''
import base64
import re
import sys
from pathlib import Path
root = Path(os.environ['START_TEST_ROOT'])
command = base64.b64decode(sys.argv[-1]).decode('utf-16le')
if '# AVD_NAME_QUERY' in command:
    with (root / 'windows-name-calls').open('a') as log:
        log.write(command + '\\n')
    print(os.environ.get('START_TEST_WINDOWS_AVD', ''))
    sys.exit(0)
(root / 'launch').write_text(sys.argv[-1])
if os.environ['START_TEST_MODE'] == 'launch-failure':
    sys.exit(1)
if os.environ['START_TEST_MODE'] == 'windows-existing' and '$processes.Count -gt 0 -and $true' in command:
    print('目标模拟器进程仍在运行，无法通过 ADB 安全关闭；请手动关闭后重试。', file=sys.stderr)
    sys.exit(1)
rate = re.search("'-vsync-rate', '([0-9]+)'", command)
if rate:
    (root / 'boot-refresh').write_text(rate.group(1))
''')
        self.tool('adb', '''
import json
import sys
import time
from pathlib import Path
root = Path(os.environ['START_TEST_ROOT'])
mode = os.environ['START_TEST_MODE']
args = sys.argv[1:]
with (root / 'adb-calls').open('a') as log:
    log.write(' '.join(args) + '\\n')
if 'devices' in args:
    if mode == 'devices-failure':
        sys.exit(1)
    print('List of devices attached')
    if mode in ('ready', 'wrong-avd', 'offline', 'shutdown-timeout', 'kill-failure', 'name-failure', 'target-changed', 'console-name-empty', 'legacy-name', 'name-leading-blank', 'name-missing', 'windows-name'):
        if not (root / 'killed').exists() or mode == 'shutdown-timeout':
            print(os.environ.get('START_TEST_SERIAL', 'emulator-5554') + '\\t' + ('offline' if mode == 'offline' else 'device'))
elif 'emu' in args:
    if args[-2:] == ['avd', 'name']:
        if mode == 'name-failure':
            sys.exit(1)
        if mode == 'console-name-empty':
            sys.exit(0)
        changed = mode == 'target-changed' and (root / 'name-probed').exists()
        (root / 'name-probed').touch()
        print('Other_AVD' if mode == 'wrong-avd' or changed else 'Medium_Phone_API_37.0')
        print('OK')
    elif args[-1] == 'kill':
        if mode == 'kill-failure':
            sys.exit(1)
        (root / 'killed').touch()
elif args[-2:] == ['am', 'get-current-user']:
    print(os.environ.get('START_TEST_ANDROID_USER', '10') + '\\r')
elif 'settings' in args:
    settings_file = root / 'settings.json'
    settings = json.loads(settings_file.read_text()) if settings_file.exists() else {
        'peak_refresh_rate': os.environ.get('START_TEST_PEAK_RATE', '60.0'),
        'min_refresh_rate': 'null',
    }
    operation = args[args.index('--user') + 2]
    setting = args[args.index('system') + 1]
    if operation == 'get':
        if mode == 'settings-read-failure' and setting == 'min_refresh_rate':
            sys.exit(1)
        value = settings[setting]
        if mode == 'settings-not-applied' and settings_file.exists():
            value = '60'
        print(value + '\\r')
    else:
        if mode == 'settings-write-failure' and setting == 'min_refresh_rate' and operation == 'put':
            sys.exit(1)
        settings[setting] = args[-1] if operation == 'put' else 'null'
        settings_file.write_text(json.dumps(settings))
elif 'getprop' in args:
    if args[-1] in ('ro.boot.qemu.avd_name', 'ro.kernel.qemu.avd_name'):
        if mode == 'name-failure':
            sys.exit(1)
        if mode == 'name-missing' or (mode == 'windows-name' and not (root / 'killed').exists()) or (mode == 'legacy-name' and args[-1] == 'ro.boot.qemu.avd_name'):
            print('\\r')
            sys.exit(0)
        changed = mode == 'target-changed' and (root / 'name-probed').exists()
        (root / 'name-probed').touch()
        name = 'Other_AVD' if mode == 'wrong-avd' or changed else 'Medium_Phone_API_37.0'
        print('\\r\\n  ' + name + '  \\r' if mode == 'name-leading-blank' else name + '\\r')
    elif args[-1] == 'ro.boot.qemu.vsync':
        rate_file = root / 'boot-refresh'
        rate = rate_file.read_text() if rate_file.exists() else os.environ.get('START_TEST_REFRESH_RATE', '60')
        print(rate + '\\r')
    elif mode == 'timeout':
        time.sleep(20)
    elif mode == 'offline' and not (root / 'boot-probed').exists():
        (root / 'boot-probed').touch()
    else:
        print('1\\r')
''')

    def tool(self, name, source):
        path = self.bin / name
        path.write_text('#!/usr/bin/python3\nimport os\n' + source)
        path.chmod(0o755)

    def run_script(self, *args, mode='new', answer=''):
        return subprocess.run(['bash', str(self.root / 'scripts' / SCRIPT.name), *args],
                              env=dict(self.env, START_TEST_MODE=mode),
                              input=answer, capture_output=True, text=True, timeout=10)

    def test_launch_waits_and_quotes_windows_path_literally(self):
        path = "D:\\Android SDK\\中文'$(literal)\\emulator.exe"
        result = self.run_script('--emulator', path)
        self.assertEqual(result.returncode, 0, result.stderr)
        command = base64.b64decode((self.root / 'launch').read_text()).decode('utf-16le')
        self.assertIn("$emulatorPath = '" + path.replace("'", "''") + "'", command)
        self.assertIn('sys.boot_completed=1', result.stdout)
        calls = (self.root / 'adb-calls').read_text()
        self.assertIn('-H 127.0.0.1 -P 5037 -s emulator-5554 shell getprop', calls)
        self.assertIn('-s emulator-5554 shell getprop ro.boot.qemu.avd_name', calls)
        self.assertNotIn('-wipe-data', command)
        self.assertNotIn('-vsync-rate', command)
        self.assertNotIn('-no-snapshot', command)
        self.assertNotIn('ro.boot.qemu.vsync', calls)
        self.assertIn("'-memory', '2048'", command)

    def test_custom_memory_is_passed_to_launcher(self):
        result = self.run_script('--memory', '4096', '--cold-boot')
        self.assertEqual(result.returncode, 0, result.stderr)
        command = base64.b64decode((self.root / 'launch').read_text()).decode('utf-16le')
        self.assertIn("'-memory', '4096'", command)
        self.assertIn('客体 RAM 上限：4096 MB', result.stdout)

    def test_memory_boundaries_and_dry_run_contact_no_devices(self):
        for value, expected in [('1536', '1536'), ('8192', '8192'), ('02048', '2048')]:
            with self.subTest(value=value):
                result = self.run_script('--memory', value, '--dry-run')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(f'-memory {expected}', result.stdout)
                self.assertFalse((self.root / 'launch').exists())
                self.assertFalse((self.root / 'adb-calls').exists())

    def test_invalid_memory_fails_before_external_commands(self):
        for value in ('1535', '8193', '0', '-1', '2048.0', 'abc', '9999999999', '2048;command'):
            with self.subTest(value=value):
                result = self.run_script('--memory', value)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('1536～8192', result.stderr)
                self.assertFalse((self.root / 'launch').exists())
                self.assertFalse((self.root / 'adb-calls').exists())
        result = self.run_script('--memory')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('缺少参数', result.stderr)

    def test_memory_on_reused_device_explains_it_only_applies_to_new_launch(self):
        result = self.run_script('--memory', '4096', mode='ready')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('仅新启动生效', result.stdout)
        self.assertFalse((self.root / 'launch').exists())

    def test_refresh_rate_is_passed_to_new_cold_boot(self):
        self.env['START_TEST_REFRESH_RATE'] = '120'
        result = self.run_script('--refresh-rate', '120')
        self.assertEqual(result.returncode, 0, result.stderr)
        command = base64.b64decode((self.root / 'launch').read_text()).decode('utf-16le')
        self.assertIn("'-vsync-rate', '120', '-no-snapshot'", command)
        self.assertNotIn('-wipe-data', command)
        calls = (self.root / 'adb-calls').read_text()
        self.assertIn('shell getprop ro.boot.qemu.vsync', calls)

    def test_matching_refresh_rate_reuses_device_without_launcher(self):
        self.env['START_TEST_REFRESH_RATE'] = '120'
        (self.bin / 'powershell.exe').unlink()
        result = self.run_script('--refresh-rate', '120', mode='ready')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / 'launch').exists())
        self.assertIn('客体刷新率已核对：120 Hz', result.stdout)

    def test_refresh_rate_mismatch_or_unknown_does_not_restart_device(self):
        for actual in ('60', ''):
            with self.subTest(actual=actual):
                self.env['START_TEST_REFRESH_RATE'] = actual
                result = self.run_script('--refresh-rate', '120', mode='ready')
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('期望 120 Hz', result.stderr)
                self.assertIn('先退出模拟器', result.stderr)
                self.assertIn('冷启动', result.stderr)
                self.assertNotIn('模拟器已就绪', result.stdout)
                self.assertFalse((self.root / 'launch').exists())
        calls = (self.root / 'adb-calls').read_text()
        self.assertTrue(all(' devices -l' in call or ' shell getprop ' in call
                            for call in calls.splitlines()), calls)

    def test_refresh_rate_dry_run_and_boundaries_contact_no_devices(self):
        for rate, expected in [('30', '30'), ('120', '120'), ('165', '165'), ('240', '240'), ('030', '30')]:
            with self.subTest(rate=rate):
                result = self.run_script('--dry-run', '--refresh-rate', rate)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(f'-vsync-rate {expected} -no-snapshot', result.stdout)
                self.assertFalse((self.root / 'launch').exists())
                self.assertFalse((self.root / 'adb-calls').exists())

    def test_invalid_refresh_rates_fail_before_external_commands(self):
        for value in ('29', '241', '0', '-1', '120.0', 'abc', '9999999999', '120;command'):
            with self.subTest(value=value):
                result = self.run_script('--refresh-rate', value)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('30～240', result.stderr)
                self.assertFalse((self.root / 'launch').exists())
                self.assertFalse((self.root / 'adb-calls').exists())
        result = self.run_script('--refresh-rate')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('缺少参数', result.stderr)

    def test_cold_boot_closes_and_restarts_after_confirmation(self):
        result = self.run_script('--cold-boot', mode='ready', answer='y\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('是否关闭并冷启动？[y/N]', result.stderr)
        calls = (self.root / 'adb-calls').read_text().splitlines()
        kill = '-H 127.0.0.1 -P 5037 -s emulator-5554 emu kill'
        name = '-H 127.0.0.1 -P 5037 -s emulator-5554 shell getprop ro.boot.qemu.avd_name'
        self.assertEqual(calls.count(kill), 1)
        self.assertEqual(calls[:3], ['-H 127.0.0.1 -P 5037 devices -l', name, name])
        self.assertIn('devices -l', calls[calls.index(kill) + 1])
        self.assertTrue((self.root / 'launch').exists())
        self.assertIn('模拟器已就绪', result.stdout)

    def test_cold_boot_applies_memory_and_refresh_rate_after_confirmation(self):
        result = self.run_script('--cold-boot', '--refresh-rate', '165', '--memory', '4096',
                                 mode='ready', answer='YES\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        command = base64.b64decode((self.root / 'launch').read_text()).decode('utf-16le')
        self.assertIn("'-memory', '4096'", command)
        self.assertIn("'-vsync-rate', '165', '-no-snapshot'", command)
        self.assertIn('客体刷新率已核对：165 Hz', result.stdout)

    def test_cold_boot_decline_default_and_eof_keep_running_device(self):
        for answer in ('n\n', 'NO\n', '\n', ''):
            with self.subTest(answer=answer):
                result = self.run_script('--cold-boot', mode='ready', answer=answer)
                self.assertEqual(result.returncode, 1 if answer == '' else 0)
                self.assertIn('取消冷启动', result.stdout + result.stderr)
                calls = (self.root / 'adb-calls').read_text()
                self.assertNotIn('emu kill', calls)
                self.assertNotIn('getprop sys.boot_completed', calls)
                self.assertFalse((self.root / 'launch').exists())
                self.assertNotIn('模拟器已就绪', result.stdout)

    def test_invalid_confirmation_is_reprompted_without_closing(self):
        result = self.run_script('--cold-boot', mode='ready', answer='invalid\nn\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('请输入 y', result.stderr)
        self.assertNotIn('emu kill', (self.root / 'adb-calls').read_text())
        self.assertFalse((self.root / 'launch').exists())

    def test_cold_boot_uses_selected_port(self):
        self.env['START_TEST_SERIAL'] = 'emulator-5556'
        result = self.run_script('--cold-boot', '--port', '5556', mode='ready', answer='y\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('emulator-5556', result.stderr)
        self.assertNotIn('emulator-5554', result.stderr)
        calls = (self.root / 'adb-calls').read_text()
        self.assertIn('-s emulator-5556 emu kill', calls)
        self.assertNotIn('emulator-5554', calls)
        self.assertTrue((self.root / 'launch').exists())

    def test_cold_boot_of_stopped_device_does_not_kill(self):
        result = self.run_script('--cold-boot')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('emu kill', (self.root / 'adb-calls').read_text())
        self.assertTrue((self.root / 'launch').exists())
        command = base64.b64decode((self.root / 'launch').read_text()).decode('utf-16le')
        self.assertIn("'-no-snapshot-load'", command)
        self.assertIn('$processes.Count -gt 0 -and $true', command)
        self.assertIn('-match $avdPattern -or $_.CommandLine -match $portPattern', command)
        self.assertIn('请手动关闭后重试', command)
        self.assertIn('Start-Sleep', command)
        self.assertNotIn('Stop-Process', command)
        self.assertNotIn('-wipe-data', command)

    def test_cold_boot_refuses_unknown_or_wrong_device(self):
        for mode in ('wrong-avd', 'offline', 'name-failure', 'devices-failure'):
            with self.subTest(mode=mode):
                result = self.run_script('--cold-boot', mode=mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('emu kill', (self.root / 'adb-calls').read_text())
                self.assertFalse((self.root / 'launch').exists())

    def test_cold_boot_missing_launcher_changes_no_device(self):
        (self.bin / 'powershell.exe').unlink()
        result = self.run_script('--cold-boot', mode='ready')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('找不到 powershell.exe', result.stderr)
        self.assertNotIn('emu kill', (self.root / 'adb-calls').read_text())

    def test_cold_boot_checks_windows_processes_when_adb_has_no_device(self):
        result = self.run_script('--cold-boot', mode='windows-existing')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('请手动关闭后重试', result.stderr)
        self.assertNotIn('getprop', (self.root / 'adb-calls').read_text())
        self.assertNotIn('模拟器已就绪', result.stdout)

    def test_cold_boot_close_failure_or_timeout_does_not_launch(self):
        for mode in ('kill-failure', 'shutdown-timeout'):
            with self.subTest(mode=mode):
                result = self.run_script('--cold-boot', '--timeout', '1', mode=mode, answer='y\n')
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.root / 'launch').exists())
                self.assertNotIn('模拟器已就绪', result.stdout)

    def test_cold_boot_target_changed_after_confirmation_is_not_closed(self):
        result = self.run_script('--cold-boot', mode='target-changed', answer='y\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Other_AVD', result.stderr)
        self.assertNotIn('emu kill', (self.root / 'adb-calls').read_text())
        self.assertFalse((self.root / 'launch').exists())

    def test_cold_boot_uses_property_when_console_name_has_no_output(self):
        result = self.run_script('--cold-boot', mode='console-name-empty', answer='y\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = (self.root / 'adb-calls').read_text()
        self.assertIn('shell getprop ro.boot.qemu.avd_name', calls)
        self.assertNotIn('emu avd name', calls)
        self.assertIn('emu kill', calls)
        self.assertTrue((self.root / 'launch').exists())

    def test_cold_boot_uses_legacy_property_when_boot_name_is_empty(self):
        result = self.run_script('--cold-boot', mode='legacy-name', answer='y\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = (self.root / 'adb-calls').read_text()
        self.assertIn('shell getprop ro.kernel.qemu.avd_name', calls)
        self.assertIn('emu kill', calls)
        self.assertIn('模拟器已就绪', result.stdout)

    def test_cold_boot_trims_blank_lines_and_whitespace_from_property(self):
        result = self.run_script('--cold-boot', mode='name-leading-blank', answer='y\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('emu kill', (self.root / 'adb-calls').read_text())

    def test_cold_boot_missing_name_properties_does_not_close_device(self):
        result = self.run_script('--cold-boot', mode='name-missing', answer='y\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('无法读取', result.stderr)
        self.assertNotIn('emu kill', (self.root / 'adb-calls').read_text())
        self.assertFalse((self.root / 'launch').exists())

    def test_cold_boot_windows_process_name_fallback_closes_confirmed_target(self):
        self.env['START_TEST_WINDOWS_AVD'] = 'Medium_Phone_API_37.0\r'
        result = self.run_script('--cold-boot', mode='windows-name', answer='y\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('是否关闭并冷启动', result.stderr)
        self.assertIn('emu kill', (self.root / 'adb-calls').read_text())
        self.assertTrue((self.root / 'launch').exists())
        self.assertIn('模拟器已就绪', result.stdout)
        command = (self.root / 'windows-name-calls').read_text()
        self.assertIn('-port\\s+5554', command)
        self.assertEqual(command.count('# AVD_NAME_QUERY'), 2)

    def test_cold_boot_wrong_or_ambiguous_windows_name_does_not_close(self):
        for name in ('Other_AVD', 'Medium_Phone_API_37.0\nOther_AVD'):
            with self.subTest(name=name):
                self.env['START_TEST_WINDOWS_AVD'] = name
                result = self.run_script('--cold-boot', mode='name-missing', answer='y\n')
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('emu kill', (self.root / 'adb-calls').read_text())
                self.assertFalse((self.root / 'launch').exists())

    def test_refresh_lock_saves_restores_values_for_same_android_user(self):
        self.env['START_TEST_REFRESH_RATE'] = '165'
        result = self.run_script('--refresh-rate', '165', '--lock-refresh-rate', mode='ready')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / 'launch').exists())
        calls = (self.root / 'adb-calls').read_text()
        self.assertIn('settings --user 10 put system peak_refresh_rate 165', calls)
        self.assertIn('settings --user 10 put system min_refresh_rate 165', calls)
        restore_script, = (self.root / '.cache/emulator-start').glob('refresh-5554-*.sh')
        restore = restore_script.read_text()
        self.assertIn('put system peak_refresh_rate 60.0', restore)
        self.assertIn('delete system min_refresh_rate', restore)
        self.assertIn(str(restore_script), result.stdout)
        restored = subprocess.run(['bash', str(restore_script)], env=self.env,
                                  capture_output=True, text=True, timeout=10)
        self.assertEqual(restored.returncode, 0, restored.stderr)
        self.assertEqual(json.loads((self.root / 'settings.json').read_text()), {
            'peak_refresh_rate': '60.0', 'min_refresh_rate': 'null',
        })

    def test_refresh_lock_requires_explicit_rate_and_dry_run_is_read_only(self):
        result = self.run_script('--lock-refresh-rate')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'adb-calls').exists())
        result = self.run_script('--cold-boot', '--refresh-rate', '165',
                                 '--lock-refresh-rate', '--dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('-vsync-rate 165 -no-snapshot', result.stdout)
        self.assertIn('peak_refresh_rate / min_refresh_rate', result.stdout)
        self.assertFalse((self.root / 'adb-calls').exists())
        self.assertFalse((self.root / '.cache').exists())

    def test_refresh_lock_read_failure_changes_no_settings(self):
        result = self.run_script('--refresh-rate', '120', '--lock-refresh-rate',
                                 mode='settings-read-failure')
        self.assertNotEqual(result.returncode, 0)
        calls = (self.root / 'adb-calls').read_text()
        self.assertNotIn('put system', calls)
        self.assertFalse((self.root / 'settings.json').exists())

    def test_refresh_lock_mismatched_boot_rate_changes_no_settings(self):
        result = self.run_script('--refresh-rate', '165', '--lock-refresh-rate', mode='ready')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('期望 165 Hz', result.stderr)
        self.assertNotIn('settings', (self.root / 'adb-calls').read_text())
        self.assertFalse((self.root / 'settings.json').exists())

    def test_refresh_lock_invalid_original_value_changes_no_settings(self):
        self.env['START_TEST_PEAK_RATE'] = '60; unsafe'
        result = self.run_script('--refresh-rate', '120', '--lock-refresh-rate')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('原值无效', result.stderr)
        self.assertFalse((self.root / 'settings.json').exists())

    def test_refresh_lock_invalid_android_user_changes_no_settings(self):
        self.env['START_TEST_ANDROID_USER'] = 'unknown'
        result = self.run_script('--refresh-rate', '120', '--lock-refresh-rate')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'settings.json').exists())

    def test_refresh_lock_write_or_verification_failure_keeps_restore_script(self):
        for mode in ('settings-write-failure', 'settings-not-applied'):
            with self.subTest(mode=mode):
                result = self.run_script('--refresh-rate', '120', '--lock-refresh-rate', mode=mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('恢复脚本', result.stderr)
                self.assertNotIn('模拟器已就绪', result.stdout)
                self.assertTrue(list((self.root / '.cache/emulator-start').glob('refresh-5554-*.sh')))

    def test_ready_device_needs_no_windows_launcher(self):
        (self.bin / 'powershell.exe').unlink()
        result = self.run_script(mode='ready')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / 'launch').exists())

    def test_offline_device_is_waited_for_without_duplicate_launch(self):
        result = self.run_script(mode='offline')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / 'launch').exists())
        self.assertTrue((self.root / 'boot-probed').exists())

    def test_wrong_avd_is_rejected(self):
        result = self.run_script(mode='wrong-avd')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Other_AVD', result.stderr)
        self.assertNotIn('模拟器已就绪', result.stdout)

    def test_hung_adb_is_bounded_by_boot_timeout(self):
        started = time.monotonic()
        result = self.run_script('--timeout', '1', mode='timeout')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('超过 1s', result.stderr)
        self.assertLess(time.monotonic() - started, 5)

    def test_launch_failure_stops_before_boot_wait(self):
        result = self.run_script(mode='launch-failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('getprop', (self.root / 'adb-calls').read_text())

    def test_dry_run_and_invalid_options_do_not_contact_devices(self):
        for args in [('--dry-run',), ('--port', '5555'), ('--timeout', '0'),
                     ('--avd', "bad';command"), ('--emulator',), ('--unknown',)]:
            with self.subTest(args=args):
                result = self.run_script(*args)
                self.assertEqual(result.returncode == 0, args == ('--dry-run',))
                self.assertFalse((self.root / 'launch').exists())
                self.assertFalse((self.root / 'adb-calls').exists())


if __name__ == '__main__':
    unittest.main()
