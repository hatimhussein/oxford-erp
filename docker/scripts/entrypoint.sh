#!/usr/bin/env bash
set -euo pipefail

# bench init runs `git clone` against bind-mounted repos before init.sh's require_local_repos().
echo "==> Configuring Git safe.directory for bind-mounted repos"
git config --global --add safe.directory /workspace/src/frappe
git config --global --add safe.directory /workspace/src/erpnext
git config --global --add safe.directory /workspace/src/education

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ensure-node-path.sh
source "${_SCRIPT_DIR}/ensure-node-path.sh"

echo "==> FrappeDev entrypoint"
echo "    Python: $(python3 --version 2>/dev/null || true)"
echo "    Node:   $(node --version 2>/dev/null || true)"
echo "    Bench:  $(bench --version 2>/dev/null || true)"

/workspace/docker/scripts/wait-for-services.sh
/workspace/docker/init.sh

cd "${BENCH_DIR:-/home/frappe/frappe-bench}"
echo "==> Starting bench (web, socketio, watch, schedule, workers)..."
exec bench start
