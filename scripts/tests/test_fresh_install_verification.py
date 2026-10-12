"""Fresh-install evidence must exercise workers before restarting the app."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
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
        verification.emulator.label.side_effect = verify.Emulator.label
        verification.resuming_installed = False
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

    def test_installation_action_is_consumed_before_obscured_dock(self):
        verification = self.verification()
        verification.emulator.nodes.return_value = [
            {'text': '模块安装完成', 'bounds': '[0,2211][1080,2400]'},
            {'text': '打开模块', 'enabled': 'true', 'bounds': '[774,2211][1049,2337]'},
        ]
        verification.emulator.label.side_effect = lambda node: node['text']
        verification.consume_install_action(expect_open=True)
        verification.emulator.tap_node.assert_called_once_with(
            verification.emulator.nodes.return_value[1])
        verification.emulator.wait_for.assert_called_once_with(
            '按学校导入', timeout=30, contains=True)
        verification.emulator.adb.assert_not_called()
        verification.step.assert_called_once_with(
            'installationActionOpenedImporterWithoutRestart')

    def test_consuming_stale_store_action_only_dismisses_notice(self):
        verification = self.verification()
        nodes = [
            {'text': '模块安装完成', 'bounds': '[0,2211][1080,2400]'},
            {'text': '打开模块', 'enabled': 'true', 'bounds': '[774,2211][1049,2337]'},
        ]
        verification.emulator.nodes.side_effect = [nodes, [], []]
        verification.consume_install_action()
        verification.emulator.tap_node.assert_called_once_with(nodes[1])
        verification.emulator.wait_for.assert_not_called()
        verification.step.assert_called_once_with('installationNoticeConsumedWithoutRestart')
        verification.emulator.adb.assert_not_called()

    def resume_fixture(self, directory):
        verification = self.verification()
        verification.output = Path(directory)
        verification.args = SimpleNamespace(user=0, serial='fresh-device')
        verification.modules = [
            {'id': 'app.schedule', 'name': '大学课表', 'version': '1.11.0'},
            {'id': 'app.import.shiguang', 'name': '拾光教务导入兼容', 'version': '1.5.0'},
        ]
        verification.report = {'apkSha256': 'a' * 64}
        verification.installed_apk_digest = Mock(return_value='a' * 64)
        previous = {
            'status': 'failed', 'androidUser': 0, 'serial': 'fresh-device',
            'apkSha256': 'a' * 64, 'expectedModules': verification.modules,
            'error': 'Navigation center covered by Snackbar', 'attempt': 1,
            'steps': [
                {'name': 'targetUserInitiallyUninstalled', 'passed': True},
                {'name': 'apkFirstInstalled', 'passed': True,
                 'installedApkSha256': 'a' * 64},
                {'name': 'modulesInstalledFromStore', 'passed': True},
                {'name': '05-modules-enabled', 'passed': True},
                {'name': 'dependencyReviewVerified', 'passed': True,
                 'modules': [{**module, 'sha256': str(index) * 64}
                             for index, module in enumerate(verification.modules, 1)]},
            ],
        }
        return verification, previous

    def test_installed_resume_archives_first_failure_and_preserves_store_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            verification, previous = self.resume_fixture(directory)
            original = json.dumps(previous)
            (Path(directory) / 'fresh-install.json').write_text(original)
            verification.prepare_resume(installed_modules=True)
            self.assertEqual((Path(directory) / 'fresh-install-attempt-01.json').read_text(), original)
            self.assertEqual(verification.report['attempt'], 2)
            self.assertEqual(verification.report['firstInstallationAttemptReport'],
                             'fresh-install-attempt-01.json')
            self.assertEqual(verification.report['previousFailure'], previous['error'])
            self.assertTrue(verification.resuming)
            verification.emulator.adb.assert_not_called()

    def test_installed_resume_refuses_wrong_apk_missing_store_or_prior_restart(self):
        for mutation in ('apk', 'store', 'restart', 'module-version', 'review-hash'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                verification, previous = self.resume_fixture(directory)
                if mutation == 'apk':
                    verification.installed_apk_digest.return_value = 'b' * 64
                elif mutation == 'store':
                    previous['steps'] = [step for step in previous['steps']
                                         if step['name'] != 'modulesInstalledFromStore']
                elif mutation == 'restart':
                    previous['steps'].append({'name': '06-modules-enabled-after-restart', 'passed': True})
                elif mutation == 'module-version':
                    previous['expectedModules'] = [{**verification.modules[0], 'version': '1.10.0'}]
                else:
                    previous['steps'][-1]['modules'][0]['sha256'] = 'bad'
                (Path(directory) / 'fresh-install.json').write_text(json.dumps(previous))
                with self.assertRaises(RuntimeError):
                    verification.prepare_resume(installed_modules=True)
                self.assertFalse((Path(directory) / 'fresh-install-attempt-01.json').exists())
                verification.emulator.adb.assert_not_called()

    def test_final_restart_occurs_only_after_immediate_pages_are_proven(self):
        verification = self.verification()
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / 'app.apk'
            apk.write_bytes(b'apk')
            digest = verify.hashlib.sha256(b'apk').hexdigest()
            verification.args = SimpleNamespace(apk=apk)
            verification.report = {'apkSha256': digest}
            verification.installed_apk_digest = Mock(return_value=digest)
            calls = []
            verification.verify_enabled = Mock(side_effect=lambda stage: calls.append(stage))
            verification.consume_install_action = Mock(side_effect=lambda: calls.append('consume-action'))
            verification.verify_module_pages = Mock(side_effect=lambda **kw: calls.append(
                'restarted-pages' if kw['after_restart'] else 'immediate-pages'))
            verification.launch = Mock(side_effect=lambda **kw: calls.append('restart'))
            verification.finish_module_verification()
            self.assertEqual(calls, ['05-modules-enabled', 'consume-action', 'immediate-pages',
                                     'restart', '06-modules-enabled-after-restart', 'restarted-pages'])
            verification.emulator.adb.assert_not_called()

    def test_resume_installed_run_never_relaunches_or_reinstalls_before_live_probes(self):
        verification = self.verification()
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / 'app.apk'
            apk.write_bytes(b'apk')
            verification.args = SimpleNamespace(
                apk=apk, user=0, resume=False, resume_installed=True)
            verification.report = {}
            verification.prepare_resume = Mock()
            verification.finish_module_verification = Mock()
            verification.launch = Mock()
            def adb(*args):
                if args[:3] == ('shell', 'pm', 'list'):
                    return 'package:' + verify.PACKAGE
                if args[:3] == ('shell', 'am', 'get-current-user'):
                    return '0'
                return ''
            verification.emulator.adb.side_effect = adb
            verification.run()
            verification.prepare_resume.assert_called_once_with(installed_modules=True)
            verification.finish_module_verification.assert_called_once_with()
            verification.launch.assert_not_called()
            commands = [call.args for call in verification.emulator.adb.call_args_list]
            self.assertFalse(any(command[0] == 'install' or 'force-stop' in command
                                 or 'start' in command for command in commands))


if __name__ == '__main__':
    unittest.main()
