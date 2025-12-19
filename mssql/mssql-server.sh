#!/bin/bash

# MSSQL Server Management Script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

function show_help() {
    echo "MSSQL Server Management Script"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  start     - Start MSSQL server and management tools"
    echo "  stop      - Stop all MSSQL services"
    echo "  restart   - Restart all services"
    echo "  logs      - Show MSSQL server logs"
    echo "  status    - Show status of all services"
    echo "  backup    - Create database backup"
    echo "  connect   - Connect to MSSQL via command line"
    echo "  test      - Test database connectivity"
    echo "  help      - Show this help message"
}

function start_services() {
    echo "🚀 Starting MSSQL Server and management tools..."
    docker compose up -d
    echo "✅ Services started!"
    echo "📊 Adminer (Web Interface): http://localhost:8889"
    echo "🔧 CloudBeaver (Advanced UI): http://localhost:8890"
    echo "🔌 MSSQL Connection: localhost:1434"
}

function stop_services() {
    echo "🛑 Stopping MSSQL services..."
    docker compose down
    echo "✅ Services stopped!"
}

function restart_services() {
    echo "🔄 Restarting MSSQL services..."
    docker compose down
    docker compose up -d
    echo "✅ Services restarted!"
}

function show_logs() {
    echo "📋 MSSQL Server logs:"
    docker compose logs -f mssql_db
}

function show_status() {
    echo "📊 Service Status:"
    docker compose ps
    echo ""
    echo "🔍 Health Status:"
    docker compose exec mssql_db /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "MSSql@2024!Strong#Pass" -Q "SELECT @@VERSION" 2>/dev/null && echo "✅ MSSQL is healthy" || echo "❌ MSSQL is not responding"
}

function backup_databases() {
    echo "💾 Creating database backups..."
    timestamp=$(date +"%Y%m%d_%H%M%S")
    
    # Backup server_driven_ui_db database
    docker compose exec mssql_db /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "MSSql@2024!Strong#Pass" -Q "
    BACKUP DATABASE [server_driven_ui_db] TO DISK = '/var/opt/mssql/backups/server_driven_ui_db_${timestamp}.bak' WITH FORMAT, INIT;
    "
    
    echo "✅ Backup completed! File saved to ./backups/"
}

function connect_sql() {
    echo "🔗 Connecting to MSSQL Server..."
    echo "Use password: MSSql@2024!Strong#Pass"
    docker compose exec -it mssql_db /opt/mssql-tools/bin/sqlcmd -S localhost -U sa
}

function test_connection() {
    echo "🧪 Testing database connectivity..."
    
    # Test SA connection
    docker compose exec mssql_db /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "MSSql@2024!Strong#Pass" -Q "SELECT 'SA Connection: OK' as Status" 2>/dev/null && echo "✅ SA user connection: OK" || echo "❌ SA user connection: FAILED"
    
    # Test service users
    docker compose exec mssql_db /opt/mssql-tools/bin/sqlcmd -S localhost -U server_driven_ui_user -P "ServerDrivenUI@2024!Pass" -Q "SELECT 'Server Driven UI: OK' as Status" 2>/dev/null && echo "✅ Server Driven UI user: OK" || echo "❌ Server Driven UI user: FAILED"
    
    # Test external connection
    echo "🌐 Testing external connection..."
    sqlcmd -S localhost,1434 -U sa -P "MSSql@2024!Strong#Pass" -Q "SELECT 'External Connection: OK' as Status" 2>/dev/null && echo "✅ External connection: OK" || echo "⚠️  External connection requires sqlcmd installed on host"
}

case "$1" in
    start)
        start_services
        ;;
    stop)
        stop_services
        ;;
    restart)
        restart_services
        ;;
    logs)
        show_logs
        ;;
    status)
        show_status
        ;;
    backup)
        backup_databases
        ;;
    connect)
        connect_sql
        ;;
    test)
        test_connection
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        if [ -z "$1" ]; then
            show_help
        else
            echo "❌ Unknown command: $1"
            echo ""
            show_help
            exit 1
        fi
        ;;
esac