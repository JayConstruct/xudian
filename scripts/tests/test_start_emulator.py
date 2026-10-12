"""Exercise the WSL startup flow with fake external processes."""
import base64
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
        self.env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}',
                        START_TEST_ROOT=str(self.root), START_TEST_MODE='new',
                        XUDIAN_ADB_HOST='127.0.0.1', XUDIAN_ADB_PORT='5037')
        self.tool('uname', 'print("6.6.0-microsoft-standard-WSL2")')
        self.tool('powershell.exe', '''
import sys
from pathlib import Path
root = Path(os.environ['START_TEST_ROOT'])
(root / 'launch').write_text(sys.argv[-1])
if os.environ['START_TEST_MODE'] == 'launch-failure':
    sys.exit(1)
''')
        self.tool('adb', '''
import sys
import time
from pathlib import Path
root = Path(os.environ['START_TEST_ROOT'])
mode = os.environ['START_TEST_MODE']
args = sys.argv[1:]
with (root / 'adb-calls').open('a') as log:
    log.write(' '.join(args) + '\\n')
if 'devices' in args:
    print('List of devices attached')
    if mode in ('ready', 'wrong-avd', 'offline'):
        print('emulator-5554\\t' + ('offline' if mode == 'offline' else 'device'))
elif 'getprop' in args:
    if args[-1] == 'ro.boot.qemu.avd_name':
        print('Other_AVD' if mode == 'wrong-avd' else 'Medium_Phone_API_37.0')
    elif args[-1] == 'ro.boot.qemu.vsync':
        print(os.environ.get('START_TEST_REFRESH_RATE', '60') + '\\r')
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

    def run_script(self, *args, mode='new'):
        return subprocess.run(['bash', str(self.root / 'scripts' / SCRIPT.name), *args],
                              env=dict(self.env, START_TEST_MODE=mode),
                              capture_output=True, text=True, timeout=10)

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
        for rate, expected in [('30', '30'), ('120', '120'), ('240', '240'), ('030', '30')]:
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
