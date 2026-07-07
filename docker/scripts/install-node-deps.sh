#!/usr/bin/env bash
# Install yarn dependencies into bind-mounted repos.
# Writes ONLY to gitignored paths: node_modules/, public/dist/, public/frontend/, public/banking/
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ensure-node-path.sh
source "${_SCRIPT_DIR}/ensure-node-path.sh"

WORKSPACE_SRC="${WORKSPACE_SRC:-/workspace/src}"

install_yarn() {
	local dir="$1"
	if [[ -f "${dir}/package.json" ]]; then
		echo "    yarn install in ${dir}"
		(cd "${dir}" && yarn install --check-files)
	fi
}

echo "==> Installing Node dependencies (written to bind-mounted src/)"

for app in frappe erpnext education; do
	install_yarn "${WORKSPACE_SRC}/${app}"
done

install_yarn "${WORKSPACE_SRC}/education/frontend"
install_yarn "${WORKSPACE_SRC}/erpnext/banking"
