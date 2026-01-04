#!/bin/bash

################################################################################
# MSSQL Server - Unified Management Script
# 
# Features:
#   - Reset entire MSSQL server (containers, volumes, images)
#   - Create/update databases (run init script)
#   - Reset specific database
#   - List all databases
#   - Test connectivity
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Connection settings
SA_PASSWORD='8u5rp3tL8p!Bkb432u!L7Q9aB7(CCy22j8YjS6L#msPff!ccHOaS3FnsmLkt2fKwDs58oP3'
CONTAINER="mssql_db"
VOLUMES="mssql_data mssql_log mssql_backup"

################################################################################
# Helper Functions
################################################################################

function run_sql() {
    docker exec -i $CONTAINER /opt/mssql-tools/bin/sqlcmd \
        -S localhost -U sa -P "$SA_PASSWORD" \
        -Q "$1" 2>/dev/null
}

function check_container() {
    if ! docker ps --format "{{.Names}}" | grep -q "^${CONTAINER}$"; then
        echo -e "${RED}Error: Container '$CONTAINER' is not running${NC}"
        echo "Start services first with option 1 or 2"
        return 1
    fi
    return 0
}

function wait_for_mssql() {
    local wait_time=${1:-60}
    echo "Waiting ${wait_time} seconds for MSSQL to initialize..."
    for i in $(seq $wait_time -1 1); do
        printf "\rTime remaining: %2d seconds" $i
        sleep 1
    done
    echo ""
}

################################################################################
# Main Menu
################################################################################

function show_main_menu() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          MSSQL Server Management Console                     ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║                                                              ║${NC}"
    echo -e "${BLUE}║${NC}  ${CYAN}1)${NC} Reset ALL (containers, volumes, images) + recreate      ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${CYAN}2)${NC} Create/Update databases (run init script)               ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${CYAN}3)${NC} Reset specific database                                 ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${CYAN}4)${NC} List all databases                                      ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${CYAN}5)${NC} Test connectivity                                       ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${CYAN}6)${NC} Start services                                          ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${CYAN}7)${NC} Stop services                                           ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${CYAN}8)${NC} View logs                                               ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${CYAN}9)${NC} Sync passwords from init script                         ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${CYAN}0)${NC} Exit                                                    ${BLUE}║${NC}"
    echo -e "${BLUE}║                                                              ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    read -p "Select option [0-9]: " choice
    
    case $choice in
        1) reset_all ;;
        2) create_databases ;;
        3) reset_specific_database ;;
        4) list_databases ;;
        5) test_connectivity ;;
        6) start_services ;;
        7) stop_services ;;
        8) view_logs ;;
        9) sync_passwords ;;
        0) echo "Goodbye!"; exit 0 ;;
        *) echo -e "${RED}Invalid option${NC}"; sleep 1; show_main_menu ;;
    esac
}

################################################################################
# Option 1: Reset ALL
################################################################################

function reset_all() {
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  ⚠  WARNING: This will DELETE everything!                    ║${NC}"
    echo -e "${YELLOW}║                                                              ║${NC}"
    echo -e "${YELLOW}║  - All containers will be removed                            ║${NC}"
    echo -e "${YELLOW}║  - All volumes (DATA) will be deleted                        ║${NC}"
    echo -e "${YELLOW}║  - All databases will be recreated from scratch              ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled."
        sleep 1
        show_main_menu
        return
    fi

    echo ""
    echo -e "${BLUE}Step 1/7: Stopping services...${NC}"
    docker compose down -v 2>/dev/null || true
    echo -e "${GREEN}✓ Services stopped${NC}"

    echo ""
    echo -e "${BLUE}Step 2/7: Removing containers...${NC}"
    CONTAINERS=$(docker ps -a --filter "name=mssql" --format "{{.Names}}" 2>/dev/null)
    if [ -n "$CONTAINERS" ]; then
        docker rm -f $CONTAINERS 2>/dev/null || true
    fi
    echo -e "${GREEN}✓ Containers removed${NC}"

    echo ""
    echo -e "${BLUE}Step 3/7: Removing volumes...${NC}"
    for vol in $VOLUMES; do
        docker volume rm "$vol" 2>/dev/null || true
    done
    docker volume rm mssql_cloudbeaver_data 2>/dev/null || true
    echo -e "${GREEN}✓ Volumes removed${NC}"

    echo ""
    echo -e "${BLUE}Step 4/7: Removing images...${NC}"
    IMAGES=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "azure-sql-edge|adminer|cloudbeaver" || true)
    if [ -n "$IMAGES" ]; then
        echo "$IMAGES" | xargs docker rmi -f 2>/dev/null || true
    fi
    echo -e "${GREEN}✓ Images removed${NC}"

    echo ""
    echo -e "${BLUE}Step 5/7: Verifying network...${NC}"
    if ! docker network ls | grep -q "internal"; then
        docker network create internal
    fi
    echo -e "${GREEN}✓ Network ready${NC}"

    echo ""
    echo -e "${BLUE}Step 6/7: Creating fresh volumes...${NC}"
    for vol in $VOLUMES; do
        docker volume create "$vol" >/dev/null
    done
    echo -e "${GREEN}✓ Volumes created${NC}"

    echo ""
    echo -e "${BLUE}Step 7/7: Starting services...${NC}"
    docker compose up -d
    echo -e "${GREEN}✓ Services started${NC}"

    wait_for_mssql 60

    # Run init scripts
    echo ""
    echo -e "${BLUE}Initializing databases...${NC}"
    docker exec -i $CONTAINER /opt/mssql-tools/bin/sqlcmd \
        -S localhost -U sa -P "$SA_PASSWORD" \
        -i /docker-entrypoint-initdb.d/01-create-databases.sql || true
    docker exec -i $CONTAINER /opt/mssql-tools/bin/sqlcmd \
        -S localhost -U sa -P "$SA_PASSWORD" \
        -i /docker-entrypoint-initdb.d/02-configure-server.sql || true
    echo -e "${GREEN}✓ Databases initialized${NC}"

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✓ Complete Reset Finished Successfully!                     ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    
    echo ""
    read -p "Press Enter to continue..."
    show_main_menu
}

################################################################################
# Option 2: Create/Update Databases
################################################################################

function create_databases() {
    echo ""
    echo -e "${BLUE}Creating/Updating databases...${NC}"
    echo -e "${CYAN}This is safe - it only creates databases that don't exist${NC}"
    echo ""
    
    if ! check_container; then
        read -p "Press Enter to continue..."
        show_main_menu
        return
    fi

    docker exec -i $CONTAINER /opt/mssql-tools/bin/sqlcmd \
        -S localhost -U sa -P "$SA_PASSWORD" \
        -i /docker-entrypoint-initdb.d/01-create-databases.sql

    echo ""
    echo -e "${GREEN}✓ Database initialization complete${NC}"
    
    echo ""
    read -p "Press Enter to continue..."
    show_main_menu
}

################################################################################
# Option 3: Reset Specific Database
################################################################################

function reset_specific_database() {
    echo ""
    
    if ! check_container; then
        read -p "Press Enter to continue..."
        show_main_menu
        return
    fi

    echo -e "${BLUE}Fetching database list...${NC}"
    echo ""

    # Get list of user databases
    DATABASES=$(docker exec -i $CONTAINER /opt/mssql-tools/bin/sqlcmd \
        -S localhost -U sa -P "$SA_PASSWORD" \
        -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE name NOT IN ('master','tempdb','model','msdb') ORDER BY name" \
        -h-1 -W 2>/dev/null | grep -v "^$" | sed 's/[[:space:]]*$//')

    if [ -z "$DATABASES" ]; then
        echo -e "${YELLOW}No user databases found${NC}"
        read -p "Press Enter to continue..."
        show_main_menu
        return
    fi

    # Convert to array
    IFS=$'\n' read -rd '' -a DB_ARRAY <<< "$DATABASES" || true

    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Select database to reset:                                   ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
    
    for i in "${!DB_ARRAY[@]}"; do
        printf "${BLUE}║${NC}  ${CYAN}%2d)${NC} %-55s ${BLUE}║${NC}\n" "$((i+1))" "${DB_ARRAY[$i]}"
    done
    
    echo -e "${BLUE}║${NC}  ${CYAN} 0)${NC} Cancel - Back to main menu                             ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    read -p "Select database number [0-${#DB_ARRAY[@]}]: " selection

    if [ "$selection" == "0" ] || [ -z "$selection" ]; then
        show_main_menu
        return
    fi

    # Validate selection
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#DB_ARRAY[@]} ]; then
        echo -e "${RED}Invalid selection${NC}"
        sleep 1
        reset_specific_database
        return
    fi

    DB_NAME="${DB_ARRAY[$((selection-1))]}"
    
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  ⚠  WARNING: This will DELETE all data in:                   ║${NC}"
    printf "${YELLOW}║${NC}     %-56s ${YELLOW}║${NC}\n" "$DB_NAME"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    read -p "Type the database name to confirm: " confirm

    if [ "$confirm" != "$DB_NAME" ]; then
        echo -e "${RED}Names don't match. Cancelled.${NC}"
        sleep 2
        show_main_menu
        return
    fi

    echo ""
    echo -e "${BLUE}Dropping database: $DB_NAME${NC}"
    
    run_sql "
    USE master;
    IF EXISTS (SELECT * FROM sys.databases WHERE name = '$DB_NAME')
    BEGIN
        ALTER DATABASE [$DB_NAME] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
        DROP DATABASE [$DB_NAME];
        PRINT 'Database $DB_NAME dropped';
    END
    "

    echo -e "${GREEN}✓ Database dropped${NC}"
    echo ""
    echo -e "${BLUE}Recreating database...${NC}"

    # Run init script to recreate
    docker exec -i $CONTAINER /opt/mssql-tools/bin/sqlcmd \
        -S localhost -U sa -P "$SA_PASSWORD" \
        -i /docker-entrypoint-initdb.d/01-create-databases.sql

    echo ""
    echo -e "${GREEN}✓ Database $DB_NAME has been reset${NC}"
    
    echo ""
    read -p "Press Enter to continue..."
    show_main_menu
}

################################################################################
# Option 4: List Databases
################################################################################

function list_databases() {
    echo ""
    
    if ! check_container; then
        read -p "Press Enter to continue..."
        show_main_menu
        return
    fi

    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Database List                                               ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    docker exec -i $CONTAINER /opt/mssql-tools/bin/sqlcmd \
        -S localhost -U sa -P "$SA_PASSWORD" \
        -Q "
        SELECT 
            name AS [Database Name],
            CONVERT(VARCHAR(20), create_date, 120) AS [Created],
            state_desc AS [State]
        FROM sys.databases 
        WHERE name NOT IN ('master','tempdb','model','msdb') 
        ORDER BY name
        "

    echo ""
    read -p "Press Enter to continue..."
    show_main_menu
}

################################################################################
# Option 5: Test Connectivity
################################################################################

function test_connectivity() {
    echo ""
    
    if ! check_container; then
        read -p "Press Enter to continue..."
        show_main_menu
        return
    fi

    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Testing Database Connectivity                               ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Test 1: SA connection
    echo -n "Test 1: SA (admin) connection... "
    if run_sql "SELECT 1" | grep -q "1"; then
        echo -e "${GREEN}✓ OK${NC}"
    else
        echo -e "${RED}✗ FAILED${NC}"
    fi

    # Test 2: List databases
    echo -n "Test 2: Listing databases... "
    DB_COUNT=$(run_sql "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.databases WHERE name NOT IN ('master','tempdb','model','msdb')" | grep -E "^[0-9]+$" | head -1)
    if [ -n "$DB_COUNT" ] && [ "$DB_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✓ Found $DB_COUNT database(s)${NC}"
    else
        echo -e "${YELLOW}⚠ No user databases found${NC}"
    fi

    # Test 3: Application user (server_driven_ui_dev_user)
    echo -n "Test 3: server_driven_ui_dev_user... "
    if docker exec -i $CONTAINER /opt/mssql-tools/bin/sqlcmd \
        -S localhost -U server_driven_ui_dev_user \
        -P 't7nN8CNtU92H2R5Uj794x6a6dK' \
        -d server_driven_ui_dev_db \
        -Q "SELECT 1" 2>/dev/null | grep -q "1"; then
        echo -e "${GREEN}✓ OK${NC}"
    else
        echo -e "${RED}✗ FAILED${NC}"
    fi

    # Test 4: imeterrecorder_dev_admin
    echo -n "Test 4: imeterrecorder_dev_admin... "
    if docker exec -i $CONTAINER /opt/mssql-tools/bin/sqlcmd \
        -S localhost -U imeterrecorder_dev_admin \
        -P 'i55374C2Lzev*SAk2!i25PG939' \
        -d imeterrecorder_dev_db \
        -Q "SELECT 1" 2>/dev/null | grep -q "1"; then
        echo -e "${GREEN}✓ OK${NC}"
    else
        echo -e "${RED}✗ FAILED${NC}"
    fi

    # Test 5: Readonly user
    echo -n "Test 5: readonly_user... "
    if docker exec -i $CONTAINER /opt/mssql-tools/bin/sqlcmd \
        -S localhost -U readonly_user \
        -P 'sddg23dfAdsd!d8GGh#2j8YjS6L#msPnsmLkt2fKwDs58oP3' \
        -d server_driven_ui_dev_db \
        -Q "SELECT 1" 2>/dev/null | grep -q "1"; then
        echo -e "${GREEN}✓ OK${NC}"
    else
        echo -e "${YELLOW}⚠ FAILED (non-critical)${NC}"
    fi

    echo ""
    echo -e "${BLUE}Container Status:${NC}"
    docker compose ps

    echo ""
    read -p "Press Enter to continue..."
    show_main_menu
}

################################################################################
# Option 6: Start Services
################################################################################

function start_services() {
    echo ""
    echo -e "${BLUE}Starting MSSQL services...${NC}"
    docker compose up -d
    echo -e "${GREEN}✓ Services started${NC}"
    echo ""
    docker compose ps
    echo ""
    echo "Management Tools:"
    echo "  • Adminer: http://localhost:8889"
    echo "  • CloudBeaver: http://localhost:8890"
    echo ""
    read -p "Press Enter to continue..."
    show_main_menu
}

################################################################################
# Option 7: Stop Services
################################################################################

function stop_services() {
    echo ""
    echo -e "${BLUE}Stopping MSSQL services...${NC}"
    docker compose down
    echo -e "${GREEN}✓ Services stopped${NC}"
    echo ""
    read -p "Press Enter to continue..."
    show_main_menu
}

################################################################################
# Option 8: View Logs
################################################################################

function view_logs() {
    echo ""
    echo -e "${BLUE}Showing MSSQL logs (Ctrl+C to exit)...${NC}"
    echo ""
    docker compose logs -f mssql_db || true
    show_main_menu
}

################################################################################
# Option 9: Sync Passwords
################################################################################

function sync_passwords() {
    echo ""
    
    if ! check_container; then
        read -p "Press Enter to continue..."
        show_main_menu
        return
    fi

    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Syncing Passwords from Init Script                          ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}This will update all LOGIN passwords to match 01-create-databases.sql${NC}"
    echo ""

    docker exec -i $CONTAINER /opt/mssql-tools/bin/sqlcmd \
        -S localhost -U sa -P "$SA_PASSWORD" \
        -Q "
        -- Update server_driven_ui passwords
        IF EXISTS (SELECT * FROM sys.server_principals WHERE name = 'server_driven_ui_dev_user')
            ALTER LOGIN [server_driven_ui_dev_user] WITH PASSWORD = 't7nN8CNtU92H2R5Uj794x6a6dK';
        
        IF EXISTS (SELECT * FROM sys.server_principals WHERE name = 'server_driven_ui_test_user')
            ALTER LOGIN [server_driven_ui_test_user] WITH PASSWORD = 't7nN8CNtU92H2R5Uj794x6a6dK';
        
        IF EXISTS (SELECT * FROM sys.server_principals WHERE name = 'server_driven_ui_db_user')
            ALTER LOGIN [server_driven_ui_db_user] WITH PASSWORD = '6VKYKouG9V87C8fe48*k979b25AFR%%8Gpk6TbPe!GN6jQb4meg22c';
        
        -- Update imeterrecorder passwords
        IF EXISTS (SELECT * FROM sys.server_principals WHERE name = 'imeterrecorder_dev_admin')
            ALTER LOGIN [imeterrecorder_dev_admin] WITH PASSWORD = 'i55374C2Lzev*SAk2!i25PG939';
        
        IF EXISTS (SELECT * FROM sys.server_principals WHERE name = 'imeterrecorder_test_admin')
            ALTER LOGIN [imeterrecorder_test_admin] WITH PASSWORD = 'i55374C2Lzev*SAk2!i25PG939';
        
        IF EXISTS (SELECT * FROM sys.server_principals WHERE name = 'imeterrecorder_user')
            ALTER LOGIN [imeterrecorder_user] WITH PASSWORD = 'z8e@6La!7CU3u33ptHKwoyA9u8sk7!2mQsW6*4zkhqKmX*#7e69%oX';
        
        -- Update readonly password
        IF EXISTS (SELECT * FROM sys.server_principals WHERE name = 'readonly_user')
            ALTER LOGIN [readonly_user] WITH PASSWORD = 'sddg23dfAdsd!d8GGh#2j8YjS6L#msPnsmLkt2fKwDs58oP3';
        
        PRINT 'All passwords synchronized!';
        "

    echo ""
    echo -e "${GREEN}✓ Passwords updated successfully${NC}"
    
    echo ""
    read -p "Press Enter to continue..."
    show_main_menu
}

################################################################################
# Entry Point
################################################################################

# Check if running with argument
case "${1:-}" in
    --reset-all)
        reset_all
        ;;
    --create)
        check_container && create_databases
        ;;
    --sync-passwords)
        check_container && sync_passwords
        ;;
    --list)
        check_container && list_databases
        ;;
    --test)
        check_container && test_connectivity
        ;;
    --start)
        start_services
        ;;
    --stop)
        stop_services
        ;;
    --help|-h)
        echo "MSSQL Manager - Interactive and CLI modes"
        echo ""
        echo "Usage: $0 [OPTION]"
        echo ""
        echo "Without options: Interactive menu"
        echo ""
        echo "Options:"
        echo "  --reset-all       Reset everything (containers, volumes, data)"
        echo "  --create          Create/update databases from init script"
        echo "  --sync-passwords  Update all login passwords"
        echo "  --list            List all databases"
        echo "  --test            Test connectivity"
        echo "  --start           Start services"
        echo "  --stop            Stop services"
        echo "  --help            Show this help"
        ;;
    "")
        show_main_menu
        ;;
    *)
        echo "Unknown option: $1"
        echo "Use --help for usage"
        exit 1
        ;;
esac