#!/usr/bin/env bash
# Symlink bind-mounted local repos into bench/apps — never clone from GitHub.
set -euo pipefail

BENCH_DIR="${BENCH_DIR:-/home/frappe/frappe-bench}"
WORKSPACE_SRC="${WORKSPACE_SRC:-/workspace/src}"
APPS_DIR="${BENCH_DIR}/apps"

mkdir -p "${APPS_DIR}"

link_app() {
	local app="$1"
	local src="${WORKSPACE_SRC}/${app}"
	local dest="${APPS_DIR}/${app}"

	if [[ ! -d "${src}" ]]; then
		echo "ERROR: Local app not found at ${src}" >&2
		exit 1
	fi

	# Safety: only ever replace the bench/apps entry — never touch the source repo.
	if [[ "${dest}" == "${src}" ]]; then
		echo "ERROR: Refusing to replace source repo path ${src}" >&2
		exit 1
	fi

	if [[ -L "${dest}" ]] && [[ "$(readlink -f "${dest}")" == "$(readlink -f "${src}")" ]]; then
		echo "    already linked ${dest} -> ${src}"
		return 0
	fi

	# Removes a symlink, stale copy, or directory under bench/apps only (not under /workspace/src).
	rm -rf "${dest}"
	ln -sfn "${src}" "${dest}"
	echo "    linked ${dest} -> ${src}"
}

echo "==> Linking local apps into ${APPS_DIR}"
link_app frappe
link_app erpnext
link_app education

# Keep bench aware of installed apps (used by build/watch).
mkdir -p "${BENCH_DIR}/sites"
printf 'frappe\nerpnext\neducation\n' > "${BENCH_DIR}/sites/apps.txt"
