# ✅ MSSQL Server Setup Complete - server_driven_ui_db

## 🎯 What's Deployed

**Database Server:**
- ✅ Azure SQL Edge (SQL Server compatible, free)
- ✅ Container: `mssql_db` (running as root, healthy)
- ✅ Database: `server_driven_ui_db` created successfully

**Management Tools:**
- ✅ Adminer: http://localhost:8889
- ✅ CloudBeaver: http://localhost:8890

## 🔐 Credentials

**Administrator:**
- Username: `sa`
- Password: `MSSql@2024!Strong#Pass`

**Application User (Use this in Spring Boot):**
- Database: `server_driven_ui_db`
- Username: `server_driven_ui_user`
- Password: `ServerDrivenUI@2024!Pass`

**Read-Only User:**
- Username: `readonly_user`
- Password: `ReadOnly@2024!Pass`

## 🔌 Spring Boot Connection

### application.yml
```yaml
spring:
  datasource:
    # For Docker (same network)
    url: jdbc:sqlserver://mssql_db:1433;databaseName=server_driven_ui_db;encrypt=false;trustServerCertificate=true
    username: server_driven_ui_user
    password: ServerDrivenUI@2024!Pass
    driver-class-name: com.microsoft.sqlserver.jdbc.SQLServerDriver
  
  jpa:
    hibernate:
      ddl-auto: update
    show-sql: true
    properties:
      hibernate:
        dialect: org.hibernate.dialect.SQLServerDialect
```

### External Connection (from host)
```yaml
spring:
  datasource:
    url: jdbc:sqlserver://localhost:1434;databaseName=server_driven_ui_db;encrypt=false;trustServerCertificate=true
    username: server_driven_ui_user
    password: ServerDrivenUI@2024!Pass
```

## 🐳 Docker Compose for Spring Boot

```yaml
services:
  spring-app:
    image: your-app:latest
    environment:
      SPRING_DATASOURCE_URL: jdbc:sqlserver://mssql_db:1433;databaseName=server_driven_ui_db;encrypt=false;trustServerCertificate=true
      SPRING_DATASOURCE_USERNAME: server_driven_ui_user
      SPRING_DATASOURCE_PASSWORD: ServerDrivenUI@2024!Pass
    depends_on:
      - mssql_db
    networks:
      - internal

networks:
  internal:
    external: true
```

## 📝 Management Commands

```bash
cd /srv/db/mssql

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

## 🧪 Test Connection

### Via Adminer (Web)
1. Open: http://localhost:8889
2. System: MS SQL
3. Server: `mssql_db`
4. Username: `server_driven_ui_user`
5. Password: `ServerDrivenUI@2024!Pass`
6. Database: `server_driven_ui_db`

### Via Command Line
```bash
docker exec -it mssql_db /opt/mssql-tools/bin/sqlcmd \
  -S localhost \
  -U server_driven_ui_user \
  -P 'ServerDrivenUI@2024!Pass' \
  -d server_driven_ui_db
```

## 📊 Status

✅ All containers running
✅ Database initialized
✅ Users created and tested
✅ Ready for Spring Boot connection

## 🔄 Adding More Databases Later

To add more databases, edit `/srv/db/mssql/init/01-create-databases.sql` and add:

```sql
-- Create new database
CREATE DATABASE [your_new_db];
GO

-- Create user
CREATE LOGIN [your_db_user] WITH PASSWORD = 'YourPassword123!';
GO

-- Grant permissions
USE [your_new_db];
CREATE USER [your_db_user] FOR LOGIN [your_db_user];
ALTER ROLE [db_owner] ADD MEMBER [your_db_user];
GO
```

Then restart: `./mssql-server.sh restart`