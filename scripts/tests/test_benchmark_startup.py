"""Cold-start sampling rejects invalid launches instead of skewing summaries."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import Mock

SCRIPT = Path(__file__).resolve().parents[1] / 'benchmark_startup.py'
spec = importlib.util.spec_from_file_location('benchmark_startup', SCRIPT)
benchmark = importlib.util.module_from_spec(spec)
spec.loader.exec_module(benchmark)

PACKAGE = 'dev.taskapp.task_app'
COMMAND = ['adb', '-H', '127.0.0.1', '-P', '5037', '-s', 'emulator-5554']
LAUNCH = '''Starting: Intent { cmp=dev.taskapp.task_app/.MainActivity }
Status: ok
LaunchState: COLD
Activity: dev.taskapp.task_app/.MainActivity
ThisTime: 350
TotalTime: 370
WaitTime: 380
Complete
'''


def response(output='', code=0, stderr=''):
    return subprocess.CompletedProcess([], code, stdout=output, stderr=stderr)


def trial(launch=LAUNCH, processes='PID NAME\n1 init\n'):
    return [response(), response(processes), response(launch)]


class ParseTests(unittest.TestCase):
    def test_readiness_only_accepts_current_launch_token_and_known_outcomes(self):
        token = 'a' * 32
        self.assertEqual(benchmark.parse_readiness(
            f'outcome=ready workspaceReadyMs=1200 launchToken={token}', token), 1200)
        self.assertIsNone(benchmark.parse_readiness(
            f'outcome=ready workspaceReadyMs=1 launchToken={"b" * 32}', token))
        self.assertIsNone(benchmark.parse_readiness('unrelated private log', token))
        for outcome in ('restoreError', 'noWorkspace'):
            with self.subTest(outcome=outcome), self.assertRaises(benchmark.BenchmarkError):
                benchmark.parse_readiness(f'outcome={outcome} workspaceReadyMs=10 launchToken={token}', token)

    def test_preserves_distinct_raw_metrics(self):
        parsed = benchmark.parse_launch(LAUNCH)
        self.assertEqual([parsed[name] for name in benchmark.METRICS], [350, 370, 380])

    def test_android_without_this_time_leaves_null(self):
        self.assertIsNone(benchmark.parse_launch(LAUNCH.replace('ThisTime: 350\n', ''))['ThisTime'])

    def test_rejects_errors_warnings_invalid_or_missing_timings_and_non_cold(self):
        for text in (
            LAUNCH.replace('Status: ok', 'Status: timeout'),
            LAUNCH.replace('Status: ok\n', ''),
            LAUNCH + '\nError: Activity does not exist',
            LAUNCH + '\nWarning: Activity not started, intent delivered',
            LAUNCH.replace('TotalTime: 370', 'TotalTime: -1'),
            LAUNCH.replace('WaitTime: 380\n', ''),
            LAUNCH.replace('LaunchState: COLD', 'LaunchState: WARM'),
            LAUNCH + '\nTotalTime: 99',
        ):
            with self.subTest(text=text), self.assertRaises(benchmark.BenchmarkError):
                benchmark.parse_launch(text)

    def test_median_nearest_rank_and_missing_metric_counts(self):
        samples = [{'TotalTime': value, 'WaitTime': value + 1, 'ThisTime': None}
                   for value in (40, 10, 30, 20)]
        summary = benchmark.summarize(samples)
        self.assertEqual(summary['TotalTime'], {'count': 4, 'p50Ms': 25.0, 'p95Ms': 40, 'minMs': 10, 'maxMs': 40})
        self.assertEqual(summary['ThisTime']['count'], 0)
        self.assertIsNone(summary['ThisTime']['p95Ms'])


TOKEN = 'a' * 32


def phase_log(phase, token=TOKEN):
    return json.dumps(phase) + f' launchToken={token}'


def complete_phases(phases, token=TOKEN):
    return '\n'.join([*(phase_log(phase, token) for phase in phases),
                      f'complete=true launchToken={token}'])


def ready_log(token=TOKEN):
    return f'outcome=ready workspaceReadyMs=1234 launchToken={token}'


PHASE = {'name': 'host.worker.load', 'count': 2, 'elapsedUs': 12000,
         'moduleId': 'app.views.today', 'worker': 'workflow'}


class PhaseTests(unittest.TestCase):
    def test_only_current_token_validated_fields_are_returned(self):
        text = '\n'.join([
            'unrelated private log',
            phase_log({'private': 'secret'}, 'b' * 32),
            f'complete=true launchToken={"b" * 32}',
            f'I/XudianStartupPhases( 567): {phase_log(PHASE)}',
            f'I/XudianStartupPhases( 567): complete=true launchToken={TOKEN}',
        ])
        phases, complete = benchmark.parse_phases(text, TOKEN)
        self.assertTrue(complete)
        self.assertEqual(phases, [PHASE])
        self.assertNotIn('private', repr(phases))
        self.assertNotIn('launchToken', repr(phases))

    def test_partial_current_snapshot_does_not_claim_completion(self):
        self.assertEqual(benchmark.parse_phases(phase_log(PHASE), TOKEN), ([PHASE], False))
        self.assertEqual(benchmark.parse_phases('', TOKEN), ([], False))
        self.assertEqual(benchmark.parse_phases(f'complete=true launchToken={TOKEN}', TOKEN), ([], True))

    def test_bad_fields_are_rejected_without_echoing_payload(self):
        for phase in (
            [], 'private', {},
            {**PHASE, 'private': 'private form value'},
            {**PHASE, 'name': 'private business event'},
            {**PHASE, 'name': []},
            {**PHASE, 'count': True},
            {**PHASE, 'count': 0},
            {**PHASE, 'count': 1.5},
            {**PHASE, 'count': '2'},
            {**PHASE, 'elapsedUs': False},
            {**PHASE, 'elapsedUs': -1},
            {**PHASE, 'elapsedUs': float('inf')},
            {**PHASE, 'elapsedUs': float('nan')},
            {**PHASE, 'elapsedUs': 1 << 63},
            {**PHASE, 'moduleId': 'app.Private'},
            {**PHASE, 'moduleId': 'app.tasks; private'},
            {**PHASE, 'moduleId': ''},
            {**PHASE, 'moduleId': None},
            {**PHASE, 'worker': 'private'},
            {**PHASE, 'worker': []},
        ):
            with self.subTest(phase=phase):
                with self.assertRaises(benchmark.BenchmarkError) as error:
                    benchmark.parse_phases(complete_phases([phase]), TOKEN)
                self.assertNotIn('private', str(error.exception))

    def test_bad_json_duplicates_and_marker_order_are_rejected(self):
        for payload in (
            f'{{private invalid JSON}} launchToken={TOKEN}',
            f'{{"name":"host.restore","name":"page.queue","count":1,"elapsedUs":1}} launchToken={TOKEN}',
            f'complete=false launchToken={TOKEN}',
            f'complete=true launchToken={TOKEN} extra=private',
            '\n'.join([phase_log(PHASE), phase_log(PHASE)]),
            '\n'.join([f'complete=true launchToken={TOKEN}', phase_log(PHASE)]),
            '\n'.join([f'complete=true launchToken={TOKEN}'] * 2),
        ):
            with self.subTest(payload=payload), self.assertRaises(benchmark.BenchmarkError):
                benchmark.parse_phases(payload, TOKEN)

    def test_group_limit_and_known_module_worker_variants(self):
        phases = [{'name': 'host.worker.load', 'count': 1, 'elapsedUs': 0,
                   'moduleId': f'app.module{index}', 'worker': 'computation'}
                  for index in range(benchmark.MAXIMUM_PHASE_GROUPS)]
        self.assertEqual(benchmark.parse_phases(complete_phases(phases), TOKEN), (phases, True))
        with self.assertRaises(benchmark.BenchmarkError):
            benchmark.parse_phases(complete_phases(phases + [{**PHASE, 'moduleId': 'app.extra-module'}]), TOKEN)
        self.assertEqual(benchmark.parse_phases(complete_phases([
            {'name': 'app.firstFrame', 'count': 1, 'elapsedUs': 0},
            {**PHASE, 'moduleId': 'app.extra_module'},
            {**PHASE, 'worker': 'computation'},
        ]), TOKEN)[1], True)

    def test_database_ready_is_accepted_as_a_distinct_phase(self):
        phases = [
            {'name': 'database.open', 'count': 1, 'elapsedUs': 525000},
            {'name': 'database.ready', 'count': 1, 'elapsedUs': 580000},
        ]
        self.assertEqual(benchmark.parse_phases(complete_phases(phases), TOKEN), (phases, True))
        summary = benchmark.summarize([{'startupPhases': phases}])['startupPhases']
        self.assertEqual(len(summary), 2)
        ready = next(item for item in summary if item['name'] == 'database.ready')
        self.assertEqual(ready['elapsedUs']['p50'], 580000)

    def test_all_native_phase_names_are_accepted(self):
        phases = [{'name': name, 'count': 1, 'elapsedUs': 1}
                  for name in sorted(benchmark.PHASE_NAMES)]
        self.assertEqual(benchmark.parse_phases(complete_phases(phases), TOKEN), (phases, True))

    def test_summary_preserves_groups_and_does_not_sum_nested_phases(self):
        parent = {'name': 'host.restore', 'count': 1, 'elapsedUs': 50000}
        other_worker = {**PHASE, 'worker': 'computation'}
        samples = [
            {'startupPhases': [parent, PHASE, other_worker]},
            {'startupPhases': [{**parent, 'elapsedUs': 70000},
                               {**PHASE, 'count': 4, 'elapsedUs': 18000}]},
        ]
        summary = benchmark.summarize(samples)['startupPhases']
        self.assertEqual(len(summary), 3)
        restored = next(item for item in summary if item['name'] == 'host.restore')
        self.assertEqual(restored['elapsedUs'], {'p50': 60000.0, 'p95': 70000, 'min': 50000, 'max': 70000})
        workflow = next(item for item in summary if item.get('worker') == 'workflow')
        self.assertEqual(workflow['count']['p50'], 3.0)
        self.assertEqual(workflow['elapsedUs']['p50'], 15000.0)
        self.assertEqual(workflow['sampleCount'], 2)
        computation = next(item for item in summary if item.get('worker') == 'computation')
        self.assertEqual(computation['sampleCount'], 1)
        self.assertNotIn('startupPhases', benchmark.summarize([{'TotalTime': 12}]))


class CaptureCollectTests(unittest.TestCase):
    def test_capture_polls_complete_snapshot_and_saves_only_whitelisted_records(self):
        run = Mock(side_effect=trial() + [response('567'), response(ready_log()),
                    response(phase_log(PHASE)), response('private log\n' + complete_phases([PHASE]))])
        sleep = Mock()
        report = benchmark.collect(COMMAND, PACKAGE, '.MainActivity', 1,
                                   run=run, sleep=sleep, wait_ready=True, capture_phases=True,
                                   token_factory=lambda: TOKEN)
        self.assertTrue(report['complete'])
        self.assertTrue(report['captureStartupPhases'])
        self.assertEqual(report['samples'][0]['startupPhases'], [PHASE])
        self.assertEqual(report['summary']['startupPhases'][0]['elapsedUs']['p50'], 12000)
        self.assertNotIn('private log', repr(report))
        self.assertNotIn('launchToken', repr(report['samples'][0]['startupPhases']))
        sleep.assert_called_once_with(0.25)
        self.assertEqual(run.call_args.args[0], COMMAND + [
            'logcat', '-d', '-b', 'main', '-v', 'raw', '--pid', '567',
            '-s', 'XudianStartupPhases:I', '*:S'])

    def test_phase_command_uses_remaining_workspace_deadline(self):
        run = Mock(side_effect=trial() + [response('567'), response(ready_log()),
                    response(complete_phases([PHASE]))])
        report = benchmark.collect(COMMAND, PACKAGE, '.MainActivity', 1,
                                   run=run, wait_ready=True, capture_phases=True,
                                   ready_timeout=10, monotonic=Mock(side_effect=[0, 1, 8]),
                                   token_factory=lambda: TOKEN)
        self.assertTrue(report['complete'])
        self.assertEqual(run.call_args_list[-2].kwargs['timeout'], 9)
        self.assertEqual(run.call_args.kwargs['timeout'], 2)

    def test_missing_or_other_launch_complete_rejects_entire_trial(self):
        for logs in (phase_log(PHASE), complete_phases([PHASE], 'b' * 32),
                     phase_log(PHASE) + f'\ncomplete=true launchToken={"b" * 32}'):
            run = Mock(side_effect=trial() + [response('567'), response(ready_log()), response(logs)])
            with self.subTest(logs=logs):
                report = benchmark.collect(COMMAND, PACKAGE, '.MainActivity', 1,
                                           run=run, wait_ready=True, capture_phases=True,
                                           monotonic=Mock(side_effect=[0, 0, 0, 31]),
                                           token_factory=lambda: TOKEN)
                self.assertFalse(report['complete'])
                self.assertEqual(report['completedRuns'], 0)
                self.assertEqual(report['samples'], [])
                error = report['errors'][0]
                self.assertEqual(error['phase'], 'waitForStartupPhases')
                self.assertEqual(error['operation'], 'logcat')
                self.assertEqual(error['exitCode'], 0)
                self.assertTrue(error['timedOut'])
                self.assertNotIn('startupPhases', report['summary'])

    def test_malformed_current_phase_is_failed_and_private_data_is_not_retained(self):
        logs = complete_phases([{**PHASE, 'private': 'private business parameter'}])
        run = Mock(side_effect=trial() + [response('567'), response(ready_log()), response(logs)])
        report = benchmark.collect(COMMAND, PACKAGE, '.MainActivity', 1,
                                   run=run, wait_ready=True, capture_phases=True,
                                   token_factory=lambda: TOKEN)
        self.assertFalse(report['complete'])
        self.assertEqual(report['samples'], [])
        self.assertEqual(report['errors'][0]['phase'], 'waitForStartupPhases')
        self.assertEqual(report['errors'][0]['operation'], 'logcat')
        self.assertEqual(report['errors'][0]['exitCode'], 0)
        self.assertFalse(report['errors'][0]['timedOut'])
        self.assertNotIn('private business parameter', repr(report))

    def test_phase_command_failures_preserve_sanitized_diagnostics(self):
        for result in (response('private stdout', code=7, stderr='private stderr'),
                       subprocess.TimeoutExpired('private command', 2,
                                                 output=b'private stdout', stderr=b'private stderr')):
            run = Mock(side_effect=trial() + [response('567'), response(ready_log()), result])
            with self.subTest(result=result):
                report = benchmark.collect(COMMAND, PACKAGE, '.MainActivity', 1,
                                           run=run, wait_ready=True, capture_phases=True,
                                           ready_timeout=10, monotonic=Mock(side_effect=[0, 1, 8]),
                                           token_factory=lambda: TOKEN)
                error = report['errors'][0]
                self.assertEqual(error['phase'], 'waitForStartupPhases')
                self.assertEqual(error['operation'], 'logcat')
                self.assertEqual(error['timeoutSeconds'], 2)
                self.assertEqual(error['exitCode'], 7 if isinstance(result, subprocess.CompletedProcess) else None)
                self.assertEqual(error['timedOut'], isinstance(result, subprocess.TimeoutExpired))
                self.assertTrue(error['stdoutPresent'])
                self.assertTrue(error['stderrPresent'])
                self.assertNotIn('private', repr(report))

    def test_expired_shared_deadline_does_not_run_phase_logcat(self):
        run = Mock(side_effect=trial() + [response('567'), response(ready_log())])
        report = benchmark.collect(COMMAND, PACKAGE, '.MainActivity', 1,
                                   run=run, wait_ready=True, capture_phases=True,
                                   monotonic=Mock(side_effect=[0, 1, 30]),
                                   token_factory=lambda: TOKEN)
        self.assertEqual(run.call_count, 5)
        self.assertFalse(report['complete'])
        self.assertEqual(report['errors'][0]['phase'], 'waitForStartupPhases')
        self.assertTrue(report['errors'][0]['timedOut'])

    def test_failed_later_capture_does_not_bias_valid_phase_summaries(self):
        next_token = 'b' * 32
        run = Mock(side_effect=(
            trial() + [response('567'), response(ready_log()), response(complete_phases([PHASE]))] +
            trial() + [response('568'), response(ready_log(next_token)),
                       response(complete_phases([{**PHASE, 'count': 0}], next_token))]))
        tokens = iter((TOKEN, next_token))
        report = benchmark.collect(COMMAND, PACKAGE, '.MainActivity', 2,
                                   interval=0, run=run, wait_ready=True, capture_phases=True,
                                   token_factory=lambda: next(tokens))
        self.assertFalse(report['complete'])
        self.assertEqual(report['completedRuns'], 1)
        self.assertEqual(report['samples'][0]['startupPhases'], [PHASE])
        self.assertEqual(report['summary']['startupPhases'][0]['sampleCount'], 1)
        self.assertEqual(report['errors'][0]['trial'], 2)
        commands = [call.args[0] for call in run.call_args_list]
        self.assertEqual(commands[8][-1], next_token)
        self.assertIn('568', commands[-1])

    def test_capture_requires_readiness_before_device_access(self):
        run = Mock()
        with self.assertRaises(benchmark.BenchmarkError):
            benchmark.collect(COMMAND, PACKAGE, '.MainActivity', 1, run=run, capture_phases=True)
        run.assert_not_called()

    def test_readiness_only_behavior_does_not_request_or_emit_phases(self):
        run = Mock(side_effect=trial() + [response('567'), response(ready_log())])
        report = benchmark.collect(COMMAND, PACKAGE, '.MainActivity', 1,
                                   run=run, wait_ready=True, token_factory=lambda: TOKEN)
        self.assertTrue(report['complete'])
        self.assertEqual(run.call_count, 5)
        self.assertNotIn('captureStartupPhases', report)
        self.assertNotIn('startupPhases', report['samples'][0])
        self.assertNotIn('startupPhases', report['summary'])


class CollectTests(unittest.TestCase):
    def test_waits_for_readiness_and_keeps_raw_logs_out_of_report(self):
        token = 'a' * 32
        run = Mock(side_effect=trial() + [response('567'), response(''), response(
            f'private unrelated log\noutcome=ready workspaceReadyMs=1234 launchToken={token}')])
        sleep = Mock()
        report = benchmark.collect(COMMAND, PACKAGE, '.MainActivity', 1,
                                   run=run, sleep=sleep, wait_ready=True,
                                   token_factory=lambda: token)
        self.assertTrue(report['complete'])
        self.assertEqual(report['summary'][benchmark.READY_METRIC]['p50Ms'], 1234)
        self.assertEqual(report['samples'][0]['workspaceOutcome'], 'ready')
        self.assertNotIn('private unrelated log', repr(report))
        commands = [call.args[0] for call in run.call_args_list]
        self.assertEqual(commands[2][-3:], ['--es', 'xudian.benchmark.launchToken', token])
        self.assertEqual(commands[-1], COMMAND + ['logcat', '-d', '-b', 'main', '-v', 'raw',
                                                 '--pid', '567', '-s', 'XudianStartup:I', '*:S'])
        sleep.assert_called_once_with(0.25)

    def test_timeout_or_unavailable_workspace_rejects_entire_trial(self):
        token = 'a' * 32
        for text, error in (('', 'Timed out'),
                            (f'outcome=noWorkspace workspaceReadyMs=30 launchToken={token}', 'noWorkspace')):
            run = Mock(side_effect=trial() + [response('567'), response(text)])
            clock = Mock(side_effect=[0.0, 0.0, 31.0])
            with self.subTest(text=text):
                report = benchmark.collect(COMMAND, PACKAGE, '.MainActivity', 1,
                                           run=run, wait_ready=True, monotonic=clock,
                                           token_factory=lambda: token)
                self.assertFalse(report['complete'])
                self.assertEqual(report['completedRuns'], 0)
                self.assertIn(error, report['errors'][0]['message'])

    def test_each_trial_force_stops_and_checks_absence_before_start(self):
        run = Mock(side_effect=trial() + trial())
        sleep = Mock()
        report = benchmark.collect(COMMAND, PACKAGE, '.MainActivity', 2, run=run, sleep=sleep)
        self.assertTrue(report['complete'])
        self.assertEqual(report['completedRuns'], 2)
        commands = [call.args[0] for call in run.call_args_list]
        self.assertEqual(commands[0], COMMAND + ['shell', 'am', 'force-stop', PACKAGE])
        self.assertEqual(commands[1], COMMAND + ['shell', 'ps', '-A', '-o', 'PID,NAME'])
        self.assertEqual(commands[2][-2:], ['-n', PACKAGE + '/.MainActivity'])
        self.assertEqual(commands[:3], commands[3:])
        sleep.assert_called_once_with(1.0)
        self.assertEqual(report['samples'][0]['rawAmStart'], LAUNCH.strip())

    def test_remaining_main_or_worker_process_prevents_launch(self):
        for name in (PACKAGE, PACKAGE + ':worker'):
            run = Mock(side_effect=[response(), response(f'PID NAME\n777 {name}\n')])
            with self.subTest(name=name):
                report = benchmark.collect(COMMAND, PACKAGE, '.MainActivity', 1, run=run)
                self.assertFalse(report['complete'])
                self.assertEqual(run.call_count, 2)
                self.assertIn('still exists', report['errors'][0]['message'])

    def test_unsupported_process_listing_is_not_accepted(self):
        for table in ('', 'USER PID NAME\nroot 1 init\n', 'PID NAME\ninvalid row extra\n'):
            run = Mock(side_effect=[response(), response(table)])
            with self.subTest(table=table):
                report = benchmark.collect(COMMAND, PACKAGE, '.MainActivity', 1, run=run)
                self.assertFalse(report['complete'])
                self.assertEqual(run.call_count, 2)

    def test_device_command_failure_and_timeout_abort_cleanly(self):
        for result in (response(code=1), response(stderr='error: device offline'),
                       subprocess.TimeoutExpired('adb', 60)):
            run = Mock(side_effect=[result])
            with self.subTest(result=result):
                report = benchmark.collect(COMMAND, PACKAGE, '.MainActivity', 1, run=run)
                self.assertFalse(report['complete'])
                self.assertEqual(report['completedRuns'], 0)

    def test_command_failures_identify_phase_exit_code_without_output(self):
        for prefix, phase, operation in (
            ([], 'forceStop', 'am force-stop'),
            (trial()[:1], 'verifyProcessAbsence', 'ps'),
            (trial()[:2], 'launch', 'am start'),
            (trial(), 'checkPid', 'pidof'),
            (trial() + [response('567')], 'waitForWorkspaceReady', 'logcat'),
        ):
            with self.subTest(phase=phase):
                run = Mock(side_effect=prefix + [response('private stdout', code=7,
                                                         stderr='private stderr')])
                report = benchmark.collect(COMMAND, PACKAGE, '.MainActivity', 1,
                                           run=run, check_pid=True, wait_ready=True)
                error = report['errors'][0]
                self.assertEqual(error['phase'], phase)
                self.assertEqual(error['operation'], operation)
                self.assertEqual(error['exitCode'], 7)
                self.assertTrue(error['stdoutPresent'])
                self.assertTrue(error['stderrPresent'])
                self.assertFalse(error['timedOut'])
                self.assertNotIn('private stdout', repr(report))
                self.assertNotIn('private stderr', repr(report))

    def test_readiness_logcat_timeout_uses_remaining_deadline(self):
        run = Mock(side_effect=trial() + [response('567'),
            subprocess.TimeoutExpired('private command', 2.5,
                                      output=b'private stdout', stderr=b'private stderr')])
        clock = Mock(side_effect=[10.0, 12.5])
        report = benchmark.collect(COMMAND, PACKAGE, '.MainActivity', 1,
                                   run=run, wait_ready=True, ready_timeout=5,
                                   monotonic=clock)
        self.assertEqual(run.call_args.kwargs['timeout'], 2.5)
        error = report['errors'][0]
        self.assertEqual(error['phase'], 'waitForWorkspaceReady')
        self.assertEqual(error['operation'], 'logcat')
        self.assertIsNone(error['exitCode'])
        self.assertTrue(error['timedOut'])
        self.assertEqual(error['timeoutSeconds'], 2.5)
        self.assertEqual(error['exceptionType'], 'TimeoutExpired')
        self.assertTrue(error['stdoutPresent'])
        self.assertTrue(error['stderrPresent'])
        self.assertNotIn('private', repr(report))

    def test_expired_readiness_deadline_does_not_launch_logcat(self):
        run = Mock(side_effect=trial() + [response('567')])
        report = benchmark.collect(COMMAND, PACKAGE, '.MainActivity', 1,
                                   run=run, wait_ready=True,
                                   monotonic=Mock(side_effect=[0.0, 30.0]))
        self.assertFalse(report['complete'])
        self.assertEqual(run.call_count, 4)
        self.assertEqual(report['errors'][0]['phase'], 'waitForWorkspaceReady')
        self.assertEqual(report['errors'][0]['operation'], 'logcat')
        self.assertIsNone(report['errors'][0]['exitCode'])
        self.assertTrue(report['errors'][0]['timedOut'])

    def test_failed_trial_is_not_included_in_summary(self):
        run = Mock(side_effect=trial() + trial(LAUNCH.replace('Status: ok', 'Status: timeout')))
        report = benchmark.collect(COMMAND, PACKAGE, '.MainActivity', 3, interval=0, run=run)
        self.assertFalse(report['complete'])
        self.assertEqual(report['summary']['TotalTime']['count'], 1)
        self.assertEqual(report['errors'][0]['trial'], 2)
        self.assertEqual(run.call_count, 6)

    def test_optional_post_launch_pid_check(self):
        run = Mock(side_effect=trial() + [response('567 568')])
        report = benchmark.collect(COMMAND, PACKAGE, '.MainActivity', 1, check_pid=True, run=run)
        self.assertTrue(report['complete'])
        self.assertEqual(report['samples'][0]['pidAfterLaunch'], [567, 568])
        run.assert_called_with(COMMAND + ['shell', 'pidof', PACKAGE], capture_output=True, text=True, check=False, timeout=60)

    def test_absent_post_launch_pid_invalidates_trial(self):
        run = Mock(side_effect=trial() + [response(code=1)])
        report = benchmark.collect(COMMAND, PACKAGE, '.MainActivity', 1, check_pid=True, run=run)
        self.assertFalse(report['complete'])
        self.assertEqual(report['completedRuns'], 0)


class ArgumentTests(unittest.TestCase):
    def test_defaults_and_explicit_configuration(self):
        args = benchmark.arguments(['--serial', 'emulator-5554', '--output', '/tmp/startup.json'])
        self.assertEqual(args.package, PACKAGE)
        self.assertEqual(args.runs, 10)
        self.assertEqual(args.adb_port, 5037)
        custom = benchmark.arguments(['--serial', 'device', '--output', '/tmp/startup.json',
                                      '--package', 'org.example.app', '--activity', 'org.example.Main',
                                      '--runs', '2', '--adb-port', '5038', '--check-pid'])
        self.assertTrue(custom.check_pid)
        self.assertEqual(custom.activity, 'org.example.Main')

    def test_phase_capture_requires_readiness_cli_flag(self):
        base = ['--serial', 'emulator-5554', '--output', '/tmp/startup.json']
        args = benchmark.arguments(base + ['--wait-ready', '--capture-phases'])
        self.assertTrue(args.capture_phases)
        self.assertTrue(args.wait_ready)
        self.assertFalse(benchmark.arguments(base).capture_phases)
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            benchmark.arguments(base + ['--capture-phases'])

    def test_invalid_arguments_fail_before_device_access(self):
        for extra in (
            ['--package', 'bad;package'], ['--activity', 'a/b'], ['--runs', '0'],
            ['--runs', '1001'], ['--adb-port', '0'], ['--adb-port', '65536'],
            ['--interval', 'nan'], ['--interval', 'inf'], ['--interval', '-1'],
            ['--ready-timeout', '0'], ['--ready-timeout', 'nan'], ['--ready-timeout', '121'],
            ['--serial', ''], ['--adb-host', ''],
        ):
            with self.subTest(extra=extra), contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                benchmark.arguments(['--serial', 'emulator-5554', '--output', '/tmp/startup.json', *extra])


if __name__ == '__main__':
    unittest.main()
