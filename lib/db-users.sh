#!/usr/bin/env bash
# Shared helpers for per-database user roles.

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

# Same TCP path remote apps use (published port + SCRAM).
verify_role_login() {
  local user="$1" pw="$2" db="$3"
  local port="${4:-$(publish_host_port)}"
  local attempt

  for attempt in 1 2 3 4 5; do
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
  if [[ -n "${PGSTACK_PASSWORD:-}" ]]; then
    printf '%s' "$PGSTACK_PASSWORD"
    return 0
  fi
  prompt_password "$role"
}

isolate_to_db() {
  local db="$1" role="$2"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres <<SQL
REVOKE ALL ON DATABASE ${db} FROM PUBLIC;
GRANT CONNECT, TEMPORARY ON DATABASE ${db} TO ${role};

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
SQL
}

schema_app_exists() {
  local db="$1"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$db" -tAc \
    "SELECT 1 FROM information_schema.schemata WHERE schema_name = 'app'" | grep -q 1
}

ensure_project_schema_if_missing() {
  local db="$1" owner="$2"
  if schema_app_exists "$db"; then
    return 0
  fi
  echo "Schema 'app' not found in '${db}' — creating project schema..."
  setup_project_schema "$db" "$owner"
}

setup_project_schema() {
  local db="$1" owner="$2"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$db" <<SQL
-- Session override: DB/role may have search_path=app before schema exists.
SET search_path = public, pg_catalog;

CREATE SCHEMA IF NOT EXISTS app AUTHORIZATION ${owner};

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" SCHEMA public;
CREATE EXTENSION IF NOT EXISTS "pg_trgm" SCHEMA public;

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM ${owner};
GRANT USAGE ON SCHEMA public TO ${owner};

GRANT ALL ON SCHEMA app TO ${owner};
ALTER DEFAULT PRIVILEGES FOR ROLE ${owner} IN SCHEMA app
  GRANT ALL ON TABLES TO ${owner};
ALTER DEFAULT PRIVILEGES FOR ROLE ${owner} IN SCHEMA app
  GRANT ALL ON SEQUENCES TO ${owner};

ALTER ROLE ${owner} SET search_path = app;

CREATE OR REPLACE FUNCTION app.provision_user(
  p_username text,
  p_access text,
  p_password text
) RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = app, pg_catalog
AS \$\$
DECLARE
  v_db text := current_database();
  other_db text;
BEGIN
  IF p_access NOT IN ('read', 'write') THEN
    RAISE EXCEPTION 'access must be read or write';
  END IF;

  IF p_username !~ '^[a-z][a-z0-9_]*\$' THEN
    RAISE EXCEPTION 'invalid username';
  END IF;

  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = p_username) THEN
    EXECUTE format('CREATE ROLE %I WITH LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT', p_username, p_password);
  ELSE
    EXECUTE format('ALTER ROLE %I WITH LOGIN PASSWORD %L', p_username, p_password);
  END IF;

  EXECUTE format('REVOKE ALL ON DATABASE %I FROM PUBLIC', v_db);
  EXECUTE format('GRANT CONNECT, TEMPORARY ON DATABASE %I TO %I', v_db, p_username);

  FOR other_db IN
    SELECT datname FROM pg_database
    WHERE datistemplate = false AND datname <> v_db
  LOOP
    EXECUTE format('REVOKE CONNECT ON DATABASE %I FROM %I', other_db, p_username);
  END LOOP;

  EXECUTE format('GRANT USAGE ON SCHEMA app TO %I', p_username);

  IF p_access = 'read' THEN
    EXECUTE format('GRANT SELECT ON ALL TABLES IN SCHEMA app TO %I', p_username);
    EXECUTE format('GRANT SELECT ON ALL SEQUENCES IN SCHEMA app TO %I', p_username);
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA app GRANT SELECT ON TABLES TO %I', '${owner}', p_username);
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA app GRANT SELECT ON SEQUENCES TO %I', '${owner}', p_username);
  ELSE
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO %I', p_username);
    EXECUTE format('GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA app TO %I', p_username);
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA app GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO %I', '${owner}', p_username);
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA app GRANT USAGE, SELECT ON SEQUENCES TO %I', '${owner}', p_username);
  END IF;

  EXECUTE format('ALTER ROLE %I SET search_path = app', p_username);
  RETURN format('postgresql://%s:PASSWORD@HOST:5432/%s', p_username, v_db);
END;
\$\$;

REVOKE ALL ON FUNCTION app.provision_user(text, text, text) FROM PUBLIC;
SQL
}

grant_db_admin() {
  local db="$1" admin="$2"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$db" <<SQL
GRANT EXECUTE ON FUNCTION app.provision_user(text, text, text) TO ${admin};
SQL
}

grant_read_access() {
  local db="$1" owner="$2" user="$3"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$db" <<SQL
GRANT USAGE ON SCHEMA app TO ${user};
GRANT SELECT ON ALL TABLES IN SCHEMA app TO ${user};
GRANT SELECT ON ALL SEQUENCES IN SCHEMA app TO ${user};
ALTER DEFAULT PRIVILEGES FOR ROLE ${owner} IN SCHEMA app
  GRANT SELECT ON TABLES TO ${user};
ALTER DEFAULT PRIVILEGES FOR ROLE ${owner} IN SCHEMA app
  GRANT SELECT ON SEQUENCES TO ${user};
ALTER ROLE ${user} SET search_path = app;
SQL
}

grant_write_access() {
  local db="$1" owner="$2" user="$3"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$db" <<SQL
GRANT USAGE ON SCHEMA app TO ${user};
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO ${user};
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA app TO ${user};
ALTER DEFAULT PRIVILEGES FOR ROLE ${owner} IN SCHEMA app
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${user};
ALTER DEFAULT PRIVILEGES FOR ROLE ${owner} IN SCHEMA app
  GRANT USAGE, SELECT ON SEQUENCES TO ${user};
ALTER ROLE ${user} SET search_path = app;
SQL
}

create_project_database() {
  local db="$1" owner="$2"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres <<SQL
SELECT format('CREATE DATABASE %I OWNER %I', '${db}', '${owner}')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${db}')\gexec
SQL
}

grant_owner_access() {
  local db="$1" user="$2"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$db" <<SQL
GRANT ALL ON SCHEMA app TO ${user};
ALTER DEFAULT PRIVILEGES FOR ROLE ${user} IN SCHEMA app
  GRANT ALL ON TABLES TO ${user};
ALTER DEFAULT PRIVILEGES FOR ROLE ${user} IN SCHEMA app
  GRANT ALL ON SEQUENCES TO ${user};
ALTER ROLE ${user} SET search_path = app;
ALTER SCHEMA app OWNER TO ${user};
SQL
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres \
    -c "ALTER DATABASE ${db} OWNER TO ${user};"
}

valid_access_type() {
  [[ "${1:-}" =~ ^(owner|read|write|admin)$ ]]
}

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
      ensure_project_schema_if_missing "$db" "$user"
      grant_owner_access "$db" "$user"
      ;;
    read)
      ensure_role_login "$user" "$pw" "NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT"
      isolate_to_db "$db" "$user"
      ensure_project_schema_if_missing "$db" "$schema_owner"
      grant_read_access "$db" "$schema_owner" "$user"
      ;;
    write)
      ensure_role_login "$user" "$pw" "NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT"
      isolate_to_db "$db" "$user"
      ensure_project_schema_if_missing "$db" "$schema_owner"
      grant_write_access "$db" "$schema_owner" "$user"
      ;;
    admin)
      ensure_role_login "$user" "$pw" "NOSUPERUSER NOCREATEDB CREATEROLE NOINHERIT"
      isolate_to_db "$db" "$user"
      ensure_project_schema_if_missing "$db" "$schema_owner"
      grant_db_admin "$db" "$user"
      ;;
  esac

  if ! verify_role_login "$user" "$pw" "$db"; then
    echo "" >&2
    echo "ERROR: user '${user}' was configured but password verification FAILED." >&2
    echo "Remote apps (Django) will not connect. This is a pgstack bug if you saw OK before." >&2
    echo "Fix with the EXACT password from your app .env:" >&2
    echo "  PGSTACK_PASSWORD='...' ./scripts/users/set-password.sh ${user}" >&2
    return 1
  fi
  echo "OK — login verified for '${user}' on '${db}' (remote-style SCRAM)"
}

print_connection_string() {
  local user="$1" db="$2"
  local host="${POSTGRES_HOST:-localhost}"
  echo "postgresql://${user}:PASSWORD@${host}:5432/${db}"
}

print_db_summary() {
  local db="$1"
  echo ""
  echo "OK — database '${db}' ready (schema: app)"
  echo ""
  echo "Add users anytime:"
  echo "  ./scripts/users/add-user.sh ${db} <owner|read|write|admin> USERNAME"
  echo ""
  echo "Users with access:"
  docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -Atc "
    SELECT r.rolname
    FROM pg_roles r
    WHERE r.rolcanlogin AND NOT r.rolsuper
      AND r.rolname <> '${POSTGRES_USER}'
      AND has_database_privilege(r.rolname, '${db}', 'CONNECT')
    ORDER BY r.rolname;
  " | while read -r u; do
    [[ -n "$u" ]] && echo "  $(print_connection_string "$u" "$db")"
  done
  echo ""
  echo "Server admin ${POSTGRES_USER} is for management only — not for apps."
}

prompt_add_user_interactive() {
  local db="$1"
  local access user pw choice

  echo ""
  echo "Access types:"
  echo "  1) owner — read, write, delete, create tables"
  echo "  2) read   — read only"
  echo "  3) write  — read + write on tables"
  echo "  4) admin  — create read/write users for this DB"
  echo "  0) cancel"
  read -r -p "Access: " choice

  case "$choice" in
    1) access="owner" ;;
    2) access="read" ;;
    3) access="write" ;;
    4) access="admin" ;;
    0|"") return 1 ;;
    *) echo "Invalid choice." >&2; return 1 ;;
  esac

  read -r -p "Username: " user
  [[ -n "$user" ]] || return 1

  pw="$(resolve_app_password "$user")"
  add_project_user "$db" "$access" "$user" "$pw"
  echo ""
  echo "OK — ${access} user '${user}' added"
  print_connection_string "$user" "$db"
}

interactive_add_users() {
  local db="$1" answer added=0

  echo ""
  echo "Users are optional. You choose access, username, and password for each."
  echo "Apps need an owner/write user — use the same password as DATABASE_URL in your .env."
  while true; do
    read -r -p "Add a user? (y/n): " answer
    [[ "$answer" =~ ^[yY] ]] || break
    if prompt_add_user_interactive "$db"; then
      added=$((added + 1))
    fi
    echo ""
  done

  if [[ "$added" -eq 0 ]]; then
    echo ""
    echo "WARNING: no users added — apps (Django, etc.) cannot connect yet."
    echo "Add one now: ./scripts/users/add-user.sh ${db} owner YOUR_USER"
    echo "Or set password from .env: PGSTACK_PASSWORD='...' ./scripts/users/set-password.sh YOUR_USER"
  fi
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

# True when role has privileges on only this non-template database.
role_exclusive_to_db() {
  local user="$1" db="$2"
  local dbs count
  dbs="$(databases_for_role "$user")"
  count="$(printf '%s\n' "$dbs" | sed '/^$/d' | wc -l | tr -d ' ')"
  [[ "$count" -eq 1 ]] && printf '%s\n' "$dbs" | grep -qx "$db"
}

reassign_db_owner_to_admin() {
  local db="$1"
  local owner
  owner="$(db_owner "$db")"
  [[ -n "$owner" && "$owner" != "$POSTGRES_USER" ]] || return 0
  echo "Reassigning database owner from '${owner}' to '${POSTGRES_USER}'..."
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres \
    -c "ALTER DATABASE ${db} OWNER TO ${POSTGRES_USER};"
}

terminate_db_connections() {
  local db="$1"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres <<SQL
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '${db}' AND pid <> pg_backend_pid();
SQL
}

revoke_user_from_database() {
  local db="$1" user="$2"
  revoke_app_grants "$db" "$user" || true
  docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$db" -v ON_ERROR_STOP=0 \
    -c "DROP OWNED BY ${user};" || true
  docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -v ON_ERROR_STOP=0 -c \
    "REVOKE ALL PRIVILEGES ON DATABASE ${db} FROM ${user};
     REVOKE CONNECT ON DATABASE ${db} FROM ${user};" || true
}

drop_role() {
  local user="$1"
  role_exists "$user" || return 0
  teardown_user_grants "$user"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres \
    -c "DROP ROLE ${user};"
}

prepare_database_drop() {
  local db="$1"
  local user others

  terminate_db_connections "$db"
  reassign_db_owner_to_admin "$db"

  while IFS= read -r user; do
    [[ -z "$user" ]] && continue
    if role_exclusive_to_db "$user" "$db"; then
      echo "Cleaning up user '${user}' (exclusive to '${db}')..."
      revoke_user_from_database "$db" "$user"
    else
      others="$(databases_for_role "$user" | grep -vx "$db" | paste -sd ', ' - || true)"
      echo "Revoking '${user}' from '${db}' (kept — also has: ${others:-other databases})..."
      revoke_user_from_database "$db" "$user"
    fi
  done < <(users_for_database "$db")
}

# List project databases where a role has CONNECT (or any) privilege.
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

wipe_database_for_restore() {
  local db="$1"
  terminate_db_connections "$db"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$db" \
    -c "DROP SCHEMA IF EXISTS app CASCADE;"
}

regrant_database_users_after_restore() {
  local db="$1" db_owner="$2"
  shift 2
  local users=("$@") user grant_owner

  grant_owner="${db_owner:-$POSTGRES_USER}"
  [[ -n "$grant_owner" ]] || grant_owner="$POSTGRES_USER"

  for user in "${users[@]}"; do
    [[ -z "$user" ]] && continue
    if [[ "$user" == "$db_owner" && "$db_owner" != "$POSTGRES_USER" ]]; then
      echo "Re-granting owner access to '${user}'..."
      grant_owner_access "$db" "$user"
    else
      echo "Re-granting write access to '${user}'..."
      grant_write_access "$db" "$grant_owner" "$user"
    fi
  done
}

revoke_app_grants() {
  local db="$1" user="$2"
  schema_app_exists "$db" || return 0
  docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$db" -v ON_ERROR_STOP=1 <<SQL
REVOKE ALL ON SCHEMA app FROM ${user};
REVOKE ALL ON ALL TABLES IN SCHEMA app FROM ${user};
REVOKE ALL ON ALL SEQUENCES IN SCHEMA app FROM ${user};
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA app FROM ${user};
SQL
}

# Revoke grants and drop objects owned by role in every database, then global.
teardown_user_grants() {
  local user="$1"
  local db

  echo "Revoking privileges for '${user}'..."

  while IFS= read -r db; do
    [[ -z "$db" ]] && continue
    revoke_app_grants "$db" "$user" || true
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
