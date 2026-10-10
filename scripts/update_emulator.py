#!/usr/bin/env python3
"""Check, build and update an x86_64 emulator, then optionally commit named files."""
import argparse
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import shutil
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from emulator_workflow import snapshot, fingerprint, changed_files, select_tests, checks_fingerprint, reusable

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = 'dev.taskapp.task_app'
SPLIT_X64_OFFSET = 4000
DEFAULT_TESTS = ['test/host_ui_test.dart', 'test/ui_pack_chrome_test.dart']


def run(command, *, cwd=ROOT, capture=False, timeout=None):
    print('+ ' + shlex.join(map(str, command)), flush=True)
    result = subprocess.run(command, cwd=cwd, check=True, text=True,
                            stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.PIPE if capture else None,
                            timeout=timeout)
    return result.stdout if capture else ''


def next_build_number(installed, previous=0):
    base = installed - SPLIT_X64_OFFSET if installed >= SPLIT_X64_OFFSET else installed
    return max(base, previous) + 1


def commit_files(message, paths, *, root=ROOT):
    # --only leaves unrelated staged files out of the commit and preserves them.
    run(['git', '--literal-pathspecs', 'add', '--', *paths], cwd=root)
    run(['git', '--literal-pathspecs', 'commit', '--only', '--message', message, '--', *paths], cwd=root)
    return run(['git', 'rev-parse', 'HEAD'], cwd=root, capture=True).strip()


def validate_commit_paths(paths, *, root=ROOT):
    names = []
    for raw in paths:
        path = (root / raw).resolve()
        try:
            name = path.relative_to(root.resolve()).as_posix()
        except ValueError:
            raise ValueError(f'提交文件必须在仓库内：{raw}') from None
        if name == '.' or name.startswith('.git/') or name == '.git' or path.is_dir():
            raise ValueError(f'请逐个指定文件，不接受目录：{raw}')
        tracked = subprocess.run(['git', '--literal-pathspecs', 'ls-files', '--error-unmatch', '--', name],
                                 cwd=root, capture_output=True).returncode == 0
        if not tracked and not path.is_file():
            raise ValueError(f'文件不存在且未被 Git 跟踪：{raw}')
        ignored = subprocess.run(['git', 'check-ignore', '--stdin', '-z'], cwd=root,
                                 input=(name + '\0').encode(), capture_output=True)
        if ignored.returncode not in (0, 1):
            raise ValueError(f'无法检查文件的 Git 忽略规则：{raw}')
        if ignored.returncode == 0:
            raise ValueError(f'文件在 Git 忽略列表中：{raw}')
        names.append(name)
    return list(dict.fromkeys(names))


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--serial', default='emulator-5554', help='模拟器序列号')
    p.add_argument('--adb-host', default=os.environ.get('XUDIAN_ADB_HOST', '127.0.0.1'))
    p.add_argument('--adb-port', type=int, default=int(os.environ.get('XUDIAN_ADB_PORT', '5037')))
    p.add_argument('--build-number', type=int, help='默认按模拟器和最近成功记录递增')
    p.add_argument('--test', action='append', default=[], metavar='TEST_FILE',
                   help='指定相关 Flutter 测试，可重复；默认验证页面与菜单')
    p.add_argument('--full-tests', action='store_true', help='执行全部 Flutter 测试')
    p.add_argument('--commit', metavar='MESSAGE', help='安装验证成功后创建本地 Git 提交')
    p.add_argument('--path', action='append', default=[], metavar='FILE',
                   help='本次提交文件，可重复；不接受目录，不自动提交整个工作区')
    p.add_argument('--dry-run', action='store_true', help='只打印流程，不连接模拟器或执行修改')
    p.add_argument('--dev', action='store_true', help='安装调试版并连接热重载：r刷新、R重启、q退出')
    p.add_argument('--no-attach', action='store_true', help='--dev仅更新调试版，不保持调试连接')
    p.add_argument('--module', action='append', default=[], metavar='MODULE_ID', help='同时更新指定独立模块，可重复')
    p.add_argument('--modules-only', action='store_true', help='只检查并更新指定模块，不构建或安装APK')
    p.add_argument('--force', action='store_true', help='忽略检查/构建缓存并重新执行')
    return p


def main(argv=None):
    p = parser()
    args = p.parse_args(argv)
    if bool(args.commit) != bool(args.path):
        p.error('--commit 和 --path 必须一起提供')
    if args.commit is not None and not args.commit.strip():
        p.error('提交说明不能为空')
    if args.full_tests and args.test:
        p.error('--full-tests 与 --test 不能同时使用')
    if args.build_number is not None and args.build_number < 1:
        p.error('--build-number 必须大于零')
    if not 1 <= args.adb_port <= 65535:
        p.error('ADB 端口必须在 1 到 65535 之间')
    if args.modules_only and (not args.module or args.dev or args.build_number):
        p.error('--modules-only 需要 --module，且不能与 --dev 或 --build-number 同用')
    if args.no_attach and not args.dev:
        p.error('--no-attach 需要 --dev')
    for module in args.module:
        if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9._-]*', module) or not (ROOT / 'packages/modules' / module / 'module.json').is_file():
            p.error(f'模块不存在或ID无效：{module}')
    paths = validate_commit_paths(args.path, root=ROOT)
    mode = 'debug' if args.dev else 'release'
    output = ROOT / '.cache/emulator-update'
    cache_file = output / f'{mode}-cache.json'
    cache = json.loads(cache_file.read_text()) if cache_file.exists() else {}
    inputs = snapshot(ROOT)
    source_digest = fingerprint(inputs)
    changes = changed_files(cache.get('inputs', {}), inputs)
    tests = None if args.full_tests else args.test or select_tests(changes, args.module, first_run=not cache)
    for test in tests or []:
        path = (ROOT / 'client' / test).resolve()
        if not path.is_relative_to(ROOT / 'client/test') or not path.is_file():
            p.error(f'测试必须是 client/test 内存在的文件：{test}')
    adb = ['adb', '-H', args.adb_host, '-P', str(args.adb_port), '-s', args.serial]
    if args.dry_run:
        print(f'模拟器：{args.serial}；仅支持 x86_64 Android 模拟器')
        print('模式：' + ('仅更新模块' if args.modules_only else mode))
        print('流程：仓库与预装资源检查 → 相关检查 → ' + ('模块打包/审核安装' if args.modules_only else '复用或构建APK → 核对安装 → 启动'))
        print('模块：' + ', '.join(args.module))
        print('构建号：' + str(args.build_number or '按需自动递增'))
        print('测试：' + ('全部测试' if tests is None else ', '.join(tests)))
        if args.dev and not args.no_attach:
            print('启动后 flutter attach，按 r 热重载、R 热重启、q 退出。')
        if args.commit:
            print('最后提交：' + args.commit + '\n文件：' + ', '.join(paths))
        print('不推送 GitHub。')
        return 0

    output.mkdir(parents=True, exist_ok=True)
    with (output / 'update.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError('已有更新流程在执行，稍后再运行') from None
        # Re-read after locking, in case another update finished during preflight.
        cache = json.loads(cache_file.read_text()) if cache_file.exists() else {}
        report = {'startedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  'serial': args.serial, 'mode': 'modules-only' if args.modules_only else mode,
                  'modulePackagesUpdated': False, 'githubPushed': False, 'completed': False,
                  'steps': [], 'stepSeconds': {}, 'selectedTests': tests,
                  'sourceFingerprint': source_digest, 'reusedBuild': False,
                  'reusedChecks': False, 'skippedInstall': False}
        phase = '连接模拟器'
        started_at = time.monotonic()

        def perform(label, command, *, cwd=ROOT, capture=False, timeout=None):
            nonlocal phase
            phase = label
            print(f'\n[{label}]', flush=True)
            start = time.monotonic()
            result = run(command, cwd=cwd, capture=capture, timeout=timeout)
            report['steps'].append(label)
            report['stepSeconds'][label] = round(time.monotonic() - start, 3)
            return result

        try:
            perform('仓库与预装资源检查', ['python3', str(ROOT / 'scripts/check_repository.py')])
            if run([*adb, 'get-state'], capture=True, timeout=15).strip() != 'device':
                raise ValueError('模拟器未就绪')
            qemu = run([*adb, 'shell', 'getprop', 'ro.kernel.qemu'], capture=True, timeout=15).strip()
            abi = run([*adb, 'shell', 'getprop', 'ro.product.cpu.abi'], capture=True, timeout=15).strip()
            if qemu != '1' or abi != 'x86_64':
                raise ValueError('此脚本只安装到 x86_64 模拟器，不能用于真机')
            info = run([*adb, 'shell', 'dumpsys', 'package', PACKAGE], capture=True, timeout=30)
            match = re.search(r'\bversionCode=(\d+)', info)
            installed = int(match[1]) if match else 0
            report['installedVersionCodeBefore'] = installed
            if args.modules_only and not installed:
                raise ValueError('请先安装客户端，再运行仅更新模块模式')
            if paths:
                run(['git', '--literal-pathspecs', 'diff', '--check', '--', *paths])
                run(['git', 'var', 'GIT_AUTHOR_IDENT'], capture=True)
                print('本次提交文件：' + ', '.join(paths), flush=True)
            client = ROOT / 'client'
            validation_digest = checks_fingerprint(ROOT, inputs, tests)
            can_reuse = (not args.modules_only and not args.force and not args.build_number
                         and reusable(cache, source_digest, mode, installed, ROOT))
            checked = (can_reuse and cache.get('checksFingerprint') == validation_digest
                       and not args.test and not args.full_tests and not args.module)
            if checked:
                report['reusedChecks'] = True
                print('源码、测试与检查工具未变化，复用已通过的检查结果。', flush=True)
            else:
                if not args.modules_only:
                    perform('静态分析', ['flutter', 'analyze', '--no-pub'], cwd=client)
                    perform('生产架构检查', ['python3', str(ROOT / 'scripts/module_host/check_architecture.py')])
                perform('相关测试', ['flutter', 'test', '--no-pub', '--concurrency=2', '--reporter', 'expanded', *(tests or [])], cwd=client)
            if not args.modules_only:
                if can_reuse:
                    apk = ROOT / cache['apk']
                    number = cache['buildNumber']
                    digest = cache['apkSha256']
                    report['reusedBuild'] = True
                    print(f'复用已验证的 {mode} APK：build{number}', flush=True)
                else:
                    latest_file = output / 'latest-success.json'
                    previous = json.loads(latest_file.read_text()).get('buildNumber', 0) if latest_file.exists() else 0
                    number = args.build_number or next_build_number(installed, previous)
                    if number + SPLIT_X64_OFFSET <= installed:
                        raise ValueError('构建号必须高于设备现有版本；不会降级或卸载应用')
                    perform('构建', ['flutter', 'build', 'apk', f'--{mode}', '--split-per-abi',
                                     '--target-platform=android-x64', f'--build-number={number}', '--no-pub'], cwd=client)
                    if snapshot(ROOT) != inputs:
                        raise ValueError('构建期间源码或依赖发生变化，请重新执行；尚未安装或提交')
                    source_apk = client / f'build/app/outputs/flutter-apk/app-x86_64-{mode}.apk'
                    apk = output / 'artifacts' / f'{mode}-{source_digest}.apk'
                    apk.parent.mkdir(exist_ok=True)
                    shutil.copy2(source_apk, apk)
                    digest = hashlib.sha256(apk.read_bytes()).hexdigest()
                report.update(buildNumber=number, apk=str(apk.relative_to(ROOT)), apkSha256=digest)
                if snapshot(ROOT) != inputs:
                    raise ValueError('检查后源码或依赖发生变化，请重新执行；尚未安装或提交')
                installed_path = run([*adb, 'shell', 'pm', 'path', PACKAGE], capture=True, timeout=30)
                base = next((line.removeprefix('package:') for line in installed_path.splitlines() if line.endswith('/base.apk')), None)
                device_digest = run([*adb, 'shell', 'sha256sum', base], capture=True, timeout=30).split()[0] if base else None
                if device_digest == digest and installed == number + SPLIT_X64_OFFSET:
                    report['skippedInstall'] = True
                    print('模拟器已安装同一APK，跳过安装。', flush=True)
                else:
                    perform('覆盖安装', [*adb, 'install', '-r', str(apk)], timeout=120)
                    perform('启动前停止旧进程', [*adb, 'shell', 'am', 'force-stop', PACKAGE], timeout=30)
                phase = '安装核对'
                if report['skippedInstall']:
                    actual = match
                    actual_digest = device_digest
                else:
                    info = run([*adb, 'shell', 'dumpsys', 'package', PACKAGE], capture=True, timeout=30)
                    actual = re.search(r'\bversionCode=(\d+)', info)
                    installed_path = run([*adb, 'shell', 'pm', 'path', PACKAGE], capture=True, timeout=30)
                    base = next((line.removeprefix('package:') for line in installed_path.splitlines() if line.endswith('/base.apk')), None)
                    actual_digest = run([*adb, 'shell', 'sha256sum', base], capture=True, timeout=30).split()[0] if base else None
                if not actual or int(actual[1]) != number + SPLIT_X64_OFFSET:
                    raise ValueError('安装后的 versionCode 不符合构建版本')
                if actual_digest != digest:
                    raise ValueError('模拟器 APK 与构建产物摘要不同')
                report.update(installedVersionCode=int(actual[1]), installedApkSha256=actual_digest)
                started = perform('启动', [*adb, 'shell', 'am', 'start', '-W', '-n', f'{PACKAGE}/.MainActivity'], capture=True, timeout=45)
                if 'Status: ok' not in started:
                    raise ValueError('Android 未确认 App 启动成功')
                cache = {'inputs': inputs, 'fingerprint': source_digest, 'mode': mode,
                         'apk': str(apk.relative_to(ROOT)), 'apkSha256': digest,
                         'buildNumber': number, 'versionCode': int(actual[1]),
                         'checksFingerprint': validation_digest}
                cache_file.write_text(json.dumps(cache, ensure_ascii=False, indent=2) + '\n')
            if args.module:
                phase = '模块更新'
                sys.path.insert(0, str(ROOT / 'scripts/module_host'))
                from verify_emulator import Emulator
                from update_emulator_modules import update_modules
                emulator = Emulator(args.serial, adb_host=args.adb_host, adb_port=args.adb_port)
                start = time.monotonic()
                report['modules'] = update_modules(args.module, emulator, output / 'modules')
                report['stepSeconds'][phase] = round(time.monotonic() - start, 3)
                report['steps'].append(phase)
                report['modulePackagesUpdated'] = True
            if args.commit:
                phase = 'Git 提交'
                report['commit'] = commit_files(args.commit, paths)
                report['steps'].append(phase)
            report['completed'] = True
            report['totalSeconds'] = round(time.monotonic() - started_at, 3)
            (output / 'latest-success.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
            print('\n更新完成：' + str(report['totalSeconds']) + ' 秒')
            print('记录：.cache/emulator-update/latest-success.json')
        except Exception as error:
            report.update(failedStep=phase, error=str(error))
            raise
        finally:
            report['totalSeconds'] = round(time.monotonic() - started_at, 3)
            (output / 'latest-attempt.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    if args.dev and not args.no_attach:
        # Release the deployment lock before a potentially long debug session.
        debug_env = os.environ.copy()
        debug_env['ADB_SERVER_SOCKET'] = f'tcp:{args.adb_host}:{args.adb_port}'
        print('热重载连接中：按 r 刷新、R 重启、q 退出。', flush=True)
        subprocess.run(['flutter', 'attach', '--debug', '-d', args.serial,
                        f'--app-id={PACKAGE}', '--no-dds'], cwd=ROOT / 'client', env=debug_env, check=True)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.SubprocessError) as failure:
        print('更新未完成：' + str(failure), file=sys.stderr)
        sys.exit(1)
