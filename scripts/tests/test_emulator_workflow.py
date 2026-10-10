import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('workflow', Path(__file__).resolve().parents[1] / 'emulator_workflow.py')
workflow = importlib.util.module_from_spec(spec)
spec.loader.exec_module(workflow)


class WorkflowTest(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.root = Path(folder.name)

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def test_build_inputs_detect_native_dependency_assets_and_source_changes(self):
        for name in ['client/lib/app.dart', 'client/android/app/src/main/AndroidManifest.xml',
                     'client/assets/catalog.json', 'client/pubspec.lock']:
            with self.subTest(name=name):
                self.write(name, 'before')
                before = workflow.snapshot(self.root)
                self.write(name, 'after')
                after = workflow.snapshot(self.root)
                self.assertNotEqual(workflow.fingerprint(before), workflow.fingerprint(after))
                self.assertEqual(workflow.changed_files(before, after), [name])

    def test_outputs_docs_and_tests_do_not_trigger_apk_rebuild(self):
        self.write('client/lib/app.dart', 'source')
        before = workflow.snapshot(self.root)
        for name in ['client/android/local.properties', 'client/android/.gradle/cache',
                     'client/build/app.apk', 'client/test/host_ui_test.dart', 'docs/note.md']:
            self.write(name, 'generated or non-APK file')
        self.assertEqual(workflow.snapshot(self.root), before)

    def test_test_changes_invalidate_checks_without_invalidating_apk(self):
        self.write('client/test/host_ui_test.dart', 'before')
        before = workflow.checks_fingerprint(self.root, {}, ['test/host_ui_test.dart'])
        self.write('client/test/host_ui_test.dart', 'after')
        self.assertNotEqual(workflow.checks_fingerprint(self.root, {}, ['test/host_ui_test.dart']), before)

    def test_reuse_rejects_corruption_lower_version_and_other_modes(self):
        apk = self.write('artifact.apk', 'apk')
        cache = {'fingerprint': 'source', 'mode': 'release', 'versionCode': 4044,
                 'apk': 'artifact.apk', 'apkSha256': hashlib.sha256(apk.read_bytes()).hexdigest()}
        self.assertTrue(workflow.reusable(cache, 'source', 'release', 4044, self.root))
        self.assertFalse(workflow.reusable(cache, 'new source', 'release', 4044, self.root))
        self.assertFalse(workflow.reusable(cache, 'source', 'debug', 4044, self.root))
        self.assertFalse(workflow.reusable(cache, 'source', 'release', 4045, self.root))
        apk.write_text('corrupted')
        self.assertFalse(workflow.reusable(cache, 'source', 'release', 4044, self.root))

    def test_core_changes_expand_checks_and_module_mode_stays_targeted(self):
        self.assertIsNone(workflow.select_tests(['client/lib/data/app_database.dart']))
        self.assertIsNone(workflow.select_tests(['client/pubspec.lock']))
        chosen = workflow.select_tests(['client/lib/app/app_shell.dart'])
        self.assertIn('test/schedule_layout_test.dart', chosen)
        self.assertIn('test/ui_pack_chrome_test.dart', chosen)
        chosen = workflow.select_tests(['client/lib/data/app_database.dart'], ['app.schedule'], first_run=True)
        self.assertIsNotNone(chosen)
        self.assertIn('test/schedule_ux_test.dart', chosen)
        self.assertIsNone(workflow.select_tests([], ['unknown.module']))


if __name__ == '__main__':
    unittest.main()
