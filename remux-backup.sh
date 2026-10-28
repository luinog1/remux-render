#!/bin/sh
set -eu

ACTION="${1:-backup}"
DATA_DIR="${DATA_DIR:-/data}"
DB_PATH="${DATA_DIR}/db.sqlite"
TMP_DIR="${TMPDIR:-/tmp}/remux-backup"
TABLE_META="remux_sqlite_backup_meta"
TABLE_CHUNKS="remux_sqlite_backup_chunks"

log() {
  echo "[remux-backup] $*"
}

enabled() {
  [ -n "${DB_HOST:-}" ] &&
  [ -n "${DB_USERNAME:-}" ] &&
  [ -n "${DB_PASSWORD:-}" ] &&
  [ -n "${DB_DATABASE:-}" ]
}

mysql_exec() {
  MYSQL_PWD="${DB_PASSWORD}" mariadb     --protocol=TCP     --host="${DB_HOST}"     --port="${DB_PORT:-3306}"     --user="${DB_USERNAME}"     --database="${DB_DATABASE}"     --batch --skip-column-names --raw     -e "$1"
}

ensure_tables() {
  mysql_exec "
    CREATE TABLE IF NOT EXISTS ${TABLE_META} (
      meta_key VARCHAR(64) PRIMARY KEY,
      meta_value VARCHAR(128) NOT NULL,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    );
    CREATE TABLE IF NOT EXISTS ${TABLE_CHUNKS} (
      backup_id VARCHAR(128) NOT NULL,
      seq INT NOT NULL,
      chunk_data LONGTEXT NOT NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (backup_id, seq)
    );
  "
}

restore_backup() {
  if ! enabled; then
    log "managed MySQL variables not found; restore disabled"
    return 0
  fi

  mkdir -p "${DATA_DIR}" "${TMP_DIR}"
  ensure_tables

  backup_id="$(mysql_exec "SELECT meta_value FROM ${TABLE_META} WHERE meta_key='current_backup' LIMIT 1;" 2>/dev/null || true)"
  if [ -z "${backup_id}" ]; then
    log "no remote SQLite snapshot found; starting with a new local database"
    return 0
  fi

  log "restoring SQLite snapshot ${backup_id} from managed MySQL"
  archive="${TMP_DIR}/restore.sqlite.gz"
  restored="${TMP_DIR}/restore.sqlite"
  : > "${archive}"

  mysql_exec "SELECT chunk_data FROM ${TABLE_CHUNKS} WHERE backup_id='${backup_id}' ORDER BY seq;" |
  while IFS= read -r line; do
    printf '%s' "${line}" | base64 -d >> "${archive}"
  done

  gzip -dc "${archive}" > "${restored}"
  check="$(sqlite3 "${restored}" 'PRAGMA quick_check;' 2>/dev/null || true)"
  if [ "${check}" != "ok" ]; then
    log "ERROR: restored snapshot failed SQLite quick_check: ${check:-no result}"
    return 1
  fi

  mv -f "${restored}" "${DB_PATH}"
  chmod 0666 "${DB_PATH}" 2>/dev/null || true
  rm -f "${archive}"
  log "restore complete ($(wc -c < "${DB_PATH}") bytes)"
}

create_backup() {
  if ! enabled; then
    log "managed MySQL variables not found; backup disabled"
    return 0
  fi
  if [ ! -s "${DB_PATH}" ]; then
    log "SQLite database does not exist yet; skipping backup"
    return 0
  fi

  mkdir -p "${TMP_DIR}"
  ensure_tables

  snapshot="${TMP_DIR}/snapshot.sqlite"
  archive="${TMP_DIR}/snapshot.sqlite.gz"
  chunks="${TMP_DIR}/chunks"
  rm -rf "${chunks}"
  mkdir -p "${chunks}"
  rm -f "${snapshot}" "${archive}"

  # SQLite's online backup API produces a consistent DB even while Remux uses WAL.
  sqlite3 "${DB_PATH}" ".timeout 15000" ".backup '${snapshot}'"

  check="$(sqlite3 "${snapshot}" 'PRAGMA quick_check;' 2>/dev/null || true)"
  if [ "${check}" != "ok" ]; then
    log "ERROR: local snapshot failed SQLite quick_check: ${check:-no result}"
    return 1
  fi

  gzip -c -6 "${snapshot}" > "${archive}"
  backup_id="$(date +%s)-$$"
  split -b 512k -d -a 6 "${archive}" "${chunks}/chunk-"

  seq=0
  for part in "${chunks}"/chunk-*; do
    [ -f "${part}" ] || continue
    encoded="$(base64 -w 0 "${part}")"
    mysql_exec "INSERT INTO ${TABLE_CHUNKS} (backup_id, seq, chunk_data) VALUES ('${backup_id}', ${seq}, '${encoded}');"
    seq=$((seq + 1))
  done

  if [ "${seq}" -eq 0 ]; then
    log "ERROR: snapshot produced no chunks"
    return 1
  fi

  # Publish the new backup only after every chunk is safely stored.
  mysql_exec "
    INSERT INTO ${TABLE_META} (meta_key, meta_value)
    VALUES ('current_backup', '${backup_id}')
    ON DUPLICATE KEY UPDATE meta_value=VALUES(meta_value);
    DELETE FROM ${TABLE_CHUNKS} WHERE backup_id <> '${backup_id}';
  "

  size="$(wc -c < "${archive}")"
  rm -rf "${chunks}" "${snapshot}" "${archive}"
  log "backup complete: ${backup_id}, ${seq} chunks, ${size} compressed bytes"
}

case "${ACTION}" in
  restore) restore_backup ;;
  backup) create_backup ;;
  *)
    echo "usage: $0 {backup|restore}" >&2
    exit 2
    ;;
esac
