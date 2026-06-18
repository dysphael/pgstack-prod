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

ensure_role_login() {
  local role="$1" pw="$2" extra="${3:-}"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres <<SQL
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${role}') THEN
    CREATE ROLE ${role} WITH LOGIN PASSWORD '${pw}' ${extra};
  ELSE
    ALTER ROLE ${role} WITH LOGIN PASSWORD '${pw}' ${extra};
  END IF;
END \$\$;
SQL
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

setup_project_schema() {
  local db="$1" owner="$2"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$db" <<SQL
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

CREATE SCHEMA IF NOT EXISTS app AUTHORIZATION ${owner};

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

print_user_summary() {
  local db="$1" owner="$2" read_user="$3" admin_user="$4"
  local host="${POSTGRES_HOST:-localhost}"
  echo ""
  echo "OK — database '${db}' ready"
  echo ""
  echo "  Roles:"
  echo "    ${owner}       read + write + delete (app)"
  echo "    ${read_user}   read only (reports, BI)"
  echo "    ${admin_user}  create read/write users for this DB only"
  echo ""
  echo "  Connection strings:"
  echo "    postgresql://${owner}:PASSWORD@${host}:5432/${db}"
  echo "    postgresql://${read_user}:PASSWORD@${host}:5432/${db}"
  echo ""
  echo "  DB admin creates users:"
  echo "    SELECT app.provision_user('new_user', 'read',  'password');"
  echo "    SELECT app.provision_user('new_user', 'write', 'password');"
  echo ""
  echo "  Or from server: ./scripts/add-user.sh ${db} read|write USERNAME"
  echo "  Tables use schema: app"
  echo "  Server admin ${POSTGRES_USER} is for backups only — not for apps."
}
