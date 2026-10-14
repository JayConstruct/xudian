"""Fresh-install evidence must exercise workers before restarting the app."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

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
    def test_overlapping_review_scroll_keeps_previous_digest_with_its_module(self):
        verification = object.__new__(verify.FreshInstallVerification)
        verification.emulator = Mock()
        verification.emulator.label.side_effect = verify.Emulator.label
        verification.modules = [
            {'id': 'app.schedule', 'name': '大学课表', 'version': '1.12.0'},
            {'id': 'app.import.shiguang', 'name': '拾光教务导入兼容', 'version': '1.5.0'},
        ]
        schedule = ['大学课表 · 1.12.0', '操作：安装并启用',
                    '新增权限：ui、files、clock.today', '全部权限：ui、files、clock.today',
                    verify.UNSIGNED, 'SHA-256：' + 'a' * 64]
        importer = ['拾光教务导入兼容 · 1.5.0', '操作：安装并启用',
                    '新增权限：ui、files、browser.capture',
                    '全部权限：ui、files、browser.capture',
                    verify.UNSIGNED, 'SHA-256：' + 'b' * 64]
        verification.record = Mock(side_effect=[
            [{'text': line} for line in schedule + importer[:3]],
            [{'text': line} for line in schedule[-1:] + importer],
            [],
        ])
        verification.swipe = Mock()
        verification.find_scrolling = Mock()
        verification.step = Mock()
        verification.wait_for_store_installation = Mock(return_value={})
        verification.verify_review()
        reviews = verification.step.call_args_list[0].kwargs['modules']
        self.assertEqual([r['sha256'] for r in reviews], ['a' * 64, 'b' * 64])
        verification.emulator.tap_node.assert_called_once()

    def review_verification(self, snapshots):
        verification = object.__new__(verify.FreshInstallVerification)
        verification.emulator = Mock()
        verification.emulator.label.side_effect = verify.Emulator.label
        verification.modules = [
            {'id': 'app.schedule', 'name': '大学课表', 'version': '1.12.0'},
            {'id': 'app.import.shiguang', 'name': '拾光教务导入兼容', 'version': '1.5.0'},
        ]
        verification.record = Mock(side_effect=snapshots)
        verification.swipe = Mock()
        verification.find_scrolling = Mock()
        verification.step = Mock()
        verification.wait_for_store_installation = Mock(return_value={})
        return verification

    def test_review_records_selection_then_expands_full_permission_and_digest_plan(self):
        expand = {'text': '技术详情与完整计划', 'enabled': 'true'}
        summary = [{'text': line} for line in [
            '你选择的模块', '拾光教务导入兼容', '安装并启用 · 1.5.0',
            '自动加入的依赖', '大学课表', '安装并启用 · 1.12.0',
            '权限与影响', '大学课表', verify.UNSIGNED,
        ]]
        details = [{'text': line} for line in [
            '1. 大学课表', '模块标识：app.schedule', '安装并启用 · 1.12.0',
            '新增权限标识：ui、files', '全部权限标识：ui、files',
            verify.UNSIGNED, 'SHA-256：' + 'a' * 64,
            '2. 拾光教务导入兼容', '模块标识：app.import.shiguang',
            '安装并启用 · 1.5.0', '新增权限标识：browser.capture',
            '全部权限标识：ui、files、browser.capture',
            verify.UNSIGNED, 'SHA-256：' + 'b' * 64,
        ]]
        verification = self.review_verification([summary, [expand], details, []])
        verification.verify_review()
        evidence = verification.step.call_args_list[0].kwargs
        self.assertEqual(evidence['summary'], {
            '你选择的模块': ['拾光教务导入兼容'], '自动加入的依赖': ['大学课表']})
        self.assertEqual([item['sha256'] for item in evidence['modules']],
                         ['a' * 64, 'b' * 64])
        self.assertEqual(evidence['modules'][1]['allPermissions'],
                         ['全部权限：ui、files、browser.capture'])
        self.assertEqual(verification.emulator.tap_node.call_args_list[0].args,
                         (expand,))
        verification.find_scrolling.assert_called_once_with('确认安装', attempts=2)

    def test_review_refuses_wrong_selection_before_expanding_or_installing(self):
        summary = [{'text': line} for line in [
            '你选择的模块', '大学课表', '自动加入的依赖',
            '拾光教务导入兼容', '权限与影响', '技术详情与完整计划',
        ]]
        verification = self.review_verification([summary])
        with self.assertRaisesRegex(RuntimeError, '区分所选模块'):
            verification.verify_review()
        verification.emulator.tap_node.assert_not_called()
        verification.step.assert_not_called()

    def test_review_refuses_digest_absent_from_expanded_plan(self):
        summary = [{'text': line} for line in [
            '你选择的模块', '拾光教务导入兼容', '自动加入的依赖',
            '大学课表', '权限与影响', '技术详情与完整计划',
        ]]
        verification = self.review_verification([summary] + [[]] * 20)
        with self.assertRaisesRegex(RuntimeError, 'SHA-256'):
            verification.verify_review()
        self.assertEqual(verification.emulator.tap_node.call_count, 1)
        verification.find_scrolling.assert_not_called()

    def test_store_installation_succeeds_after_short_completion_toast_is_gone(self):
        verification = self.verification()
        verification.modules = [
            {'id': 'app.import.shiguang', 'name': '拾光教务导入兼容', 'version': '1.5.0'}]
        card = {'text': '拾光教务导入兼容\n版本：1.5.0 · 已启用'}
        verification.emulator.nodes.return_value = [card]
        self.assertEqual(verification.wait_for_store_installation(),
                         {'storeCard': card['text'], 'completionNotice': None})
        verification.emulator.wait_for.assert_not_called()

    def test_installed_store_card_accepts_current_and_legacy_status_formats(self):
        verification = self.verification()
        verification.modules = [
            {'id': 'app.import.shiguang', 'name': '拾光教务导入兼容', 'version': '1.5.0'}]
        for status in ['版本：1.5.0 · 已启用', '已启用 · 1.5.0',
                       '版本：1.5.0 → 1.6.0 · 已启用 · 可更新',
                       '已启用 · 可更新 · 1.5.0 → 1.6.0']:
            with self.subTest(status=status):
                card = {'text': f'查看 拾光教务导入兼容 详情\n{status}'}
                self.assertIs(verification.installed_store_card([card]), card)

    def test_installed_store_card_rejects_update_target_and_disabled_modules(self):
        verification = self.verification()
        verification.modules = [
            {'id': 'app.import.shiguang', 'name': '拾光教务导入兼容', 'version': '1.5.0'}]
        for status in ['版本：1.4.0 → 1.5.0 · 已启用 · 可更新',
                       '已启用 · 可更新 · 1.4.0 → 1.5.0',
                       '已停用 · 1.5.0', '版本：1.5.0 · 已停用',
                       '可安装 · 1.5.0', '已启用 · 1.5.01']:
            with self.subTest(status=status):
                card = {'text': f'拾光教务导入兼容\n{status}'}
                self.assertIsNone(verification.installed_store_card([card]))

    def test_store_card_state_rejects_ancestor_with_ambiguous_module_versions(self):
        self.assertIsNone(verify.FreshInstallVerification.store_card_state(
            '大学课表\n已启用 · 1.5.0\n拾光教务导入兼容\n已启用 · 1.4.0'))

    def store_version_verification(self, card):
        verification = self.verification()
        verification.args = SimpleNamespace(expected_importer_version='1.5.0')
        verification.report = {}
        verification.find_scrolling = Mock(return_value=card)
        verification.emulator.nodes.return_value = [card]
        verification.write_report = Mock()
        return verification

    def test_store_version_wait_accepts_current_and_legacy_available_versions(self):
        for status in ['可安装 · 1.5.0', '版本：1.5.0 · 可安装']:
            with self.subTest(status=status):
                card = {'text': f'查看 拾光教务导入兼容 详情\n{status}'}
                verification = self.store_version_verification(card)
                self.assertIs(verification.wait_for_store_version(), card)
                verification.step.assert_called_once_with(
                    'expectedStoreVersionReady', actualVersion='1.5.0', refreshCount=0)

    def test_store_version_wait_refreshes_stale_current_format_index(self):
        stale = {'text': '拾光教务导入兼容\n可安装 · 1.4.0'}
        fresh = {'text': '拾光教务导入兼容\n可安装 · 1.5.0'}
        refresh = {'text': '刷新 / 重试', 'enabled': 'true'}
        verification = self.store_version_verification(stale)
        verification.emulator.nodes.side_effect = [[stale, refresh], [fresh]]
        with patch.object(verify.time, 'monotonic', side_effect=[0, 1, 19, 20, 21, 22, 23]), \
                patch.object(verify.time, 'sleep'):
            self.assertIs(verification.wait_for_store_version(), fresh)
        verification.emulator.tap_node.assert_called_once_with(refresh)
        self.assertEqual(verification.report['storeVersionWait']['actualVersion'], '1.4.0')
        verification.step.assert_called_once_with(
            'expectedStoreVersionReady', actualVersion='1.5.0', refreshCount=1)

    def test_store_version_wait_does_not_accept_update_target_as_available_version(self):
        for status in ['已启用 · 可更新 · 1.4.0 → 1.5.0',
                       '版本：1.4.0 → 1.5.0 · 已启用 · 可更新']:
            with self.subTest(status=status):
                card = {'text': f'拾光教务导入兼容\n{status}'}
                verification = self.store_version_verification(card)
                with patch.object(verify.time, 'monotonic', side_effect=[0, 1, 121]):
                    with self.assertRaisesRegex(RuntimeError, '实际版本：1.4.0'):
                        verification.wait_for_store_version()
                verification.step.assert_not_called()

    def test_current_completion_toast_uses_persistent_importer_card_action(self):
        for show_toast in (False, True):
            with self.subTest(show_toast=show_toast):
                verification = self.verification()
                verification.labels = verify.FreshInstallVerification.labels.__get__(verification)
                verification.modules = [
                    {'id': 'app.import.shiguang', 'name': '拾光教务导入兼容', 'version': '1.5.0'}]
                wrong_action = {'text': '打开模块', 'enabled': 'true',
                                'bounds': '[0,30][200,80]'}
                card = {'text': '查看 拾光教务导入兼容 详情\n已启用 · 1.5.0',
                        'bounds': '[0,100][1080,500]'}
                action = {'text': '打开模块', 'enabled': 'true',
                          'bounds': '[30,300][200,350]'}
                nodes = [wrong_action, card, action]
                if show_toast:
                    nodes.append({'text': '模块安装完成，共 2 个'})
                verification.emulator.nodes.return_value = nodes
                verification.emulator.bounds.side_effect = verify.Emulator.bounds
                verification.find_scrolling = Mock()
                verification.consume_install_action(expect_open=True)
                verification.emulator.tap_node.assert_called_once_with(action)
                verification.emulator.wait_for.assert_called_once_with(
                    '按学校导入', timeout=30, contains=True)
                verification.step.assert_called_once_with('storeEntryOpenedImporterWithoutRestart')
                verification.emulator.adb.assert_not_called()

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
                self.assertEqual(taps, ['课表', '拾光教务导入', '日程'])

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
