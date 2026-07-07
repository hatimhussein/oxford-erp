#!/usr/bin/env bash
# Resolve node/yarn onto PATH for non-login container entrypoints (safe with set -u).
# Uses node if already available; otherwise picks the newest NVM-managed version.

ensure_node_in_path() {
	if command -v node >/dev/null 2>&1; then
		return 0
	fi

	local nvm_root=""
	if [[ -n "${NVM_DIR:-}" && -d "${NVM_DIR}/versions/node" ]]; then
		nvm_root="${NVM_DIR}"
	elif [[ -n "${HOME:-}" && -d "${HOME}/.nvm/versions/node" ]]; then
		nvm_root="${HOME}/.nvm"
	fi

	if [[ -n "${nvm_root}" ]]; then
		local version_dir=""
		version_dir="$(find "${nvm_root}/versions/node" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -1)"
		if [[ -n "${version_dir}" && -x "${version_dir}/bin/node" ]]; then
			export PATH="${version_dir}/bin:${PATH}"
			return 0
		fi
	fi

	if [[ -n "${nvm_root}" && -s "${nvm_root}/nvm.sh" ]]; then
		set +u
		# shellcheck disable=SC1090,SC1091
		source "${nvm_root}/nvm.sh"
		set -u
		if command -v node >/dev/null 2>&1; then
			return 0
		fi
	fi

	echo "ERROR: node not found on PATH (check frappe/bench image Node/NVM setup)" >&2
	return 1
}

ensure_node_in_path
