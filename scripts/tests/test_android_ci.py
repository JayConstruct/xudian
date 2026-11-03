"""Exercise duplicate-run identity checks and the actual release gate shell."""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import textwrap
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import plan_android_ci as ci

WORKFLOW = Path(__file__).resolve().parents[2] / '.github/workflows/android.yml'
SHA = 'a' * 40
OTHER = 'b' * 40
PUBSPEC = 'version: 0.2.0-beta.13+1\n'
TAG = 'v0.2.0-beta.13'


def workflow_job(name):
    body = WORKFLOW.read_text().split(f'\n  {name}:\n', 1)[1]
    return re.split(r'\n  (?=\S)', body, maxsplit=1)[0]


class AndroidPlanTest(unittest.TestCase):
    def setUp(self):
        self.calls = []
        self.target = {'type': 'commit', 'sha': SHA}
        self.run = {'id': 123, 'head_sha': SHA, 'head_branch': TAG,
                    'event': 'push', 'status': 'in_progress', 'conclusion': None}
        self.runs = [self.run]

    def load(self, path):
        self.calls.append(path)
        if '/git/ref/tags/' in path:
            return {'object': self.target}
        if '/git/tags/' in path:
            return {'object': {'type': 'commit', 'sha': SHA}}
        return {'workflow_runs': self.runs}

    def plan(self, **kwargs):
        return ci.delegate_run(kwargs.get('event', 'push'),
                               kwargs.get('ref', 'refs/heads/main'), SHA,
                               'Owner/repo', kwargs.get('pubspec', PUBSPEC),
                               kwargs.get('load', self.load))

    def test_exact_tag_and_running_workflow_can_share_checks(self):
        self.assertEqual(self.plan(), 123)
        self.assertIn('head_sha=' + SHA, self.calls[-1])

    def test_tag_and_pull_request_and_manual_runs_always_validate(self):
        for event, ref in [('push', 'refs/tags/' + TAG),
                           ('pull_request', 'refs/pull/1/merge'),
                           ('workflow_dispatch', 'refs/heads/main')]:
            with self.subTest(event=event):
                self.assertEqual(self.plan(event=event, ref=ref), 0)
        self.assertEqual(self.calls, [])

    def test_annotated_tag_is_peeled_before_sharing(self):
        self.target = {'type': 'tag', 'sha': OTHER}
        self.assertEqual(self.plan(), 123)
        self.assertTrue(any('/git/tags/' in call for call in self.calls))

    def test_other_source_tag_or_absent_registered_run_keeps_full_checks(self):
        self.target['sha'] = OTHER
        self.assertEqual(self.plan(), 0)
        self.target['sha'] = SHA
        self.runs = []
        self.assertEqual(self.plan(), 0)

    def test_wrong_run_identity_never_shares_checks(self):
        for field, wrong in [('head_sha', OTHER), ('head_branch', 'v0.1.0'),
                             ('event', 'pull_request')]:
            with self.subTest(field=field):
                before = self.run[field]
                self.run[field] = wrong
                self.assertEqual(self.plan(), 0)
                self.run[field] = before

    def test_failed_cancelled_or_skipped_latest_run_does_not_hide_behind_old_success(self):
        for conclusion in ['failure', 'cancelled', 'skipped', 'timed_out']:
            with self.subTest(conclusion=conclusion):
                self.runs = [dict(self.run, status='completed', conclusion='success'),
                             dict(self.run, id=124, status='completed', conclusion=conclusion)]
                self.assertEqual(self.plan(), 0)

    def test_successful_completed_run_can_share(self):
        self.run.update(status='completed', conclusion='success')
        self.assertEqual(self.plan(), 123)

    def test_bad_api_or_invalid_version_falls_back_to_full_validation(self):
        for failure in [OSError('offline'), ValueError('bad json'), KeyError('object')]:
            with self.subTest(failure=type(failure)):
                with patch.object(ci, 'github_json', side_effect=failure) as load:
                    self.assertEqual(self.plan(load=load), 0)
        self.assertEqual(self.plan(pubspec='version: invalid\n'), 0)

    def test_main_waits_for_successful_matching_android_gate(self):
        run = dict(self.run)
        jobs = {'jobs': [{'name': 'tests (0)', 'status': 'completed', 'conclusion': 'success'}]}
        self.assertFalse(ci.delegated_result(run, jobs, SHA))
        jobs['jobs'].append({'name': 'android', 'status': 'completed', 'conclusion': 'success'})
        self.assertTrue(ci.delegated_result(run, jobs, SHA))
        jobs['jobs'][-1]['conclusion'] = 'failure'
        with self.assertRaises(ValueError):
            ci.delegated_result(run, jobs, SHA)
        with self.assertRaises(ValueError):
            ci.delegated_result(dict(run, head_sha=OTHER), jobs, SHA)
        with self.assertRaises(ValueError):
            ci.delegated_result(dict(run, status='completed'), {'jobs': []}, SHA)

    def test_wait_retries_api_failure_and_requires_gate_success(self):
        with patch.object(ci.time, 'sleep'):
            load = unittest.mock.Mock(side_effect=[OSError('transient'),
                self.run, {'jobs': []}, self.run,
                {'jobs': [{'name': 'android', 'status': 'completed', 'conclusion': 'success'}]}])
            ci.wait_for_checks(123, 'Owner/repo', SHA, load, timeout=1)
            self.assertEqual(load.call_count, 5)
        with self.assertRaises(TimeoutError):
            ci.wait_for_checks(123, 'Owner/repo', SHA, timeout=0)


class AffectedChecksTest(unittest.TestCase):
    def baseline(self):
        return {'workflow_runs': [{'id': 1, 'event': 'push', 'status': 'completed',
            'conclusion': 'success', 'head_branch': 'main', 'head_sha': OTHER}]}

    def comparison(self, files):
        return {'status': 'ahead', 'base_commit': {'sha': OTHER},
                'merge_base_commit': {'sha': OTHER},
                'files': [{'filename': name, 'status': 'modified'} for name in files]}

    def mode(self, data, **kwargs):
        def load(path):
            return self.baseline() if '/actions/' in path else data
        return ci.affected_mode(kwargs.get('event', 'push'),
                                kwargs.get('ref', 'refs/heads/main'), SHA,
                                'Owner/repo', load)

    def test_tools_and_docs_keep_tool_checks_without_flutter_or_apk(self):
        self.assertEqual(self.mode(self.comparison([
            'AGENTS.md', 'docs/RELEASE_WORKFLOW.md', 'docs/verification/release.json',
            'docs/design/selected/example.png',
            'scripts/module_host/verify_catalog.py', 'scripts/tests/test_catalog_acceptance.py'])), 'tools')

    def test_dart_tests_and_independent_modules_keep_full_flutter_without_apk(self):
        for name in ['client/test/example_test.dart', 'packages/modules/app.tasks/main.js',
                     'module-index/app.tasks.json', 'releases/modules/app.tasks-1.7.0.xmodule']:
            with self.subTest(name=name):
                self.assertEqual(self.mode(self.comparison([name, 'docs/note.md'])), 'tests')

    def test_runtime_build_tools_unknown_paths_and_tags_always_build(self):
        for name in ['client/lib/app.dart', 'client/assets/modules/a.xmodule',
                     'client/pubspec.yaml', 'client/android/app/build.gradle.kts',
                     'packages/xquickjs/lib/xquickjs.dart', 'new-runtime/input.js',
                     '.github/workflows/android.yml', 'scripts/update_emulator.py',
                     'scripts/plan_android_ci.py']:
            with self.subTest(name=name):
                self.assertEqual(self.mode(self.comparison([name])), 'full')
        for event, ref in [('push', 'refs/tags/v0.2.0-beta.20'),
                           ('pull_request', 'refs/pull/1/merge'),
                           ('workflow_dispatch', 'refs/heads/main')]:
            self.assertEqual(self.mode(self.comparison(['docs/note.md']), event=event, ref=ref), 'full')

    def test_runtime_renamed_to_a_document_still_requires_a_build(self):
        data = self.comparison(['docs/removed.md'])
        data['files'][0].update(status='renamed', previous_filename='client/lib/old.dart')
        self.assertEqual(self.mode(data), 'full')

    def test_incomplete_divergent_or_unavailable_comparisons_keep_full_checks(self):
        self.assertEqual(self.mode(self.comparison([])), 'full')
        self.assertEqual(self.mode(self.comparison(['docs/a.md'] * 300)), 'full')
        self.assertEqual(self.mode({}), 'full')
        for field in ['base_commit', 'merge_base_commit']:
            data = self.comparison(['docs/a.md']);data[field]['sha'] = SHA
            self.assertEqual(self.mode(data), 'full')
        data = self.comparison(['docs/a.md']);data['status'] = 'diverged'
        self.assertEqual(self.mode(data), 'full')
        with patch.object(ci, 'github_json', side_effect=OSError('network')) as load:
            self.assertEqual(ci.affected_mode('push', 'refs/heads/main', SHA,
                'Owner/repo', load), 'full')

    def test_failed_or_missing_baseline_cannot_make_a_later_docs_push_green(self):
        for conclusion in ['failure', 'cancelled', 'skipped']:
            data = self.baseline();data['workflow_runs'][0]['conclusion'] = conclusion
            load = unittest.mock.Mock(return_value=data)
            self.assertEqual(ci.affected_mode('push', 'refs/heads/main', SHA,
                'Owner/repo', load), 'full')
            self.assertEqual(load.call_count, 1)
        self.assertEqual(ci.affected_mode('push', 'refs/heads/main', SHA,
            'Owner/repo', lambda _: {'workflow_runs': []}), 'full')

    def test_comparison_includes_unverified_runtime_changes_before_the_latest_push(self):
        calls = []
        def load(path):
            calls.append(path)
            return self.baseline() if '/actions/' in path else self.comparison(
                ['docs/latest.md', 'client/lib/earlier-unverified.dart'])
        self.assertEqual(ci.affected_mode('push', 'refs/heads/main', SHA, 'Owner/repo', load), 'full')
        self.assertIn(OTHER + '...' + SHA, calls[-1])


class AndroidWorkflowGateTest(unittest.TestCase):
    def run_gate(self, **overrides):
        gate = workflow_job('android').split('        run: |\n', 1)[1]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'scripts').mkdir()
            # Stub only the remote waiter; the actual gate shell must decide
            # when to invoke it and must propagate its failure unchanged.
            (root / 'scripts/plan_android_ci.py').write_text(
                'import os,sys\n'
                'assert sys.argv[1:]==["--wait-for-run","123"]\n'
                'sys.exit(int(os.environ.get("WAIT_EXIT", "0")))\n')
            env = dict(os.environ, PLAN_RESULT='success', RUN_ANDROID='true',
                       VALIDATION_MODE='full',
                       CHECKS_RESULT='success', TESTS_RESULT='success',
                       BUILD_RESULT='success', DELEGATE_RUN='123')
            env.update(overrides)
            return subprocess.run(['bash', '-c', textwrap.dedent(gate)],
                                  cwd=root, env=env, capture_output=True).returncode

    def test_full_gate_requires_every_check_and_build_to_succeed(self):
        self.assertEqual(self.run_gate(), 0)
        for field in ['PLAN_RESULT', 'CHECKS_RESULT', 'TESTS_RESULT', 'BUILD_RESULT']:
            for result in ['failure', 'cancelled', 'skipped', '']:
                with self.subTest(field=field, result=result):
                    self.assertNotEqual(self.run_gate(**{field: result}), 0)
        self.assertNotEqual(self.run_gate(RUN_ANDROID=''), 0)

    def test_shared_gate_propagates_tag_failure(self):
        env = dict(RUN_ANDROID='false', VALIDATION_MODE='delegate', CHECKS_RESULT='skipped',
                   TESTS_RESULT='skipped', BUILD_RESULT='skipped')
        self.assertEqual(self.run_gate(**env), 0)
        self.assertEqual(self.run_gate(**env, WAIT_EXIT='7'), 7)

    def test_build_and_complete_test_matrix_run_independently_before_gate(self):
        for name in ['checks', 'tests', 'build']:
            body = workflow_job(name)
            self.assertIn('needs: plan', body)
        self.assertIn("if: needs.plan.outputs.run_android == 'true'", workflow_job('checks'))
        self.assertIn("if: needs.plan.outputs.run_flutter == 'true'", workflow_job('tests'))
        self.assertIn("if: needs.plan.outputs.run_apk == 'true'", workflow_job('build'))
        tests = workflow_job('tests')
        self.assertIn('shard: [0, 1, 2]', tests)
        self.assertIn('--total-shards=3', tests)
        self.assertIn('--shard-index="$TEST_SHARD"', tests)
        self.assertIn('needs: [plan, checks, tests, build]', workflow_job('android'))
        self.assertIn('if: always()', workflow_job('android'))
        self.assertIn('needs: android', workflow_job('sign'))

    def test_tools_gate_requires_checks_and_both_expensive_jobs_to_be_skipped(self):
        env = dict(VALIDATION_MODE='tools', TESTS_RESULT='skipped', BUILD_RESULT='skipped')
        self.assertEqual(self.run_gate(**env), 0)
        self.assertNotEqual(self.run_gate(**env, CHECKS_RESULT='failure'), 0)
        for field in ['TESTS_RESULT', 'BUILD_RESULT']:
            for result in ['failure', 'cancelled', 'success']:
                self.assertNotEqual(self.run_gate(**{**env, field: result}), 0)

    def test_test_only_gate_cannot_skip_or_ignore_a_failed_flutter_shard(self):
        self.assertEqual(self.run_gate(VALIDATION_MODE='tests', BUILD_RESULT='skipped'), 0)
        for result in ['failure', 'cancelled', 'skipped']:
            self.assertNotEqual(self.run_gate(VALIDATION_MODE='tests',
                BUILD_RESULT='skipped', TESTS_RESULT=result), 0)
        self.assertNotEqual(self.run_gate(VALIDATION_MODE='unknown'), 0)
        self.assertNotEqual(self.run_gate(VALIDATION_MODE='delegate'), 0)


if __name__ == '__main__':
    unittest.main()
