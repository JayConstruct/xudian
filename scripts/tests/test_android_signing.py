"""Exercise the actual CI signing shell without exposing a real private key."""
import base64
import hashlib
import os
from pathlib import Path
import re
import subprocess
import tempfile
import textwrap
import unittest


WORKFLOW = Path(__file__).resolve().parents[2] / '.github/workflows/android.yml'
ABIS = ('armeabi-v7a', 'arm64-v8a', 'x86_64')
CERT = 'ab' * 32


def signing_shell():
    step = WORKFLOW.read_text().split('      - name: Sign and verify APKs\n', 1)[1]
    body = step.split('        run: |\n', 1)[1].split('      - uses:', 1)[0]
    return textwrap.dedent(body)


class AndroidSigningTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'candidate').mkdir()
        (self.root / 'temp').mkdir()
        for abi in ABIS:
            (self.root / 'candidate' / f'app-{abi}-release.apk').write_bytes(b'APK fixture')
        (self.root / 'candidate/SOURCE_COMMIT').write_text('source-revision\n')
        tool = self.root / 'sdk/build-tools/36.0.0/apksigner'
        tool.parent.mkdir(parents=True)
        tool.write_text(textwrap.dedent('''\
            #!/usr/bin/env python3
            import os
            from pathlib import Path
            import stat
            import sys
            args = sys.argv[1:]
            if args[0] == 'sign':
                key = Path(args[args.index('--ks') + 1])
                assert stat.S_IMODE(key.stat().st_mode) == 0o600
                assert stat.S_IMODE(key.parent.stat().st_mode) == 0o700
                assert key.read_bytes() == b'private-key-fixture'
                assert 'KEYSTORE_BASE64' not in os.environ
                assert args[args.index('--ks-pass') + 1] == 'env:STORE_PASSWORD'
                assert args[args.index('--key-pass') + 1] == 'env:KEY_PASSWORD'
                assert os.environ['STORE_PASSWORD'] not in args
                assert os.environ['KEY_PASSWORD'] not in args
                if os.environ.get('FAIL_SIGN') == '1':
                    sys.exit(3)
                Path(args[args.index('--out') + 1]).write_bytes(Path(args[-1]).read_bytes() + b'-signed')
            else:
                if os.environ.get('FAIL_VERIFY') == '1':
                    sys.exit(4)
                cert = 'cd' * 32 if os.environ.get('WRONG_CERT') == '1' else 'ab' * 32
                print('Signer #1 certificate SHA-256 digest: ' + cert)
        '''))
        tool.chmod(0o755)
        self.env = {
            **os.environ,
            'KEYSTORE_BASE64': base64.b64encode(b'private-key-fixture').decode(),
            'STORE_PASSWORD': 'store-password-fixture',
            'KEY_ALIAS': 'release',
            'KEY_PASSWORD': 'key-password-fixture',
            'EXPECTED_CERT_SHA256': CERT,
            'RUNNER_TEMP': str(self.root / 'temp'),
            'ANDROID_HOME': str(self.root / 'sdk'),
        }

    def run_signing(self):
        result = subprocess.run(['bash', '-c', signing_shell()], cwd=self.root,
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(list((self.root / 'temp').iterdir()), [], 'Private key was not cleaned up')
        for secret in ['private-key-fixture', 'store-password-fixture',
                       'key-password-fixture', base64.b64encode(b'private-key-fixture').decode()]:
            self.assertNotIn(secret, result.stdout + result.stderr)
        return result

    def test_all_abis_signed_and_checksums_recomputed(self):
        result = self.run_signing()
        self.assertEqual(result.returncode, 0, result.stderr)
        signed = self.root / 'signed'
        for line in (signed / 'SHA256SUMS').read_text().splitlines():
            digest, name = line.split()
            self.assertEqual(digest, hashlib.sha256((signed / name).read_bytes()).hexdigest())
        self.assertEqual(len(list(signed.glob('*.apk'))), 3)
        self.assertEqual((signed / 'SOURCE_COMMIT').read_text(), 'source-revision\n')

    def test_accepts_colon_separated_uppercase_public_fingerprint(self):
        self.env['EXPECTED_CERT_SHA256'] = ':'.join(['AB'] * 32)
        self.assertEqual(self.run_signing().returncode, 0)

    def test_each_missing_setting_blocks_signing(self):
        for name in ['KEYSTORE_BASE64', 'STORE_PASSWORD', 'KEY_ALIAS',
                     'KEY_PASSWORD', 'EXPECTED_CERT_SHA256']:
            with self.subTest(name=name):
                previous = self.env.pop(name)
                result = self.run_signing()
                self.env[name] = previous
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(name, result.stderr)
                self.assertFalse((self.root / 'signed').exists())

    def test_malformed_fingerprint_blocks_signing(self):
        self.env['EXPECTED_CERT_SHA256'] = 'not-a-fingerprint'
        self.assertNotEqual(self.run_signing().returncode, 0)
        self.assertFalse((self.root / 'signed').exists())

    def test_wrong_certificate_blocks_release(self):
        self.env['WRONG_CERT'] = '1'
        result = self.run_signing()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Signing certificate mismatch', result.stderr)
        self.assertFalse((self.root / 'signed/SHA256SUMS').exists())

    def test_sign_failure_cleans_up_key_and_stops(self):
        self.env['FAIL_SIGN'] = '1'
        self.assertEqual(self.run_signing().returncode, 3)
        self.assertFalse((self.root / 'signed/SHA256SUMS').exists())

    def test_verify_failure_cleans_up_key_and_stops(self):
        self.env['FAIL_VERIFY'] = '1'
        self.assertEqual(self.run_signing().returncode, 4)

    def test_malformed_keystore_cleans_up_key_and_stops(self):
        self.env['KEYSTORE_BASE64'] = '!invalid-base64!'
        self.assertNotEqual(self.run_signing().returncode, 0)
        self.assertFalse((self.root / 'signed').exists())

    def test_signing_runner_isolated_and_used_for_every_app_tag(self):
        workflow = WORKFLOW.read_text()
        build, rest = workflow.split('\n  sign:\n', 1)
        sign, publish = rest.split('\n  publish:\n', 1)
        self.assertNotIn('secrets.', build)
        self.assertNotIn('secrets.', publish.replace('github.token', ''))
        self.assertIn("if: startsWith(github.ref, 'refs/tags/v')", sign)
        self.assertNotIn('contains(github.ref_name', sign)
        self.assertIn('environment: android-release', sign)
        self.assertNotIn('actions/checkout', sign)
        self.assertNotIn('flutter', sign)
        self.assertIn('needs: sign', publish)
        self.assertIn("'candidate' || 'release'", build)
        self.assertIn('path: candidate', sign)
        self.assertIn('signed/*-release.apk', sign)
        self.assertNotIn('if: always()', sign)

    def test_workflow_actions_pinned_to_immutable_commits(self):
        for action in re.findall(r'^\s+- uses: (\S+)', WORKFLOW.read_text(), re.MULTILINE):
            with self.subTest(action=action):
                self.assertRegex(action, r'@[0-9a-f]{40}$')


if __name__ == '__main__':
    unittest.main()
