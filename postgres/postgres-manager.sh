#!/usr/bin/env bash

################################################################################
# PostgreSQL Server - Unified Management Script
#
# Databases and their owner roles are declared in databases.conf.
# Credentials are read from /srv/db/.env:
#   POSTGRES_CONTAINER, POSTGRES_USER, POSTGRES_PASSWORD   (admin)
#   PG_PASSWORD_<ROLE_UPPERCASE>                            (per app role)
#
# Features:
#   - Apply databases.conf (create missing roles/databases, idempotent)
#   - Add a new database (+ role, generated password, conf + .env entries)
#   - Reset a specific database (drop + recreate, backup first)
#   - Drop a database permanently
#   - Reset ALL (wipe data volume, recreate everything)
#   - List databases, test connectivity, sync passwords, psql shell
#   - Start / stop / logs
#
# Run without arguments for the interactive menu, or see --help.
################################################################################

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ENV_FILE="${SCRIPT_DIR}/../.env"
CONF_FILE="${SCRIPT_DIR}/databases.conf"
SCRIPTS_DIR="${SCRIPT_DIR}/databases"
BACKUP_ROOT="${SCRIPT_DIR}/backups"
DATA_VOLUME="postgres_data"
EXTERNAL_PORT="5436"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

if [[ ! -r "$ENV_FILE" ]]; then
    echo -e "${RED}Error: cannot read env file: $ENV_FILE${NC}" >&2
    exit 2
fi
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${POSTGRES_CONTAINER:?POSTGRES_CONTAINER missing in .env}"
: "${POSTGRES_USER:?POSTGRES_USER missing in .env}"
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD missing in .env}"
CONTAINER="$POSTGRES_CONTAINER"

################################################################################
# Helper Functions
################################################################################

info()  { echo -e "${BLUE}$*${NC}"; }
ok()    { echo -e "${GREEN}✓ $*${NC}"; }
warn()  { echo -e "${YELLOW}⚠ $*${NC}"; }
err()   { echo -e "${RED}✗ $*${NC}" >&2; }

# psql as admin. Passwords go through the environment (PGPASSWORD without a
# value is inherited from this shell), so they never appear in process args.
function pg() {
    PGPASSWORD="$POSTGRES_PASSWORD" docker exec -i -e PGPASSWORD "$CONTAINER" \
        psql -X -q -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -h localhost "$@"
}

# Single-value query as admin: pgq "<sql>" [database]
function pgq() {
    pg -tA -d "${2:-postgres}" -c "$1" </dev/null
}

function valid_name() {
    [[ "$1" =~ ^[a-z_][a-z0-9_]*$ ]] && [[ ${#1} -le 63 ]]
}

function is_protected_db() {
    [[ "$1" == "postgres" || "$1" == template0 || "$1" == template1 ]]
}

function check_container() {
    if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
        err "Container '$CONTAINER' is not running (start it with: $0 start)"
        return 1
    fi
}

function wait_for_postgres() {
    local timeout=${1:-90}
    echo -n "Waiting for PostgreSQL to accept connections"
    for _ in $(seq 1 "$timeout"); do
        # -h localhost only succeeds once the real server is up (the temporary
        # server used during first-time init listens on the unix socket only).
        if docker exec "$CONTAINER" pg_isready -q -h localhost -U "$POSTGRES_USER" 2>/dev/null; then
            echo ""
            ok "PostgreSQL is ready"
            return 0
        fi
        echo -n "."
        sleep 1
    done
    echo ""
    err "PostgreSQL did not become ready within ${timeout}s"
    return 1
}

function pause() {
    [[ -n "${INTERACTIVE:-}" ]] && read -rp "Press Enter to continue..." _
}

# Env var name holding a role's password: PG_PASSWORD_<ROLE_UPPERCASE>
function pw_var() {
    echo "PG_PASSWORD_${1^^}"
}

function role_password() {
    local var
    var="$(pw_var "$1")"
    echo "${!var:-}"
}

################################################################################
# databases.conf
################################################################################

# Prints "db owner" pairs, one per line (comments/blank lines removed).
function conf_entries() {
    [[ -f "$CONF_FILE" ]] || return 0
    sed -e 's/#.*//' "$CONF_FILE" | awk 'NF >= 2 { print $1, $2 }'
}

function conf_owner() {
    conf_entries | awk -v db="$1" '$1 == db { print $2; exit }'
}

function conf_has_db() {
    [[ -n "$(conf_owner "$1")" ]]
}

function validate_conf() {
    local db owner bad=0
    while read -r -u 3 db owner; do
        if ! valid_name "$db"; then
            err "databases.conf: invalid database name '$db'"; bad=1
        fi
        if [[ "$owner" != "-" ]] && ! valid_name "$owner"; then
            err "databases.conf: invalid owner role '$owner' (database $db)"; bad=1
        fi
        if is_protected_db "$db"; then
            err "databases.conf: '$db' is a system database and cannot be managed"; bad=1
        fi
    done 3< <(conf_entries)
    return $bad
}

################################################################################
# Core operations
################################################################################

function role_exists() {
    [[ "$(pgq "SELECT 1 FROM pg_roles WHERE rolname = '$1'")" == "1" ]]
}

function db_exists() {
    [[ "$(pgq "SELECT 1 FROM pg_database WHERE datname = '$1'")" == "1" ]]
}

# Creates a LOGIN role if it does not exist. Never modifies existing roles.
function ensure_role() {
    local role="$1" pw
    if role_exists "$role"; then
        echo "  Role $role already exists - skipping"
        return 0
    fi
    pw="$(role_password "$role")"
    if [[ -z "$pw" ]]; then
        err "Role '$role' does not exist and $(pw_var "$role") is not set in $ENV_FILE"
        return 1
    fi
    printf "CREATE ROLE \"%s\" LOGIN PASSWORD '%s';\n" "$role" "${pw//\'/\'\'}" \
        | pg -d postgres || return 1
    ok "Created role: $role"
}

# Runs databases/<db>/*.sql in order, as the owner role.
function run_db_scripts() {
    local db="$1" owner="$2" f
    [[ -d "$SCRIPTS_DIR/$db" ]] || return 0
    for f in "$SCRIPTS_DIR/$db"/*.sql; do
        [[ -e "$f" ]] || continue
        echo "  Running $(basename "$f")..."
        {
            [[ "$owner" != "-" ]] && printf 'SET ROLE "%s";\n' "$owner"
            cat "$f"
        } | pg -d "$db" || { err "Script failed: $f"; return 1; }
    done
}

# Creates the database (and its owner role) if missing.
function ensure_database() {
    local db="$1" owner="$2" current_owner expected
    if [[ "$owner" != "-" ]]; then
        ensure_role "$owner" || return 1
    fi

    if db_exists "$db"; then
        expected="$owner"; [[ "$owner" == "-" ]] && expected="$POSTGRES_USER"
        current_owner="$(pgq "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = '$db'")"
        if [[ "$current_owner" != "$expected" ]]; then
            warn "Database $db exists but is owned by '$current_owner' (conf says '$expected') - not changed"
        else
            echo "  Database $db already exists - skipping"
        fi
        return 0
    fi

    if [[ "$owner" == "-" ]]; then
        pgq "CREATE DATABASE \"$db\"" >/dev/null || return 1
    else
        pgq "CREATE DATABASE \"$db\" OWNER \"$owner\"" >/dev/null || return 1
        # Since PG15 only the database owner can create in schema public,
        # and that is pg_database_owner - make it explicit for the app role.
        pgq "ALTER SCHEMA public OWNER TO \"$owner\"" "$db" >/dev/null || return 1
    fi
    ok "Created database: $db (owner: ${owner/#-/$POSTGRES_USER})"
    run_db_scripts "$db" "$owner"
}

# Fails if any role that would need creating has no password in .env.
function check_passwords_available() {
    local db owner missing=0
    while read -r -u 3 db owner; do
        [[ "$owner" == "-" ]] && continue
        if [[ -z "$(role_password "$owner")" ]]; then
            err "$(pw_var "$owner") is not set in $ENV_FILE (needed to create role $owner)"
            missing=1
        fi
    done 3< <(conf_entries | sort -u -k2,2)
    return $missing
}

function backup_db() {
    local db="$1" dir out
    dir="${BACKUP_ROOT}/${db}"
    out="${dir}/${db}_prereset_$(date +%Y%m%d_%H%M%S).dump"
    mkdir -p "$dir"
    info "Backing up $db -> ${out#"$SCRIPT_DIR"/}"
    if pg_dump_db "$db" > "$out"; then
        ok "Backup written ($(du -h "$out" | cut -f1))"
    else
        rm -f "$out"
        err "Backup of $db failed"
        return 1
    fi
}

function pg_dump_db() {
    PGPASSWORD="$POSTGRES_PASSWORD" docker exec -i -e PGPASSWORD "$CONTAINER" \
        pg_dump -U "$POSTGRES_USER" -h localhost -Fc -Z 6 "$1" </dev/null
}

function generate_password() {
    # 32 alphanumeric chars: safe in .env, JDBC URLs and shells without quoting.
    LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32
}

################################################################################
# Commands
################################################################################

function cmd_apply() {
    check_container || return 1
    validate_conf || return 1
    info "Applying databases.conf (creates only what is missing)..."
    local db owner failed=0
    while read -r -u 3 db owner; do
        echo -e "${CYAN}• $db${NC}"
        ensure_database "$db" "$owner" || failed=1
    done 3< <(conf_entries)
    echo ""
    if [[ $failed -eq 0 ]]; then ok "All databases are in place"; else err "Some databases failed - see above"; fi
    return $failed
}

function cmd_add() {
    check_container || return 1
    local db="${1:-}" owner="${2:-}" pw new_pw=""

    if [[ -z "$db" ]]; then
        read -rp "New database name (e.g. myapp_dev_db): " db
    fi
    if ! valid_name "$db" || is_protected_db "$db"; then
        err "Invalid database name '$db' (allowed: lowercase letters, digits, _)"
        return 1
    fi
    if conf_has_db "$db"; then
        err "$db is already in databases.conf (use 'apply' to create it)"
        return 1
    fi
    if db_exists "$db"; then
        err "Database $db already exists on the server but not in databases.conf."
        echo "    Add it manually to databases.conf with its current owner."
        return 1
    fi

    if [[ -z "$owner" ]]; then
        local default_owner="${db%_db}_user"
        if [[ -n "${INTERACTIVE:-}" ]]; then
            read -rp "Owner role [$default_owner] (\"-\" = admin user): " owner
        fi
        owner="${owner:-$default_owner}"
    fi
    if [[ "$owner" != "-" ]] && ! valid_name "$owner"; then
        err "Invalid role name '$owner'"
        return 1
    fi

    # Generate a password only for a brand-new role without one in .env.
    if [[ "$owner" != "-" ]] && ! role_exists "$owner" && [[ -z "$(role_password "$owner")" ]]; then
        new_pw="$(generate_password)"
        printf '\n# PostgreSQL role for %s (added %s)\n%s=%s\n' \
            "$db" "$(date +%F)" "$(pw_var "$owner")" "$new_pw" >> "$ENV_FILE"
        printf -v "$(pw_var "$owner")" '%s' "$new_pw"
        ok "Generated password stored in .env as $(pw_var "$owner")"
    fi

    printf '%-24s %s\n' "$db" "$owner" >> "$CONF_FILE"
    ok "Added $db to databases.conf"

    ensure_database "$db" "$owner" || return 1

    echo ""
    echo -e "${GREEN}Connection details${NC}"
    echo "  Database : $db"
    if [[ "$owner" == "-" ]]; then
        echo "  User     : $POSTGRES_USER (admin)"
    else
        pw="$(role_password "$owner")"
        echo "  User     : $owner"
        if [[ -n "$new_pw" ]]; then
            echo "  Password : $pw"
        else
            echo "  Password : (existing - see $(pw_var "$owner") in .env)"
        fi
    fi
    echo "  Internal : jdbc:postgresql://${CONTAINER}:5432/${db}"
    echo "  External : jdbc:postgresql://localhost:${EXTERNAL_PORT}/${db}"
}

function pick_database() {
    # Interactive picker over databases.conf; sets PICKED_DB.
    local dbs i sel
    mapfile -t dbs < <(conf_entries | awk '{print $1}')
    if [[ ${#dbs[@]} -eq 0 ]]; then
        warn "No databases in databases.conf"
        return 1
    fi
    echo ""
    for i in "${!dbs[@]}"; do
        printf "  ${CYAN}%2d)${NC} %s\n" "$((i+1))" "${dbs[$i]}"
    done
    printf "  ${CYAN}%2d)${NC} Cancel\n" 0
    echo ""
    read -rp "Select database [0-${#dbs[@]}]: " sel
    if ! [[ "$sel" =~ ^[0-9]+$ ]] || [[ "$sel" -lt 1 || "$sel" -gt ${#dbs[@]} ]]; then
        return 1
    fi
    PICKED_DB="${dbs[$((sel-1))]}"
}

function cmd_reset() {
    check_container || return 1
    local db="${1:-}" owner confirm do_backup
    if [[ -z "$db" ]]; then
        pick_database || { echo "Cancelled."; return 0; }
        db="$PICKED_DB"
    fi
    if is_protected_db "$db"; then err "Refusing to reset system database $db"; return 1; fi
    owner="$(conf_owner "$db")"
    if [[ -z "$owner" ]]; then
        err "$db is not in databases.conf - can't know how to recreate it"
        return 1
    fi
    validate_conf || return 1

    echo ""
    warn "This will DELETE all data in '$db' and recreate it empty"
    warn "(plus databases/$db/*.sql if present). Active connections are terminated."
    read -rp "Type the database name to confirm: " confirm
    if [[ "$confirm" != "$db" ]]; then
        echo "Names don't match. Cancelled."
        return 1
    fi

    if db_exists "$db"; then
        read -rp "Create a backup first? [Y/n]: " do_backup
        if [[ ! "$do_backup" =~ ^[Nn] ]]; then
            backup_db "$db" || { err "Aborting reset because the backup failed"; return 1; }
        fi
        info "Dropping $db..."
        pgq "DROP DATABASE \"$db\" WITH (FORCE)" >/dev/null || return 1
        ok "Dropped $db"
    fi

    info "Recreating $db..."
    ensure_database "$db" "$owner" || return 1
    ok "Database $db has been reset"
}

function cmd_drop() {
    check_container || return 1
    local db="${1:-}" owner confirm do_backup drop_role
    if [[ -z "$db" ]]; then
        pick_database || { echo "Cancelled."; return 0; }
        db="$PICKED_DB"
    fi
    if ! valid_name "$db" || is_protected_db "$db"; then err "Refusing to drop '$db'"; return 1; fi
    owner="$(conf_owner "$db")"

    echo ""
    warn "This will PERMANENTLY DROP '$db' and remove it from databases.conf"
    read -rp "Type the database name to confirm: " confirm
    if [[ "$confirm" != "$db" ]]; then
        echo "Names don't match. Cancelled."
        return 1
    fi

    if db_exists "$db"; then
        read -rp "Create a backup first? [Y/n]: " do_backup
        if [[ ! "$do_backup" =~ ^[Nn] ]]; then
            backup_db "$db" || { err "Aborting drop because the backup failed"; return 1; }
        fi
        pgq "DROP DATABASE \"$db\" WITH (FORCE)" >/dev/null || return 1
        ok "Dropped database $db"
    else
        warn "Database $db does not exist on the server"
    fi

    if [[ -n "$owner" ]]; then
        sed -i -E "/^[[:space:]]*${db}[[:space:]]+/d" "$CONF_FILE"
        ok "Removed $db from databases.conf"
    fi

    # Offer to drop the role only if no other configured database uses it.
    if [[ -n "$owner" && "$owner" != "-" ]] && role_exists "$owner" \
        && ! conf_entries | awk -v r="$owner" '$2 == r { found=1 } END { exit !found }'; then
        read -rp "Also drop role '$owner'? [y/N]: " drop_role
        if [[ "$drop_role" =~ ^[Yy] ]]; then
            if pgq "DROP ROLE \"$owner\"" >/dev/null; then
                ok "Dropped role $owner"
                echo "    You can remove $(pw_var "$owner") from .env"
            else
                warn "Role $owner still owns objects elsewhere - kept"
            fi
        fi
    fi
}

function cmd_reset_all() {
    validate_conf || return 1
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  ⚠  WARNING: This will DELETE the whole PostgreSQL server!   ║${NC}"
    echo -e "${YELLOW}║                                                              ║${NC}"
    echo -e "${YELLOW}║  - The data volume '${DATA_VOLUME}' is deleted (ALL databases)  ║${NC}"
    echo -e "${YELLOW}║  - All roles are deleted                                     ║${NC}"
    echo -e "${YELLOW}║  - Databases in databases.conf are recreated EMPTY           ║${NC}"
    echo -e "${YELLOW}║  - Databases NOT in databases.conf are gone for good         ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    info "Checking that every owner role has a password in .env..."
    check_passwords_available || { err "Fix .env first - nothing was changed"; return 1; }
    ok "Passwords available"

    local confirm do_backup
    read -rp "Type RESET ALL to continue: " confirm
    if [[ "$confirm" != "RESET ALL" ]]; then
        echo "Cancelled."
        return 1
    fi

    if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
        read -rp "Run a full backup (./backup.sh) first? [Y/n]: " do_backup
        if [[ ! "$do_backup" =~ ^[Nn] ]]; then
            "$SCRIPT_DIR/backup.sh" || { err "Backup reported failures - aborting"; return 1; }
        fi
    fi

    info "Step 1/5: Stopping services..."
    docker compose down || return 1
    ok "Services stopped"

    info "Step 2/5: Removing data volume..."
    docker volume rm "$DATA_VOLUME" >/dev/null 2>&1 || true
    ok "Volume removed"

    info "Step 3/5: Creating fresh volume and verifying network..."
    docker volume create "$DATA_VOLUME" >/dev/null || return 1
    docker network inspect internal >/dev/null 2>&1 || docker network create internal >/dev/null
    ok "Volume and network ready"

    info "Step 4/5: Starting services..."
    docker compose up -d || return 1
    wait_for_postgres 120 || return 1

    info "Step 5/5: Creating databases..."
    cmd_apply || return 1

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✓ Complete Reset Finished Successfully!                     ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
}

function cmd_list() {
    check_container || return 1
    info "Databases on $CONTAINER:"
    pg -d postgres </dev/null -c "
        SELECT d.datname                                   AS \"Database\",
               pg_get_userbyid(d.datdba)                   AS \"Owner\",
               pg_size_pretty(pg_database_size(d.datname)) AS \"Size\",
               (SELECT count(*) FROM pg_stat_activity a
                 WHERE a.datname = d.datname)              AS \"Connections\"
          FROM pg_database d
         WHERE NOT d.datistemplate
         ORDER BY d.datname;"

    local db owner existing
    existing="$(pgq "SELECT datname FROM pg_database WHERE NOT datistemplate AND datname <> 'postgres'")"
    while read -r -u 3 db owner; do
        grep -qx "$db" <<<"$existing" || warn "In databases.conf but missing on server: $db (run 'apply')"
    done 3< <(conf_entries)
    while read -r -u 3 db; do
        [[ -z "$db" ]] && continue
        conf_has_db "$db" || warn "On server but not in databases.conf (unmanaged): $db"
    done 3<<<"$existing"
}

function cmd_test() {
    check_container || return 1
    info "Testing database connectivity"
    echo ""
    local db owner pw failed=0

    echo -n "Admin ($POSTGRES_USER) ... "
    if [[ "$(pgq 'SELECT 1')" == "1" ]]; then ok "OK"; else err "FAILED"; failed=1; fi

    while read -r -u 3 db owner; do
        if [[ "$owner" == "-" ]]; then
            echo -n "$db as $POSTGRES_USER ... "
            if [[ "$(pgq 'SELECT 1' "$db" 2>/dev/null)" == "1" ]]; then ok "OK"; else err "FAILED"; failed=1; fi
            continue
        fi
        echo -n "$db as $owner ... "
        pw="$(role_password "$owner")"
        if [[ -z "$pw" ]]; then
            warn "SKIPPED ($(pw_var "$owner") not in .env)"
            continue
        fi
        if [[ "$(PGPASSWORD="$pw" docker exec -i -e PGPASSWORD "$CONTAINER" \
                psql -X -tA -U "$owner" -h localhost -d "$db" -c 'SELECT 1' 2>/dev/null </dev/null)" == "1" ]]; then
            ok "OK"
        else
            err "FAILED"; failed=1
        fi
    done 3< <(conf_entries)

    echo ""
    docker compose ps
    return $failed
}

function cmd_sync_passwords() {
    check_container || return 1
    info "Setting role passwords from .env (PG_PASSWORD_<ROLE>)..."
    local owner pw
    while read -r -u 3 owner; do
        [[ "$owner" == "-" ]] && continue
        pw="$(role_password "$owner")"
        if [[ -z "$pw" ]]; then
            warn "$owner: $(pw_var "$owner") not set in .env - skipped"
        elif ! role_exists "$owner"; then
            warn "$owner: role does not exist - run 'apply'"
        else
            printf "ALTER ROLE \"%s\" WITH PASSWORD '%s';\n" "$owner" "${pw//\'/\'\'}" \
                | pg -d postgres && ok "$owner: password updated"
        fi
    done 3< <(conf_entries | awk '{print $2}' | sort -u)
}

function cmd_psql() {
    check_container || return 1
    local db="${1:-postgres}"
    PGPASSWORD="$POSTGRES_PASSWORD" docker exec -it -e PGPASSWORD "$CONTAINER" \
        psql -U "$POSTGRES_USER" -h localhost -d "$db"
}

function cmd_start() {
    info "Starting PostgreSQL services..."
    docker network inspect internal >/dev/null 2>&1 || docker network create internal >/dev/null
    docker volume inspect "$DATA_VOLUME" >/dev/null 2>&1 || docker volume create "$DATA_VOLUME" >/dev/null
    docker compose up -d || return 1
    wait_for_postgres 90 || return 1
    docker compose ps
    echo ""
    echo "  • External: localhost:${EXTERNAL_PORT}"
    echo "  • pgAdmin:  http://localhost:8888"
}

function cmd_stop() {
    info "Stopping PostgreSQL services..."
    docker compose down && ok "Services stopped"
}

function cmd_status() {
    docker compose ps
}

function cmd_logs() {
    info "Showing PostgreSQL logs (Ctrl+C to exit)..."
    docker compose logs -f --tail 200 postgresql_db || true
}

################################################################################
# Interactive Menu
################################################################################

function show_main_menu() {
    INTERACTIVE=1
    local choice
    while true; do
        clear
        echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║          PostgreSQL Server Management Console                ║${NC}"
        echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${BLUE}║${NC}  ${CYAN} 1)${NC} Create/Update databases (apply databases.conf)          ${BLUE}║${NC}"
        echo -e "${BLUE}║${NC}  ${CYAN} 2)${NC} Add new database                                       ${BLUE}║${NC}"
        echo -e "${BLUE}║${NC}  ${CYAN} 3)${NC} Reset specific database                                ${BLUE}║${NC}"
        echo -e "${BLUE}║${NC}  ${CYAN} 4)${NC} Drop database permanently                              ${BLUE}║${NC}"
        echo -e "${BLUE}║${NC}  ${CYAN} 5)${NC} List all databases                                     ${BLUE}║${NC}"
        echo -e "${BLUE}║${NC}  ${CYAN} 6)${NC} Test connectivity                                      ${BLUE}║${NC}"
        echo -e "${BLUE}║${NC}  ${CYAN} 7)${NC} Sync role passwords from .env                          ${BLUE}║${NC}"
        echo -e "${BLUE}║${NC}  ${CYAN} 8)${NC} Open psql shell                                        ${BLUE}║${NC}"
        echo -e "${BLUE}║${NC}  ${CYAN} 9)${NC} Start services                                         ${BLUE}║${NC}"
        echo -e "${BLUE}║${NC}  ${CYAN}10)${NC} Stop services                                          ${BLUE}║${NC}"
        echo -e "${BLUE}║${NC}  ${CYAN}11)${NC} View logs                                              ${BLUE}║${NC}"
        echo -e "${BLUE}║${NC}  ${CYAN}12)${NC} Reset ALL (wipe data volume) + recreate                ${BLUE}║${NC}"
        echo -e "${BLUE}║${NC}  ${CYAN} 0)${NC} Exit                                                   ${BLUE}║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        read -rp "Select option [0-12]: " choice
        echo ""
        case $choice in
            1)  cmd_apply ;;
            2)  cmd_add ;;
            3)  cmd_reset ;;
            4)  cmd_drop ;;
            5)  cmd_list ;;
            6)  cmd_test ;;
            7)  cmd_sync_passwords ;;
            8)  read -rp "Database [postgres]: " db; cmd_psql "${db:-postgres}" ;;
            9)  cmd_start ;;
            10) cmd_stop ;;
            11) cmd_logs ;;
            12) cmd_reset_all ;;
            0)  echo "Goodbye!"; exit 0 ;;
            *)  err "Invalid option"; sleep 1; continue ;;
        esac
        echo ""
        pause
    done
}

function show_help() {
    cat <<EOF
PostgreSQL Manager - Interactive and CLI modes

Usage: $0 [COMMAND] [ARGS]

Without a command: interactive menu

Commands:
  apply                 Create missing roles/databases from databases.conf
  add <db> [owner]      Add a database (owner defaults to <db without _db>_user,
                        "-" = admin). Generates a password into .env if needed.
  reset <db>            Drop and recreate a database (backup offered first)
  drop <db>             Drop a database permanently and remove it from the conf
  reset-all             Wipe the data volume and recreate everything
  list                  List databases with owner, size and connections
  test                  Test connectivity for every configured database
  sync-passwords        Set role passwords from PG_PASSWORD_<ROLE> in .env
  psql [db]             Open a psql shell as admin
  start | stop | status | logs
  help                  Show this help
EOF
}

################################################################################
# Entry Point
################################################################################

cmd="${1:-}"
[[ $# -gt 0 ]] && shift
case "$cmd" in
    "")                         show_main_menu ;;
    apply|--create)             cmd_apply ;;
    add)                        cmd_add "$@" ;;
    reset)                      cmd_reset "$@" ;;
    drop)                       cmd_drop "$@" ;;
    reset-all|--reset-all)      cmd_reset_all ;;
    list|--list)                cmd_list ;;
    test|--test)                cmd_test ;;
    sync-passwords|--sync-passwords) cmd_sync_passwords ;;
    psql)                       cmd_psql "$@" ;;
    start|--start)              cmd_start ;;
    stop|--stop)                cmd_stop ;;
    status)                     cmd_status ;;
    logs)                       cmd_logs ;;
    help|--help|-h)             show_help ;;
    *)                          err "Unknown command: $cmd"; show_help; exit 1 ;;
esac
