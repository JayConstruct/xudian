"""Module workflow boundaries, deterministic packages and reviewed UI routing."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile
import xml.etree.ElementTree as ET

HELPERS = Path(__file__).resolve().parents[1] / 'module_host'
sys.path.insert(0, str(HELPERS))
spec = importlib.util.spec_from_file_location('update_emulator_modules', HELPERS / 'update_emulator_modules.py')
update = importlib.util.module_from_spec(spec)
spec.loader.exec_module(update)


class FakeEmulator:
    def __init__(self, permission='无', bad_digest=False, bad_version=False, already_installed=False,
                 stored_digest='match', stored_id=None):
        self.state = 'home'
        self.permission = permission
        self.bad_digest = bad_digest
        self.bad_version = bad_version
        self.already_installed = already_installed
        self.stored_digest = stored_digest
        self.stored_id = stored_id
        self.calls = []
        self.module = None

    @staticmethod
    def label(node):
        return node.get('text')

    def adb(self, *args):
        self.calls.append(args)
        if args[0] == 'push':
            path = Path(args[1])
            with zipfile.ZipFile(path) as archive:
                manifest = json.loads(archive.read('module.json'))['manifest']
            self.module = dict(manifest, sha256=hashlib.sha256(path.read_bytes()).hexdigest(), filename=path.name)
        return ''

    def manager(self):
        self.state = 'manager'

    def nodes(self):
        # Real Emulator uses XML Elements; a leaf node has false truthiness.
        return [ET.Element('node', text=label) for label in self.visible_labels()]

    def visible_labels(self):
        if self.state == 'home':
            return ['页面菜单']
        if self.state == 'manager':
            return ['模块管理', '导入 .xmodule']
        if self.state == 'picker':
            return ['显示根目录', '列表视图']
        if self.state == 'roots':
            return ['下载']
        if self.state == 'downloads':
            return [self.module['filename']]
        if self.state == 'review':
            digest = 'wrong' if self.bad_digest else self.module['sha256']
            return ['确认模块安装计划', f'{self.module["name"]} · {self.module["version"]}',
                    f'新增权限：{self.permission}', f'SHA-256：{digest}', '确认安装', '取消']
        if self.state == 'installed':
            version = '0.0.1' if self.bad_version else self.module['version']
            return ['模块管理', '导入 .xmodule', f'{self.module["name"]}\n描述\n{version} · 已启用',
                    '所需模块已经安装并启用' if self.already_installed else '模块安装完成']
        if self.state == 'details':
            digest = self.module['sha256'] if self.stored_digest == 'match' else '0' * 64
            labels = [self.module['name'], '模块 ID', self.stored_id or self.module['id'],
                      '版本与状态', f'{self.module["version"]} · 已启用', '关闭']
            return labels if self.stored_digest == 'missing' else labels + ['SHA-256', digest]
        raise AssertionError(self.state)

    def tap_node(self, node):
        node = self.label(node)
        self.calls.append(('tap', node))
        if node == '导入 .xmodule':
            self.state = 'picker'
        elif node == '显示根目录':
            self.state = 'roots'
        elif node == '下载':
            self.state = 'downloads'
        elif node == '列表视图':
            pass
        elif node == self.module['filename']:
            self.state = 'installed' if self.already_installed else 'review'
        elif node == '确认安装':
            self.state = 'installed'
        elif node == f'{self.module["name"]}\n描述\n{self.module["version"]} · 已启用':
            self.state = 'details'
        elif node == '关闭':
            self.state = 'installed'
        else:
            raise AssertionError(node)


class ModuleWorkflowTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.sources = self.root / 'packages/modules'
        self.output = self.root / 'packages-out'
        self.patch = patch.object(update, 'ROOT', self.root)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.create_module('app.schedule')
        self.create_module('app.other')

    def create_module(self, module_id):
        folder = self.sources / module_id
        folder.mkdir(parents=True)
        (folder / 'module.json').write_text(json.dumps({'formatVersion': 3, 'manifest': {
            'id': module_id, 'version': '1.7.0', 'name': module_id, 'permissions': ['ui']}}))
        (folder / 'main.js').write_text('function render() { return {}; }')
        return folder

    def test_only_selected_module_and_duplicate_ids_produce_one_deterministic_package(self):
        result = update.prepare_modules(['app.schedule', 'app.schedule'], self.output)
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]['id'], 'app.schedule')
        self.assertEqual([p.name for p in self.output.iterdir()], ['app.schedule-1.7.0.xmodule'])
        self.assertEqual(result, update.prepare_modules(['app.schedule'], self.output))
        with zipfile.ZipFile(result[0]['package']) as archive:
            self.assertEqual(set(archive.namelist()), {'module.json', 'main.js', 'package.json'})

    def test_rejects_escape_absolute_shell_and_missing_ids_before_packaging(self):
        for module_id in ['../app.schedule', '/tmp/module', '.', '..', 'app.schedule/child', 'app;echo', 'missing']:
            with self.subTest(module_id=module_id), self.assertRaises(ValueError):
                update.prepare_modules(['app.schedule', module_id], self.output)
            self.assertFalse(self.output.exists())

    def test_symlink_folder_and_source_file_are_rejected(self):
        outside = self.root / 'outside'
        outside.mkdir()
        (self.sources / 'escape').symlink_to(outside, target_is_directory=True)
        with self.assertRaises(ValueError):
            update.prepare_modules(['escape'], self.output)
        (self.sources / 'app.schedule/private').symlink_to(outside, target_is_directory=True)
        with self.assertRaises(ValueError):
            update.prepare_modules(['app.schedule'], self.output)
        self.assertFalse(self.output.exists())

    def test_manifest_mismatch_rejects_batch_before_device_or_packages(self):
        definition = self.sources / 'app.other/module.json'
        definition.write_text(json.dumps({'formatVersion': 3, 'manifest': {'id': 'spoof', 'version': '1.0.0'}}))
        emulator = FakeEmulator()
        with self.assertRaises(ValueError):
            update.update_modules(['app.schedule', 'app.other'], emulator, self.output)
        self.assertEqual(emulator.calls, [])
        self.assertFalse(self.output.exists())

    def test_unsafe_version_cannot_escape_output_folder(self):
        path = self.sources / 'app.schedule/module.json'
        definition = json.loads(path.read_text())
        definition['manifest']['version'] = '../../outside'
        path.write_text(json.dumps(definition))
        with self.assertRaises(ValueError):
            update.prepare_modules(['app.schedule'], self.output)

    def test_reviewed_update_routes_downloads_verifies_digest_and_keeps_other_modules(self):
        emulator = FakeEmulator()
        result = update.update_modules(['app.schedule'], emulator, self.output)
        self.assertEqual(result[0]['version'], '1.7.0')
        taps = [call[1] for call in emulator.calls if call[0] == 'tap']
        self.assertEqual(taps, ['导入 .xmodule', '列表视图', '显示根目录', '下载',
                                'app.schedule-1.7.0.xmodule', '确认安装'])
        self.assertEqual(len([call for call in emulator.calls if call[0] == 'push']), 1)
        self.assertFalse(any('uninstall' in call for call in emulator.calls))

    def test_new_or_missing_permissions_stay_on_review_without_confirmation_or_restart(self):
        for permissions in ['network', '']:
            with self.subTest(permissions=permissions):
                emulator = FakeEmulator(permission=permissions)
                with self.assertRaisesRegex(RuntimeError, '新增权限'):
                    update.update_modules(['app.schedule'], emulator, self.output)
                self.assertEqual(emulator.state, 'review')
                self.assertNotIn(('tap', '确认安装'), emulator.calls)
                self.assertFalse(any('force-stop' in call for call in emulator.calls))

    def test_digest_mismatch_never_confirms(self):
        emulator = FakeEmulator(bad_digest=True)
        with self.assertRaisesRegex(RuntimeError, '摘要'):
            update.update_modules(['app.schedule'], emulator, self.output)
        self.assertNotIn(('tap', '确认安装'), emulator.calls)

    def test_same_version_noop_is_reported_without_claiming_new_install(self):
        emulator = FakeEmulator(already_installed=True)
        result = update.update_modules(['app.schedule'], emulator, self.output)
        self.assertEqual(result[0]['status'], 'already-installed')
        self.assertEqual(result[0]['installedSha256'], result[0]['sha256'])
        self.assertNotIn(('tap', '确认安装'), emulator.calls)

    def test_same_version_changed_source_fails_with_instruction_to_increase_version(self):
        emulator = FakeEmulator(already_installed=True, stored_digest='different')
        with self.assertRaisesRegex(RuntimeError, '请提升 module.json'):
            update.update_modules(['app.schedule'], emulator, self.output)
        self.assertEqual(emulator.state, 'details')
        self.assertFalse(any('force-stop' in call for call in emulator.calls))

    def test_same_version_missing_stored_digest_does_not_report_success(self):
        emulator = FakeEmulator(already_installed=True, stored_digest='missing')
        with self.assertRaisesRegex(RuntimeError, '无法读取已安装模块 SHA-256'):
            update.update_modules(['app.schedule'], emulator, self.output)

    def test_same_version_wrong_module_identity_does_not_report_success(self):
        emulator = FakeEmulator(already_installed=True, stored_id='app.other')
        with self.assertRaisesRegex(RuntimeError, 'ID 或版本不一致'):
            update.update_modules(['app.schedule'], emulator, self.output)

    def test_wrong_installed_version_does_not_report_success(self):
        emulator = FakeEmulator(bad_version=True)
        with self.assertRaisesRegex(RuntimeError, '未核对到'):
            update.update_modules(['app.schedule'], emulator, self.output)
        self.assertFalse(any('force-stop' in call for call in emulator.calls))

    def test_host_error_after_confirmation_cannot_be_mistaken_for_same_version_success(self):
        emulator = FakeEmulator()
        visible = emulator.visible_labels

        def with_error():
            labels = visible()
            return labels + ['Bad state: Cannot activate module'] if emulator.state == 'installed' else labels

        emulator.visible_labels = with_error
        with self.assertRaisesRegex(RuntimeError, '宿主拒绝'):
            update.update_modules(['app.schedule'], emulator, self.output)
        self.assertFalse(any('force-stop' in call for call in emulator.calls))

    def test_empty_selection_does_not_touch_device(self):
        emulator = FakeEmulator()
        self.assertEqual(update.update_modules([], emulator, self.output), [])
        self.assertEqual(emulator.calls, [])


if __name__ == '__main__':
    unittest.main()
