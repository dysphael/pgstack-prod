#!/usr/bin/env bash
# pgstack-prod — Deployment and operations helper script.
# Usage: ./deploy.sh [command]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

load_env() {
    if [[ ! -f .env ]]; then
        error ".env file not found. Copy .env.example to .env and configure it:"
        error "  cp .env.example .env"
        exit 1
    fi
    # shellcheck disable=SC1091
    set -a
    source .env
    set +a
}

validate_passwords() {
    if [[ "${POSTGRES_PASSWORD:-}" == "CHANGE_ME_STRONG_PASSWORD" ]]; then
        error "POSTGRES_PASSWORD is still set to the placeholder value."
        error "Edit .env and set a strong password before deploying."
        exit 1
    fi
}

print_connection_info() {
    info "Stack is running. Access URLs:"
    echo ""
    echo "  pgAdmin:  https://${PGADMIN_DOMAIN}"
    echo "  Netdata:  https://${NETDATA_DOMAIN}"
    echo ""
    info "Connection strings:"
    echo ""
    echo "  Docker network (db_internal):"
    echo "    postgresql://${POSTGRES_USER}:****@pgbouncer:5432/${POSTGRES_DB}"
    echo ""
    echo "  Host loopback (VPS local):"
    echo "    postgresql://${POSTGRES_USER}:****@localhost:5432/${POSTGRES_DB}"
}

cmd_up() {
    load_env
    validate_passwords

    info "Ensuring traefik_proxy network exists..."
    docker network create traefik_proxy 2>/dev/null || true

    info "Starting pgstack-prod..."
    docker compose up -d --remove-orphans

    ok "Stack deployed successfully."
    print_connection_info
}

cmd_down() {
    load_env
    info "Stopping pgstack-prod..."
    docker compose down
    ok "Stack stopped."
    warn "Named volumes (pgdata, pgbackups, netdata_lib, netdata_cache) are preserved. Data is intact."
}

cmd_restart() {
    load_env
    local service="${1:-}"
    if [[ -n "$service" ]]; then
        info "Restarting ${service}..."
        docker compose restart "$service"
        ok "Service ${service} restarted."
    else
        info "Restarting pgstack-prod..."
        docker compose restart
        ok "Stack restarted."
    fi
}

cmd_status() {
    load_env
    info "Service status:"
    docker compose ps
    echo ""
    info "Stack volumes:"
    docker volume ls --filter "name=pgstack-prod" 2>/dev/null || \
        docker volume ls | grep -E 'pgstack-prod|pgdata|pgbackups|netdata_lib|netdata_cache' || true
}

cmd_logs() {
    load_env
    local service="${1:-}"
    if [[ -n "$service" ]]; then
        docker compose logs -f --tail=100 "$service"
    else
        docker compose logs -f --tail=100
    fi
}

cmd_shell() {
    load_env
    info "Opening psql shell as ${POSTGRES_USER}..."
    docker compose exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"
}

cmd_backup() {
    load_env
    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    local outfile="backup_manual_${timestamp}.sql.gz"

    info "Creating manual backup: ${outfile}"
    docker compose exec -T postgres pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" | gzip > "$outfile"
    ok "Backup saved to ${outfile}"
}

cmd_restore() {
    load_env
    local file="${1:-}"

    if [[ -z "$file" ]]; then
        error "Usage: ./deploy.sh restore <file.sql.gz>"
        exit 1
    fi

    if [[ ! -f "$file" ]]; then
        error "File not found: ${file}"
        exit 1
    fi

    warn "This will restore database '${POSTGRES_DB}' from: ${file}"
    warn "Existing data in the target database will be overwritten."
    read -r -p "Type 'yes' to confirm: " confirm

    if [[ "$confirm" != "yes" ]]; then
        info "Restore cancelled."
        exit 0
    fi

    info "Restoring from ${file}..."
    gunzip -c "$file" | docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"
    ok "Restore completed."
}

cmd_htpasswd() {
    local user="${1:-}"
    local password="${2:-}"

    if [[ -z "$user" || -z "$password" ]]; then
        error "Usage: ./deploy.sh htpasswd <user> <password>"
        exit 1
    fi

    info "Generating htpasswd entry for Docker Compose..."
    local entry
    entry="$(docker run --rm httpd:alpine htpasswd -nbB "$user" "$password" | sed 's/\$/\$\$/g')"

    ok "Paste this into your .env file:"
    echo ""
    echo "NETDATA_BASIC_AUTH=${entry}"
    echo ""
}

cmd_help() {
    cat <<'EOF'
pgstack-prod — Deployment and operations helper

Usage: ./deploy.sh [command]

Commands:
  up                    Start the stack (validates .env and passwords first)
  down                  Stop the stack (volumes are preserved)
  restart [service]     Restart all services or a specific one
  status                Show service status and volumes
  logs [service]        Tail logs (optionally for a single service)
  shell                 Open psql inside the postgres container
  backup                Create a manual pg_dump backup (gzip)
  restore <file>        Restore from a .sql.gz backup file
  htpasswd <user> <pw>  Generate NETDATA_BASIC_AUTH value for .env
  help                  Show this help message

Examples:
  ./deploy.sh up
  ./deploy.sh htpasswd admin mypassword
  ./deploy.sh logs netdata
  ./deploy.sh restart postgres
  ./deploy.sh backup
  ./deploy.sh restore backup_manual_20260101_120000.sql.gz
EOF
}

main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        up)      cmd_up ;;
        down)    cmd_down ;;
        restart) cmd_restart "$@" ;;
        logs)    cmd_logs "$@" ;;
        shell)   cmd_shell ;;
        backup)  cmd_backup ;;
        restore) cmd_restore "$@" ;;
        htpasswd) cmd_htpasswd "$@" ;;
        help|-h|--help) cmd_help ;;
        *)
            error "Unknown command: ${command}"
            echo ""
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
