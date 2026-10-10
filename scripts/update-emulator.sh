#!/usr/bin/env bash
set -euo pipefail
update_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$update_root/scripts/dev-env.sh"
exec python3 "$update_root/scripts/update_emulator.py" "$@"
