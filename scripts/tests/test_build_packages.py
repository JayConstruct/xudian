"""Default selection, immutable preflight and source-package boundaries."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    'build_packages', Path(__file__).resolve().parents[1] / 'module_host/build_packages.py')
packer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packer)


class BuildPackagesTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.modules = self.root / 'modules'
        self.output = self.root / 'dist/modules'
        self.assets = self.root / 'client/assets/modules'
        self.assets.mkdir(parents=True)
        self.catalog = self.assets / 'catalog.json'
        self.archive = self.root / 'dist/bundle-archive'
        self.catalog.write_text(json.dumps([
            {'id': 'app.first', 'asset': 'assets/modules/app.first-0.9.0.xmodule',
             'sha256': 'old', 'default': False},
            {'id': 'app.second', 'asset': 'assets/modules/app.second-0.9.0.xmodule',
             'sha256': 'old', 'default': True}]))
        for module_id in ('app.first', 'app.second', 'app.schedule', 'app.import.shiguang'):
            folder = self.modules / module_id
            folder.mkdir(parents=True)
            (folder / 'module.json').write_text(json.dumps({
                'formatVersion': 3, 'manifest': {'id': module_id, 'version': '1.0.0',
                                              'defaultInstall': module_id != 'app.second'}}))
            (folder / 'main.js').write_text('export default {};')

    def build(self):
        return packer.build_modules(self.modules, self.output, self.catalog, self.archive)

    def test_defaults_preserve_selection_flags_and_use_only_versioned_assets(self):
        self.build()
        entries = json.loads(self.catalog.read_text())
        self.assertEqual(['app.first', 'app.second'], [entry['id'] for entry in entries])
        self.assertEqual([False, True], [entry['default'] for entry in entries])
        self.assertEqual({'app.first-1.0.0.xmodule', 'app.second-1.0.0.xmodule'},
                         {path.name for path in self.assets.glob('*.xmodule')})
        self.assertEqual(4, len(list(self.output.glob('*.xmodule'))))
        self.assertEqual(2, len(packer.validate_bundle(self.catalog, self.assets)))

    def test_later_immutable_conflict_leaves_catalog_all_assets_and_outputs_untouched(self):
        conflicting = self.assets / 'app.second-1.0.0.xmodule'
        conflicting.write_bytes(b'existing immutable package')
        original_catalog = self.catalog.read_bytes()
        with self.assertRaisesRegex(ValueError, 'immutable'):
            self.build()
        self.assertEqual(original_catalog, self.catalog.read_bytes())
        self.assertEqual(b'existing immutable package', conflicting.read_bytes())
        self.assertFalse((self.assets / 'app.first-1.0.0.xmodule').exists())
        self.assertFalse(self.output.exists())

    def test_same_version_change_is_refused_but_identical_rerun_succeeds(self):
        self.build()
        self.build()
        original = {p.name: p.read_bytes() for p in self.assets.iterdir()}
        (self.modules / 'app.second/main.js').write_text('export default {changed:true};')
        with self.assertRaisesRegex(ValueError, 'immutable'):
            self.build()
        self.assertEqual(original, {p.name: p.read_bytes() for p in self.assets.iterdir()})

    def test_version_upgrade_archives_old_bytes_and_leaves_only_pinned_assets(self):
        self.build()
        old = self.assets / 'app.first-1.0.0.xmodule'
        original = old.read_bytes()
        definition_path = self.modules / 'app.first/module.json'
        definition = json.loads(definition_path.read_text())
        definition['manifest']['version'] = '1.0.1'
        definition_path.write_text(json.dumps(definition))
        self.build()
        self.assertFalse(old.exists())
        self.assertEqual(original, (self.archive / old.name).read_bytes())
        self.assertEqual({'app.first-1.0.1.xmodule', 'app.second-1.0.0.xmodule'},
                         packer.validate_bundle(self.catalog, self.assets))
        self.assertFalse(json.loads(self.catalog.read_text())[0]['default'])

    def test_archive_collision_rejects_whole_update_and_identical_archive_is_reused(self):
        self.build()
        old = self.assets / 'app.first-1.0.0.xmodule'
        self.archive.mkdir(parents=True)
        archived = self.archive / old.name
        archived.write_bytes(b'different archive bytes')
        definition_path = self.modules / 'app.first/module.json'
        definition = json.loads(definition_path.read_text())
        definition['manifest']['version'] = '1.0.1'
        definition_path.write_text(json.dumps(definition))
        before = {p.relative_to(self.root): p.read_bytes() for directory in
                  (self.assets, self.output, self.archive) for p in directory.iterdir()}
        with self.assertRaisesRegex(ValueError, 'archive is immutable'):
            self.build()
        self.assertEqual(before, {p.relative_to(self.root): p.read_bytes() for directory in
                                 (self.assets, self.output, self.archive) for p in directory.iterdir()})
        archived.write_bytes(old.read_bytes())
        self.build()
        self.assertFalse(old.exists())
        packer.validate_bundle(self.catalog, self.assets)

    def test_invalid_later_source_writes_nothing(self):
        (self.modules / 'app.second/package.json').write_text('{}')
        original = self.catalog.read_bytes()
        with self.assertRaisesRegex(ValueError, 'generated'):
            self.build()
        self.assertEqual(original, self.catalog.read_bytes())
        self.assertFalse(list(self.assets.glob('*.xmodule')))
        self.assertFalse(self.output.exists())

    def test_symlink_and_local_generated_files_are_rejected_before_output(self):
        folder = self.modules / 'app.first'
        link = folder / 'linked.js'
        link.symlink_to(folder / 'main.js')
        with self.assertRaisesRegex(ValueError, 'symlinks'):
            self.build()
        link.unlink()
        for name in ('.env', '__pycache__/cache.pyc', 'node_modules/dependency.js', 'native.so', 'debug.log'):
            with self.subTest(name=name):
                path = folder / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('local generated data')
                with self.assertRaisesRegex(ValueError, 'Unsafe package path'):
                    self.build()
                path.unlink()
        self.assertFalse(self.output.exists())

    def test_bundle_validation_rejects_changed_bytes_and_unreferenced_packages(self):
        self.build()
        extra = self.assets / 'app.first.xmodule'
        extra.write_bytes(b'old unversioned asset')
        with self.assertRaisesRegex(ValueError, 'Unreferenced'):
            packer.validate_bundle(self.catalog, self.assets)
        packer.validate_bundle(self.catalog, self.assets, allow_unreferenced=True)
        extra.unlink()
        (self.assets / 'app.first-1.0.0.xmodule').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'digest mismatch'):
            packer.validate_bundle(self.catalog, self.assets)

    def test_archive_directory_or_parent_file_rejects_upgrade_before_writing(self):
        for parent_file in (False, True):
            with self.subTest(parent_file=parent_file):
                self.build()
                definition_path = self.modules / 'app.first/module.json'
                definition = json.loads(definition_path.read_text())
                definition['manifest']['version'] = '1.0.1'
                definition_path.write_text(json.dumps(definition))
                blocked = self.root / ('blocked-parent' if parent_file else 'blocked-archive')
                blocked.write_bytes(b'ordinary local file')
                archive_dir = blocked / 'nested/archive' if parent_file else blocked
                before = {p.relative_to(self.root): p.read_bytes() for directory in
                          (self.assets, self.output) for p in directory.iterdir()}
                with self.assertRaisesRegex(ValueError, 'parent must be a directory'):
                    packer.build_modules(self.modules, self.output, self.catalog, archive_dir)
                self.assertEqual(before, {p.relative_to(self.root): p.read_bytes() for directory in
                                         (self.assets, self.output) for p in directory.iterdir()})
                definition['manifest']['version'] = '1.0.0'
                definition_path.write_text(json.dumps(definition))

    def test_identical_asset_symlink_is_rejected_by_builder_and_validator(self):
        self.build()
        asset = self.assets / 'app.first-1.0.0.xmodule'
        outside = self.root / 'outside.xmodule'
        outside.write_bytes(asset.read_bytes())
        asset.unlink()
        asset.symlink_to(outside)
        original_catalog = self.catalog.read_bytes()
        with self.assertRaisesRegex(ValueError, 'symlinks'):
            self.build()
        with self.assertRaisesRegex(ValueError, 'symlinks'):
            packer.validate_bundle(self.catalog, self.assets)
        self.assertEqual(original_catalog, self.catalog.read_bytes())

    def test_identical_archive_destination_symlink_rejects_upgrade_before_writing(self):
        self.build()
        old = self.assets / 'app.first-1.0.0.xmodule'
        self.archive.mkdir(parents=True)
        (self.archive / old.name).symlink_to(old)
        definition_path = self.modules / 'app.first/module.json'
        definition = json.loads(definition_path.read_text())
        definition['manifest']['version'] = '1.0.1'
        definition_path.write_text(json.dumps(definition))
        before = {p.relative_to(self.root): p.read_bytes() for directory in
                  (self.assets, self.output) for p in directory.iterdir()}
        with self.assertRaisesRegex(ValueError, 'archive cannot contain symlinks'):
            self.build()
        self.assertEqual(before, {p.relative_to(self.root): p.read_bytes() for directory in
                                 (self.assets, self.output) for p in directory.iterdir()})


if __name__ == '__main__':
    unittest.main()
