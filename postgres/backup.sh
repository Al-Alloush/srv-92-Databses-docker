#!/usr/bin/env bash
###############################################################################
# Daily backup for selected databases on the postgresql_db container.
#
# - Backs up each DB listed in POSTGRES_DATABASES (or all non-template DBs
#   except 'postgres' if empty).
# - Globals (roles, tablespaces) go to ./backups/_globals/.
# - Each DB dump goes to ./backups/<dbname>/.
# - Streams output over stdout to host so no compose change is needed.
# - Rotates files older than RETENTION_DAYS, per subfolder.
#
# Config is sourced from /srv/db/.env (see that file for required keys).
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"
BACKUP_ROOT="${SCRIPT_DIR}/backups"
GLOBALS_DIR="${BACKUP_ROOT}/_globals"
LOG_FILE="${BACKUP_ROOT}/backup.log"

if [[ ! -r "$ENV_FILE" ]]; then
    echo "ERROR: cannot read env file: $ENV_FILE" >&2
    exit 2
fi
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${POSTGRES_CONTAINER:?POSTGRES_CONTAINER missing in .env}"
: "${POSTGRES_USER:?POSTGRES_USER missing in .env}"
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD missing in .env}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"; }

mkdir -p "$BACKUP_ROOT" "$GLOBALS_DIR"

if ! docker ps --format '{{.Names}}' | grep -qx "$POSTGRES_CONTAINER"; then
    log "ERROR: container '$POSTGRES_CONTAINER' is not running"
    exit 1
fi

pg_exec() {
    docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" -i "$POSTGRES_CONTAINER" "$@"
}

log "=== Postgres backup started (retention=${RETENTION_DAYS}d) ==="

# 1) Globals (roles, tablespaces) — required for full disaster recovery.
globals_file="${GLOBALS_DIR}/_globals_${TIMESTAMP}.sql.gz"
log "Dumping globals -> _globals/$(basename "$globals_file")"
if pg_exec pg_dumpall -U "$POSTGRES_USER" -h localhost --globals-only \
        | gzip > "$globals_file"; then
    log "  OK"
else
    log "  FAIL: globals"
    rm -f "$globals_file"
fi

# Rotate globals
find "$GLOBALS_DIR" -maxdepth 1 -type f -name '*.sql.gz' \
    -mtime "+${RETENTION_DAYS}" -print -delete 2>/dev/null \
    | sed 's|^|  rotated: |' >> "$LOG_FILE" || true

# 2) Resolve the list of databases:
#   - If POSTGRES_DATABASES is set (non-empty), use that allowlist.
#   - Otherwise, list every non-template DB except 'postgres'.
read -ra ALLOWLIST <<<"${POSTGRES_DATABASES:-}"
if [[ ${#ALLOWLIST[@]} -gt 0 && -n "${ALLOWLIST[0]}" ]]; then
    DATABASES=("${ALLOWLIST[@]}")
    log "Allowlist mode: ${DATABASES[*]}"
else
    mapfile -t DATABASES < <(
        pg_exec psql -U "$POSTGRES_USER" -h localhost -d postgres -tAc \
            "SELECT datname FROM pg_database
             WHERE datistemplate = false AND datname <> 'postgres'
             ORDER BY datname;"
    )
    log "Auto-discovery mode: ${DATABASES[*]:-(none)}"
fi

if [[ ${#DATABASES[@]} -eq 0 ]]; then
    log "WARN: no databases selected"
fi

failed=0
for db in "${DATABASES[@]}"; do
    db="${db//[$'\r\n\t ']}"
    [[ -z "$db" ]] && continue

    db_dir="${BACKUP_ROOT}/${db}"
    mkdir -p "$db_dir"

    out="${db_dir}/${db}_${TIMESTAMP}.dump"
    log "Backing up: ${db}"
    if pg_exec pg_dump -U "$POSTGRES_USER" -h localhost -Fc -Z 6 "$db" > "$out"; then
        log "  OK -> ${db}/$(basename "$out") ($(du -h "$out" | cut -f1))"
    else
        log "  FAIL: ${db}"
        rm -f "$out"
        failed=$((failed + 1))
    fi

    # Rotate this DB's folder
    find "$db_dir" -maxdepth 1 -type f -name '*.dump' \
        -mtime "+${RETENTION_DAYS}" -print -delete 2>/dev/null \
        | sed 's|^|  rotated: |' >> "$LOG_FILE" || true
done

log "=== Postgres backup finished (failed=${failed}) ==="
exit "$failed"
