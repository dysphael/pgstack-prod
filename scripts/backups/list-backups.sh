#!/usr/bin/env bash
# List backup files with full paths.
# Usage: ./scripts/backups/list-backups.sh
#        ./scripts/backups/list-backups.sh --path <number>

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
source "${ROOT}/lib/backups.sh"
set_env

case "${1:-}" in
  --path)
    [[ -n "${2:-}" ]] || { echo "Usage: ./scripts/backups/list-backups.sh --path <number>" >&2; exit 1; }
    path="$(backup_path_at "$2")" || { echo "ERROR: invalid backup number." >&2; exit 1; }
    printf '%s\n' "$path"
    ;;
  *)
    print_backup_table
    ;;
esac
