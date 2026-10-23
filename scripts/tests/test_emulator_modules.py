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
        return [ET.Element('node', text=label, bounds='[0,0][1080,2400]')
                for label in self.visible_labels()]

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


class ExpandedReviewEmulator(FakeEmulator):
    def __init__(self, *, added='无', all_permissions='ui', review_id=None,
                 action=None, dependency_added=None, missing=None, digest=None):
        super().__init__()
        self.added = added
        self.all_permissions = all_permissions
        self.review_id = review_id
        self.action = action
        self.dependency_added = dependency_added
        self.missing = missing
        self.digest = digest
        self.review_page = 0

    def detail_lines(self):
        target = ['2. 同名模块' if self.dependency_added is not None else '1. 同名模块',
                  '模块标识：' + (self.review_id or self.module['id']),
                  self.action or f'升级并启用 · 1.6.0 → {self.module["version"]}',
                  '新增权限标识：' + self.added,
                  '全部权限标识：' + self.all_permissions,
                  'SHA-256：' + (self.digest or self.module['sha256'])]
        if self.missing:
            target = [line for line in target if not line.startswith(self.missing)]
        dependency = [] if self.dependency_added is None else [
            '1. 同名模块', '模块标识：app.other', '继续使用 · 1.2.0（无需安装）',
            '新增权限标识：' + self.dependency_added,
            '全部权限标识：ui、network', 'SHA-256：' + 'b' * 64]
        return dependency + target

    def visible_labels(self):
        if self.state == 'review':
            if self.review_page == 0:
                count = 1 if self.dependency_added is None else 2
                return ['确认模块安装计划', f'升级 {count} 个', '你选择的模块',
                        self.module['name'], '权限与影响', '确认安装', '取消']
            return ['确认模块安装计划', '技术详情与完整计划', '确认安装', '取消']
        if self.state == 'expanded':
            lines = self.detail_lines()
            # The digest appears only after scrolling, with an overlapping
            # permission field that preserves the current module's ownership.
            return ['确认模块安装计划'] + (lines[:-1] if self.review_page == 0 else lines[-2:]) + [
                '确认安装', '取消']
        return super().visible_labels()

    def adb(self, *args):
        result = super().adb(*args)
        if args[:3] == ('shell', 'input', 'swipe') and self.state in ('review', 'expanded'):
            self.review_page = (0 if int(args[4]) < int(args[6]) else self.review_page + 1)
        return result

    def tap_node(self, node):
        if self.label(node) == '技术详情与完整计划':
            self.calls.append(('tap', self.label(node)))
            self.state = 'expanded'
            self.review_page = 0
        else:
            super().tap_node(node)


class BundledRestoreEmulator(FakeEmulator):
    def __init__(self, module, *, review_version=None, ambiguous=False, **kwargs):
        super().__init__(**kwargs)
        self.module = {**module, 'filename': Path(module['package']).name}
        self.review_version = review_version
        self.ambiguous = ambiguous

    def visible_labels(self):
        if self.state == 'manager':
            return ['模块管理', '导入 .xmodule', '恢复随客户端发布的模块',
                    'app.other', '安装 / 恢复', self.module['id'], '安装 / 恢复']
        labels = super().visible_labels()
        if self.state == 'review' and self.review_version:
            labels = [label.replace(f'{self.module["name"]} · {self.module["version"]}',
                                    f'{self.module["name"]} · {self.review_version}')
                      for label in labels]
        return labels

    def nodes(self):
        if self.state != 'manager':
            return super().nodes()
        nodes = [ET.Element('node', text=label, bounds=f'[0,{i * 100}][500,{i * 100 + 60}]')
                 for i, label in enumerate(self.visible_labels())]
        # Each restore button must belong to its own measured module row.
        nodes[4].set('bounds', '[600,300][1000,360]')
        nodes[4].set('module', 'app.other')
        nodes[6].set('bounds', '[600,500][1000,560]')
        nodes[6].set('module', self.module['id'])
        if self.ambiguous:
            nodes.append(ET.Element('node', text='安装 / 恢复',
                                    bounds='[700,500][1000,560]', module='app.other'))
        return nodes

    def tap_node(self, node):
        if self.label(node) == '安装 / 恢复':
            self.calls.append(('restore', node.get('module')))
            if node.get('module') != self.module['id']:
                raise AssertionError('恢复按钮属于其他模块')
            self.state = 'installed' if self.already_installed else 'review'
        else:
            super().tap_node(node)


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

    def pin_bundled(self):
        module = update.prepare_modules(['app.schedule'], self.output)[0]
        catalog = self.root / 'client/assets/modules/catalog.json'
        catalog.parent.mkdir(parents=True)
        catalog.write_text(json.dumps([{'id': module['id'], 'sha256': module['sha256'],
                                       'asset': 'assets/modules/current.xmodule'}]))
        return module

    def test_bundled_pin_uses_its_restore_row_without_local_import_and_verifies_installed_digest(self):
        module = self.pin_bundled()
        emulator = BundledRestoreEmulator(module)
        result = update.update_modules([module['id']], emulator, self.output)[0]
        self.assertEqual(result['installationSource'], 'bundled')
        self.assertEqual(result['installedSha256'], module['sha256'])
        self.assertIn(('restore', module['id']), emulator.calls)
        self.assertIn(('tap', '确认安装'), emulator.calls)
        self.assertNotIn(('tap', '导入 .xmodule'), emulator.calls)
        self.assertFalse(any(call[0] == 'push' for call in emulator.calls))

    def test_source_bundled_pin_mismatch_rejects_before_touching_device(self):
        module = self.pin_bundled()
        (self.sources / module['id'] / 'main.js').write_text('export function changed() {}')
        emulator = FakeEmulator()
        with self.assertRaisesRegex(RuntimeError, '预装 pin 不一致'):
            update.update_modules([module['id']], emulator, self.output)
        self.assertEqual(emulator.calls, [])

    def test_stale_apk_bundle_version_or_digest_is_never_confirmed(self):
        module = self.pin_bundled()
        for kwargs in ({'review_version': '1.6.0'}, {'bad_digest': True}):
            with self.subTest(kwargs=kwargs):
                emulator = BundledRestoreEmulator(module, **kwargs)
                with self.assertRaisesRegex(RuntimeError, '版本或摘要'):
                    update.update_modules([module['id']], emulator, self.output)
                self.assertNotIn(('tap', '确认安装'), emulator.calls)
                self.assertNotIn(('tap', '导入 .xmodule'), emulator.calls)

    def test_bundled_restore_still_requires_exact_added_permission_authorization(self):
        module = self.pin_bundled()
        emulator = BundledRestoreEmulator(module, permission='network')
        with self.assertRaisesRegex(RuntimeError, '未授权新增权限'):
            update.update_modules([module['id']], emulator, self.output)
        self.assertNotIn(('tap', '确认安装'), emulator.calls)

    def test_bundled_install_checks_stored_digest_after_a_successful_review(self):
        module = self.pin_bundled()
        emulator = BundledRestoreEmulator(module, stored_digest='different')
        with self.assertRaisesRegex(RuntimeError, '摘要不同'):
            update.update_modules([module['id']], emulator, self.output)
        self.assertIn(('tap', '确认安装'), emulator.calls)

    def test_ambiguous_restore_button_ownership_never_clicks_either_button(self):
        module = self.pin_bundled()
        emulator = BundledRestoreEmulator(module, ambiguous=True)
        with self.assertRaisesRegex(RuntimeError, '归属不明确'):
            update.update_modules([module['id']], emulator, self.output)
        self.assertFalse(any(call[0] == 'restore' for call in emulator.calls))

    def test_bundled_same_package_noop_still_verifies_digest(self):
        module = self.pin_bundled()
        emulator = BundledRestoreEmulator(module, already_installed=True)
        result = update.update_modules([module['id']], emulator, self.output)[0]
        self.assertEqual(result['status'], 'already-installed')
        self.assertEqual(result['installedSha256'], module['sha256'])
        self.assertNotIn(('tap', '确认安装'), emulator.calls)

    def test_bundled_digest_dialog_can_close_when_import_button_is_scrolled_offscreen(self):
        class ScrolledManager(BundledRestoreEmulator):
            def visible_labels(self):
                labels = super().visible_labels()
                if self.state == 'installed':
                    return [label for label in labels if label != '导入 .xmodule']
                return labels

        module = self.pin_bundled()
        result = update.update_modules([module['id']], ScrolledManager(module), self.output)[0]
        self.assertEqual(result['installedSha256'], module['sha256'])

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
        self.assertFalse(any('force-stop' in call for call in emulator.calls))

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

    def test_same_version_waits_until_details_dismissal_finishes(self):
        class ClosingDetails(FakeEmulator):
            closing_reads = 0

            def tap_node(self, node):
                closing = self.label(node) == '关闭'
                super().tap_node(node)
                if closing:
                    self.state = 'closing'

            def visible_labels(self):
                if self.state == 'closing':
                    self.closing_reads += 1
                    if self.closing_reads < 3:
                        return ['关闭', '模块 ID', 'app.schedule']
                    self.state = 'installed'
                return super().visible_labels()

        emulator = ClosingDetails(already_installed=True)
        result = update.update_modules(['app.schedule'], emulator, self.output)
        self.assertEqual(emulator.closing_reads, 3)
        self.assertEqual(emulator.state, 'installed')
        self.assertEqual(result[0]['status'], 'already-installed')

    def test_same_version_closes_button_instead_of_full_screen_scrim(self):
        class DuplicateClose(FakeEmulator):
            def nodes(self):
                nodes = super().nodes()
                if self.state == 'details':
                    for node in nodes:
                        if self.label(node) == '关闭':
                            node.set('class', 'android.widget.Button')
                    nodes.append(ET.Element('node', text='关闭', **{
                        'class': 'android.view.View', 'bounds': '[0,0][1080,2400]',
                    }))
                return nodes

            def tap_node(self, node):
                if self.label(node) == '关闭':
                    assert node.get('class') == 'android.widget.Button'
                super().tap_node(node)

        result = update.update_modules(['app.schedule'], DuplicateClose(already_installed=True), self.output)
        self.assertEqual(result[0]['status'], 'already-installed')

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

    def test_expanded_plan_checks_id_target_version_digest_after_scrolling_without_restart(self):
        emulator = ExpandedReviewEmulator()
        result = update.update_modules(['app.schedule'], emulator, self.output)
        self.assertEqual(result[0]['status'], 'installed')
        taps = [call[1] for call in emulator.calls if call[0] == 'tap']
        self.assertLess(taps.index('技术详情与完整计划'), taps.index('确认安装'))
        self.assertGreaterEqual(sum(call[:3] == ('shell', 'input', 'swipe')
                                    for call in emulator.calls), 2)
        self.assertFalse(any('force-stop' in call for call in emulator.calls))

    def test_new_permission_requires_explicit_exact_authorization(self):
        for allowed in (set(), {'clock.today'}):
            with self.subTest(allowed=allowed):
                emulator = ExpandedReviewEmulator(added='clock.today', all_permissions='ui、clock.today')
                if allowed:
                    result = update.update_modules(['app.schedule'], emulator, self.output,
                                                   allowed_added_permissions=allowed)
                    self.assertEqual(result[0]['status'], 'installed')
                else:
                    with self.assertRaisesRegex(RuntimeError, '未授权新增权限'):
                        update.update_modules(['app.schedule'], emulator, self.output)
                    self.assertNotIn(('tap', '确认安装'), emulator.calls)

    def test_authorized_subset_does_not_authorize_additional_permissions(self):
        emulator = ExpandedReviewEmulator(added='clock.today、network',
                                         all_permissions='ui、clock.today、network')
        with self.assertRaisesRegex(RuntimeError, '未授权新增权限'):
            update.update_modules(['app.schedule'], emulator, self.output,
                                  allowed_added_permissions={'clock.today'})
        self.assertNotIn(('tap', '确认安装'), emulator.calls)

    def test_unknown_or_incomplete_permission_fields_never_confirm(self):
        for value in ['', 'clock.today…', 'clock.today、', 'clock.today...',
                      'clock.today\nnetwork', 'clock.today ']:
            with self.subTest(value=value):
                emulator = ExpandedReviewEmulator(added=value, all_permissions='ui、clock.today')
                with self.assertRaisesRegex(RuntimeError, '权限字段'):
                    update.update_modules(['app.schedule'], emulator, self.output,
                                          allowed_added_permissions={'clock.today'})
                self.assertNotIn(('tap', '确认安装'), emulator.calls)

    def test_added_permissions_must_exist_in_complete_permission_list(self):
        emulator = ExpandedReviewEmulator(added='clock.today', all_permissions='ui')
        with self.assertRaisesRegex(RuntimeError, '权限字段不一致'):
            update.update_modules(['app.schedule'], emulator, self.output,
                                  allowed_added_permissions={'clock.today'})
        self.assertNotIn(('tap', '确认安装'), emulator.calls)

    def test_missing_full_permission_or_digest_fields_never_confirm(self):
        for missing in ('全部权限标识：', '新增权限标识：', 'SHA-256：'):
            with self.subTest(missing=missing):
                emulator = ExpandedReviewEmulator(missing=missing)
                with self.assertRaisesRegex(RuntimeError, '不完整'):
                    update.update_modules(['app.schedule'], emulator, self.output)
                self.assertNotIn(('tap', '确认安装'), emulator.calls)

    def test_target_identity_version_and_digest_must_match_package(self):
        for kwargs in [{'review_id': 'app.other'}, {'digest': '0' * 64},
                       {'action': '升级并启用 · 1.7.0 → 1.8.0'},
                       {'action': '安装并启用 · 1.7.01'}]:
            with self.subTest(kwargs=kwargs):
                emulator = ExpandedReviewEmulator(**kwargs)
                with self.assertRaisesRegex(RuntimeError, 'ID、版本或摘要'):
                    update.update_modules(['app.schedule'], emulator, self.output)
                self.assertNotIn(('tap', '确认安装'), emulator.calls)

    def test_dependencies_with_same_name_are_checked_by_id_and_permissions(self):
        for dependency_added in ('无', 'network'):
            with self.subTest(dependency_added=dependency_added):
                emulator = ExpandedReviewEmulator(dependency_added=dependency_added)
                if dependency_added == '无':
                    self.assertEqual(update.update_modules(['app.schedule'], emulator, self.output)[0]['status'],
                                     'installed')
                else:
                    with self.assertRaisesRegex(RuntimeError, '未授权新增权限'):
                        update.update_modules(['app.schedule'], emulator, self.output,
                                              allowed_added_permissions={'clock.today'})
                    self.assertNotIn(('tap', '确认安装'), emulator.calls)

    def test_invalid_permission_authorization_is_rejected_before_device_access(self):
        for authorization in ('clock.today', {'clock.today…'}, {'clock.today、network'}, {None}):
            with self.subTest(authorization=authorization):
                emulator = FakeEmulator()
                with self.assertRaises(ValueError):
                    update.update_modules(['app.schedule'], emulator, self.output,
                                          allowed_added_permissions=authorization)
                self.assertEqual(emulator.calls, [])

    def test_swipe_uses_measured_scrollable_bounds_and_direction(self):
        for width, height in ((320, 640), (1080, 2400)):
            with self.subTest(size=(width, height)):
                emulator = FakeEmulator()
                node = ET.Element('node', bounds=f'[0,0][{width},{height}]', scrollable='true')
                update._swipe(emulator, [node])
                update._swipe(emulator, [node], down=False)
                upper, lower = str(int(height * .35)), str(int(height * .65))
                x = str(width // 2)
                self.assertEqual(emulator.calls, [
                    ('shell', 'input', 'swipe', x, lower, x, upper, '250'),
                    ('shell', 'input', 'swipe', x, upper, x, lower, '250')])

    def test_missing_screen_measurements_refuse_fixed_coordinate_swipe(self):
        emulator = FakeEmulator()
        with self.assertRaisesRegex(RuntimeError, '尺寸'):
            update._swipe(emulator, [ET.Element('node', text='内容')])
        self.assertEqual(emulator.calls, [])

    def test_unknown_full_plan_count_never_confirms(self):
        emulator = ExpandedReviewEmulator()
        visible = emulator.visible_labels

        def without_count():
            return [line for line in visible() if line != '升级 1 个']

        emulator.visible_labels = without_count
        with self.assertRaisesRegex(RuntimeError, '模块数量'):
            update.update_modules(['app.schedule'], emulator, self.output)
        self.assertNotIn(('tap', '确认安装'), emulator.calls)

    def test_open_picker_drawer_hides_matching_file_until_download_root_is_selected(self):
        class DrawerEmulator(FakeEmulator):
            def __init__(self, *, persistent=False):
                super().__init__()
                self.module = {'filename': 'app.schedule-1.7.0.xmodule'}
                self.state = 'roots'
                self.pending = 0
                self.persistent = persistent

            def nodes(self):
                if self.state == 'roots' or self.pending or self.persistent:
                    if self.pending:
                        self.pending -= 1
                    hidden = ET.Element('node', text=self.module['filename'],
                                        bounds='[100,300][800,450]')
                    drawer = ET.Element('node', text='',
                                        **{'resource-id': 'com.android.documentsui:id/roots_list',
                                           'bounds': '[0,0][700,2400]'})
                    root = ET.SubElement(drawer, 'node', text='下载', selected='true',
                                         bounds='[0,200][700,350]')
                    toolbar = ET.Element('node', text='打开文档', bounds='[0,0][700,150]')
                    return [hidden, toolbar, drawer, root]
                return super().nodes()

            def tap_node(self, node):
                if self.label(node) == self.module['filename'] and (self.state == 'roots' or self.pending):
                    raise AssertionError('不可点击抽屉后被遮挡的文件')
                super().tap_node(node)
                if self.label(node) == '下载':
                    self.pending = 2

        emulator = DrawerEmulator()
        update._select_download(emulator, emulator.module['filename'])
        self.assertEqual([call for call in emulator.calls if call[0] == 'tap'], [
            ('tap', '下载'), ('tap', 'app.schedule-1.7.0.xmodule')])
        self.assertNotIn(('tap', '打开文档'), emulator.calls)
        blocked = DrawerEmulator(persistent=True)
        with self.assertRaisesRegex(RuntimeError, '抽屉未关闭'):
            update._select_download(blocked, blocked.module['filename'])
        self.assertEqual(blocked.calls, [('tap', '下载')])

    def test_no_overlap_does_not_invent_permission_or_digest_ownership(self):
        emulator = ExpandedReviewEmulator()
        visible = emulator.visible_labels

        def disconnected():
            if emulator.state == 'expanded':
                first = ['模块标识：app.schedule', '升级并启用 · 1.6.0 → 1.7.0', '来源：本地模块包']
                tail = ['新增权限标识：无', '全部权限标识：ui',
                        'SHA-256：' + emulator.module['sha256']]
                return ['确认模块安装计划'] + (first if emulator.review_page == 0 else tail) + ['确认安装', '取消']
            return visible()

        emulator.visible_labels = disconnected
        with self.assertRaisesRegex(RuntimeError, '不完整'):
            update.update_modules(['app.schedule'], emulator, self.output)
        self.assertNotIn(('tap', '确认安装'), emulator.calls)

    def test_selected_download_root_drawer_can_back_only_after_breadcrumb_proof(self):
        class RetainedDrawer(FakeEmulator):
            def __init__(self, breadcrumb):
                super().__init__()
                self.state = 'roots'
                self.module = {'filename': 'app.schedule-1.7.0.xmodule'}
                self.breadcrumb = breadcrumb

            def nodes(self):
                if self.state != 'roots':
                    return super().nodes()
                drawer = ET.Element('node', text='',
                                    **{'resource-id': 'com.android.documentsui:id/drawer_roots'})
                ET.SubElement(drawer, 'node', text='下载', bounds='[0,200][700,350]')
                breadcrumb = ET.Element('node', text=self.breadcrumb,
                                        **{'resource-id': 'com.android.documentsui:id/breadcrumb_text'})
                hidden = ET.Element('node', text=self.module['filename'], bounds='[100,300][800,450]')
                return [hidden, breadcrumb, drawer]

            def tap_node(self, node):
                if self.label(node) == '下载':
                    self.calls.append(('tap', '下载'))
                else:
                    super().tap_node(node)

            def adb(self, *args):
                result = super().adb(*args)
                if args == ('shell', 'input', 'keyevent', '4'):
                    self.state = 'downloads'
                return result

        for breadcrumb in ('下载', '其他目录'):
            with self.subTest(breadcrumb=breadcrumb):
                emulator = RetainedDrawer(breadcrumb)
                if breadcrumb == '下载':
                    update._select_download(emulator, emulator.module['filename'])
                    self.assertEqual(emulator.calls, [('tap', '下载'),
                        ('shell', 'input', 'keyevent', '4'), ('tap', 'app.schedule-1.7.0.xmodule')])
                else:
                    with self.assertRaisesRegex(RuntimeError, '抽屉未关闭'):
                        update._select_download(emulator, emulator.module['filename'])
                    self.assertEqual(emulator.calls, [('tap', '下载')])

    def test_review_scan_records_real_overlap_identity_recovery(self):
        emulator = ExpandedReviewEmulator()
        result = update.update_modules(['app.schedule'], emulator, self.output)
        scan = result[0]['reviewScan']
        self.assertEqual(scan[0]['moduleIds'], ['app.schedule'])
        self.assertGreater(scan[1]['overlapFieldCount'], 0)
        self.assertEqual(scan[1]['recoveredModuleIds'], ['app.schedule'])
        swipes = [call for call in emulator.calls if call[:3] == ('shell', 'input', 'swipe')]
        self.assertTrue(any(int(call[4]) < int(call[6]) for call in swipes))

    def test_installed_checks_reset_retained_manager_scroll_before_scan_and_same_package_probe(self):
        class RetainedManagerScroll(FakeEmulator):
            def __init__(self, *, already_installed):
                super().__init__(already_installed=already_installed)
                self.at_top = False

            def visible_labels(self):
                labels = super().visible_labels()
                if self.state == 'installed' and not self.at_top:
                    notice = ('所需模块已经安装并启用' if self.already_installed else '模块安装完成')
                    return ['模块管理', '其他模块\n1.0.0 · 已启用', notice]
                return labels

            def adb(self, *args):
                result = super().adb(*args)
                if (self.state == 'installed' and args[:3] == ('shell', 'input', 'swipe')
                        and int(args[4]) < int(args[6])):
                    self.at_top = True
                return result

        for same_package in (False, True):
            with self.subTest(same_package=same_package):
                emulator = RetainedManagerScroll(already_installed=same_package)
                result = update.update_modules(['app.schedule'], emulator, self.output)
                self.assertEqual(result[0]['status'], 'already-installed' if same_package else 'installed')
                self.assertTrue(emulator.at_top)
                if same_package:
                    self.assertEqual(result[0]['installedSha256'], result[0]['sha256'])

    def test_empty_selection_does_not_touch_device(self):
        emulator = FakeEmulator()
        self.assertEqual(update.update_modules([], emulator, self.output), [])
        self.assertEqual(emulator.calls, [])


if __name__ == '__main__':
    unittest.main()
