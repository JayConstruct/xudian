import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location(
    'repository_check', Path(__file__).resolve().parents[1] / 'check_repository.py')
repository = importlib.util.module_from_spec(spec)
spec.loader.exec_module(repository)


class RepositoryTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.bundle = self.root / 'client/assets/modules/app.test-1.0.0.xmodule'
        self.bundle.parent.mkdir(parents=True)
        source = self.root / 'source'
        source.mkdir()
        (source / 'module.json').write_text(json.dumps({
            'formatVersion': 3, 'manifest': {'id': 'app.test', 'version': '1.0.0'}}))
        (source / 'main.js').write_text('export default {};')
        repository.packer.pack(source, self.bundle)
        (self.bundle.parent / 'catalog.json').write_text(json.dumps([{
            'id': 'app.test', 'asset': 'assets/modules/' + self.bundle.name,
            'sha256': hashlib.sha256(self.bundle.read_bytes()).hexdigest(), 'default': True}]))
        self.release = self.root / 'releases/modules' / self.bundle.name
        self.release.parent.mkdir(parents=True)
        self.release.write_bytes(self.bundle.read_bytes())
        indexes = self.root / 'module-index'
        indexes.mkdir()
        (indexes / 'app.test.json').write_text(json.dumps({
            'moduleId': 'app.test', 'versions': [{'version': '1.0.0',
            'url': 'https://github.com/Author/repo/releases/download/modules-test/' + self.bundle.name}]}))
        self.tracked = [file.relative_to(self.root).as_posix() for file in self.root.rglob('*') if file.is_file()]

    def test_only_catalog_referenced_packages_pass(self):
        self.assertEqual(repository.check_repository(self.root, self.tracked), [])

    def test_force_tracked_local_artifacts_are_rejected(self):
        for name in ['client/build/app.apk', 'delivery.apk', '.env.production',
                     'client/android/local.properties', 'dist/report.json', 'user.sqlite']:
            with self.subTest(name=name):
                errors = repository.check_repository(self.root, self.tracked + [name])
                self.assertTrue(any('Local-only file' in error for error in errors))

    def test_ignored_unversioned_bundle_is_detected_before_apk_build(self):
        (self.bundle.parent / 'app.test.xmodule').write_bytes(self.bundle.read_bytes())
        errors = repository.check_repository(self.root, self.tracked)
        self.assertTrue(any('Unreferenced bundled packages' in error for error in errors))

    def test_corrupted_bundle_is_rejected(self):
        with zipfile.ZipFile(self.bundle, 'a') as archive:
            archive.writestr('unreviewed.js', 'changed')
        self.assertTrue(any('digest mismatch' in error for error in
                            repository.check_repository(self.root, self.tracked)))

    def test_missing_indexed_release_and_orphan_release_are_detected(self):
        self.release.rename(self.release.with_name('app.orphan-1.0.0.xmodule'))
        errors = repository.check_repository(self.root, self.tracked)
        self.assertTrue(any('Missing indexed release' in error for error in errors))
        self.assertTrue(any('Unreferenced release' in error for error in errors))


if __name__ == '__main__':
    unittest.main()
