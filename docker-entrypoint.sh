#!/bin/sh
set -eu

DATA_DIR="${DATA_DIR:-/data}"
DB_PATH="${DATA_DIR}/db.sqlite"
LOG_DIR="${DATA_DIR}/logs"
TORRENT_DIR="${DATA_DIR}/torrents"
BACKUP_INTERVAL_SECONDS="${BACKUP_INTERVAL_SECONDS:-300}"

# DockHosting/Coolify may inject its own DATABASE_URL when a managed database
# is linked. Remux itself must keep using local SQLite, while the linked MySQL
# service is used only as durable backup storage.
export DATA_DIR
export HOST="0.0.0.0"
export PORT="${PORT:-3000}"
export DATABASE_URL="sqlite://${DB_PATH}?mode=rwc"
export LOG_FILE="${LOG_DIR}/remux.jsonl"
export TORRENT_DATA_DIR="${TORRENT_DIR}"

echo "[dockhosting-entrypoint] uid=$(id -u) gid=$(id -g)"
echo "[dockhosting-entrypoint] preparing DATA_DIR=${DATA_DIR}"
echo "[dockhosting-entrypoint] forcing DATABASE_URL=sqlite://${DB_PATH}?mode=rwc"

mkdir -p "${DATA_DIR}" "${LOG_DIR}" "${TORRENT_DIR}"
chmod 0777 "${DATA_DIR}" "${LOG_DIR}" "${TORRENT_DIR}" 2>/dev/null || true

PROBE="${DATA_DIR}/.remux-write-test"
if ! ( : > "${PROBE}" && rm -f "${PROBE}" ); then
  echo "[dockhosting-entrypoint] ERROR: ${DATA_DIR} is not writable." >&2
  exit 70
fi

# If this is a fresh ephemeral container, restore the latest durable SQLite
# snapshot from the linked MySQL service before Remux starts.
if [ ! -s "${DB_PATH}" ]; then
  /usr/local/bin/remux-backup.sh restore || {
    echo "[dockhosting-entrypoint] WARNING: remote restore failed; starting without restored state" >&2
  }
fi

if [ ! -e "${DB_PATH}" ]; then
  : > "${DB_PATH}"
fi
chmod 0666 "${DB_PATH}" 2>/dev/null || true

echo "[dockhosting-entrypoint] data directory is writable"
ls -l "${DB_PATH}" || true

backup_loop() {
  # Give Remux time to run migrations and finish startup before first snapshot.
  sleep 60
  while :; do
    /usr/local/bin/remux-backup.sh backup || true
    sleep "${BACKUP_INTERVAL_SECONDS}"
  done
}

shutdown() {
  echo "[dockhosting-entrypoint] shutdown requested; creating final backup"
  /usr/local/bin/remux-backup.sh backup || true
  if [ -n "${APP_PID:-}" ]; then
    kill -TERM "${APP_PID}" 2>/dev/null || true
  fi
}

trap shutdown TERM INT

/app/remux-server &
APP_PID=$!

backup_loop &
BACKUP_PID=$!

set +e
wait "${APP_PID}"
STATUS=$?
set -e

kill "${BACKUP_PID}" 2>/dev/null || true
wait "${BACKUP_PID}" 2>/dev/null || true

exit "${STATUS}"
