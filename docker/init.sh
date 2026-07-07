#!/usr/bin/env bash
# Idempotent bench initialization for FrappeDev Docker.
# Uses ONLY local bind-mounted repos under /workspace/src — no GitHub clones.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_SCRIPTS="${SCRIPT_DIR}/scripts"

BENCH_DIR="${BENCH_DIR:-/home/frappe/frappe-bench}"
WORKSPACE_SRC="${WORKSPACE_SRC:-/workspace/src}"
SITE_NAME="${SITE_NAME:-development.localhost}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
MARIADB_ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD:-admin}"
MARIADB_HOST="${MARIADB_HOST:-mariadb}"
DEVELOPER_MODE="${DEVELOPER_MODE:-1}"
SKIP_ASSETS_BUILD="${SKIP_ASSETS_BUILD:-0}"
FORCE_REINSTALL="${FORCE_REINSTALL:-0}"

# shellcheck source=scripts/ensure-node-path.sh
source "${DOCKER_SCRIPTS}/ensure-node-path.sh"

log() { echo "==> $*"; }

bench_is_initialized() {
	[[ -f "${BENCH_DIR}/sites/common_site_config.json" ]] \
		&& [[ -f "${BENCH_DIR}/Procfile" ]] \
		&& [[ -e "${BENCH_DIR}/env/bin/python" ]]
}

require_local_repos() {
	for app in frappe erpnext education; do
		git config --global --add safe.directory "${WORKSPACE_SRC}/${app}" 2>/dev/null || true
		if [[ ! -d "${WORKSPACE_SRC}/${app}/.git" ]]; then
			echo "ERROR: Expected git repo at ${WORKSPACE_SRC}/${app}" >&2
			exit 1
		fi
		if [[ ! -r "${WORKSPACE_SRC}/${app}/pyproject.toml" ]]; then
			echo "ERROR: Bind mount not readable at ${WORKSPACE_SRC}/${app} (check Docker Desktop file sharing for D:)" >&2
			exit 1
		fi
	done
}

configure_bench_services() {
	cd "${BENCH_DIR}"
	log "Configuring MariaDB and Redis hosts"
	bench set-mariadb-host "${MARIADB_HOST}"
	bench set-redis-cache-host "redis://redis:6379"
	bench set-redis-queue-host "redis://redis:6379"
	bench set-redis-socketio-host "redis://redis:6379"
	# Socket.IO auth callbacks from Node must reach the web process inside this container.
	# Browser Origin uses the site hostname (e.g. development.localhost) which does not
	# resolve in Docker DNS; loop back via 127.0.0.1 instead.
	bench set-config -g webserver_host "127.0.0.1"
	bench set-config -g webserver_port "${WEB_PORT:-8000}"
}

configure_procfile_for_docker() {
	cd "${BENCH_DIR}"
	# External MariaDB/Redis — drop embedded redis from Procfile if present.
	if [[ -f "${BENCH_DIR}/Procfile" ]]; then
		sed -i '/^redis:/d' "${BENCH_DIR}/Procfile" || true
		sed -i '/^redis_cache:/d' "${BENCH_DIR}/Procfile" || true
		sed -i '/^redis_queue:/d' "${BENCH_DIR}/Procfile" || true
		sed -i '/^redis_socketio:/d' "${BENCH_DIR}/Procfile" || true

		# Ensure watch is enabled for asset hot reload in development.
		if ! grep -q '^watch:' "${BENCH_DIR}/Procfile"; then
			echo 'watch: bench watch' >> "${BENCH_DIR}/Procfile"
		fi
	fi
}

# Bind-mounted apps live under WORKSPACE_SRC (e.g. /workspace/src/erpnext) but their
# Vite tooling resolves ../../../sites/ relative to the real file path, which lands on
# /workspace/sites/ — not BENCH_DIR/sites/. Link the bench sites dir there after init.
ensure_workspace_sites_link() {
	local bench_sites="${BENCH_DIR}/sites"
	local workspace_sites="$(dirname "${WORKSPACE_SRC}")/sites"

	if [[ ! -f "${bench_sites}/common_site_config.json" ]]; then
		echo "ERROR: ${bench_sites}/common_site_config.json missing — finish bench init first." >&2
		exit 1
	fi

	if [[ -L "${workspace_sites}" ]]; then
		if [[ "$(readlink -f "${workspace_sites}")" == "$(readlink -f "${bench_sites}")" ]]; then
			return 0
		fi
		rm -f "${workspace_sites}"
	elif [[ -e "${workspace_sites}" ]]; then
		echo "ERROR: ${workspace_sites} exists and is not a symlink to ${bench_sites}" >&2
		exit 1
	fi

	ln -sfn "${bench_sites}" "${workspace_sites}"
	log "Linked ${workspace_sites} -> ${bench_sites}"
}

require_common_site_config_for_build() {
	local bench_config="${BENCH_DIR}/sites/common_site_config.json"
	local workspace_config="$(dirname "${WORKSPACE_SRC}")/sites/common_site_config.json"

	if [[ ! -f "${bench_config}" ]]; then
		echo "ERROR: ${bench_config} missing — create the site before building assets." >&2
		exit 1
	fi

	ensure_workspace_sites_link

	if [[ ! -f "${workspace_config}" ]]; then
		echo "ERROR: ${workspace_config} missing — bind-mount apps cannot build without bench sites." >&2
		exit 1
	fi
}

init_bench_if_needed() {
	if bench_is_initialized; then
		log "Bench already initialized at ${BENCH_DIR} — skipping bench init"
		return 0
	fi

	# Guard: do not run bench init into a non-empty directory (would fail or corrupt).
	if [[ -d "${BENCH_DIR}" ]] && [[ -n "$(ls -A "${BENCH_DIR}" 2>/dev/null || true)" ]]; then
		echo "ERROR: ${BENCH_DIR} exists but is not a valid bench." >&2
		echo "       Remove host directory docker/data/bench and retry." >&2
		exit 1
	fi

	log "Initializing bench (local frappe only — no GitHub)"
	mkdir -p "$(dirname "${BENCH_DIR}")"

	# bench init creates the skeleton under BENCH_DIR only; --frappe-path reads local
	# source without modifying the bind-mounted repository.
	# Bind mount creates an empty BENCH_DIR before first init; bench refuses otherwise.
	bench init "${BENCH_DIR}" \
		--ignore-exist \
		--frappe-path "${WORKSPACE_SRC}/frappe" \
		--skip-redis-config-generation \
		--skip-assets \
		--python "$(command -v python3)"

	cd "${BENCH_DIR}"
	configure_bench_services
	bash "${DOCKER_SCRIPTS}/link-local-apps.sh"
	configure_procfile_for_docker
}

ensure_app_links() {
	cd "${BENCH_DIR}"
	bash "${DOCKER_SCRIPTS}/link-local-apps.sh"
}

install_python_deps() {
	log "Installing Python dependencies"
	cd "${BENCH_DIR}"
	bench setup requirements
	bench setup requirements --dev
}

install_node_deps() {
	bash "${DOCKER_SCRIPTS}/install-node-deps.sh"
}

build_assets() {
	if [[ "${SKIP_ASSETS_BUILD}" == "1" ]]; then
		log "Skipping asset build (SKIP_ASSETS_BUILD=1)"
		return 0
	fi
	require_common_site_config_for_build
	log "Building assets (first run may take several minutes)"
	cd "${BENCH_DIR}"
	bench build
}

create_site_if_needed() {
	cd "${BENCH_DIR}"

	if [[ -d "${BENCH_DIR}/sites/${SITE_NAME}" && "${FORCE_REINSTALL}" != "1" ]]; then
		log "Site ${SITE_NAME} already exists"
		bench use "${SITE_NAME}" || true
		return 0
	fi

	if [[ "${FORCE_REINSTALL}" == "1" && -d "${BENCH_DIR}/sites/${SITE_NAME}" ]]; then
		log "FORCE_REINSTALL=1 — dropping site ${SITE_NAME}"
		bench drop-site "${SITE_NAME}" --force --db-root-password "${MARIADB_ROOT_PASSWORD}" || true
	fi

	log "Creating site ${SITE_NAME}"
	bench new-site "${SITE_NAME}" \
		--db-host "${MARIADB_HOST}" \
		--mariadb-root-password "${MARIADB_ROOT_PASSWORD}" \
		--admin-password "${ADMIN_PASSWORD}" \
		--no-mariadb-socket

	bench use "${SITE_NAME}"
}

install_apps_if_needed() {
	cd "${BENCH_DIR}"
	bench use "${SITE_NAME}"

	install_one() {
		local app="$1"
		if bench --site "${SITE_NAME}" list-apps 2>/dev/null | grep -qx "${app}"; then
			log "App ${app} already installed on ${SITE_NAME}"
		else
			log "Installing app ${app} on ${SITE_NAME}"
			bench --site "${SITE_NAME}" install-app "${app}"
		fi
	}

	install_one erpnext
	install_one education
}

configure_developer_mode() {
	cd "${BENCH_DIR}"
	log "Enabling developer mode and scheduler"
	bench --site "${SITE_NAME}" set-config developer_mode "${DEVELOPER_MODE}"
	bench --site "${SITE_NAME}" set-config server_script_enabled 1
	bench --site "${SITE_NAME}" enable-scheduler
	bench --site "${SITE_NAME}" clear-cache
	bench use "${SITE_NAME}"
}

INIT_MARKER="${BENCH_DIR}/.docker-dev-init-done"

require_local_repos
init_bench_if_needed
ensure_app_links
configure_bench_services
configure_procfile_for_docker
ensure_workspace_sites_link

if [[ ! -f "${INIT_MARKER}" || "${FORCE_REINSTALL}" == "1" ]]; then
	install_python_deps
	install_node_deps
	create_site_if_needed
	install_apps_if_needed
	build_assets
	configure_developer_mode
	touch "${INIT_MARKER}"
else
	log "Heavy init already done (${INIT_MARKER} exists) — skipping deps/build/site setup"
	log "To rerun full setup: set FORCE_REINSTALL=1 in .env and recreate the frappe container"
	cd "${BENCH_DIR}"
	bench use "${SITE_NAME}" 2>/dev/null || true
fi

log "Init complete — bench is ready"
