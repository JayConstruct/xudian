import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    'design_artifacts', Path(__file__).resolve().parents[1] / 'design_artifacts.py')
design = importlib.util.module_from_spec(spec)
spec.loader.exec_module(design)


class DesignArtifactsTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for name, value in [('ROOT', self.root), ('DESIGNS', self.root / 'dist/design'),
                            ('UI_DESIGNS', self.root / 'design')]:
            replacement = patch.object(design, name, value)
            replacement.start()
            self.addCleanup(replacement.stop)

    def image(self, batch):
        manifest = json.loads((batch / 'manifest.json').read_text())
        area = self.root / manifest['artifactDirectory']
        image = area / (manifest['filePrefix'] + 'style-a-v01.png')
        # This fixture checks archiving, not image rendering or PNG decoding.
        image.write_bytes(b'archive fixture')
        image.with_suffix('.prompt.txt').write_text('Exact fixture prompt')
        manifest['tool'] = 'archive fixture'
        (batch / 'manifest.json').write_text(json.dumps(manifest))
        return image

    def test_styles_are_shallow_and_batches_do_not_mix(self):
        first = design.new_batch('styles', 'first')
        second = design.new_batch('styles', 'second')
        image = self.image(first)
        self.image(second)
        _, files = design.inspect_batch(first)
        self.assertEqual(image.parent, self.root / 'design/styles')
        self.assertEqual({file['path'] for file in files},
                         {image.name, image.with_suffix('.prompt.txt').name})
        self.assertNotIn(second.name, '\n'.join(file['path'] for file in files))

    def test_page_paths_missing_prompt_and_digest_changes(self):
        batch = design.new_batch('ui-23', 'project progress')
        image = self.image(batch)
        self.assertEqual(image.parent, self.root / 'design/projects')
        _, before = design.inspect_batch(batch)
        image.write_bytes(b'changed fixture')
        _, after = design.inspect_batch(batch)
        self.assertNotEqual(before, after)
        image.with_suffix('.prompt.txt').unlink()
        with self.assertRaisesRegex(ValueError, '提示词'):
            design.inspect_batch(batch)

    def test_legacy_batches_still_work(self):
        batch = design.new_batch('planner-cancellation', 'legacy-compatible')
        manifest, files = design.inspect_batch(batch)
        self.assertEqual(batch.parent, self.root / 'dist/design/planner-cancellation')
        self.assertEqual(manifest['schemaVersion'], 1)
        self.assertEqual(files, [])

    def test_old_page_batch_and_moved_page_link(self):
        batch = design.new_batch('settings', 'settings', page=True)
        image = self.image(batch)
        area = image.parent
        old = self.root / 'design/screens/ui-20'
        old.parent.mkdir()
        old_batch = old / '.batches' / batch.name
        old.symlink_to('../settings')
        self.assertEqual(design.inspect_batch(old_batch), design.inspect_batch(batch))

        old.unlink()
        numbered = self.root / 'design/ui-20'
        area.rename(numbered)
        old.symlink_to('../ui-20')
        manifest_file = numbered / '.batches' / batch.name / 'manifest.json'
        manifest = json.loads(manifest_file.read_text())
        manifest.update(topic='ui-20', artifactDirectory='design/ui-20')
        manifest_file.write_text(json.dumps(manifest))
        design.inspect_batch(old_batch)

        old.unlink()
        numbered.rename(old)
        manifest_file = old_batch / 'manifest.json'
        manifest['artifactDirectory'] = 'design/screens/ui-20'
        manifest_file.write_text(json.dumps(manifest))
        _, files = design.inspect_batch(old_batch)
        self.assertIn(image.name, [item['path'] for item in files])

    def test_new_page_can_use_its_feature_name_without_a_number(self):
        batch = design.new_batch('weekly-review', 'review', page=True)
        manifest, _ = design.inspect_batch(batch)
        self.assertEqual(manifest['artifactDirectory'], 'design/weekly-review')
        self.assertEqual(manifest['topic'], 'weekly-review')

    def test_selection_rejects_another_batch_and_forged_area(self):
        batch = design.new_batch('styles', 'selected')
        image = self.image(batch)
        manifest = json.loads((batch / 'manifest.json').read_text())
        manifest.update(status='selected', selection={'source': image.name, 'reason': 'chosen'})
        (batch / 'manifest.json').write_text(json.dumps(manifest))
        design.inspect_batch(batch)
        manifest['selection']['source'] = '../private.png'
        (batch / 'manifest.json').write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError, '选定稿'):
            design.inspect_batch(batch)
        manifest.update(artifactDirectory='../private', selection=None, status='draft')
        (batch / 'manifest.json').write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError, '目录'):
            design.inspect_batch(batch)

    def test_symlinks_and_unknown_page_are_rejected(self):
        batch = design.new_batch('styles', 'symlink')
        outside = self.root / 'outside'
        outside.write_text('private')
        (batch / 'notes/leak').symlink_to(outside)
        with self.assertRaisesRegex(ValueError, '符号链接'):
            design.inspect_batch(batch)
        with self.assertRaisesRegex(ValueError, '浅层主题'):
            design.new_batch('ui-24', 'unregistered page')
        with self.assertRaisesRegex(ValueError, '浅层主题'):
            design.new_batch('ui-99', 'invalid page')

    def test_manifest_symlink_is_rejected_before_reading(self):
        batch = design.new_batch('styles', 'manifest link')
        manifest = batch / 'manifest.json'
        outside = self.root / 'private.json'
        manifest.rename(outside)
        manifest.symlink_to(outside)
        with self.assertRaisesRegex(ValueError, '符号链接'):
            design.inspect_batch(batch)


class PageCatalogTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        (self.root / 'design/settings').mkdir(parents=True)
        (self.root / 'design/settings/light.png').write_bytes(b'image fixture')
        self.catalog = self.root / 'design/PAGES.md'
        self.rows = (
            '| 应用设置 | settings | 设置首页 | 应用设置 | [浅色](settings/light.png)<br>'
            '[深色](settings/dark.png) | — |\n'
            '| 应用设置 | settings-search | 搜索设置 | — | — | 补充空结果图 |\n')
        self.catalog.write_text(self.rows)

    def test_exact_alias_legacy_id_partial_and_pending(self):
        pages = design.read_page_catalog(self.catalog)
        found, missing = design.query_pages(pages, ['应用设置', 'UI-20', '设置', '无此页'], False)
        self.assertEqual(found, pages)
        self.assertEqual(missing, ['无此页'])
        self.assertEqual(design.query_pages(pages, ['SETTINGS'], False), ([pages[0]], []))
        self.assertEqual(design.query_pages(pages, [], True), ([pages[1]], []))
        self.assertEqual(design.query_pages(pages, ['应用设置'], True), ([], []))
        self.assertEqual([i['available'] for i in found[0]['images']], [True, False])

    def test_invalid_registry_reports_the_row(self):
        for row in ('| 应用设置 | other | 搜索设置 | — | — | 收录 |',
                    '| 应用设置 | other | 其他 | — | — | — |',
                    '| 应用设置 | other | 其他 | — | [稿](../outside.png) | — |',
                    '| 应用设置 | other | 其他 | — | 没有图片链接 | — |',
                    '| — | other | 其他 | — | — | 收录 |'):
            with self.subTest(row=row):
                self.catalog.write_text(self.rows + row)
                with self.assertRaisesRegex(ValueError, 'PAGES.md:3'):
                    design.read_page_catalog(self.catalog)

    def test_category_scopes_name_search_before_pending_filter(self):
        self.catalog.write_text(self.rows +
                                '| 课表与教务 | school | 课表设置首页 | — | — | 收录 |\n')
        pages = design.read_page_catalog(self.catalog)
        self.assertEqual(design.query_pages(pages, [], True, category='应用设置'), ([pages[1]], []))
        self.assertEqual(design.query_pages(pages, ['设置首页', 'UI-20'], False, category='课表与教务'),
                         ([pages[2]], ['UI-20']))

    def test_published_catalog_and_batch_cli(self):
        script = Path(design.__file__)
        pages = design.read_page_catalog(script.parents[1] / 'design/PAGES.md')
        self.assertLessEqual(set(design.PAGE_ALIASES.values()), {p['id'] for p in pages})
        run = subprocess.run([sys.executable, str(script), 'query', 'UI-20', '无此页', '--json'],
                             cwd=self.root, capture_output=True, text=True)
        self.assertEqual(run.returncode, 1)
        self.assertIn('未找到页面：无此页', run.stderr)
        self.assertEqual([p['id'] for p in json.loads(run.stdout)], ['settings'])


if __name__ == '__main__':
    unittest.main()
