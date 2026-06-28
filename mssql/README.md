# MSSQL Server - Quick Reference

## 📁 Files Overview

### Essential Files (Keep These)
- ✅ `docker-compose.yml` - Container orchestration configuration
- ✅ `mssql-server.sh` - Management script for daily operations
- ✅ `reset-and-test.sh` - Complete reset and verification script
- ✅ `init/01-create-databases.sql` - Database initialization script
- ✅ `init/02-configure-server.sql` - Server configuration script
- ✅ `connection-config.env` - Connection strings reference
- ✅ `SETUP-COMPLETE.md` - Complete setup documentation

### Files Removed (No Longer Needed)
- ❌ `initialize-db.sh` - **DELETED** (redundant - initialization happens automatically)

## 🚀 Quick Commands

### Daily Operations
```bash
# Start services
./mssql-server.sh start

# Check status
./mssql-server.sh status

# Test connections
./mssql-server.sh test

# View logs
./mssql-server.sh logs

# Create backup
./mssql-server.sh backup

# Stop services
./mssql-server.sh stop
```

### Complete Reset (Use When Needed)
```bash
# Reset everything and verify
./reset-and-test.sh
```

## 🔌 Connection Details

**Database:** `server_driven_ui_db`
**User:** `server_driven_ui_user`
**Password:** `ServerDrivenUI@2024!Pass`
**Internal:** `mssql_db:1433`
**External:** `localhost:1434`

## 🧩 Connecting with the VS Code SQL Server (mssql) Extension

> ⚠️ Two common mistakes cause:
> *"A network-related or instance-specific error occurred... The server was not found or was not accessible (provider: TCP Provider, error: 35)"*
>
> 1. **Don't use `mssql_db`.** That hostname only resolves *inside* the Docker `internal` network (it's what the Spring app uses). An external client must connect to the host.
> 2. **Use the external port `1434`, and a comma — not a colon.** SQL clients use `host,port` syntax: `localhost,1434` (not `localhost:1434`, not `mssql_db:1433`).

| Field | Value |
|-------|-------|
| **Server name** | `localhost,1434` (if VS Code runs on the server) — or `<server-ip>,1434` from another machine |
| **Authentication type** | SQL Login |
| **User name** | `sa` (admin) — or `server_driven_ui_user` for the app DB |
| **Password** | SA password from `docker-compose.yml` (`MSSQL_SA_PASSWORD`) — or `ServerDrivenUI@2024!Pass` for the app user |
| **Database** | leave blank, or `server_driven_ui_db` |
| **Encrypt** | Optional (or Mandatory) |
| **Trust server certificate** | **Yes** — the cert is self-signed (matches `trustServerCertificate=true`) |

If connecting from a different machine, make sure host port `1434` is reachable through the server firewall.

## 🌐 Web Interfaces

- **Adminer:** http://localhost:8889
- **CloudBeaver:** http://localhost:8890

## 📝 What Each Script Does

### `reset-and-test.sh` (New)
Complete automation script that:
1. Stops all MSSQL containers
2. Removes containers, volumes, and images
3. Verifies network configuration
4. Creates fresh volumes
5. Starts services
6. Waits for initialization (60 seconds)
7. Tests all connections (6 comprehensive tests)
8. Displays connection information

**When to use:** Fresh start, troubleshooting, or verification

### `mssql-server.sh`
Day-to-day management script for:
- Starting/stopping services
- Checking status and health
- Viewing logs
- Creating backups
- Connecting to database
- Testing connections

**When to use:** Daily operations and maintenance

## 🎯 For Spring Boot

```yaml
spring:
  datasource:
    url: jdbc:sqlserver://mssql_db:1433;databaseName=server_driven_ui_db;encrypt=false;trustServerCertificate=true
    username: server_driven_ui_user
    password: ServerDrivenUI@2024!Pass
```

See `SETUP-COMPLETE.md` for full Spring Boot integration guide.