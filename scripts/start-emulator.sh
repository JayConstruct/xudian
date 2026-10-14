#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
用法：scripts/start-emulator.sh [选项]

从 WSL 启动 Windows Android 模拟器，等待 Linux ADB 确认 Android 已启动。
默认复用已运行的模拟器；--cold-boot 询问是否关闭目标设备，确认后自动冷启动，保留应用和数据。

  --avd NAME       AVD 名称（默认 Medium_Phone_API_37.0）
  --emulator PATH  Windows emulator.exe 路径
                  默认 D:\x128_install\AndroidSdk\emulator\emulator.exe
  --port PORT      模拟器控制台端口（默认 5554，须为 5554～5682 的偶数）
  --memory MB      客体 RAM 上限（默认 2048，须为 1536～8192 MB 的整数）
                  仅新启动生效，不限制 Windows 进程总内存
  --refresh-rate HZ 客体刷新率（30～240 的整数），新启动时冷启动；复用时核对
  --cold-boot      冷启动；已运行时询问，输入 y 后关闭并重启，不清除数据
  --lock-refresh-rate 同时设置 Android 最高/最低刷新率，须指定 --refresh-rate
                  保存原值恢复脚本；设置持续生效，实际帧率仍需测量
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
memory=2048
refresh_rate=''
cold_boot=false
lock_refresh_rate=false
boot_timeout=180
dry_run=false
while (( $# )); do
  case "$1" in
    --help) usage; exit 0 ;;
    --dry-run) dry_run=true; shift ;;
    --cold-boot) cold_boot=true; shift ;;
    --lock-refresh-rate) lock_refresh_rate=true; shift ;;
    --avd|--emulator|--port|--memory|--refresh-rate|--timeout)
      (( $# >= 2 )) && [[ -n "$2" && "$2" != --* ]] || fail "$1 缺少参数。"
      case "$1" in
        --avd) avd="$2" ;;
        --emulator) emulator="$2" ;;
        --port) port="$2" ;;
        --memory) memory="$2" ;;
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
[[ "$memory" =~ ^[0-9]{1,5}$ ]] || fail '客体 RAM 上限必须为 1536～8192 MB 的整数。'
memory=$((10#$memory))
(( memory >= 1536 && memory <= 8192 )) || fail '客体 RAM 上限必须为 1536～8192 MB 的整数。'
if [[ -n "$refresh_rate" ]]; then
  [[ "$refresh_rate" =~ ^[0-9]{1,3}$ ]] || fail '客体刷新率必须为 30～240 Hz 的整数。'
  refresh_rate=$((10#$refresh_rate))
  (( refresh_rate >= 30 && refresh_rate <= 240 )) || fail '客体刷新率必须为 30～240 Hz 的整数。'
fi
if "$lock_refresh_rate"; then
  [[ -n "$refresh_rate" ]] || fail '--lock-refresh-rate 必须与 --refresh-rate HZ 一起使用。'
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
launch_arguments=(-avd "$avd" -port "$port" -memory "$memory")
if [[ -n "$refresh_rate" ]]; then
  launch_arguments+=(-vsync-rate "$refresh_rate" -no-snapshot)
elif "$cold_boot"; then
  launch_arguments+=(-no-snapshot-load)
fi
echo "AVD：$avd；设备：$serial；ADB：$adb_host:$adb_port；超时：${boot_timeout}s"
echo "客体 RAM 上限：${memory} MB（仅新启动生效；Windows 进程总内存另含图形等开销）。"
if "$dry_run"; then
  if "$cold_boot"; then echo "冷启动：若 $serial 已运行，询问是否关闭；确认后自动关闭并重新启动，不清除应用和数据。"; fi
  printf 'Windows 启动命令：%s' "$emulator"
  printf ' %s' "${launch_arguments[@]}"
  printf '\n'
  if "$lock_refresh_rate"; then
    echo "Android 刷新率策略：保存原值后，将当前用户 peak_refresh_rate / min_refresh_rate 设为 $refresh_rate Hz。"
  fi
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
read_avd_name() {
  local property value avd_deadline="${1:-}" probe_timeout="$probe_timeout"
  # adb emu commands can exit successfully without returning console output.
  for property in ro.boot.qemu.avd_name ro.kernel.qemu.avd_name; do
    if [[ -n "$avd_deadline" ]]; then
      probe_timeout=$((avd_deadline - SECONDS))
      (( probe_timeout > 0 )) || return 1
      (( probe_timeout <= 5 )) || probe_timeout=5
    fi
    value="$(probe -s "$serial" shell getprop "$property")" || continue
    value="$(awk '{ sub(/\r$/, ""); sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); if (length) { print; exit } }' <<< "$value")"
    if [[ -n "$value" ]]; then printf '%s\n' "$value"; return 0; fi
  done
  return 1
}
read_windows_avd_name() {
  local encoded value
  encoded="$(python3 - "$port" <<'PY'
import base64
import sys

port = sys.argv[1]
command = f"""# AVD_NAME_QUERY
$ErrorActionPreference = 'Stop'
$names = @(Get-CimInstance Win32_Process | Where-Object {{
    $_.Name -match '^(emulator|qemu-system-.*)\\.exe$' -and
    $_.CommandLine -match '-port\\s+{port}(?=\\s|$)'
}} | ForEach-Object {{
    $match = [regex]::Match($_.CommandLine, '-avd\\s+"?([A-Za-z0-9_][A-Za-z0-9_.-]*)"?(?=\\s|$)')
    if ($match.Success) {{ $match.Groups[1].Value }} else {{ '__unknown__' }}
}} | Sort-Object -Unique)
if ($names.Count -eq 1 -and $names[0] -ne '__unknown__') {{ Write-Output $names[0] }}
"""
print(base64.b64encode(command.encode('utf-16le')).decode('ascii'))
PY
  )" || return 1
  value="$(timeout 10 powershell.exe -NoProfile -NonInteractive -OutputFormat Text -EncodedCommand "$encoded" 9>&- 2>/dev/null)" || return 1
  value="${value//$'\r'/}"
  [[ "$value" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || return 1
  printf '%s\n' "$value"
}
probe_timeout=5
if ! devices="$(probe devices -l)"; then
  if "$cold_boot"; then fail '无法查询 ADB 设备，不能安全执行冷启动；请检查 ADB 连接。'; fi
fi
state="$(awk -v serial="$serial" '$1 == serial { print $2; exit }' <<< "$devices")"
if "$cold_boot" && [[ -n "$state" ]]; then
  for tool in powershell.exe python3; do
    command -v "$tool" >/dev/null || fail "找不到 $tool，不能执行冷启动。"
  done
  [[ "$state" == device ]] || fail "$serial 当前为 $state，无法安全核对 AVD；请先手动退出目标模拟器再冷启动。"
  verify_target_avd() {
    local actual_avd
    if ! actual_avd="$(read_avd_name)"; then
      actual_avd="$(read_windows_avd_name)" || fail "无法读取 $serial 的 AVD 名称属性或 Windows 进程参数；不会关闭设备。"
    fi
    [[ "$actual_avd" == "$avd" ]] || fail "$serial 的 AVD 为 ${actual_avd:-未知}，期望 $avd；不会关闭设备。"
  }
  verify_target_avd
  while true; do
    printf '%s' "$serial（$avd）已运行，是否关闭并冷启动？[y/N] " >&2
    if ! IFS= read -r answer; then
      echo '未收到确认，已取消冷启动。' >&2
      exit 1
    fi
    case "$answer" in
      [yY]|[yY][eE][sS]) break ;;
      ''|[nN]|[nN][oO]) echo '已取消冷启动，保留正在运行的模拟器。'; exit 0 ;;
      *) echo '请输入 y（关闭并冷启动）或 n（取消）。' >&2 ;;
    esac
  done
  # Recheck after the user answers in case the device changed while waiting.
  verify_target_avd
  echo "关闭 $serial（$avd），准备冷启动…"
  probe -s "$serial" emu kill || fail "无法关闭 $serial；请手动退出后重试。"
  shutdown_deadline=$((SECONDS + boot_timeout))
  while [[ -n "$state" ]]; do
    probe_timeout=$((shutdown_deadline - SECONDS))
    (( probe_timeout > 0 )) || fail "等待 $serial 退出超过 ${boot_timeout}s；不会启动重复进程。"
    (( probe_timeout <= 5 )) || probe_timeout=5
    devices="$(probe devices -l)" || fail '等待退出时 ADB 查询失败；不会启动重复进程。'
    state="$(awk -v serial="$serial" '$1 == serial { print $2; exit }' <<< "$devices")"
    if [[ -n "$state" ]]; then sleep 1; fi
  done
  probe_timeout=5
fi
if [[ -z "$state" ]]; then
  command -v powershell.exe >/dev/null || fail '找不到 powershell.exe，请检查 WSL 的 Windows 互操作配置。'
  command -v python3 >/dev/null || fail '找不到 python3。'
  # Encode as UTF-16LE so paths with spaces, quotes or Chinese remain literal.
  # Only the emulator process is launched here; all device operations use Linux ADB.
  encoded_command="$(python3 - "$emulator" "$avd" "$port" "$cold_boot" "$boot_timeout" "${launch_arguments[@]}" <<'PY'
import base64
import sys

executable, avd, port, cold_boot, boot_timeout, *arguments = sys.argv[1:]
literal = "'" + executable.replace("'", "''") + "'"
argument_literals = ', '.join("'" + argument.replace("'", "''") + "'" for argument in arguments)
command = f"""$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$emulatorPath = {literal}
if (-not (Test-Path -LiteralPath $emulatorPath -PathType Leaf)) {{
    throw "emulator.exe does not exist: $emulatorPath"
}}
$avdPattern = '-avd\\s+"?{avd.replace('.', '[.]')}"?(?=\\s|$)'
$portPattern = '-port\\s+{port}(?=\\s|$)'
$findExisting = {{ @(Get-CimInstance Win32_Process | Where-Object {{
    $_.Name -match '^(emulator|qemu-system-.*)\\.exe$' -and
    ($_.CommandLine -match $avdPattern -or $_.CommandLine -match $portPattern)
}}) }}
$processes = @(& $findExisting)
if ($processes.Count -gt 0 -and ${cold_boot}) {{
    $deadline = (Get-Date).AddSeconds({boot_timeout})
    while ($processes.Count -gt 0 -and (Get-Date) -lt $deadline) {{
        Start-Sleep -Milliseconds 500
        $processes = @(& $findExisting)
    }}
    if ($processes.Count -gt 0) {{
        throw '目标模拟器进程仍在运行，无法通过 ADB 安全关闭；请手动关闭后重试。'
    }}
}}
$existing = @($processes | Where-Object {{
    $_.CommandLine -match $avdPattern -and $_.CommandLine -match $portPattern
}})
if ($existing) {{
    Write-Output 'Emulator process already running; waiting for Android.'
}} else {{
    $process = Start-Process -FilePath $emulatorPath -ArgumentList {argument_literals} -PassThru
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
    actual_avd="$(read_avd_name "$deadline" || true)"
    [[ "$actual_avd" == "$avd" ]] || fail "$serial 的 AVD 为 ${actual_avd:-未知}，期望 $avd；请核对 --avd 或 --port。"
    if [[ -n "$refresh_rate" ]]; then
      probe_timeout=$((deadline - SECONDS))
      (( probe_timeout > 0 )) || break
      (( probe_timeout <= 5 )) || probe_timeout=5
      actual_refresh_rate="$(probe -s "$serial" shell getprop ro.boot.qemu.vsync || true)"
      actual_refresh_rate="${actual_refresh_rate//$'\r'/}"
      actual_refresh_rate="${actual_refresh_rate%%$'\n'*}"
      [[ "$actual_refresh_rate" == "$refresh_rate" ]] || fail "$serial 的客体刷新率为 ${actual_refresh_rate:-未知} Hz，期望 $refresh_rate Hz；请先退出模拟器，或用 --cold-boot --refresh-rate $refresh_rate 冷启动。未指定 --cold-boot 时脚本不会自动重启。"
      echo "客体刷新率已核对：${refresh_rate} Hz（ro.boot.qemu.vsync）；实际显示模式需另行核对。"
      if "$lock_refresh_rate"; then
        boot_probe() {
          probe_timeout=$((deadline - SECONDS))
          (( probe_timeout > 0 )) || return 124
          (( probe_timeout <= 5 )) || probe_timeout=5
          probe "$@"
        }
        android_user="$(boot_probe -s "$serial" shell am get-current-user)" || fail '无法读取 Android 当前用户。'
        android_user="${android_user//$'\r'/}"
        [[ "$android_user" =~ ^[0-9]+$ ]] || fail 'Android 当前用户 ID 无效；不会修改刷新率设置。'
        setting_names=(peak_refresh_rate min_refresh_rate)
        setting_values=()
        for setting in "${setting_names[@]}"; do
          previous="$(boot_probe -s "$serial" shell settings --user "$android_user" get system "$setting")" || fail "无法读取 $setting；不会修改刷新率设置。"
          previous="${previous//$'\r'/}"
          [[ "$previous" == null || "$previous" =~ ^[0-9]+([.][0-9]+)?$ ]] || fail "$setting 原值无效；不会修改刷新率设置。"
          setting_values+=("$previous")
        done
        restore_script="$(mktemp "$start_root/.cache/emulator-start/refresh-$port-XXXXXX.sh")"
        {
          printf '#!/usr/bin/env bash\nset -euo pipefail\nsource %q\n' "$start_root/scripts/dev-env.sh"
          for index in 0 1; do
            if [[ "${setting_values[index]}" == null ]]; then
              printf '%q ' "${adb_command[@]}" -s "$serial" shell settings --user "$android_user" delete system "${setting_names[index]}"
            else
              printf '%q ' "${adb_command[@]}" -s "$serial" shell settings --user "$android_user" put system "${setting_names[index]}" "${setting_values[index]}"
            fi
            printf '\n'
          done
        } > "$restore_script"
        printf '刷新率原值已保存；恢复命令：bash %q\n' "$restore_script"
        for setting in "${setting_names[@]}"; do
          boot_probe -s "$serial" shell settings --user "$android_user" put system "$setting" "$refresh_rate" || fail "设置 $setting 失败；请用恢复脚本还原原值。"
          current="$(boot_probe -s "$serial" shell settings --user "$android_user" get system "$setting")" || fail "无法核对 $setting；请用恢复脚本还原原值。"
          current="${current//$'\r'/}"
          [[ "$current" =~ ^0*${refresh_rate}([.]0+)?$ ]] || fail "$setting 未生效（${current:-未知}）；请用恢复脚本还原原值。"
        done
        echo "Android 用户 $android_user 的最高/最低刷新率已设为 $refresh_rate Hz；设置持续生效，实际帧率仍需测量。"
      fi
    fi
    echo "模拟器已就绪：$serial（$avd，sys.boot_completed=1）"
    echo "更新并连接热重载：scripts/update-emulator.sh --dev --serial $serial --adb-host $adb_host --adb-port $adb_port"
    exit 0
  fi
  if (( SECONDS < deadline )); then sleep 1; fi
done
fail "等待 $serial 启动超过 ${boot_timeout}s。请查看 Windows 模拟器窗口，核对 AVD、端口和 WSL 到 Windows ADB 的连接；可增加 --timeout 后重试。"
