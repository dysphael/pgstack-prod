#!/usr/bin/env bash
# Compact PostgreSQL query output for the interactive manager.

pg_table_width() {
  echo "${PGSTACK_TABLE_WIDTH:-68}"
}

pg_truncate_field() {
  local text="${1:-}" max="$2"
  if (( max < 1 )); then
    return 0
  fi
  if (( ${#text} <= max )); then
    printf '%s' "$text"
    return 0
  fi
  if (( max <= 3 )); then
    printf '%s' "${text:0:max}"
    return 0
  fi
  printf '%s...' "${text:0:$((max - 3))}"
}

# Usage: pg_query_csv <database> <sql>
pg_query_csv() {
  local db="$1" sql="$2"
  docker compose exec -T postgres psql -U "${POSTGRES_USER}" -d "$db" --csv -c "$sql" 2>/dev/null
}

# Parse one CSV line into PG_CSV_FIELDS array (handles quoted fields).
pg_parse_csv_line() {
  local line="$1"
  PG_CSV_FIELDS=()
  local field="" ch in_quotes=0 i c
  for ((i = 0; i < ${#line}; i++)); do
    c="${line:i:1}"
    if [[ "$c" == '"' ]]; then
      if (( in_quotes )) && [[ "${line:i+1:1}" == '"' ]]; then
        field+='"'
        ((i++))
      else
        in_quotes=$((1 - in_quotes))
      fi
      continue
    fi
    if [[ "$c" == ',' ]] && (( ! in_quotes )); then
      PG_CSV_FIELDS+=("$field")
      field=""
      continue
    fi
    field+="$c"
  done
  PG_CSV_FIELDS+=("$field")
}

# Usage: pg_print_table <database> <sql> <width1> [width2 ...]
pg_print_table() {
  local db="$1" sql="$2"
  shift 2
  local -a widths=("$@")
  local data line row=0
  local -a headers=() fields=()
  local i w

  data="$(pg_query_csv "$db" "$sql")" || {
    echo "Query failed."
    return 1
  }

  if [[ -z "${data//[$'\r\n']/}" ]]; then
    echo "(0 rows)"
    return 0
  fi

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    pg_parse_csv_line "$line"
    fields=("${PG_CSV_FIELDS[@]}")

    if (( row == 0 )); then
      headers=("${fields[@]}")
      for i in "${!headers[@]}"; do
        w="${widths[i]:-12}"
        printf '%-*s ' "$w" "$(pg_truncate_field "${headers[i]}" "$w")"
      done
      printf '\n'
      row=1
      continue
    fi

    for i in "${!fields[@]}"; do
      w="${widths[i]:-12}"
      printf '%-*s ' "$w" "$(pg_truncate_field "${fields[i]}" "$w")"
    done
    printf '\n'
  done <<<"$data"

  if (( row < 2 )); then
    echo "(0 rows)"
  fi
}

# Usage: pg_print_rows <database> <sql>
# Prints each result row as "column: value" lines (compact blocks).
pg_print_rows() {
  local db="$1" sql="$2"
  local data line row=0
  local -a headers=() fields=()
  local i

  data="$(pg_query_csv "$db" "$sql")" || {
    echo "Query failed."
    return 1
  }

  if [[ -z "${data//[$'\r\n']/}" ]]; then
    echo "(0 rows)"
    return 0
  fi

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    pg_parse_csv_line "$line"
    fields=("${PG_CSV_FIELDS[@]}")

    if (( row == 0 )); then
      headers=("${fields[@]}")
      row=1
      continue
    fi

    if (( row > 1 )); then
      echo ""
    fi
    for i in "${!fields[@]}"; do
      printf '%-16s %s\n' "${headers[i]}:" "$(pg_truncate_field "${fields[i]}" "$(pg_table_width)")"
    done
    row=$((row + 1))
  done <<<"$data"

  if (( row < 2 )); then
    echo "(0 rows)"
  fi
}

# Run psql aligned output (CLI default).
pg_psql_aligned() {
  local db="$1" sql="$2"
  docker compose exec -T postgres psql -U "${POSTGRES_USER}" -d "$db" -c "$sql"
}
