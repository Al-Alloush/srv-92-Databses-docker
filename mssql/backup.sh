#!/usr/bin/env bash
###############################################################################
# Daily backup for selected databases on the mssql_db container.
#
# - Backs up each DB listed in MSSQL_DATABASES (or all user DBs if empty).
# - Runs BACKUP DATABASE inside the container; the .bak file lands in
#   ./backups/<dbname>/ via the docker-compose bind mount.
# - Gzips each .bak inside the container.
# - Rotates files older than RETENTION_DAYS, per-database subfolder.
#
# Config is sourced from /srv/db/.env (see that file for required keys).
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"
BACKUP_ROOT_HOST="${SCRIPT_DIR}/backups"
BACKUP_ROOT_CONTAINER="/var/opt/mssql/backups"
LOG_FILE="${BACKUP_ROOT_HOST}/backup.log"

if [[ ! -r "$ENV_FILE" ]]; then
    echo "ERROR: cannot read env file: $ENV_FILE" >&2
    exit 2
fi
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${MSSQL_CONTAINER:?MSSQL_CONTAINER missing in .env}"
: "${MSSQL_SA_USER:?MSSQL_SA_USER missing in .env}"
: "${MSSQL_SA_PASSWORD:?MSSQL_SA_PASSWORD missing in .env}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"; }

mkdir -p "$BACKUP_ROOT_HOST"

if ! docker ps --format '{{.Names}}' | grep -qx "$MSSQL_CONTAINER"; then
    log "ERROR: container '$MSSQL_CONTAINER' is not running"
    exit 1
fi

run_sql() {
    docker exec -i "$MSSQL_CONTAINER" /opt/mssql-tools/bin/sqlcmd \
        -S localhost -U "$MSSQL_SA_USER" -P "$MSSQL_SA_PASSWORD" \
        -b -h -1 -W "$@"
}

log "=== MSSQL backup started (retention=${RETENTION_DAYS}d) ==="

# Resolve the list of databases to back up:
#   - If MSSQL_DATABASES is set (non-empty), use that allowlist.
#   - Otherwise, query every online user DB.
read -ra ALLOWLIST <<<"${MSSQL_DATABASES:-}"
if [[ ${#ALLOWLIST[@]} -gt 0 && -n "${ALLOWLIST[0]}" ]]; then
    DATABASES=("${ALLOWLIST[@]}")
    log "Allowlist mode: ${DATABASES[*]}"
else
    mapfile -t DATABASES < <(
        run_sql -Q "SET NOCOUNT ON; SELECT name FROM sys.databases
                    WHERE database_id > 4 AND state_desc = 'ONLINE'
                    ORDER BY name;" \
            | sed '/^$/d;/rows affected/d'
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

    host_dir="${BACKUP_ROOT_HOST}/${db}"
    container_dir="${BACKUP_ROOT_CONTAINER}/${db}"
    mkdir -p "$host_dir"
    docker exec "$MSSQL_CONTAINER" mkdir -p "$container_dir" >/dev/null 2>&1 || true

    bak="${container_dir}/${db}_${TIMESTAMP}.bak"
    log "Backing up: ${db}"
    if run_sql -Q "BACKUP DATABASE [${db}] TO DISK = N'${bak}'
                   WITH INIT, FORMAT, CHECKSUM, NAME = N'${db}-${TIMESTAMP}';" \
            >> "$LOG_FILE" 2>&1; then
        if docker exec "$MSSQL_CONTAINER" gzip -f "$bak"; then
            log "  OK -> ${db}/${db}_${TIMESTAMP}.bak.gz"
        else
            log "  WARN: gzip failed for ${db}"
        fi
    else
        log "  FAIL: ${db}"
        failed=$((failed + 1))
    fi

    # Rotate this DB's folder
    find "$host_dir" -maxdepth 1 -type f \
        \( -name '*.bak.gz' -o -name '*.bak' \) \
        -mtime "+${RETENTION_DAYS}" -print -delete 2>/dev/null \
        | sed "s|^|  rotated: |" >> "$LOG_FILE" || true
done

log "=== MSSQL backup finished (failed=${failed}) ==="
exit "$failed"
