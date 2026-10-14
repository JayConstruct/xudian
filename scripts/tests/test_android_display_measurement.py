import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import Mock

path = Path(__file__).resolve().parents[1] / 'module_host/measure_android_display.py'
spec = importlib.util.spec_from_file_location('measure_android_display', path)
measure = importlib.util.module_from_spec(spec)
spec.loader.exec_module(measure)


class DisplayMeasurementTest(unittest.TestCase):
    def runner(self, values):
        def run(command, **kwargs):
            self.assertEqual(command[:6], ['adb', '-P', '5037', '-s', 'device', 'shell'])
            self.assertTrue(kwargs['check'])
            key = tuple(command[6:])
            self.assertIn(key, values)  # Every command must be a declared read.
            value = values[key]
            if isinstance(value, Exception):
                raise value
            return subprocess.CompletedProcess(command, 0, value, '')
        return run

    def collect(self, extra=None):
        values = {
            ('wm', 'size'): 'Physical size: 1080x2400',
            ('wm', 'density'): 'Physical density: 420',
            ('settings', 'get', 'system', 'font_scale'): '1.0',
            ('getprop', 'ro.product.model'): 'test-model',
            ('getprop', 'ro.build.version.release'): '17',
            ('getprop', 'ro.product.cpu.abi'): 'x86_64',
            ('getprop', 'persist.sys.timezone'): 'GMT',
            ('dumpsys', 'activity', 'activities'):
                'packageName=dev.taskapp.task_app processName=dev.taskapp.task_app\n'
                'CurrentConfiguration={1.0 sw411dp w411dp h914dp 420dpi}',
        }
        values.update(extra or {})
        return measure.collect(['adb', '-P', '5037', '-s', 'device'],
                               'dev.taskapp.task_app', self.runner(values))

    def test_default_measurement_is_explicitly_estimated_not_flutter(self):
        result = self.collect()
        self.assertEqual(result['estimatedPixelRatio'], 2.625)
        self.assertEqual(result['estimatedLogicalDisplay']['width'], 411.429)
        self.assertEqual(result['androidAppConfiguration']['logicalWidthDp'], 411)
        self.assertEqual(result['systemFontScale'], 1)
        self.assertIsNone(result['flutterView'])
        self.assertFalse(result['deviceSettingsChanged'])
        self.assertEqual(result['failedReads'], [])

    def test_overrides_are_distinct_and_use_effective_values(self):
        result = self.collect({
            ('wm', 'size'): 'Physical size: 1080x2400\nOverride size: 720x1600',
            ('wm', 'density'): 'Physical density: 420\nOverride density: 320',
            ('settings', 'get', 'system', 'font_scale'): '1.5',
        })
        self.assertEqual(result['screenPixels']['physical']['width'], 1080)
        self.assertEqual(result['estimatedPixelRatio'], 2)
        self.assertEqual(result['estimatedLogicalDisplay']['width'], 360)
        self.assertEqual(result['systemFontScale'], 1.5)

    def test_unknown_or_failed_values_never_become_fake_defaults(self):
        result = self.collect({
            ('wm', 'density'): subprocess.TimeoutExpired('adb', 20),
            ('settings', 'get', 'system', 'font_scale'): 'NaN',
        })
        self.assertIsNone(result['estimatedPixelRatio'])
        self.assertIsNone(result['estimatedLogicalDisplay'])
        self.assertIsNone(result['systemFontScale'])
        self.assertEqual(result['failedReads'], ['density'])

    def test_other_application_and_text_data_are_not_exported(self):
        result = self.collect({('dumpsys', 'activity', 'activities'):
            'packageName=private.app processName=private.app\n'
            'CurrentConfiguration={1.0 w999dp h999dp 300dpi}\n'
            'user-secret-draft\n'
            'packageName=dev.taskapp.task_app processName=dev.taskapp.task_app\n'
            'CurrentConfiguration={1.0 w411dp h914dp 420dpi}\n'})
        self.assertEqual(result['androidAppConfiguration']['logicalWidthDp'], 411)
        self.assertNotIn('user-secret-draft', str(result))
        self.assertNotIn('private.app', str(result))

    def test_missing_target_configuration_stays_unavailable(self):
        self.assertIsNone(measure.app_configuration(
            'packageName=other.app processName=other.app\nCurrentConfiguration={w300dp}',
            'dev.taskapp.task_app'))


if __name__ == '__main__':
    unittest.main()
