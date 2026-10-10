import json
import subprocess
import unittest
from unittest.mock import patch

import test_catalog
from release import find_release, gh, prepared_assets, publish


class ReleaseTest(unittest.TestCase):
    def setUp(self):
        self.fixture = test_catalog.PublicationTest()
        self.fixture.setUp()
        self.fixture.publish()
        self.assets = prepared_assets(self.fixture.catalog_path, self.fixture.index_dir,
                                      self.fixture.output, 'Author/example', 'modules-test', 1)
        self.names = sorted(self.assets)
        self.release = {'id': 123, 'tag_name': 'modules-test', 'draft': False,
                        'assets': [{'id': 456 + i, 'name': name} for i, name in enumerate(self.names)],
                        'body': '<!-- xudian-module-release-ref:original -->'}
        self.calls = []
        self.private = False
        self.download_bad = False
        self.change_tag = False
        self.ref_reads = 0
        self.hide_created_draft = False
        self.created = False

    def tearDown(self):
        self.fixture.tearDown()

    def gh(self, arguments, *, binary=False):
        self.calls.append(arguments)
        if arguments[:2] == ['api', 'repos/Author/example']:
            return json.dumps({'private': self.private})
        if arguments[:2] == ['api', 'repos/Author/example/git/ref/tags/modules-test']:
            self.ref_reads += 1
            return json.dumps({'object': {'sha': 'changed' if self.change_tag and self.ref_reads > 1 else 'original'}})
        if arguments[:2] == ['api', 'repos/Author/example/releases?per_page=100']:
            self.assertIn('--paginate', arguments)
            self.assertIn('--slurp', arguments)
            # An existing draft is on a later page; by-tag GET would return 404.
            visible = self.release and not (self.created and self.hide_created_draft)
            return json.dumps([[{'id': 1, 'tag_name': 'unrelated'}], [self.release] if visible else []])
        if arguments[:2] == ['api', 'repos/Author/example/releases']:
            self.assertEqual('POST', arguments[arguments.index('--method') + 1])
            self.assertIn('draft=true', arguments)
            self.assertIn('tag_name=modules-test', arguments)
            self.release = {'id': 123, 'tag_name': 'modules-test', 'draft': True, 'assets': [],
                            'body': next(arg.removeprefix('body=') for arg in arguments if arg.startswith('body='))}
            self.created = True
            return json.dumps(self.release)
        if arguments[:2] == ['api', 'repos/Author/example/releases/123']:
            if '--method' in arguments:
                self.assertEqual('PATCH', arguments[arguments.index('--method') + 1])
                self.assertEqual('draft=false', arguments[arguments.index('-F') + 1])
                self.release['draft'] = False
            return json.dumps(self.release)
        if arguments[0] == 'api' and arguments[1].startswith('repos/Author/example/releases/assets/'):
            self.assertTrue(binary)
            self.assertIn('Accept: application/octet-stream', arguments)
            asset = next(asset for asset in self.release['assets'] if str(asset['id']) == arguments[1].split('/')[-1])
            data = (self.fixture.output / asset['name']).read_bytes()
            return data[:-1] + b'!' if self.download_bad else data
        if arguments[0] == 'api' and arguments[1].startswith('https://uploads.github.com/'):
            self.assertTrue(self.release['draft'])
            self.assertEqual('POST', arguments[arguments.index('--method') + 1])
            self.assertIn('Content-Type: application/octet-stream', arguments)
            name = arguments[1].split('?name=')[1]
            self.assertEqual(str(self.fixture.output / name), arguments[arguments.index('--input') + 1])
            self.assertFalse(any(asset['name'] == name for asset in self.release['assets']))
            self.release['assets'].append({'id': 456 + len(self.release['assets']), 'name': name})
            return json.dumps(self.release['assets'][-1])
        if arguments[0] == 'api':
            raise ValueError('gh: Not Found (HTTP 404)')
        raise AssertionError(f'Tag-based release command must not be used: {arguments}')

    def run_publish(self):
        with patch('release.shutil.which', return_value='/usr/bin/gh'), patch('release.gh', side_effect=self.gh):
            return publish('Author/example', 'modules-test', self.fixture.output,
                           self.assets, 'Title', 'Unsigned')

    def test_published_release_rerun_verifies_bytes_without_writing(self):
        self.run_publish()
        self.assertFalse(any(call[:2] in (['release', 'create'], ['release', 'upload']) or '--method' in call
                             for call in self.calls))

    def test_digest_mismatch_refuses_overwrite(self):
        self.download_bad = True
        with self.assertRaisesRegex(ValueError, 'digest mismatch'):
            self.run_publish()
        self.assertFalse(any('--method' in call for call in self.calls))

    def test_new_release_stays_draft_until_verified(self):
        self.release = None
        self.run_publish()
        create = next(call for call in self.calls if call[:2] == ['api', 'repos/Author/example/releases'])
        self.assertIn('draft=true', create)
        self.assertLess(next(i for i, call in enumerate(self.calls) if '/releases/assets/' in call[1]),
                        next(i for i, call in enumerate(self.calls) if 'PATCH' in call))

    def test_complete_draft_on_later_page_is_recovered_without_by_tag_get(self):
        self.release['draft'] = True
        self.run_publish()
        self.assertFalse(self.release['draft'])
        self.assertFalse(any(call[:2] == ['api', 'repos/Author/example/releases'] for call in self.calls))
        self.assertFalse(any('/releases/tags/' in part for call in self.calls for part in call))

    def test_ambiguous_pending_tags_refuse_publication(self):
        with patch('release.gh', return_value=json.dumps([[self.release], [self.release]])):
            with self.assertRaisesRegex(ValueError, 'Multiple Releases'):
                find_release('Author/example', 'modules-test')

    def test_incomplete_draft_can_resume_without_clobber(self):
        self.release['assets'] = []
        self.release['draft'] = True
        self.run_publish()
        upload = next(call for call in self.calls if call[1].startswith('https://uploads.github.com/'))
        self.assertNotIn('--clobber', upload)
        self.assertFalse(self.release['draft'])

    def test_created_draft_missing_from_release_list_is_published_by_id(self):
        self.release = None
        self.hide_created_draft = True
        self.run_publish()
        self.assertFalse(self.release['draft'])
        self.assertEqual(1, sum(call[1].endswith('/releases?per_page=100') for call in self.calls))
        self.assertEqual(1, sum(call[:2] == ['api', 'repos/Author/example/releases'] for call in self.calls))
        self.assertFalse(any(call[0] == 'release' or '/releases/tags/' in call[1] for call in self.calls))

    def test_uploaded_digest_mismatch_keeps_created_release_draft(self):
        self.release = None
        self.download_bad = True
        with self.assertRaisesRegex(ValueError, 'digest mismatch'):
            self.run_publish()
        self.assertTrue(self.release['draft'])
        self.assertFalse(any('PATCH' in call for call in self.calls))

    def test_binary_asset_download_preserves_bytes(self):
        data = bytes(range(256))
        with patch('release.subprocess.run', return_value=subprocess.CompletedProcess([], 0, data, b'')) as run:
            self.assertEqual(data, gh(['api', 'repos/Author/example/releases/assets/456'], binary=True))
        self.assertFalse(run.call_args.kwargs['text'])

    def test_incomplete_published_release_cannot_change(self):
        self.release['assets'] = []
        with self.assertRaisesRegex(ValueError, 'missing indexed packages'):
            self.run_publish()

    def test_private_repo_and_changed_tag_refused(self):
        self.private = True
        with self.assertRaisesRegex(ValueError, 'must be public'):
            self.run_publish()
        self.private = False
        self.change_tag = True
        self.release['draft'] = True
        with self.assertRaisesRegex(ValueError, 'Tag changed'):
            self.run_publish()
        self.assertTrue(self.release['draft'])

    def test_existing_release_without_tag_marker_refused(self):
        self.release['body'] = 'Other release'
        with self.assertRaisesRegex(ValueError, 'tag identity'):
            self.run_publish()

    def test_missing_cli_and_unexpected_prepared_package_are_actionable(self):
        with patch('release.shutil.which', return_value=None):
            with self.assertRaisesRegex(ValueError, 'gh auth login'):
                publish('Author/example', 'modules-test', self.fixture.output, self.assets, 'Title', 'Notes')
        (self.fixture.output / 'unexpected.xmodule').write_bytes(b'invalid')
        with self.assertRaisesRegex(ValueError, 'exactly the packages'):
            prepared_assets(self.fixture.catalog_path, self.fixture.index_dir,
                            self.fixture.output, 'Author/example', 'modules-test')


if __name__ == '__main__':
    unittest.main()
