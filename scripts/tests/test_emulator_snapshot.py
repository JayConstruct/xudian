"""UI snapshot reuse and invalidation checks; no emulator required."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    'verify_emulator', Path(__file__).resolve().parents[1] / 'module_host/verify_emulator.py')
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)


class EmulatorSnapshotTest(unittest.TestCase):
    def setUp(self):
        self.clock = 100.0
        self.calls = []
        self.visible = '课表'
        self.emulator = verify.Emulator('test-device')
        self.addCleanup(patch.stopall)
        patch.object(verify.time, 'monotonic', side_effect=lambda: self.clock).start()
        patch.object(verify.subprocess, 'run', side_effect=self.fake_run).start()

    def fake_run(self, command, **kwargs):
        args = command[7:]
        self.calls.append(args)
        if args[:2] == ['shell', 'cat']:
            stdout = (f'<hierarchy><node text="{self.visible}" bounds="[0,0][100,40]" />'
                      '</hierarchy>').encode()
        elif args[:2] == ['exec-out', 'screencap']:
            stdout = b'PNG'
        else:
            stdout = b''
        return subprocess.CompletedProcess(command, 0, stdout, b'')

    def dump_count(self):
        return sum(args[:3] == ['shell', 'uiautomator', 'dump'] for args in self.calls)

    def test_custom_adb_endpoint(self):
        emulator = verify.Emulator('serial', adb_host='localhost', adb_port=1234)
        self.assertEqual(emulator.command, ['adb', '-H', 'localhost', '-P', '1234', '-s', 'serial'])

    def test_snapshot_reuses_immediate_reads_but_expires(self):
        first = self.emulator.snapshot()
        self.assertIs(self.emulator.snapshot(), first)
        self.assertEqual(self.dump_count(), 1)
        self.clock += self.emulator.SNAPSHOT_TTL
        self.assertIsNot(self.emulator.snapshot(), first)
        self.assertEqual(self.dump_count(), 2)

    def test_nodes_polls_are_always_fresh(self):
        self.assertEqual(self.emulator.label(self.emulator.nodes()[0]), '课表')
        self.visible = '今天'
        self.assertEqual(self.emulator.label(self.emulator.nodes()[0]), '今天')
        self.assertEqual(self.dump_count(), 2)

    def test_tap_reuses_latest_nodes_then_invalidates(self):
        self.emulator.nodes()
        self.emulator.tap('课表')
        self.assertEqual(self.dump_count(), 1)
        self.assertEqual(self.calls[-1], ['shell', 'input', 'tap', '50', '20'])
        self.visible = '今天'
        self.emulator.tap('今天')
        self.assertEqual(self.dump_count(), 2)

    def test_public_adb_commands_invalidate_even_quoted_shell(self):
        commands = [
            ('shell', 'input', 'text', 'example'),
            ('shell', 'input', 'keyevent', '4'),
            ('shell', 'input', 'swipe', '0', '0', '100', '100'),
            ('shell', 'am', 'start', '-n', 'example/.MainActivity'),
            ('shell', 'am', 'force-stop', 'example'),
            ('install', '-r', '/tmp/example.apk'),
            ('shell', 'input tap 20 20'),
        ]
        for command in commands:
            with self.subTest(command=command):
                first = self.emulator.snapshot()
                self.emulator.adb(*command)
                self.assertIsNot(self.emulator.snapshot(), first)

    def test_failed_command_also_invalidates(self):
        first = self.emulator.snapshot()
        with patch.object(verify.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, ['adb'])):
            with self.assertRaises(subprocess.CalledProcessError):
                self.emulator.adb('shell', 'input', 'text', 'example')
        self.assertIsNot(self.emulator.snapshot(), first)

    def test_external_mutation_can_explicitly_invalidate(self):
        first = self.emulator.snapshot()
        self.emulator.invalidate_snapshot()
        self.assertIsNot(self.emulator.snapshot(), first)

    def test_record_uses_one_fresh_dump_and_preserves_other_files(self):
        self.emulator.nodes()
        self.visible = '今天'
        with tempfile.TemporaryDirectory() as folder, patch.object(verify, 'OUT', Path(folder)):
            old = Path(folder) / 'old.png'
            old.write_bytes(b'old screenshot')
            self.emulator.record('current')
            self.assertEqual((Path(folder) / 'current.png').read_bytes(), b'PNG')
            xml = (Path(folder) / 'current.xml').read_text()
            self.assertIn('今天', xml)
            self.assertEqual(xml, self.emulator.snapshot().xml)
            self.assertEqual(old.read_bytes(), b'old screenshot')
            self.assertEqual(set(p.name for p in Path(folder).iterdir()),
                             {'old.png', 'current.png', 'current.xml'})
        self.assertEqual(self.dump_count(), 2)  # One before record, one inside it.
        self.assertEqual(self.calls[-3][1:3], ['uiautomator', 'dump'])
        self.assertEqual(self.calls[-2][:2], ['shell', 'cat'])
        self.assertEqual(self.calls[-1][:2], ['exec-out', 'screencap'])

    def test_wait_for_polls_fresh_and_sleeps_less_than_one_second(self):
        sleeps = []

        def sleep(duration):
            sleeps.append(duration)
            self.clock += duration
            self.visible = '今天'

        with patch.object(verify.time, 'sleep', side_effect=sleep):
            node = self.emulator.wait_for('今天', timeout=1)
        self.assertEqual(self.emulator.label(node), '今天')
        self.assertEqual(self.dump_count(), 2)
        self.assertTrue(all(0 < delay < 1 for delay in sleeps))

    def test_wait_for_timeout_reports_latest_visible_nodes(self):
        with self.assertRaisesRegex(RuntimeError, 'UI item missing: 今天.*课表'):
            self.emulator.wait_for('今天', timeout=0)
        self.assertEqual(self.dump_count(), 1)


if __name__ == '__main__':
    unittest.main()
