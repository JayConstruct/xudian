import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    'validate_app_release', Path(__file__).resolve().parents[1] / 'validate_app_release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class AppReleaseTest(unittest.TestCase):
    def test_release_tag_matches_embedded_stable_version(self):
        release.validate_release('v0.2.0', 'name: task_app\nversion: 0.2.0+123\n')

    def test_prerelease_tag_matches_exact_embedded_channel_and_number(self):
        for channel in ['alpha', 'beta', 'rc']:
            release.validate_release(f'v0.2.0-{channel}.1', f'version: 0.2.0-{channel}.1+123\n')
        for tag in ['v0.2.0-beta.2', 'v0.2.0-rc.1', 'v0.2.0']:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release.validate_release(tag, 'version: 0.2.0-beta.1+123\n')

    def test_malformed_prereleases_are_rejected(self):
        for version in ['0.2.0-beta', '0.2.0-beta.01', '0.2.0-beta.1+123+4',
                        '0.2.0-preview.1', '0.2.0-beta.1;echo']:
            with self.subTest(version=version), self.assertRaises(ValueError):
                release.validate_release('v' + version, f'version: {version}\n')

    def test_mismatched_and_module_tags_are_rejected(self):
        for tag in ['v0.3.0', '0.2.0', 'modules-20261011', 'v0.2.0-beta.1', 'v00.2.0']:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release.validate_release(tag, 'version: 0.2.0+123\n')

    def test_missing_and_prerelease_pubspec_cannot_publish_a_stable_tag(self):
        for pubspec in ['', 'version: 0.2.0-beta.1+123\n', 'version: nonsense\n']:
            with self.subTest(pubspec=pubspec), self.assertRaises(ValueError):
                release.validate_release('v0.2.0', pubspec)


if __name__ == '__main__':
    unittest.main()
