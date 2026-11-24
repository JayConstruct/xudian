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

    def test_gallery_resolves_module_per_state_and_keeps_one_link_per_state(self):
        self.catalog.write_text(
            '| 日程与任务 | 宿主 | overview | 概览 | — | [设置](settings/light.png)<br>'
            '[完成复盘](settings/light.png "app.views.today") | — |\n')
        manifest = self.root / 'packages/modules/app.views.today/module.json'
        manifest.parent.mkdir(parents=True)
        manifest.write_text(json.dumps({'manifest': {'id': 'app.views.today', 'name': '日程'}}))
        pages = design.read_page_catalog(self.catalog)
        self.assertEqual([i['module'] for i in pages[0]['images']], ['宿主', 'app.views.today'])
        output = self.root / 'design/汇总/目录.html'
        with patch.object(design, 'ROOT', self.root):
            design.write_gallery(pages, output)
        gallery = output.read_text()
        self.assertEqual(gallery.count('href="../settings/light.png"'), 2)
        self.assertEqual(gallery.count('data-module="app.views.today"'), 1)
        self.assertIn('<option value="app.views.today">日程</option>', gallery)
        self.assertIn('<h3>日程</h3>', gallery)
        self.assertEqual(gallery.count('data-page="overview"><h4>概览</h4>'), 2)
        links = list(output.parent.glob('*/*/*/*.png'))
        self.assertEqual({p.relative_to(output.parent).as_posix() for p in links},
                         {'日程与任务/应用宿主/概览/设置.png', '日程与任务/日程/概览/完成复盘.png'})
        for link in links:
            self.assertFalse(link.readlink().is_absolute())
            self.assertEqual(link.resolve(), self.root / 'design/settings/light.png')

    def test_gallery_refresh_moves_a_page_and_preserves_original_and_local_files(self):
        page = '| 应用设置 | 宿主 | settings | 设置首页 | — | [浅色/手机](settings/light.png) | — |'
        self.catalog.write_text(page)
        output = self.root / 'design/看图目录/目录.html'
        with patch.object(design, 'ROOT', self.root):
            design.write_gallery(design.read_page_catalog(self.catalog), output)
            old_folder = output.parent / '应用设置/应用宿主/设置首页'
            old_link = old_folder / '浅色／手机.png'
            self.assertTrue(old_link.is_file())
            note = old_folder.parent / '说明.txt'
            note.write_text('备注')
            self.catalog.write_text(page.replace('应用设置', '全局与通用'))
            pages = design.read_page_catalog(self.catalog)
            design.write_gallery(pages, output)
            self.assertFalse(old_folder.exists())
            self.assertEqual(note.read_text(), '备注')
            new_link = output.parent / '全局与通用/应用宿主/设置首页/浅色／手机.png'
            self.assertEqual(new_link.read_bytes(), b'image fixture')
            design.write_gallery(pages, output)
            self.assertTrue(new_link.is_symlink())
            new_link.unlink()
            new_link.write_text('本机文件')
            with self.assertRaisesRegex(ValueError, '已有文件冲突'):
                design.write_gallery(pages, output)
            self.assertEqual(new_link.read_text(), '本机文件')

    def test_review_preserves_order_and_scopes_decisions_to_image_contents(self):
        pages = design.read_page_catalog(self.catalog)
        light = 'design/settings/light.png'
        dark = 'design/settings/dark.png'
        (self.root / dark).write_bytes(b'dark fixture')
        spec = self.root / 'design/current-review.json'
        with patch.object(design, 'ROOT', self.root):
            self.assertIsNone(design.current_review(pages))
            spec.write_text('{}')
            self.assertIsNone(design.current_review(pages))
            spec.write_text(json.dumps({'title': '设置', 'images': [dark, light]}))
            images = design.current_review(pages)['images']
            self.assertEqual([item['path'] for item in images], [dark, light])
            (self.root / dark).write_bytes(b'revised')
            revised = design.current_review(pages)['images']
            self.assertNotEqual(images[0]['digest'], revised[0]['digest'])
            self.assertEqual(images[1], revised[1])
            for paths, reason in (([dark, dark], '重复'), (['other.png'], '未登记')):
                spec.write_text(json.dumps({'title': '设置', 'images': paths}))
                with self.assertRaisesRegex(ValueError, reason):
                    design.current_review(pages)

    def test_revision_replacement_clears_only_comments_for_obsolete_images(self):
        light, dark = ('design/settings/light.png', 'design/settings/dark.png')
        (self.root / dark).write_bytes(b'dark')
        spec = self.root / 'design/current-review.json'
        spec.write_text(json.dumps({'title': '审核', 'images': [light, dark]}))
        output = self.root / 'design/看图目录/目录.html'
        report = output.with_name('本轮评论.json')
        with patch.object(design, 'ROOT', self.root):
            pages = design.read_page_catalog(self.catalog)
            images = design.current_review(pages)['images']
            design.write_gallery(pages, output)
            report.write_text(json.dumps({'format': 'design-gallery-comments-v1', 'images': [
                {**item, 'comments': [{'text': '反馈'}]} for item in images]}))
            # Taking a still-current image out of the round preserves its comments.
            spec.write_text(json.dumps({'title': '审核', 'images': [dark]}))
            design.write_gallery(pages, output)
            self.assertEqual(len(json.loads(report.read_text())['images']), 2)
            (self.root / dark).write_bytes(b'revised')
            design.write_gallery(pages, output)
            self.assertEqual(json.loads(report.read_text())['images'], [{**images[0], 'comments': [{'text': '反馈'}]}])
            design.write_gallery(pages, output)
            self.assertIn(dark + ':' + images[1]['digest'], output.read_text())

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
