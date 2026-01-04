#!/bin/bash

################################################################################
# MSSQL Server - Complete Reset and Test Script
# 
# This script will:
# 1. Stop all MSSQL containers
# 2. Remove all containers, volumes, and images
# 3. Clean up networks if needed
# 4. Recreate fresh volumes
# 5. Start MSSQL services
# 6. Wait for initialization
# 7. Test database creation and connectivity
################################################################################

set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Step 1: Stop all running MSSQL services
################################################################################
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Step 1: Stopping all MSSQL services...${NC}"
echo -e "${BLUE}========================================${NC}"

if docker compose ps | grep -q "mssql"; then
    docker compose down -v
    echo -e "${GREEN}✓ Services stopped${NC}"
else
    echo -e "${YELLOW}⚠ No running services found${NC}"
fi

################################################################################
# Step 2: Remove all MSSQL containers
################################################################################
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Step 2: Removing MSSQL containers...${NC}"
echo -e "${BLUE}========================================${NC}"

CONTAINERS=$(docker ps -a --filter "name=mssql" --format "{{.Names}}")
if [ -n "$CONTAINERS" ]; then
    echo "Found containers: $CONTAINERS"
    docker rm -f $CONTAINERS 2>/dev/null || true
    echo -e "${GREEN}✓ Containers removed${NC}"
else
    echo -e "${YELLOW}⚠ No containers to remove${NC}"
fi

################################################################################
# Step 3: Remove MSSQL Docker volumes
################################################################################
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Step 3: Removing Docker volumes...${NC}"
echo -e "${BLUE}========================================${NC}"

VOLUMES="mssql_data mssql_log mssql_backup"
for vol in $VOLUMES; do
    if docker volume ls | grep -q "$vol"; then
        echo "Removing volume: $vol"
        docker volume rm "$vol" 2>/dev/null || true
        echo -e "${GREEN}✓ Volume $vol removed${NC}"
    else
        echo -e "${YELLOW}⚠ Volume $vol not found${NC}"
    fi
done

# Remove cloudbeaver data volume
if docker volume ls | grep -q "mssql_cloudbeaver_data"; then
    docker volume rm mssql_cloudbeaver_data 2>/dev/null || true
    echo -e "${GREEN}✓ CloudBeaver data removed${NC}"
fi

################################################################################
# Step 4: Remove MSSQL Docker images
################################################################################
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Step 4: Removing Docker images...${NC}"
echo -e "${BLUE}========================================${NC}"

IMAGES=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "azure-sql-edge|adminer|cloudbeaver")
if [ -n "$IMAGES" ]; then
    echo "Found images:"
    echo "$IMAGES"
    echo "$IMAGES" | xargs docker rmi -f 2>/dev/null || true
    echo -e "${GREEN}✓ Images removed${NC}"
else
    echo -e "${YELLOW}⚠ No MSSQL-related images found${NC}"
fi

################################################################################
# Step 5: Verify network exists
################################################################################
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Step 5: Verifying Docker network...${NC}"
echo -e "${BLUE}========================================${NC}"

if docker network ls | grep -q "internal"; then
    echo -e "${GREEN}✓ Network 'internal' exists${NC}"
else
    echo -e "${YELLOW}⚠ Creating 'internal' network...${NC}"
    docker network create internal
    echo -e "${GREEN}✓ Network created${NC}"
fi

################################################################################
# Step 6: Create fresh volumes
################################################################################
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Step 6: Creating fresh volumes...${NC}"
echo -e "${BLUE}========================================${NC}"

for vol in $VOLUMES; do
    echo "Creating volume: $vol"
    docker volume create "$vol"
    echo -e "${GREEN}✓ Volume $vol created${NC}"
done

################################################################################
# Step 7: Start MSSQL services
################################################################################
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Step 7: Starting MSSQL services...${NC}"
echo -e "${BLUE}========================================${NC}"

docker compose up -d

echo -e "${GREEN}✓ Services started${NC}"
echo ""
echo "Services started:"
docker compose ps

################################################################################
# Step 8: Wait for MSSQL to be ready
################################################################################
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Step 8: Waiting for MSSQL startup...${NC}"
echo -e "${BLUE}========================================${NC}"

echo "Waiting 60 seconds for MSSQL to initialize..."
for i in {60..1}; do
    printf "\rTime remaining: %2d seconds" $i
    sleep 1
done
echo ""

################################################################################
# Step 9: Test database connectivity
################################################################################
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Step 9: Testing database connectivity...${NC}"
echo -e "${BLUE}========================================${NC}"

# Test 1: SA user connection
echo ""
echo "Test 1: Testing SA (admin) connection..."
if docker exec mssql_db /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P '8u5rp3tL8p!Bkb432u!L7Q9aB7(CCy22j8YjS6L#msPff!ccHOaS3FnsmLkt2fKwDs58oP3' -Q "SELECT 'OK' as Status" -h-1 2>/dev/null | grep -q "OK"; then
    echo -e "${GREEN}✓ SA connection successful${NC}"
else
    echo -e "${RED}✗ SA connection failed${NC}"
    exit 1
fi

# Test 2: Check if database exists
echo ""
echo "Test 2: Checking if server_driven_ui_dev_db exists..."
DB_EXISTS=$(docker exec mssql_db /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P '8u5rp3tL8p!Bkb432u!L7Q9aB7(CCy22j8YjS6L#msPff!ccHOaS3FnsmLkt2fKwDs58oP3' -Q "SELECT name FROM sys.databases WHERE name = 'server_driven_ui_dev_db'" -h-1 2>/dev/null | grep -c "server_driven_ui_dev_db" || echo "0")

if [ "$DB_EXISTS" -gt 0 ]; then
    echo -e "${GREEN}✓ Database server_driven_ui_dev_db exists${NC}"
else
    echo -e "${RED}✗ Database server_driven_ui_dev_db NOT found${NC}"
    echo ""
    echo -e "${YELLOW}Running initialization script...${NC}"
    docker exec mssql_db /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P '8u5rp3tL8p!Bkb432u!L7Q9aB7(CCy22j8YjS6L#msPff!ccHOaS3FnsmLkt2fKwDs58oP3' -i /docker-entrypoint-initdb.d/01-create-databases.sql
    docker exec mssql_db /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P '8u5rp3tL8p!Bkb432u!L7Q9aB7(CCy22j8YjS6L#msPff!ccHOaS3FnsmLkt2fKwDs58oP3' -i /docker-entrypoint-initdb.d/02-configure-server.sql
    echo -e "${GREEN}✓ Database initialized${NC}"
fi

# Test 3: Check if application user exists
echo ""
echo "Test 3: Checking if application user exists..."
if docker exec mssql_db /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P '8u5rp3tL8p!Bkb432u!L7Q9aB7(CCy22j8YjS6L#msPff!ccHOaS3FnsmLkt2fKwDs58oP3' -Q "SELECT name FROM sys.server_principals WHERE name = 'server_driven_ui_dev_user'" -h-1 2>/dev/null | grep -q "server_driven_ui_dev_user"; then
    echo -e "${GREEN}✓ User server_driven_ui_dev_user exists${NC}"
else
    echo -e "${RED}✗ User server_driven_ui_dev_user NOT found${NC}"
    exit 1
fi

# Test 4: Test application user connection
echo ""
echo "Test 4: Testing application user connection..."
if docker exec mssql_db /opt/mssql-tools/bin/sqlcmd -S localhost -U server_driven_ui_dev_user -P '8fd2SSSvf3fp3tL8p!Bkdd!d8GGh#2j8YjS6L#msPnsmLkt2fKwDs58oP3' -d server_driven_ui_dev_db -Q "SELECT 'OK' as Status" -h-1 2>/dev/null | grep -q "OK"; then
    echo -e "${GREEN}✓ Application user connection successful${NC}"
else
    echo -e "${RED}✗ Application user connection failed${NC}"
    exit 1
fi

# Test 5: Verify database permissions
echo ""
echo "Test 5: Verifying database permissions..."
PERMISSION_TEST=$(docker exec mssql_db /opt/mssql-tools/bin/sqlcmd -S localhost -U server_driven_ui_dev_user -P '8fd2SSSvf3fp3tL8p!Bkdd!d8GGh#2j8YjS6L#msPnsmLkt2fKwDs58oP3' -d server_driven_ui_dev_db -Q "SELECT IS_MEMBER('db_owner') as IsOwner" -h-1 2>/dev/null | grep -c "1" || echo "0")

if [ "$PERMISSION_TEST" -gt 0 ]; then
    echo -e "${GREEN}✓ User has db_owner permissions${NC}"
else
    echo -e "${RED}✗ User does NOT have proper permissions${NC}"
    exit 1
fi

# Test 6: Test readonly user
echo ""
echo "Test 6: Testing readonly user..."
if docker exec mssql_db /opt/mssql-tools/bin/sqlcmd -S localhost -U readonly_user -P 'sddg23dfAdsd!d8GGh#2j8YjS6L#msPnsmLkt2fKwDs58oP3' -d server_driven_ui_dev_db -Q "SELECT 'OK' as Status" -h-1 2>/dev/null | grep -q "OK"; then
    echo -e "${GREEN}✓ Readonly user connection successful${NC}"
else
    echo -e "${YELLOW}⚠ Readonly user connection failed (non-critical)${NC}"
fi

################################################################################
# Step 10: Display connection information
################################################################################
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Step 10: Connection Information${NC}"
echo -e "${BLUE}========================================${NC}"

echo ""
echo -e "${GREEN}Database Details:${NC}"
docker exec mssql_db /opt/mssql-tools/bin/sqlcmd -S localhost -U server_driven_ui_dev_user -P '8fd2SSSvf3fp3tL8p!Bkdd!d8GGh#2j8YjS6L#msPnsmLkt2fKwDs58oP3' -d server_driven_ui_dev_db -Q "
SELECT 
    DB_NAME() as DatabaseName,
    USER_NAME() as CurrentUser,
    GETDATE() as Timestamp
"

echo ""
echo -e "${GREEN}Container Status:${NC}"
docker compose ps

################################################################################
# Final Summary
################################################################################
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Reset and Test Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "MSSQL Server Information:"
echo "  • Database: server_driven_ui_dev_db"
echo "  • User: server_driven_ui_dev_user"
echo "  • Password: 8fd2SSSvf3fp3tL8p!Bkdd!d8GGh#2j8YjS6L#msPnsmLkt2fKwDs58oP3"
echo "  • Internal Host: mssql_db:1433"
echo "  • External Host: localhost:1434"
echo ""
echo "Management Tools:"
echo "  • Adminer: http://localhost:8889"
echo "  • CloudBeaver: http://localhost:8890"
echo ""
echo -e "${YELLOW}Spring Boot Connection:${NC}"
echo "  jdbc:sqlserver://mssql_db:1433;databaseName=server_driven_ui_dev_db;encrypt=false;trustServerCertificate=true"
echo ""