#!/usr/bin/env bash
# Configure Frappe site for https://arrdh.com/oxforderp reverse-proxy.
# Usage (from host, in docker/):
#   bash scripts/configure-oxforderp-host.sh
# Loads SITE_NAME / HOST_NAME from .env when present.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${DOCKER_DIR}/.env" ]]; then
	set -a
	# shellcheck disable=SC1091
	source "${DOCKER_DIR}/.env"
	set +a
fi

CONTAINER="${FRAPPE_CONTAINER:-frappedev-frappe}"
SITE_NAME="${SITE_NAME:-development.localhost}"
HOST_NAME="${HOST_NAME:-https://arrdh.com/oxforderp}"
BENCH_DIR="${BENCH_DIR:-/home/frappe/frappe-bench}"

if ! docker ps --format '{{.Names}}' | grep -qx "${CONTAINER}"; then
	echo "Container ${CONTAINER} is not running. Start with: docker compose up -d" >&2
	exit 1
fi

# Auto-detect site if configured name is missing
if ! docker exec -u frappe -w "${BENCH_DIR}" "${CONTAINER}" \
	test -d "sites/${SITE_NAME}"; then
	echo "==> Site '${SITE_NAME}' not found — detecting from sites/"
	DETECTED="$(docker exec -u frappe -w "${BENCH_DIR}" "${CONTAINER}" \
		bash -lc 'ls -1 sites | grep -v -E "^(apps|assets|common_site_config.json|currentsite.txt)$" | head -1' || true)"
	if [[ -z "${DETECTED}" ]]; then
		echo "ERROR: No site found under ${BENCH_DIR}/sites" >&2
		exit 1
	fi
	echo "    using detected site: ${DETECTED}"
	SITE_NAME="${DETECTED}"
fi

echo "==> Setting host_name=${HOST_NAME} on site ${SITE_NAME}"
docker exec -u frappe -w "${BENCH_DIR}" "${CONTAINER}" \
	bench --site "${SITE_NAME}" set-config host_name "${HOST_NAME}"

docker exec -u frappe -w "${BENCH_DIR}" "${CONTAINER}" \
	bench --site "${SITE_NAME}" set-config hostname "${HOST_NAME}" || true

# Use HTTPS port for Socket.IO (LiteSpeed proxies /socket.io → Docker :9000)
docker exec -u frappe -w "${BENCH_DIR}" "${CONTAINER}" \
	bench --site "${SITE_NAME}" set-config socketio_port 443

docker exec -u frappe -w "${BENCH_DIR}" "${CONTAINER}" \
	bench use "${SITE_NAME}" || true

echo "==> Clearing cache"
docker exec -u frappe -w "${BENCH_DIR}" "${CONTAINER}" \
	bench --site "${SITE_NAME}" clear-cache

echo "==> Done. Public URL: ${HOST_NAME}/desk"
echo "    Recreate nginx: docker compose up -d --force-recreate --no-deps nginx"
echo "    Update public_html/.htaccess from nginx/public_html-oxforderp.htaccess-snippet"
echo "    Add OLS Contexts for /assets/frappe /api/method /socket.io if rewrite [P] is not enough"
