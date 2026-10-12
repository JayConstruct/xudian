#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
用法：scripts/start-emulator.sh [选项]

从 WSL 启动 Windows Android 模拟器，等待 Linux ADB 确认 Android 已启动。
已运行的模拟器会直接复用，保留原有应用和数据。

  --avd NAME       AVD 名称（默认 Medium_Phone_API_37.0）
  --emulator PATH  Windows emulator.exe 路径
                  默认 D:\x128_install\AndroidSdk\emulator\emulator.exe
  --port PORT      模拟器控制台端口（默认 5554，须为 5554～5682 的偶数）
  --refresh-rate HZ 客体刷新率（30～240 的整数），新启动时冷启动；复用时核对
  --timeout SEC    等待启动的秒数（默认 180）
  --dry-run        显示启动配置，不连接设备或启动进程
  --help          显示帮助

ADB 使用项目 Linux SDK，连接 XUDIAN_ADB_HOST / XUDIAN_ADB_PORT
（默认 127.0.0.1:5037）。Windows 只负责模拟器进程及 ADB server。
EOF
}

fail() { echo "错误：$*" >&2; exit 1; }
avd='Medium_Phone_API_37.0'
emulator='D:\x128_install\AndroidSdk\emulator\emulator.exe'
port=5554
refresh_rate=''
boot_timeout=180
dry_run=false
while (( $# )); do
  case "$1" in
    --help) usage; exit 0 ;;
    --dry-run) dry_run=true; shift ;;
    --avd|--emulator|--port|--refresh-rate|--timeout)
      (( $# >= 2 )) && [[ -n "$2" && "$2" != --* ]] || fail "$1 缺少参数。"
      case "$1" in
        --avd) avd="$2" ;;
        --emulator) emulator="$2" ;;
        --port) port="$2" ;;
        --refresh-rate) refresh_rate="$2" ;;
        --timeout) boot_timeout="$2" ;;
      esac
      shift 2 ;;
    *) fail "未知参数：$1；使用 --help 查看用法。" ;;
  esac
done
[[ "$avd" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || fail 'AVD 名称只允许字母、数字、下划线、点和连字符。'
[[ "$port" =~ ^[0-9]{4}$ ]] || fail '模拟器端口必须为 5554～5682 的偶数。'
port=$((10#$port))
(( port >= 5554 && port <= 5682 && port % 2 == 0 )) || fail '模拟器端口必须为 5554～5682 的偶数。'
if [[ -n "$refresh_rate" ]]; then
  [[ "$refresh_rate" =~ ^[0-9]{1,3}$ ]] || fail '客体刷新率必须为 30～240 Hz 的整数。'
  refresh_rate=$((10#$refresh_rate))
  (( refresh_rate >= 30 && refresh_rate <= 240 )) || fail '客体刷新率必须为 30～240 Hz 的整数。'
fi
[[ "$boot_timeout" =~ ^[0-9]{1,5}$ ]] || fail '启动超时必须为 1～86400 秒。'
boot_timeout=$((10#$boot_timeout))
(( boot_timeout >= 1 && boot_timeout <= 86400 )) || fail '启动超时必须为 1～86400 秒。'
adb_host="${XUDIAN_ADB_HOST:-127.0.0.1}"
adb_port="${XUDIAN_ADB_PORT:-5037}"
[[ "$adb_port" =~ ^[0-9]{1,5}$ ]] || fail 'XUDIAN_ADB_PORT 必须为 1～65535。'
adb_port=$((10#$adb_port))
(( adb_port >= 1 && adb_port <= 65535 )) || fail 'XUDIAN_ADB_PORT 必须为 1～65535。'
[[ "$adb_host" == 127.0.0.1 || "$adb_host" == localhost ]] || fail '启动本机 Windows 模拟器时，XUDIAN_ADB_HOST 必须为 127.0.0.1 或 localhost。'
serial="emulator-$port"
echo "AVD：$avd；设备：$serial；ADB：$adb_host:$adb_port；超时：${boot_timeout}s"
if "$dry_run"; then
  printf 'Windows 启动命令：%s -avd %s -port %s' "$emulator" "$avd" "$port"
  if [[ -n "$refresh_rate" ]]; then printf ' -vsync-rate %s -no-snapshot' "$refresh_rate"; fi
  printf '\n'
  exit 0
fi

[[ "$(uname -r)" == *[Mm]icrosoft* ]] || fail '此脚本用于 WSL + Windows Android 模拟器。'
start_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$start_root/scripts/dev-env.sh"
for tool in adb timeout flock; do
  command -v "$tool" >/dev/null || fail "找不到 $tool，请先准备开发环境。"
done
mkdir -p "$start_root/.cache/emulator-start"
exec 9>"$start_root/.cache/emulator-start/$port.lock"
flock -n 9 || fail "另一个启动流程正在等待 $serial，请稍后重试。"
adb_command=(adb -H "$adb_host" -P "$adb_port")
probe() { timeout "$probe_timeout" "${adb_command[@]}" "$@" 2>/dev/null; }
probe_timeout=5
devices="$(probe devices -l || true)"
state="$(awk -v serial="$serial" '$1 == serial { print $2; exit }' <<< "$devices")"
if [[ -z "$state" ]]; then
  command -v powershell.exe >/dev/null || fail '找不到 powershell.exe，请检查 WSL 的 Windows 互操作配置。'
  command -v python3 >/dev/null || fail '找不到 python3。'
  # Encode as UTF-16LE so paths with spaces, quotes or Chinese remain literal.
  # Only the emulator process is launched here; all device operations use Linux ADB.
  encoded_command="$(python3 - "$emulator" "$avd" "$port" "$refresh_rate" <<'PY'
import base64
import sys

executable, avd, port, refresh_rate = sys.argv[1:]
literal = "'" + executable.replace("'", "''") + "'"
refresh_arguments = f", '-vsync-rate', '{refresh_rate}', '-no-snapshot'" if refresh_rate else ''
command = f"""$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$emulatorPath = {literal}
if (-not (Test-Path -LiteralPath $emulatorPath -PathType Leaf)) {{
    throw "emulator.exe does not exist: $emulatorPath"
}}
$avdPattern = '-avd\\s+"?{avd.replace('.', '[.]')}"?(?=\\s|$)'
$portPattern = '-port\\s+{port}(?=\\s|$)'
$existing = Get-CimInstance Win32_Process | Where-Object {{
    $_.Name -match '^(emulator|qemu-system-.*)\\.exe$' -and
    $_.CommandLine -match $avdPattern -and $_.CommandLine -match $portPattern
}}
if ($existing) {{
    Write-Output 'Emulator process already running; waiting for Android.'
}} else {{
    $process = Start-Process -FilePath $emulatorPath -ArgumentList '-avd', '{avd}', '-port', '{port}'{refresh_arguments} -PassThru
    Write-Output "Emulator started, PID: $($process.Id)"
}}
"""
print(base64.b64encode(command.encode('utf-16le')).decode('ascii'))
PY
  )"
  echo '启动 Windows 模拟器…'
  powershell.exe -NoProfile -NonInteractive -OutputFormat Text -EncodedCommand "$encoded_command" 9>&- || fail 'Windows 模拟器启动失败；若沙箱阻止 Windows 互操作，请在沙箱外运行同一脚本。'
else
  echo "复用已连接的 $serial（$state），等待 Android 启动…"
fi

deadline=$((SECONDS + boot_timeout))
while (( SECONDS < deadline )); do
  probe_timeout=$((deadline - SECONDS))
  (( probe_timeout <= 5 )) || probe_timeout=5
  boot="$(probe -s "$serial" shell getprop sys.boot_completed || true)"
  if [[ "${boot//$'\r'/}" == 1 ]]; then
    probe_timeout=$((deadline - SECONDS))
    (( probe_timeout > 0 )) || break
    (( probe_timeout <= 5 )) || probe_timeout=5
    actual_avd="$(probe -s "$serial" shell getprop ro.boot.qemu.avd_name || true)"
    actual_avd="${actual_avd//$'\r'/}"
    actual_avd="${actual_avd%%$'\n'*}"
    [[ "$actual_avd" == "$avd" ]] || fail "$serial 的 AVD 为 ${actual_avd:-未知}，期望 $avd；请核对 --avd 或 --port。"
    if [[ -n "$refresh_rate" ]]; then
      probe_timeout=$((deadline - SECONDS))
      (( probe_timeout > 0 )) || break
      (( probe_timeout <= 5 )) || probe_timeout=5
      actual_refresh_rate="$(probe -s "$serial" shell getprop ro.boot.qemu.vsync || true)"
      actual_refresh_rate="${actual_refresh_rate//$'\r'/}"
      actual_refresh_rate="${actual_refresh_rate%%$'\n'*}"
      [[ "$actual_refresh_rate" == "$refresh_rate" ]] || fail "$serial 的客体刷新率为 ${actual_refresh_rate:-未知} Hz，期望 $refresh_rate Hz；请先退出模拟器，再用 --refresh-rate $refresh_rate 冷启动。脚本不会自动重启。"
      echo "客体刷新率已核对：${refresh_rate} Hz（ro.boot.qemu.vsync）；实际显示模式需另行核对。"
    fi
    echo "模拟器已就绪：$serial（$avd，sys.boot_completed=1）"
    echo "更新并连接热重载：scripts/update-emulator.sh --dev --serial $serial --adb-host $adb_host --adb-port $adb_port"
    exit 0
  fi
  if (( SECONDS < deadline )); then sleep 1; fi
done
fail "等待 $serial 启动超过 ${boot_timeout}s。请查看 Windows 模拟器窗口，核对 AVD、端口和 WSL 到 Windows ADB 的连接；可增加 --timeout 后重试。"
