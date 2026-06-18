#!/usr/bin/env bash
# Shared helpers for databases and per-database user roles.
# Standard layout: one database, default schema "public" (no forced schema).

prompt_password() {
  local role="$1"
  read -r -s -p "Password for ${role}: " PW
  echo
  read -r -s -p "Confirm: " PW2
  echo
  [[ "$PW" == "$PW2" ]] || { echo "ERROR: passwords do not match." >&2; exit 1; }
  printf '%s' "$PW"
}

sql_escape() {
  printf '%s' "${1//\'/\'\'}"
}

db_exists() {
  local db="$1"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres -tAc \
    "SELECT 1 FROM pg_database WHERE datname = '${db}'" | grep -q 1
}

role_exists() {
  local role="$1"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres -tAc \
    "SELECT 1 FROM pg_roles WHERE rolname = '${role}'" | grep -q 1
}

db_owner() {
  local db="$1"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres -tAc \
    "SELECT pg_catalog.pg_get_userbyid(datdba) FROM pg_database WHERE datname = '${db}'"
}

# Safely quote a password literal regardless of special characters.
role_password_literal() {
  local pw="$1" b64 quoted
  if base64 --help 2>/dev/null | grep -q -- '-w'; then
    b64="$(printf '%s' "$pw" | base64 -w 0)"
  else
    b64="$(printf '%s' "$pw" | base64 | tr -d '\n')"
  fi
  quoted="$(docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres -tAc \
    "SELECT quote_literal(convert_from(decode('${b64}', 'base64'), 'UTF8'));")"
  quoted="${quoted//$'\r'/}"
  quoted="${quoted//$'\n'/}"
  printf '%s' "$quoted"
}

ensure_role_login() {
  local role="$1" pw="$2" extra="${3:-}"
  local pw_lit op
  pw_lit="$(role_password_literal "$pw")"
  [[ -n "$pw_lit" ]] || { echo "ERROR: failed to encode password." >&2; return 1; }
  if role_exists "$role"; then
    op="ALTER ROLE"
  else
    op="CREATE ROLE"
  fi
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres \
    -c "${op} \"${role}\" WITH LOGIN PASSWORD ${pw_lit} ${extra};"
}

set_role_password() {
  local role="$1" pw="$2"
  local pw_lit
  pw_lit="$(role_password_literal "$pw")"
  [[ -n "$pw_lit" ]] || { echo "ERROR: failed to encode password." >&2; return 1; }
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres \
    -c "ALTER ROLE \"${role}\" WITH PASSWORD ${pw_lit};"
}

# Verify a role can log in over TCP the same way remote apps do (SCRAM).
verify_role_login() {
  local user="$1" pw="$2" db="$3"
  local port ip attempt

  port="$(publish_host_port)"
  ip="$(docker compose exec -T postgres sh -c 'hostname -i 2>/dev/null | awk "{print \$1}"' 2>/dev/null | tr -d '\r\n')"

  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if [[ -n "$ip" ]]; then
      docker compose exec -T -e PGPASSWORD="$pw" postgres \
        psql -v ON_ERROR_STOP=1 -h "$ip" -U "$user" -d "$db" -tc "SELECT 1" 2>/dev/null | grep -q 1 && return 0
    fi
    if command -v psql >/dev/null 2>&1; then
      PGPASSWORD="$pw" psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$port" -U "$user" -d "$db" -tc "SELECT 1" 2>/dev/null | grep -q 1 && return 0
    else
      docker run --rm --network host -e PGPASSWORD="$pw" postgres:16-alpine \
        psql -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$port" -U "$user" -d "$db" -tc "SELECT 1" 2>/dev/null | grep -q 1 && return 0
    fi
    sleep 1
  done
  return 1
}

resolve_app_password() {
  local role="$1"
  # Manager UI always prompts — ignore PGSTACK_PASSWORD from the shell.
  if [[ -n "${PGSTACK_UI:-}" ]]; then
    prompt_password "$role"
    return 0
  fi
  if [[ -n "${PGSTACK_PASSWORD:-}" ]]; then
    printf '%s' "$PGSTACK_PASSWORD"
    return 0
  fi
  prompt_password "$role"
}

create_project_database() {
  local db="$1" owner="$2"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres <<SQL
SELECT format('CREATE DATABASE %I OWNER %I', '${db}', '${owner}')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${db}')\gexec
SQL
}

# Common, harmless extensions so app migrations don't fail.
ensure_common_extensions() {
  local db="$1"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$db" <<SQL
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
SQL
}

# Restrict a role to a single database (revoke access elsewhere).
isolate_to_db() {
  local db="$1" role="$2"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres <<SQL
REVOKE ALL ON DATABASE ${db} FROM PUBLIC;
GRANT CONNECT, TEMPORARY ON DATABASE ${db} TO ${role};

-- postgres DB still grants CONNECT via PUBLIC on many clusters; block app users.
REVOKE CONNECT ON DATABASE postgres FROM PUBLIC;

DO \$\$
DECLARE other_db text;
BEGIN
  FOR other_db IN
    SELECT datname FROM pg_database
    WHERE datistemplate = false AND datname <> '${db}'
  LOOP
    EXECUTE format('REVOKE CONNECT ON DATABASE %I FROM %I', other_db, '${role}');
  END LOOP;
END \$\$;

REVOKE ALL ON DATABASE postgres FROM ${role};
REVOKE CONNECT ON DATABASE postgres FROM ${role};
SQL
}

# Full ownership of everything in public, including objects loaded by a restore.
grant_owner_access() {
  local db="$1" user="$2"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$db" <<SQL
GRANT ALL ON SCHEMA public TO ${user};
GRANT ALL ON ALL TABLES IN SCHEMA public TO ${user};
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO ${user};
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO ${user};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${user};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${user};
ALTER ROLE ${user} RESET search_path;

-- Take ownership of objects created by the admin (e.g. after a restore),
-- so the app can run migrations / ALTER TABLE.
ALTER SCHEMA public OWNER TO ${user};
DO \$\$
DECLARE r record;
BEGIN
  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public'
  LOOP
    EXECUTE format('ALTER TABLE public.%I OWNER TO %I', r.tablename, '${user}');
  END LOOP;
  FOR r IN
    SELECT c.relname AS seq
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'S'
  LOOP
    EXECUTE format('ALTER SEQUENCE public.%I OWNER TO %I', r.seq, '${user}');
  END LOOP;
  FOR r IN
    SELECT viewname FROM pg_views WHERE schemaname = 'public'
  LOOP
    EXECUTE format('ALTER VIEW public.%I OWNER TO %I', r.viewname, '${user}');
  END LOOP;
END \$\$;
SQL
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres \
    -c "ALTER DATABASE ${db} OWNER TO ${user};"
}

grant_read_access() {
  local db="$1" user="$2"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$db" <<SQL
GRANT USAGE ON SCHEMA public TO ${user};
GRANT SELECT ON ALL TABLES IN SCHEMA public TO ${user};
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO ${user};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO ${user};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON SEQUENCES TO ${user};
ALTER ROLE ${user} RESET search_path;
SQL
}

grant_write_access() {
  local db="$1" user="$2"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$db" <<SQL
GRANT USAGE ON SCHEMA public TO ${user};
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ${user};
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO ${user};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${user};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO ${user};
ALTER ROLE ${user} RESET search_path;
SQL
}

valid_access_type() {
  [[ "${1:-}" =~ ^(owner|read|write|admin)$ ]]
}

# Add or update a user with a given access level on a database.
add_project_user() {
  local db="$1" access="$2" user="$3" pw="$4"
  local schema_owner

  valid_db_name "$user" || { echo "ERROR: invalid username." >&2; return 1; }
  valid_access_type "$access" || { echo "ERROR: invalid access type." >&2; return 1; }

  schema_owner="$(db_owner "$db")"
  [[ -n "$schema_owner" ]] || { echo "ERROR: database '${db}' not found." >&2; return 1; }

  case "$access" in
    owner)
      if [[ "$schema_owner" != "$POSTGRES_USER" && "$schema_owner" != "$user" ]]; then
        echo "ERROR: database already has owner '${schema_owner}'." >&2
        return 1
      fi
      ensure_role_login "$user" "$pw" "NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT"
      isolate_to_db "$db" "$user"
      grant_owner_access "$db" "$user"
      ;;
    read)
      ensure_role_login "$user" "$pw" "NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT"
      isolate_to_db "$db" "$user"
      grant_read_access "$db" "$user"
      ;;
    write)
      ensure_role_login "$user" "$pw" "NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT"
      isolate_to_db "$db" "$user"
      grant_write_access "$db" "$user"
      ;;
    admin)
      ensure_role_login "$user" "$pw" "NOSUPERUSER NOCREATEDB CREATEROLE NOINHERIT"
      isolate_to_db "$db" "$user"
      grant_write_access "$db" "$user"
      ;;
  esac

  if ! verify_role_login "$user" "$pw" "$db"; then
    echo "" >&2
    echo "ERROR: user '${user}' was configured but login verification FAILED." >&2
    echo "Use the EXACT password from your app DATABASE_URL:" >&2
    echo "  PGSTACK_PASSWORD='...' ./scripts/users/set-password.sh ${user}" >&2
    return 1
  fi
  echo "OK — '${user}' verified on '${db}' (remote-style login)"
}

print_connection_string() {
  local user="$1" db="$2"
  local host="${POSTGRES_HOST:-localhost}"
  echo "postgresql://${user}:PASSWORD@${host}:5432/${db}"
}

# Login roles with CONNECT on a database (project users only).
users_for_database() {
  local db="$1"
  docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -Atc "
    SELECT r.rolname
    FROM pg_roles r
    WHERE r.rolcanlogin
      AND NOT r.rolsuper
      AND r.rolname <> '${POSTGRES_USER}'
      AND has_database_privilege(r.rolname, '${db}', 'CONNECT')
    ORDER BY r.rolname;
  "
}

# List project databases where a role has CONNECT (or CREATE) privilege.
databases_for_role() {
  local user="$1"
  docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -Atc "
    SELECT d.datname
    FROM pg_database d
    WHERE d.datistemplate = false
      AND (
        has_database_privilege('${user}', d.datname, 'CONNECT')
        OR has_database_privilege('${user}', d.datname, 'CREATE')
      )
    ORDER BY d.datname;
  "
}

terminate_db_connections() {
  local db="$1"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres <<SQL
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '${db}' AND pid <> pg_backend_pid();
SQL
}

# Revoke privileges and drop objects owned by a role across all databases.
teardown_user_grants() {
  local user="$1"
  local db

  echo "Revoking privileges for '${user}'..."

  while IFS= read -r db; do
    [[ -z "$db" ]] && continue
    docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$db" -v ON_ERROR_STOP=0 \
      -c "DROP OWNED BY ${user};" || true
  done < <(docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -Atc \
    "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname;")

  docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -v ON_ERROR_STOP=0 -c \
    "DROP OWNED BY ${user};" || true

  while IFS= read -r db; do
    [[ -z "$db" ]] && continue
    docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -v ON_ERROR_STOP=0 -c \
      "REVOKE ALL PRIVILEGES ON DATABASE ${db} FROM ${user};
       REVOKE CONNECT ON DATABASE ${db} FROM ${user};" || true
  done < <(databases_for_role "$user")
}
