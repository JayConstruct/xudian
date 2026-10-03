#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
  cat <<'EOF'
用法：scripts/share-apk.sh [--debug]

为序点 arm64 APK 创建临时 HTTPS 下载地址。运行期间重建 APK，原链接会下载新版。
--debug 改为分享 app-debug.apk，供下载后安装并使用 flutter attach 热重载。
保持脚本运行，下载结束后按 Ctrl+C。
如需使用其他本地端口，可设置 APK_SHARE_PORT（默认 8765）。
EOF
  exit 0
fi

if (( $# > 1 )) || { (( $# == 1 )) && [[ "$1" != "--debug" ]]; }; then
  echo "未知参数。运行 scripts/share-apk.sh --help 查看用法。" >&2
  exit 2
fi

app_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
apk="$app_root/client/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
if [[ "${1:-}" == "--debug" ]]; then
  apk="$app_root/client/build/app/outputs/flutter-apk/app-debug.apk"
fi
port="${APK_SHARE_PORT:-8765}"

if [[ ! -f "$apk" ]]; then
  echo "未找到 APK：$apk" >&2
  if [[ "${1:-}" == "--debug" ]]; then
    echo "先运行：source scripts/dev-env.sh && cd client && flutter build apk --debug --no-pub" >&2
  else
    echo "先运行：source scripts/dev-env.sh && cd client && flutter build apk --release --split-per-abi" >&2
  fi
  exit 1
fi
if [[ ! "$port" =~ ^[0-9]+$ ]] || (( 10#$port < 1 || 10#$port > 65535 )); then
  echo "APK_SHARE_PORT 必须是 1 到 65535 之间的端口。" >&2
  exit 2
fi
for command_name in python3 cloudflared; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "缺少命令：$command_name" >&2
    exit 1
  fi
done

server_log="$(mktemp /tmp/xudian-server.XXXXXX)"
server_pid=""
cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -f -- "$server_log"
}
trap cleanup EXIT

python3 "$app_root/scripts/serve-apk.py" "$apk" --port "$port" >"$server_log" 2>&1 &
server_pid=$!
sleep 0.3
if ! kill -0 "$server_pid" 2>/dev/null; then
  cat "$server_log" >&2
  echo "本地下载服务启动失败；可以尝试设置 APK_SHARE_PORT 为其他端口。" >&2
  exit 1
fi

echo "正在为 $(basename "$apk") 创建临时下载地址。按 Ctrl+C 结束分享。"
cloudflared tunnel --no-autoupdate --url "http://127.0.0.1:$port" 2>&1 |
  while IFS= read -r line; do
    printf '%s\n' "$line"
    if [[ "$line" =~ https://[[:alnum:]-]+\.trycloudflare\.com ]]; then
      printf '\n手机浏览器下载地址：%s/xudian.apk\n\n' "${BASH_REMATCH[0]}"
    fi
  done
