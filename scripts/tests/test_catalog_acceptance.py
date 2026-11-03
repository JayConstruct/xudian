"""Regress the Android accessibility cases that delayed release acceptance."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock
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
        self.emulator.bounds = catalog.verify_emulator.Emulator.bounds
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


if __name__ == '__main__':
    unittest.main()
