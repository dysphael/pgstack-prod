#!/usr/bin/env bash
set -euo pipefail
mkdir -p "${LOG_DIR:-/var/log/postgresql}"
chown postgres:postgres "${LOG_DIR:-/var/log/postgresql}" 2>/dev/null || true
exec docker-entrypoint.sh "$@"
