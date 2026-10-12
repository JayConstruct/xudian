"""Fresh-install evidence must exercise workers before restarting the app."""
import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock

HOST_SCRIPTS = Path(__file__).resolve().parents[1] / 'module_host'
sys.path.insert(0, str(HOST_SCRIPTS))
try:
    spec = importlib.util.spec_from_file_location(
        'verify_fresh_install', HOST_SCRIPTS / 'verify_fresh_install.py')
    verify = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(verify)
finally:
    sys.path.remove(str(HOST_SCRIPTS))


class FreshInstallPagesTest(unittest.TestCase):
    def verification(self):
        verification = object.__new__(verify.FreshInstallVerification)
        verification.emulator = Mock()
        verification.emulator.nodes.return_value = []
        verification.tap_scrolling = Mock()
        verification.record = Mock()
        verification.step = Mock()
        verification.labels = Mock(return_value=[])
        return verification

    def test_immediate_and_restarted_pages_use_distinct_evidence_without_restart(self):
        for restarted in (False, True):
            with self.subTest(after_restart=restarted):
                verification = self.verification()
                verification.verify_module_pages(after_restart=restarted)
                names = [call.args[0] for call in verification.step.call_args_list]
                suffix = 'AfterRestart' if restarted else 'ImmediatelyAfterInstall'
                self.assertEqual(names, [
                    'scheduleOpened' + suffix,
                    'importerSettingsOpened' + suffix,
                    'agendaOpened' + suffix,
                ])
                # No force-stop or launch is permitted inside immediate probes.
                verification.emulator.adb.assert_not_called()
                self.assertEqual(verification.emulator.wait_for.call_count, 3)
                taps = [call.args[0] for call in verification.tap_scrolling.call_args_list]
                self.assertEqual(taps, ['课表', '模块与连接', '拾光教务导入', '日程'])

    def test_runtime_error_cannot_be_recorded_as_a_successful_page_open(self):
        verification = self.verification()
        verification.emulator.nodes.return_value = [
            {'text': 'Bad state: A transaction was used after being closed.'},
        ]
        verification.labels = Mock(return_value=[
            'Bad state: A transaction was used after being closed.',
        ])
        with self.assertRaisesRegex(RuntimeError, 'transaction was used'):
            verification.verify_module_pages(after_restart=False)
        verification.step.assert_not_called()
        verification.record.assert_not_called()


if __name__ == '__main__':
    unittest.main()
