#!/usr/bin/env bash
# Wait for MariaDB and Redis before bench init/start.
set -euo pipefail

MARIADB_HOST="${MARIADB_HOST:-mariadb}"
MARIADB_PORT="${MARIADB_PORT:-3306}"
REDIS_HOST="${REDIS_HOST:-redis}"
REDIS_PORT="${REDIS_PORT:-6379}"

echo "==> Waiting for MariaDB at ${MARIADB_HOST}:${MARIADB_PORT}..."
wait-for-it "${MARIADB_HOST}:${MARIADB_PORT}" -t 120 -- echo "MariaDB is up"

echo "==> Waiting for Redis at ${REDIS_HOST}:${REDIS_PORT}..."
wait-for-it "${REDIS_HOST}:${REDIS_PORT}" -t 60 -- echo "Redis is up"
