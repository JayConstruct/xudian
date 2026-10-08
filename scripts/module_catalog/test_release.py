import json
import pathlib
import unittest
from unittest.mock import patch

import test_catalog
from release import prepared_assets, publish


class ReleaseTest(unittest.TestCase):
    def setUp(self):
        self.fixture = test_catalog.PublicationTest()
        self.fixture.setUp()
        self.fixture.publish()
        self.assets = prepared_assets(self.fixture.catalog_path, self.fixture.index_dir,
                                      self.fixture.output, 'Author/example', 'modules-test', 1)
        self.names = sorted(self.assets)
        self.release = {'draft': False, 'assets': [{'name': name} for name in self.names],
                        'body': '<!-- xudian-module-release-ref:original -->'}
        self.calls = []
        self.private = False
        self.download_bad = False
        self.change_tag = False
        self.ref_reads = 0

    def tearDown(self):
        self.fixture.tearDown()

    def gh(self, arguments, allow_missing=False):
        self.calls.append(arguments)
        if arguments[:2] == ['api', 'repos/Author/example']:
            return json.dumps({'private': self.private})
        if arguments[:2] == ['api', 'repos/Author/example/git/ref/tags/modules-test']:
            self.ref_reads += 1
            return json.dumps({'object': {'sha': 'changed' if self.change_tag and self.ref_reads > 1 else 'original'}})
        if arguments[0] == 'api':
            return json.dumps(self.release) if self.release is not None else None
        if arguments[:2] == ['release', 'download']:
            destination = pathlib.Path(arguments[arguments.index('--dir') + 1])
            for asset in self.release['assets']:
                data = (self.fixture.output / asset['name']).read_bytes()
                (destination / asset['name']).write_bytes(data[:-1] + b'!' if self.download_bad else data)
        elif arguments[:2] == ['release', 'create']:
            self.release = {'draft': True, 'assets': [{'name': name} for name in self.names],
                            'body': arguments[arguments.index('--notes') + 1]}
        elif arguments[:2] == ['release', 'upload']:
            self.release['assets'] = [{'name': name} for name in self.names]
        elif arguments[:2] == ['release', 'edit']:
            self.release['draft'] = False
        return ''

    def run_publish(self):
        with patch('release.shutil.which', return_value='/usr/bin/gh'), patch('release.gh', side_effect=self.gh):
            return publish('Author/example', 'modules-test', self.fixture.output,
                           self.assets, 'Title', 'Unsigned')

    def test_published_release_rerun_verifies_bytes_without_writing(self):
        self.run_publish()
        self.assertFalse(any(call[:2] in (['release', 'create'], ['release', 'upload'], ['release', 'edit'])
                             for call in self.calls))

    def test_digest_mismatch_refuses_overwrite(self):
        self.download_bad = True
        with self.assertRaisesRegex(ValueError, 'digest mismatch'):
            self.run_publish()
        self.assertFalse(any(call[:2] == ['release', 'upload'] for call in self.calls))

    def test_new_release_stays_draft_until_verified(self):
        self.release = None
        self.run_publish()
        create = next(call for call in self.calls if call[:2] == ['release', 'create'])
        self.assertIn('--verify-tag', create)
        self.assertIn('--draft', create)
        self.assertLess(next(i for i, call in enumerate(self.calls) if call[:2] == ['release', 'download']),
                        next(i for i, call in enumerate(self.calls) if call[:2] == ['release', 'edit']))

    def test_incomplete_draft_can_resume_without_clobber(self):
        self.release['assets'] = []
        self.release['draft'] = True
        self.run_publish()
        upload = next(call for call in self.calls if call[:2] == ['release', 'upload'])
        self.assertNotIn('--clobber', upload)
        self.assertFalse(self.release['draft'])

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
