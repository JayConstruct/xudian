#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
  cat <<'EOF'
用法：bash scripts/preview-android.sh <设备序列号>

在 Linux / WSL 连接已安装的 Android 调试版并启用 Flutter 热重载。
先通过 HTTPS 下载 debug APK，在手机或手机旁电脑安装，再打开应用。
此脚本使用 flutter attach，不构建、传输或安装 APK。
VPS 模式先从手机旁电脑建立 SSH 反向转发：
  ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -R 127.0.0.1:15037:127.0.0.1:5037 -R 127.0.0.1:8181:127.0.0.1:8181 用户名@VPS地址

VPS 端口 15037 连接电脑的 ADB server，8181 连接手机的 Dart VM Service。
配置参数（均为本机 loopback 端口）：
  XUDIAN_ADB_PORT          默认 15037
  XUDIAN_VM_SERVICE_PORT   默认 8181
WSL 镜像网络模式示例：
  XUDIAN_ADB_PORT=5037 XUDIAN_VM_SERVICE_PORT=8182 bash scripts/preview-android.sh 设备序列号
设备序列号从电脑上的 adb devices -l 获取。
运行后按 r 热重载、R 热重启、q 退出。
完整说明见 DEVELOPMENT.md 的“通过 SSH 远程预览 Android”。
多机配置见 docs/MULTI_MACHINE_DEVELOPMENT.md。
EOF
  exit 0
fi

if [[ $# != 1 || -z "$1" || "$1" == -* ]]; then
  echo '请提供设备序列号；运行 bash scripts/preview-android.sh --help 查看用法。' >&2
  exit 2
fi

preview_adb_port="${XUDIAN_ADB_PORT:-15037}"
preview_vm_port="${XUDIAN_VM_SERVICE_PORT:-8181}"
for preview_port in "$preview_adb_port" "$preview_vm_port"; do
  if [[ ! "$preview_port" =~ ^[0-9]{1,5}$ ]] || (( 10#$preview_port < 1 || 10#$preview_port > 65535 )); then
    echo 'XUDIAN_ADB_PORT 与 XUDIAN_VM_SERVICE_PORT 必须为 1 到 65535 的端口号。' >&2
    exit 2
  fi
done
preview_adb_port=$((10#$preview_adb_port))
preview_vm_port=$((10#$preview_vm_port))
if (( preview_adb_port == preview_vm_port )); then
  echo 'ADB 与 VM Service 必须使用不同的端口。' >&2
  exit 2
fi

preview_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$preview_root/scripts/dev-env.sh"
export ADB_SERVER_SOCKET="tcp:127.0.0.1:$preview_adb_port"

cd "$preview_root/client"
exec flutter attach --debug -d "$1" --app-id=dev.taskapp.task_app --no-dds --host-vmservice-port="$preview_vm_port"
