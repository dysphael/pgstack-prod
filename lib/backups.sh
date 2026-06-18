#!/usr/bin/env bash
# Shared backup listing helpers.

backup_dir() {
  abs_path "${BACKUP_DIR:-./data/backups}"
}

backup_db_from_filename() {
  local file="$1"
  local base="${file##*/}"
  if [[ "$base" =~ ^backup_([a-z][a-z0-9_]*)_[0-9]{8}_[0-9]{6}\.sql\.gz$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    printf '%s' "?"
  fi
}

collect_backups() {
  BACKUP_FILES=()
  local dir file
  dir="$(backup_dir)"
  mkdir -p "$dir"
  while IFS= read -r file; do
    [[ -n "$file" ]] && BACKUP_FILES+=("$file")
  done < <(find "$dir" -maxdepth 1 -name 'backup_*.sql.gz' -type f 2>/dev/null | sort -r)
}

backup_path_at() {
  local index="$1"
  collect_backups
  [[ "$index" =~ ^[0-9]+$ ]] || return 1
  (( index >= 1 && index <= ${#BACKUP_FILES[@]} )) || return 1
  printf '%s' "${BACKUP_FILES[$((index - 1))]}"
}

backup_mtime() {
  local file="$1"
  date -r "$file" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$file"
}

print_backup_table() {
  collect_backups
  local dir
  dir="$(backup_dir)"

  if [[ ${#BACKUP_FILES[@]} -eq 0 ]]; then
    echo "No backups in ${dir}"
    return 0
  fi

  printf '%-3s %-12s %-6s %-20s %s\n' "#" "DB" "Size" "Date" "Path"
  local i file db size mtime
  for i in "${!BACKUP_FILES[@]}"; do
    file="${BACKUP_FILES[$i]}"
    db="$(backup_db_from_filename "$file")"
    size="$(du -h "$file" | cut -f1)"
    mtime="$(backup_mtime "$file")"
    printf '%-3s %-12s %-6s %-20s %s\n' "$((i + 1))" "$db" "$size" "$mtime" "$file"
  done
}
