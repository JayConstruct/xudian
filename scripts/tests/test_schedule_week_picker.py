import unittest
from unittest.mock import Mock, patch

from scripts.verification import verify_schedule_week_picker as picker


class InstalledScheduleTest(unittest.TestCase):
    def read_details(self, *pages):
        emulator = Mock()
        emulator.label.side_effect = str
        # The last viewport remains visible when there is nothing left to scroll.
        row = '大学课表\n9.8.7 · 已启用'
        emulator.nodes.side_effect = [[row], *pages, *([pages[-1]] * 8)]
        self.addCleanup(emulator.adb.assert_called_with, 'shell', 'input', 'keyevent', '4')
        with patch.object(picker, '_scroll_to_top', return_value=[row]), patch.object(picker, '_swipe'):
            return picker.installed_schedule(emulator)

    def test_reports_enabled_package_from_details_across_scroll(self):
        digest = 'a' * 64
        result = self.read_details(
            ['模块 ID', 'app.schedule', '版本与状态', '9.8.7-beta.2 · 已启用'],
            ['SHA-256', digest])
        self.assertEqual(result, ('9.8.7-beta.2', digest))

    def test_rejects_wrong_identity_disabled_package_or_missing_digest(self):
        for module_id, state, digest in [
            ('app.other', '已启用', 'a' * 64),
            ('app.schedule', '已停用', 'a' * 64),
            ('app.schedule', '已启用', ''),
        ]:
            with self.subTest(module_id=module_id, state=state, digest=digest):
                with self.assertRaisesRegex(RuntimeError, '无法从同一模块详情核对'):
                    self.read_details(['模块 ID', module_id, '版本与状态',
                                       f'9.8.7 · {state}', 'SHA-256', digest])
