import importlib.util
import json
from pathlib import Path
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
        batch = design.new_batch('ui-03', 'new task')
        image = self.image(batch)
        self.assertEqual(image.parent, self.root / 'design/screens/ui-03')
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
            design.new_batch('ui-99', 'invalid page')

    def test_manifest_symlink_is_rejected_before_reading(self):
        batch = design.new_batch('styles', 'manifest link')
        manifest = batch / 'manifest.json'
        outside = self.root / 'private.json'
        manifest.rename(outside)
        manifest.symlink_to(outside)
        with self.assertRaisesRegex(ValueError, '符号链接'):
            design.inspect_batch(batch)


if __name__ == '__main__':
    unittest.main()
