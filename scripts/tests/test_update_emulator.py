"""Safety and failure-boundary checks; no emulator or Flutter required."""
import hashlib
import json
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('update_emulator', Path(__file__).resolve().parents[1] / 'update_emulator.py')
update = importlib.util.module_from_spec(spec)
spec.loader.exec_module(update)


class UpdateEmulatorTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.invalid')
        for name in ['selected.txt', 'other.txt']:
            (self.root / name).write_text('before\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'Initial')

    def git(self, *args):
        return subprocess.run(['git', *args], cwd=self.root, check=True,
                              capture_output=True, text=True).stdout.strip()

    def test_commit_preserves_unrelated_staging_and_handles_new_files(self):
        (self.root / 'selected.txt').write_text('after\n')
        (self.root / 'new file.txt').write_text('new\n')
        (self.root / 'other.txt').write_text('other change\n')
        self.git('add', 'other.txt')
        update.commit_files('Selected changes', ['selected.txt', 'new file.txt'], root=self.root)
        committed = self.git('diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD')
        self.assertEqual(set(committed.splitlines()), {'selected.txt', 'new file.txt'})
        self.assertEqual(self.git('diff', '--cached', '--name-only'), 'other.txt')

    def test_paths_reject_directories_ignored_files_and_repository_escape(self):
        (self.root / '.gitignore').write_text('ignored.txt\n')
        (self.root / 'ignored.txt').write_text('private')
        for path in ['.', '.git/config', 'ignored.txt', '../outside.txt', ':(glob)*']:
            with self.subTest(path=path), self.assertRaises(ValueError):
                update.validate_commit_paths([path], root=self.root)
        self.assertEqual(update.validate_commit_paths(['selected.txt'], root=self.root), ['selected.txt'])

    def test_split_and_universal_versions_increment_without_downgrade(self):
        self.assertEqual(update.next_build_number(4043), 44)
        self.assertEqual(update.next_build_number(2002), 2003)
        self.assertEqual(update.next_build_number(0, 45), 46)
        self.assertEqual(update.next_build_number(4043, 50), 51)

    def exercise_failure(self, failure):
        test_file = self.root / 'client/test/example_test.dart'
        test_file.parent.mkdir(parents=True)
        test_file.write_text('// test fixture')
        calls = []

        def fake_run(command, **kwargs):
            calls.append(command)
            if 'get-state' in command:
                return 'device\n'
            if 'ro.kernel.qemu' in command:
                return '1\n'
            if 'ro.product.cpu.abi' in command:
                return 'x86_64\n'
            if 'dumpsys' in command:
                return 'versionCode=4043' if not any('install' in c for c in calls) else 'versionCode=4044'
            if command[:3] == ['flutter', 'build', 'apk']:
                if failure == 'build':
                    raise subprocess.CalledProcessError(1, command)
                apk = self.root / 'client/build/app/outputs/flutter-apk/app-x86_64-release.apk'
                apk.parent.mkdir(parents=True)
                apk.write_bytes(b'build')
            if 'path' in command and 'pm' in command:
                return 'package:/data/app/example/base.apk\n'
            if 'sha256sum' in command:
                return 'wrong /data/app/example/base.apk\n' if failure == 'digest' else hashlib.sha256(b'build').hexdigest()
            return ''

        with patch.object(update, 'ROOT', self.root), patch.object(update, 'run', fake_run):
            with self.assertRaises((ValueError, subprocess.CalledProcessError)):
                update.main(['--test', 'test/example_test.dart', '--commit', 'Update', '--path', 'selected.txt'])
        self.assertFalse(any('commit' in command for command in calls))
        self.assertFalse(any(command[:3] == ['git', '--literal-pathspecs', 'add'] for command in calls))
        if failure == 'build':
            self.assertFalse(any('install' in command for command in calls))
        self.assertFalse((self.root / '.cache/emulator-update/latest-success.json').exists())
        self.assertTrue((self.root / '.cache/emulator-update/latest-attempt.json').exists())

    def test_build_failure_prevents_install_and_commit(self):
        self.exercise_failure('build')

    def test_installed_digest_mismatch_prevents_commit(self):
        self.exercise_failure('digest')

    def cached_update(self, arguments=(), *, catalog_failure=False):
        for test in update.DEFAULT_TESTS:
            path = self.root / 'client' / test
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('// unchanged test')
        output = self.root / '.cache/emulator-update'
        output.mkdir(parents=True)
        apk = output / 'verified.apk'
        apk.write_bytes(b'verified APK')
        digest = hashlib.sha256(apk.read_bytes()).hexdigest()
        inputs = update.snapshot(self.root)
        tests = sorted(update.DEFAULT_TESTS)
        cache = {'fingerprint': update.fingerprint(inputs), 'inputs': inputs, 'mode': 'release',
                 'apk': str(apk.relative_to(self.root)), 'apkSha256': digest,
                 'buildNumber': 44, 'versionCode': 4044,
                 'checksFingerprint': update.checks_fingerprint(self.root, inputs, tests)}
        (output / 'release-cache.json').write_text(json.dumps(cache))
        calls = []

        def fake_run(command, **kwargs):
            calls.append(command)
            if 'get-state' in command:
                return 'device'
            if 'ro.kernel.qemu' in command:
                return '1'
            if 'ro.product.cpu.abi' in command:
                return 'x86_64'
            if 'dumpsys' in command:
                return 'versionCode=4044'
            if 'pm' in command:
                return 'package:/data/app/example/base.apk'
            if 'sha256sum' in command:
                return digest + ' base.apk'
            if 'start' in command:
                return 'Status: ok'
            if command == ['python3', str(self.root / 'scripts/check_repository.py')]:
                return ''
            if command[:2] == ['python3', str(self.root / 'scripts/module_host/verify_catalog.py')]:
                self.assertFalse((output / 'latest-success.json').exists())
                installation = json.loads((output / 'catalog-installation.json').read_text())
                self.assertEqual(installation['installedApkSha256'], digest)
                self.assertIn('--cold-start', command)
                if catalog_failure:
                    raise subprocess.CalledProcessError(1, command)
                target = Path(command[command.index('--output') + 1])
                target.mkdir(parents=True)
                (target / 'results.json').write_text(json.dumps({'completed': True, 'seconds': 1.25}))
                return ''
            if command[:4] == ['git', '--literal-pathspecs', 'diff', '--check']:
                return ''
            if command == ['git', 'var', 'GIT_AUTHOR_IDENT']:
                return 'Test <test@example.invalid>'
            raise AssertionError('Unexpected repeated work: ' + str(command))

        with patch.object(update, 'ROOT', self.root), patch.object(update, 'run', fake_run):
            if catalog_failure:
                with self.assertRaises(subprocess.CalledProcessError):
                    update.main(list(arguments))
            else:
                self.assertEqual(update.main(list(arguments)), 0)
        return output, calls

    def test_unchanged_verified_apk_skips_checks_build_and_install(self):
        output, calls = self.cached_update()
        report = json.loads((output / 'latest-success.json').read_text())
        self.assertTrue(report['reusedBuild'])
        self.assertTrue(report['reusedChecks'])
        self.assertTrue(report['skippedInstall'])
        self.assertIn(['python3', str(self.root / 'scripts/check_repository.py')], calls)
        self.assertFalse(any('flutter' in command or 'install' in command for command in calls))

    def test_single_command_reuses_apk_then_requires_catalog_acceptance(self):
        output, calls = self.cached_update(['--verify-catalog', '--catalog-offline'])
        report = json.loads((output / 'latest-success.json').read_text())
        self.assertTrue(report['catalogAcceptance']['completed'])
        self.assertTrue(report['reusedBuild'])
        command = next(c for c in calls if 'verify_catalog.py' in ' '.join(c))
        self.assertIn('--offline', command)
        self.assertFalse(any('flutter' in command or 'install' in command for command in calls))

    def test_catalog_failure_prevents_success_and_commit(self):
        output, calls = self.cached_update(
            ['--verify-catalog', '--commit', 'test', '--path', 'selected.txt'], catalog_failure=True)
        self.assertFalse((output / 'latest-success.json').exists())
        report = json.loads((output / 'latest-attempt.json').read_text())
        self.assertFalse(report['completed'])
        self.assertEqual(report['failedStep'], '商店页面验收')
        self.assertFalse(any('commit' in command for command in calls))

    def test_offline_acceptance_requires_catalog_acceptance_flag(self):
        with self.assertRaises(SystemExit):
            update.main(['--catalog-offline', '--dry-run'])


if __name__ == '__main__':
    unittest.main()
