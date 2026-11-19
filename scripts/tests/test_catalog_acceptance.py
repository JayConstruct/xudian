"""Regress the Android accessibility cases that delayed release acceptance."""
from pathlib import Path
import json
import tempfile
import unittest
from unittest.mock import Mock, patch
import xml.etree.ElementTree as ET

from scripts.module_host import verify_catalog as catalog


def node(**attributes):
    return ET.Element('node', {'bounds': '[0,0][100,50]', 'enabled': 'true', **attributes})


class CatalogAcceptanceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.emulator = Mock()
        self.flow = catalog.CatalogAcceptance(
            self.emulator, Path(self.temp.name), {'id': 'app.schedule', 'name': '大学课表'})

    def test_empty_edit_text_is_found_by_hint(self):
        search = node(text='', **{'class': 'android.widget.EditText', 'hint': '搜索模块 ID'})
        self.assertIs(catalog.find_node([search], '搜索模块 ID'), search)

    def test_close_uses_visible_button_instead_of_full_screen_dismiss_barrier(self):
        close = node(**{'class': 'android.widget.Button', 'content-desc': '关闭'})
        barrier = node(**{'class': 'android.view.View', 'content-desc': '关闭',
                          'bounds': '[0,0][1080,2400]'})
        self.assertIs(catalog.find_node([close, barrier], '关闭', button=True), close)
        self.assertIsNone(catalog.find_node([barrier], '关闭', button=True))

    def test_disabled_and_clipped_nodes_are_not_tapped(self):
        disabled = node(text='关闭', enabled='false', **{'class': 'android.widget.Button'})
        clipped = node(text='关闭', bounds='[0,210][100,210]', **{'class': 'android.widget.Button'})
        self.assertIsNone(catalog.find_node([disabled, clipped], '关闭', button=True))

    def test_expansion_tile_matches_its_combined_accessibility_label(self):
        settings = node(**{'content-desc': '商店设置, 已收起'})
        self.assertIs(catalog.find_node([settings], '商店设置', contains=True), settings)

    def test_scroll_stops_when_the_view_no_longer_moves(self):
        scrollable = node(scrollable='true')
        self.emulator.snapshot.return_value.nodes = [scrollable]
        self.emulator.bounds = catalog.emulator_ui.Emulator.bounds
        with self.assertRaisesRegex(RuntimeError, '滚动后找不到'):
            self.flow.scroll_to('商店设置')
        self.assertEqual(self.emulator.adb.call_count, 1)

    def test_unknown_switch_state_is_never_toggled(self):
        self.flow.settings_open = True
        self.flow.scroll_to = Mock(return_value=node(text='离线浏览缓存', checkable='false'))
        with self.assertRaisesRegex(RuntimeError, '无法读取离线开关状态'):
            self.flow.set_offline(True)
        self.emulator.tap_node.assert_not_called()

    def test_back_must_reach_parent_settings_after_dismissing_keyboard(self):
        self.emulator.nodes.side_effect = [
            [node(text='模块商店')], [node(text='模块管理与恢复')]]
        self.flow.tap = Mock()
        self.flow.wait_label = Mock()
        self.flow.reopen()
        self.assertEqual(self.emulator.adb.call_count, 2)
        self.flow.tap.assert_called_once_with('模块商店', contains=True)

    def test_remaining_on_storefront_cannot_count_as_a_successful_back(self):
        self.emulator.nodes.return_value = [node(text='模块商店')]
        with self.assertRaisesRegex(RuntimeError, '返回未到达'):
            self.flow.reopen()
        self.emulator.record.assert_not_called()


class CatalogEvidenceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        source = self.root / 'packages/catalog/catalog.json'
        source.parent.mkdir(parents=True)
        source.write_text(json.dumps({'modules': [{'id': 'app.schedule', 'name': '课表'}]}))
        self.build_report = self.root / '.cache/emulator-update/latest-success.json'
        self.build_report.parent.mkdir(parents=True)
        self.build_report.write_text(json.dumps({
            'completed': True, 'installedApkSha256': 'digest',
            'installedVersionCode': 4044, 'sourceFingerprint': 'source'}))

    def run_acceptance(self, arguments=(), *, failed=False):
        emulator = Mock()
        emulator.adb.return_value = 'versionName=0.2.0 versionCode=4044'
        emulator.installed_digest.return_value = 'digest'
        flow = Mock()
        flow.steps = []

        def step(name, action):
            flow.steps.append({'name': name})
            (catalog.emulator_ui.OUT / 'details.xml').write_text('<hierarchy/>')
            if failed:
                raise RuntimeError('page verification failed')

        flow.step.side_effect = step
        with patch.object(catalog, 'ROOT', self.root), \
                patch.object(catalog, 'snapshot', return_value={}), \
                patch.object(catalog, 'fingerprint', return_value='source'), \
                patch.object(catalog.emulator_ui, 'Emulator', return_value=emulator), \
                patch.object(catalog.emulator_ui, 'OUT'), \
                patch.object(catalog, 'CatalogAcceptance', return_value=flow):
            if failed:
                with self.assertRaisesRegex(RuntimeError, 'page verification failed'):
                    catalog.main(list(arguments))
            else:
                self.assertEqual(catalog.main(list(arguments)), 0)

    def test_default_runs_keep_separate_complete_evidence_directories(self):
        self.run_acceptance()
        reports = list((self.root / 'dist/verification').glob('*-catalog/results.json'))
        self.assertEqual(len(reports), 1)
        first = reports[0]
        original = first.read_text()
        report = json.loads(original)
        self.assertTrue(report['completed'])
        self.assertEqual(self.root / report['evidenceDir'], first.parent)
        self.assertRegex(first.parent.name, r'^\d{8}T\d{6}\.\d{6}Z-catalog$')
        self.assertTrue((first.parent / 'details.xml').is_file())
        self.run_acceptance()
        self.assertEqual(len(list((self.root / 'dist/verification').glob('*-catalog/results.json'))), 2)
        self.assertEqual(first.read_text(), original)

    def test_failure_keeps_report_and_recordings_together(self):
        self.run_acceptance(failed=True)
        reports = list((self.root / 'dist/verification').glob('*-catalog/results.json'))
        self.assertEqual(len(reports), 1)
        report = json.loads(reports[0].read_text())
        self.assertFalse(report['completed'])
        self.assertIn('page verification failed', report['error'])
        self.assertEqual(self.root / report['evidenceDir'], reports[0].parent)
        self.assertTrue((reports[0].parent / 'details.xml').is_file())

    def test_explicit_output_preserves_existing_report(self):
        output = self.root / 'custom'
        self.run_acceptance(['--output', str(output)])
        original = (output / 'results.json').read_text()
        with self.assertRaises(SystemExit):
            self.run_acceptance(['--output', str(output)])
        self.assertEqual((output / 'results.json').read_text(), original)

    def test_dry_run_does_not_create_output_or_connect_to_device(self):
        output = self.root / 'dry-run'
        before = sorted(str(path.relative_to(self.root)) for path in self.root.rglob('*'))
        with patch.object(catalog, 'ROOT', self.root), \
                patch.object(catalog.emulator_ui, 'Emulator') as emulator:
            self.assertEqual(catalog.main(['--dry-run', '--output', str(output)]), 0)
        emulator.assert_not_called()
        self.assertEqual(before, sorted(str(path.relative_to(self.root)) for path in self.root.rglob('*')))


if __name__ == '__main__':
    unittest.main()
