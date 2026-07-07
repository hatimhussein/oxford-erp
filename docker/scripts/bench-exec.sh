#!/usr/bin/env bash
# Helper: run an arbitrary bench command inside the running frappe container.
# Usage (from host, in docker/):
#   ./scripts/bench-exec.sh migrate
#   ./scripts/bench-exec.sh --site development.localhost console
set -euo pipefail

CONTAINER="${FRAPPE_CONTAINER:-frappedev-frappe}"

if ! docker ps --format '{{.Names}}' | grep -qx "${CONTAINER}"; then
	echo "Container ${CONTAINER} is not running. Start with: docker compose up -d" >&2
	exit 1
fi

docker exec -it -u frappe -w /home/frappe/frappe-bench "${CONTAINER}" bench "$@"
