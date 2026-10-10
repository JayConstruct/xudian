import copy
import hashlib
import json
import pathlib
import sys
import tempfile
import unittest
import zipfile
from io import BytesIO

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from catalog import validate_catalog, validate_index, validate_package, validate_directory
from publish import prepare, bundle_catalog


class PublicationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        self.modules = self.root / 'modules'
        self.source = self.modules / 'app.test'
        self.source.mkdir(parents=True)
        self.definition = {
            'formatVersion': 3, 'manifest': {
                'id': 'app.test', 'name': '测试', 'description': '测试模块', 'author': 'Author',
                'version': '1.0.0', 'hostApi': '^1.8.0', 'dataVersion': 1,
                'permissions': ['ui'], 'dependencies': []},
            'entryPoint': 'main.js', 'collections': [], 'pages': [],
            'services': [{'id': 'test.query', 'major': 1, 'kind': 'query', 'handler': 'query', 'input': {}, 'output': {}}]}
        self.write_definition()
        (self.source / 'main.js').write_text('export function query() { return {}; }')
        self.entry = {k: self.definition['manifest'][k] for k in ('id', 'name', 'description', 'author')}
        self.entry.update(repository='Author/example', indexUrl='https://raw.githubusercontent.com/Author/example/main/module-index/app.test.json')
        self.catalog = {'catalogFormat': 1, 'modules': [self.entry]}
        self.catalog_path = self.root / 'catalog.json'
        self.catalog_path.write_text(json.dumps(self.catalog))
        self.output = self.root / 'releases'
        self.index_dir = self.root / 'indexes'

    def tearDown(self):
        self.temp.cleanup()

    def write_definition(self):
        (self.source / 'module.json').write_text(json.dumps(self.definition))

    def publish(self, tag='modules-test'):
        return prepare(self.modules, self.catalog_path, 'Author/example', tag, self.output, self.index_dir)

    def release(self):
        return json.loads((self.index_dir / 'app.test.json').read_text())['versions'][-1]

    def test_deterministic_and_full_validation(self):
        asset = self.publish()[0]
        first = asset.read_bytes()
        self.publish('different-tag')
        self.assertEqual(first, asset.read_bytes())
        self.assertIn('/modules-test/', self.release()['url'])
        validate_directory(self.catalog_path, self.index_dir, self.output)
        self.assertIsNone(self.release()['signature'])

    def test_published_version_and_asset_are_immutable(self):
        asset = self.publish()[0]
        original = asset.read_bytes()
        original_index = (self.index_dir / 'app.test.json').read_bytes()
        (self.source / 'main.js').write_text('export function query() { return {changed:true}; }')
        with self.assertRaisesRegex(ValueError, 'already published'):
            self.publish()
        self.assertEqual(original, asset.read_bytes())
        self.assertEqual(original_index, (self.index_dir / 'app.test.json').read_bytes())
        self.definition['manifest']['version'] = '1.0.1'
        self.write_definition()
        self.publish('modules-next')
        versions = json.loads((self.index_dir / 'app.test.json').read_text())['versions']
        self.assertEqual(['1.0.0', '1.0.1'], [v['version'] for v in versions])
        self.assertEqual(original, asset.read_bytes())

    def test_duplicates_and_unrelated_repository_rejected(self):
        duplicate = copy.deepcopy(self.catalog)
        duplicate['modules'].append(self.entry)
        with self.assertRaisesRegex(ValueError, 'duplicate module ID'):
            validate_catalog(duplicate)
        invalid = copy.deepcopy(self.catalog)
        invalid['modules'][0]['indexUrl'] = 'https://raw.githubusercontent.com/Other/repo/main/index.json'
        with self.assertRaisesRegex(ValueError, 'URL must be HTTPS'):
            validate_catalog(invalid)
        self.publish()
        index = json.loads((self.index_dir / 'app.test.json').read_text())
        index['versions'][0]['url'] = index['versions'][0]['url'].replace('Author/example', 'Other/repo')
        with self.assertRaisesRegex(ValueError, 'URL must be HTTPS'):
            validate_index(index, self.entry)

    def test_digest_manifest_and_services_checked(self):
        data = self.publish()[0].read_bytes()
        release = self.release()
        with self.assertRaisesRegex(ValueError, 'digest mismatch'):
            validate_package(data[:-1] + bytes([data[-1] ^ 1]), release)
        for field in ('manifest', 'services'):
            altered = copy.deepcopy(release)
            if field == 'manifest':
                altered[field]['id'] = 'app.other'
            else:
                altered[field][0]['major'] = 2
            with self.assertRaisesRegex(ValueError, 'identity mismatch'):
                validate_package(data, altered)

    def test_unsafe_zip_modes_and_unlisted_payload_rejected(self):
        data = self.publish()[0].read_bytes()
        for extra, mode in [('extra.js', 0), ('link.js', 0o120777 << 16)]:
            output = BytesIO(data)
            with zipfile.ZipFile(output, 'a') as archive:
                info = zipfile.ZipInfo(extra)
                info.external_attr = mode
                archive.writestr(info, b'payload')
            altered = output.getvalue()
            release = dict(self.release(), size=len(altered), sha256=hashlib.sha256(altered).hexdigest())
            with self.assertRaisesRegex(ValueError, 'unsafe package entry|unlisted package files'):
                validate_package(altered, release)

    def test_empty_and_unsafe_release_urls_rejected(self):
        self.publish()
        index = json.loads((self.index_dir / 'app.test.json').read_text())
        for url in ('http://github.com/Author/example/releases/download/tag/app.test.xmodule',
                    'https://github.com/Author/example/releases/download/../app.test.xmodule',
                    'https://github.com/Author/example/releases/download/tag/a.xmodule?redirect=1'):
            malformed = copy.deepcopy(index)
            malformed['versions'][0]['url'] = url
            with self.assertRaises(ValueError):
                validate_index(malformed, self.entry)

    def test_directory_seed_validator_matches_author_validator(self):
        root = pathlib.Path(__file__).resolve().parents[2]
        self.assertEqual((root / 'scripts/module_catalog/catalog.py').read_bytes(),
                         (root / 'packages/catalog/tools/validate.py').read_bytes())

    def test_optional_store_metadata_preserves_old_directories(self):
        self.assertIs(self.catalog, validate_catalog(self.catalog))
        self.assertNotIn('category', self.entry)
        self.assertNotIn('featured', self.entry)
        self.entry.update(category=' 学习 ', featured=True)
        self.assertIs(self.catalog, validate_catalog(self.catalog))
        self.entry.update(category='分' * 20, featured=False)
        self.assertIs(self.catalog, validate_catalog(self.catalog))

    def test_invalid_store_metadata_is_rejected(self):
        for category in ('', ' \t\n ', None, 1, True, [], '分' * 21):
            with self.subTest(category=category):
                malformed = copy.deepcopy(self.catalog)
                malformed['modules'][0]['category'] = category
                with self.assertRaisesRegex(ValueError, 'invalid category'):
                    validate_catalog(malformed)
        for featured in (None, '', 'true', 0, 1, [], {}):
            with self.subTest(featured=featured):
                malformed = copy.deepcopy(self.catalog)
                malformed['modules'][0]['featured'] = featured
                with self.assertRaisesRegex(ValueError, 'invalid featured'):
                    validate_catalog(malformed)

    def test_historical_package_is_kept_byte_identical(self):
        old_asset = self.publish()[0]
        old_data = old_asset.read_bytes()
        archives = self.root / 'history'
        archives.mkdir()
        (archives / 'app.test.xmodule').write_bytes(old_data)
        self.definition['manifest']['version'] = '1.0.1'
        self.definition['manifest']['description'] = '新说明'
        self.write_definition()
        self.entry['description'] = '新说明'
        self.catalog_path.write_text(json.dumps(self.catalog))
        prepare(self.modules, self.catalog_path, 'Author/example', 'modules-new', self.output, self.index_dir, [archives])
        self.assertEqual(old_data, old_asset.read_bytes())
        versions = json.loads((self.index_dir / 'app.test.json').read_text())['versions']
        self.assertEqual('测试模块', versions[0]['manifest']['description'])
        self.assertEqual('新说明', versions[-1]['manifest']['description'])
        validate_directory(self.catalog_path, self.index_dir, self.output)

    def test_bundle_pins_new_name_keeps_default_flag_and_old_asset(self):
        self.publish()
        bundle_dir = self.root / 'client/assets/modules'
        bundle_dir.mkdir(parents=True)
        old = bundle_dir / 'app.test.xmodule'
        old.write_bytes((self.output / 'app.test-1.0.0.xmodule').read_bytes())
        original = old.read_bytes()
        catalog_path = bundle_dir / 'catalog.json'
        catalog_path.write_text(json.dumps([{'id': 'app.test', 'asset': 'assets/modules/app.test.xmodule',
                                             'sha256': 'old', 'default': False}]))
        bundle_catalog(catalog_path, bundle_dir, self.modules, self.output, self.root / 'bundle-archive')
        entry = json.loads(catalog_path.read_text())[0]
        self.assertFalse(entry['default'])
        self.assertEqual('assets/modules/app.test-1.0.0.xmodule', entry['asset'])
        self.assertFalse(old.exists())
        self.assertEqual(original, (self.root / 'bundle-archive' / old.name).read_bytes())
        self.assertEqual(entry['sha256'], hashlib.sha256((bundle_dir / 'app.test-1.0.0.xmodule').read_bytes()).hexdigest())

    def test_bundle_later_conflict_leaves_every_asset_and_catalog_unchanged(self):
        self.publish()
        second = copy.deepcopy(self.definition)
        second['manifest']['id'] = 'app.second'
        folder = self.modules / 'app.second'
        folder.mkdir()
        (folder / 'module.json').write_text(json.dumps(second))
        from publish import packer
        packer.pack(folder, self.output / 'app.second-1.0.0.xmodule')
        bundle_dir = self.root / 'client/assets/modules'
        bundle_dir.mkdir(parents=True)
        conflicting = bundle_dir / 'app.second-1.0.0.xmodule'
        conflicting.write_bytes(b'prior immutable bytes')
        catalog_path = bundle_dir / 'catalog.json'
        catalog_path.write_text(json.dumps([
            {'id': 'app.test', 'default': False}, {'id': 'app.second', 'default': True}]))
        original = {path.name: path.read_bytes() for path in bundle_dir.iterdir()}
        with self.assertRaisesRegex(ValueError, 'immutable'):
            bundle_catalog(catalog_path, bundle_dir, self.modules, self.output, self.root / 'bundle-archive')
        self.assertEqual(original, {path.name: path.read_bytes() for path in bundle_dir.iterdir()})

    def test_bundle_rejects_corrupt_release_before_writing(self):
        asset = self.publish()[0]
        with zipfile.ZipFile(asset) as archive:
            entries = {name: archive.read(name) for name in archive.namelist()}
        entries['main.js'] = b'changed without updating package manifest'
        with zipfile.ZipFile(asset, 'w') as archive:
            for name, data in entries.items():
                archive.writestr(name, data)
        bundle_dir = self.root / 'client/assets/modules'
        bundle_dir.mkdir(parents=True)
        catalog_path = bundle_dir / 'catalog.json'
        catalog_path.write_text(json.dumps([{'id': 'app.test', 'default': True}]))
        original = catalog_path.read_bytes()
        with self.assertRaisesRegex(ValueError, 'payload digest mismatch'):
            bundle_catalog(catalog_path, bundle_dir, self.modules, self.output, self.root / 'bundle-archive')
        self.assertEqual(original, catalog_path.read_bytes())
        self.assertFalse(list(bundle_dir.glob('*.xmodule')))


if __name__ == '__main__':
    unittest.main()
