#!/usr/bin/env bash
# App lifecycle: setup, backup, restore, drop, verify.
# Used by scripts/app.sh and bin/manager.sh.

app_registry_file() {
  printf '%s/apps/registry.json' "${DATA_DIR:-./data}"
}

app_registry_ensure() {
  local file dir
  file="$(app_registry_file)"
  dir="$(dirname "$file")"
  mkdir -p "$dir"
  [[ -f "$file" ]] || echo '{}' >"$file"
}

# Read registry field: app_registry_get <db> [user|label]
app_registry_get() {
  local db="$1" field="${2:-user}"
  app_registry_ensure
  python3 - "$(app_registry_file)" "$db" "$field" <<'PY'
import json, sys
path, db, field = sys.argv[1:4]
with open(path) as f:
    data = json.load(f)
entry = data.get(db, {})
print(entry.get(field, ""))
PY
}

app_register() {
  local db="$1" user="$2" label="${3:-}"
  app_registry_ensure
  python3 - "$(app_registry_file)" "$db" "$user" "$label" <<'PY'
import json, sys
path, db, user, label = sys.argv[1:5]
with open(path) as f:
    data = json.load(f)
entry = {"user": user}
if label:
    entry["label"] = label
data[db] = entry
with open(path, "w") as f:
    json.dump(data, f, indent=2, sort_keys=True)
    f.write("\n")
PY
  echo "OK — registered app '${db}' (user: ${user})"
}

app_registry_list_dbs() {
  app_registry_ensure
  python3 - "$(app_registry_file)" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for db in sorted(data):
    print(db)
PY
}

app_registry_print_table() {
  local db user label exists role_ok
  app_registry_ensure
  echo ""
  printf '%-14s %-18s %-20s %-8s %-8s\n' "DATABASE" "USER" "LABEL" "DB" "USER"
  while IFS= read -r db; do
    [[ -z "$db" ]] && continue
    user="$(app_registry_get "$db" user)"
    label="$(app_registry_get "$db" label)"
    exists="no"
    role_ok="no"
    db_exists "$db" && exists="yes"
    role_exists "$user" && role_ok="yes"
    printf '%-14s %-18s %-20s %-8s %-8s\n' "$db" "$user" "${label:-—}" "$exists" "$role_ok"
  done < <(app_registry_list_dbs)
  echo ""
}

require_app_password() {
  [[ -n "${PGSTACK_PASSWORD:-}" ]] || {
    echo "ERROR: set PGSTACK_PASSWORD to the exact app password (from DATABASE_URL)." >&2
    return 1
  }
}

confirm_yes() {
  local prompt="${1:-Type YES to continue:}"
  if [[ "${PGSTACK_YES:-}" == "1" ]]; then
    return 0
  fi
  read -r -p "$prompt " OK
  [[ "$OK" == "YES" ]]
}

manifest_path_for_backup() {
  local backup_file="$1"
  printf '%s' "${backup_file%.sql.gz}.manifest.json"
}

write_backup_manifest() {
  local db="$1" backup_file="$2"
  local manifest owner users_json
  manifest="$(manifest_path_for_backup "$backup_file")"
  owner="$(db_owner "$db")"

  users_json="$(python3 - <<'PY'
import json, sys
users = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    user, access = line.split(":", 1)
    users.append({"name": user, "access": access})
print(json.dumps(users))
PY
<<< "$(snapshot_database_users "$db")")"

  python3 - "$manifest" "$db" "$owner" "$users_json" <<'PY'
import json, sys
from datetime import datetime, timezone
path, db, owner, users_json = sys.argv[1:5]
users = json.loads(users_json)
data = {
    "database": db,
    "owner": owner,
    "users": users,
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "pgstack_version": "1",
}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
  echo "OK manifest ${manifest}" >&2
}

load_backup_manifest_entries() {
  local backup_file="$1"
  local manifest
  manifest="$(manifest_path_for_backup "$backup_file")"
  [[ -f "$manifest" ]] || return 1
  python3 - "$manifest" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
print(data.get("database", ""))
print(data.get("owner", ""))
for u in data.get("users", []):
    print(f"{u['name']}:{u.get('access', 'write')}")
PY
}

app_setup() {
  local db="$1" user="$2" pw="$3"

  valid_db_name "$db" && valid_db_name "$user" || { echo "ERROR: invalid name." >&2; return 1; }
  [[ -n "$pw" ]] || { echo "ERROR: password required." >&2; return 1; }

  if db_exists "$db"; then
    echo "ERROR: database '${db}' already exists." >&2
    echo "Use: ./scripts/app.sh verify ${db}" >&2
    echo " or: PGSTACK_PASSWORD='...' ./scripts/users/set-password.sh ${user}" >&2
    return 1
  fi

  echo "Setting up app '${db}' with owner '${user}'..."
  create_project_database "$db" "$POSTGRES_USER"
  setup_project_schema "$db" "$POSTGRES_USER"
  add_project_user "$db" owner "$user" "$pw" || return 1
  app_register "$db" "$user" "${4:-}"
  app_print_ready "$db" "$user"
}

app_backup() {
  local db="$1"
  local file ts

  valid_db_name "$db" || return 1
  db_exists "$db" || { echo "ERROR: database '${db}' not found." >&2; return 1; }

  mkdir -p "$BACKUP_DIR"
  ts="$(date +%Y%m%d_%H%M%S)"
  file="${BACKUP_DIR}/backup_${db}_${ts}.sql.gz"

  echo "Backing up ${db}..." >&2
  docker compose exec -T postgres pg_dump -U "$POSTGRES_USER" --no-owner --no-acl -d "$db" | gzip >"$file"
  [[ -s "$file" ]] || { rm -f "$file"; echo "ERROR: backup failed." >&2; return 1; }
  echo "OK ${file} ($(du -h "$file" | cut -f1))" >&2

  write_backup_manifest "$db" "$file" >&2
  printf '%s' "$file"
}

app_drop() {
  local db="$1" backup_first="${2:-1}"

  valid_db_name "$db" || return 1
  [[ "$db" != "postgres" ]] || { echo "ERROR: cannot drop system database." >&2; return 1; }
  db_exists "$db" || { echo "ERROR: database '${db}' not found." >&2; return 1; }

  if [[ "$backup_first" == "1" ]]; then
    echo "Creating safety backup before drop..."
    app_backup "$db" >/dev/null || return 1
  fi

  echo "Dropping database '${db}'..."
  PGSTACK_YES=1 "${ROOT}/scripts/databases/drop-db.sh" "$db"
}

app_restore() {
  local file="$1" db="$2" owner_user="$3" pw="$4"
  local -a user_entries=()
  local line user access entry
  local manifest_db="" manifest_owner=""

  [[ -f "$file" ]] || { echo "ERROR: backup not found: ${file}" >&2; return 1; }
  [[ -n "$pw" ]] || { echo "ERROR: password required for restore verification." >&2; return 1; }

  if [[ -f "$(manifest_path_for_backup "$file")" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      if [[ -z "$manifest_db" ]]; then
        manifest_db="$line"
      elif [[ -z "$manifest_owner" ]]; then
        manifest_owner="$line"
      else
        user_entries+=("$line")
      fi
    done < <(load_backup_manifest_entries "$file")
  fi

  [[ -n "$db" ]] || db="$manifest_db"
  [[ -n "$owner_user" ]] || owner_user="$(app_registry_get "$db" user)"
  [[ -z "$owner_user" && -n "$manifest_owner" && "$manifest_owner" != "$POSTGRES_USER" ]] && owner_user="$manifest_owner"

  valid_db_name "$db" || return 1
  [[ -n "$owner_user" ]] || {
    echo "ERROR: owner user unknown — register app or pass username." >&2
    return 1
  }

  if [[ ${#user_entries[@]} -eq 0 ]]; then
    if db_exists "$db"; then
      while IFS= read -r user; do
        [[ -z "$user" ]] && continue
        access="$(user_access_type "$db" "$user")"
        user_entries+=("${user}:${access}")
      done < <(users_for_database "$db")
    fi
    [[ ${#user_entries[@]} -gt 0 ]] || user_entries+=("${owner_user}:owner")
  fi

  echo "Restore ${file} → ${db} (owner: ${owner_user})"
  echo "WARNING: this replaces existing data in '${db}'."
  confirm_yes "Type YES to continue:" || { echo "Cancelled."; return 0; }

  if db_exists "$db"; then
    echo "Clearing schema 'app' before restore..."
    wipe_database_for_restore "$db"
  else
    echo "Creating empty database '${db}'..."
    docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres \
      -c "CREATE DATABASE ${db};"
  fi

  terminate_db_connections "$db"
  echo "Importing backup..."
  gunzip -c "$file" | docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$db"

  echo "Ensuring app users and grants..."
  for entry in "${user_entries[@]}"; do
    user="${entry%%:*}"
    access="${entry#*:}"
    [[ "$user" == "$access" ]] && access="owner"
    if [[ "$user" == "$owner_user" ]]; then
      ensure_app_user_after_restore "$db" "$user" "$access" "$pw"
      set_role_password "$user" "$pw"
    else
      ensure_app_user_after_restore "$db" "$user" "$access" "$pw"
    fi
  done

  if ! confirm_project_user "$owner_user" "$pw" "$db"; then
    echo "" >&2
    echo "ERROR: restore finished but app verification FAILED." >&2
    echo "Fix: PGSTACK_PASSWORD='...' ./scripts/app.sh verify ${db}" >&2
    return 1
  fi

  app_register "$db" "$owner_user" "$(app_registry_get "$db" label)"
  echo ""
  echo "OK — restored '${db}' and verified '${owner_user}'"
  app_print_ready "$db" "$owner_user"
}

app_verify() {
  local db="$1" user="$2" pw="$3"

  [[ -n "$pw" ]] || require_app_password || return 1
  pw="${pw:-$PGSTACK_PASSWORD}"

  valid_db_name "$db" || return 1
  [[ -n "$user" ]] || user="$(app_registry_get "$db" user)"
  [[ -n "$user" ]] || { echo "ERROR: user unknown — register app or pass username." >&2; return 1; }

  echo "=== Verify ${user} @ ${db} ==="
  echo ""

  role_exists "$user" || { echo "FAIL role '${user}' does not exist" >&2; return 1; }
  echo "OK   role exists"

  db_exists "$db" || { echo "FAIL database '${db}' does not exist" >&2; return 1; }
  echo "OK   database exists"

  schema_app_exists "$db" || { echo "FAIL schema 'app' missing" >&2; return 1; }
  echo "OK   schema 'app' exists"

  if confirm_project_user "$user" "$pw" "$db"; then
    echo "OK   login + search_path verified (SCRAM)"
    echo ""
    echo "PASS — app '${db}' is ready"
    app_print_ready "$db" "$user"
    return 0
  fi

  echo "FAIL verification" >&2
  echo "Fix: PGSTACK_PASSWORD='...' ./scripts/users/set-password.sh ${user}" >&2
  return 1
}

app_print_ready() {
  local db="$1" user="$2"
  local host="${POSTGRES_HOST:-localhost}"
  echo ""
  echo "DATABASE_URL:"
  echo "  postgresql://${user}:PASSWORD@${host}:5432/${db}"
  echo ""
  echo "Next: restart your app (Django, etc.) to refresh connection pools."
}

collect_backups_for_db() {
  local db="$1" file d
  local -a all=()
  collect_backups
  all=("${BACKUP_FILES[@]}")
  BACKUP_FILES=()
  for file in "${all[@]}"; do
    d="$(backup_db_from_filename "$file")"
    [[ "$d" == "$db" ]] && BACKUP_FILES+=("$file")
  done
}
