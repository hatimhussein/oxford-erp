#!/usr/bin/env bash
# Configure Frappe site for https://arrdh.com/oxforderp reverse-proxy.
# Usage (from host, in docker/):
#   bash scripts/configure-oxforderp-host.sh
set -euo pipefail

CONTAINER="${FRAPPE_CONTAINER:-frappedev-frappe}"
SITE_NAME="${SITE_NAME:-arrdh.com}"
HOST_NAME="${HOST_NAME:-https://arrdh.com/oxforderp}"
BENCH_DIR="${BENCH_DIR:-/home/frappe/frappe-bench}"

if ! docker ps --format '{{.Names}}' | grep -qx "${CONTAINER}"; then
	echo "Container ${CONTAINER} is not running. Start with: docker compose up -d" >&2
	exit 1
fi

echo "==> Setting host_name=${HOST_NAME} on site ${SITE_NAME}"
docker exec -u frappe -w "${BENCH_DIR}" "${CONTAINER}" \
	bench --site "${SITE_NAME}" set-config host_name "${HOST_NAME}"

docker exec -u frappe -w "${BENCH_DIR}" "${CONTAINER}" \
	bench --site "${SITE_NAME}" set-config hostname "${HOST_NAME}"

# Accept requests whose Host header is arrdh.com even if site folder differs
docker exec -u frappe -w "${BENCH_DIR}" "${CONTAINER}" \
	bench set-config -g dns_multitenant 0 || true

echo "==> Clearing cache"
docker exec -u frappe -w "${BENCH_DIR}" "${CONTAINER}" \
	bench --site "${SITE_NAME}" clear-cache

echo "==> Done. Public URL: ${HOST_NAME}/desk"
echo "    Ensure host SSL proxy is configured (see nginx/host-arrdh-oxforderp.conf)"
