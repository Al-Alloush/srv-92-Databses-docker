-- *******************************************************************************
-- MSSQL Server Database Initialization Script
--
-- Purpose: Creates all application databases with their service accounts
-- Features:
--   - Safe creation (IF NOT EXISTS)
--   - Idempotent (can run multiple times)
--   - Each database section is independent
-- 
-- CONCEPTS:
--   LOGIN  = Server-level authentication (connects to SQL Server)
--   USER   = Database-level authorization (permissions within a database)
-- *******************************************************************************

USE master;
GO

-- *******************************************************************************
-- SHARED LOGINS (Server-Level) - Create only if not exists

IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'readonly_user')
BEGIN
    CREATE LOGIN [readonly_user] WITH PASSWORD = 'sddg23dfAdsd!d8GGh#2j8YjS6L#msPnsmLkt2fKwDs58oP3';
    PRINT 'Created login: readonly_user';
END
ELSE
    PRINT 'Login readonly_user already exists - skipping';
GO

-- *******************************************************************************
-- DATABASE DEV: server_driven_ui_dev_db

IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'server_driven_ui_dev_db')
BEGIN
    CREATE DATABASE [server_driven_ui_dev_db];
    PRINT 'Created database: server_driven_ui_dev_db';
END
ELSE
    PRINT 'Database server_driven_ui_dev_db already exists - skipping';
GO

IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'server_driven_ui_dev_user')
BEGIN
    CREATE LOGIN [server_driven_ui_dev_user] WITH PASSWORD = 't7nN8CNtU92H2R5Uj794x6a6dK';
    PRINT 'Created login: server_driven_ui_dev_user';
END
GO

USE [server_driven_ui_dev_db];
GO

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'server_driven_ui_dev_user')
BEGIN
    CREATE USER [server_driven_ui_dev_user] FOR LOGIN [server_driven_ui_dev_user];
    ALTER ROLE [db_owner] ADD MEMBER [server_driven_ui_dev_user];
    PRINT 'Created user: server_driven_ui_dev_user';
END
GO

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'readonly_user')
BEGIN
    CREATE USER [readonly_user] FOR LOGIN [readonly_user];
    ALTER ROLE [db_datareader] ADD MEMBER [readonly_user];
    PRINT 'Created readonly user in server_driven_ui_dev_db';
END
GO

-- *******************************************************************************
-- DATABASE TEST: server_driven_ui_test_db

IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'server_driven_ui_test_db')
BEGIN
    CREATE DATABASE [server_driven_ui_test_db];
    PRINT 'Created database: server_driven_ui_test_db';
END
ELSE
    PRINT 'Database server_driven_ui_test_db already exists - skipping';
GO

IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'server_driven_ui_test_user')
BEGIN
    CREATE LOGIN [server_driven_ui_test_user] WITH PASSWORD = 't7nN8CNtU92H2R5Uj794x6a6dK';
    PRINT 'Created login: server_driven_ui_test_user';
END
GO

USE [server_driven_ui_test_db];
GO

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'server_driven_ui_test_user')
BEGIN
    CREATE USER [server_driven_ui_test_user] FOR LOGIN [server_driven_ui_test_user];
    ALTER ROLE [db_owner] ADD MEMBER [server_driven_ui_test_user];
    PRINT 'Created user: server_driven_ui_test_user';
END
GO

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'readonly_user')
BEGIN
    CREATE USER [readonly_user] FOR LOGIN [readonly_user];
    ALTER ROLE [db_datareader] ADD MEMBER [readonly_user];
    PRINT 'Created readonly user in server_driven_ui_dev_db';
END
GO
-- *******************************************************************************
-- DATABASE PROD: server_driven_ui_db

IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'server_driven_ui_db')
BEGIN
    CREATE DATABASE [server_driven_ui_db];
    PRINT 'Created database: server_driven_ui_db';
END
ELSE
    PRINT 'Database server_driven_ui_db already exists - skipping';
GO

IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'server_driven_ui_db_user')
BEGIN
    CREATE LOGIN [server_driven_ui_db_user] WITH PASSWORD = '6VKYKouG9V87C8fe48*k979b25AFR%%8Gpk6TbPe!GN6jQb4meg22c';
    PRINT 'Created login: server_driven_ui_db_user';
END
GO

USE [server_driven_ui_db];
GO

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'server_driven_ui_db_user')
BEGIN
    CREATE USER [server_driven_ui_db_user] FOR LOGIN [server_driven_ui_db_user];
    ALTER ROLE [db_owner] ADD MEMBER [server_driven_ui_db_user];
    PRINT 'Created user: server_driven_ui_db_user';
END
GO

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'readonly_user')
BEGIN
    CREATE USER [readonly_user] FOR LOGIN [readonly_user];
    ALTER ROLE [db_datareader] ADD MEMBER [readonly_user];
    PRINT 'Created readonly user in server_driven_ui_dev_db';
END
GO
-- ------------------------------------------------------------------------------


-- ****************************************************************************** DATABASE DEV: imeterrecorder_dev_db

USE master;
GO

IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'imeterrecorder_dev_db')
BEGIN
    CREATE DATABASE [imeterrecorder_dev_db];
    PRINT 'Created database: imeterrecorder_dev_db';
END
GO

IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'imeterrecorder_dev_admin')
BEGIN
    CREATE LOGIN [imeterrecorder_dev_admin] WITH PASSWORD = 'i55374C2Lzev*SAk2!i25PG939';
    PRINT 'Created login: imeterrecorder_dev_admin';
END
GO

USE [imeterrecorder_dev_db];
GO

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'imeterrecorder_dev_admin')
BEGIN
    CREATE USER [imeterrecorder_dev_admin] FOR LOGIN [imeterrecorder_dev_admin];
    ALTER ROLE [db_owner] ADD MEMBER [imeterrecorder_dev_admin];
    PRINT 'Created user: imeterrecorder_dev_admin';
END
GO

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'readonly_user')
BEGIN
    CREATE USER [readonly_user] FOR LOGIN [readonly_user];
    ALTER ROLE [db_datareader] ADD MEMBER [readonly_user];
END
GO

-- ******************************************************************************
-- DATABASE TEST: imeterrecorder_test_db

USE master;
GO

IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'imeterrecorder_test_db')
BEGIN
    CREATE DATABASE [imeterrecorder_test_db];
    PRINT 'Created database: imeterrecorder_test_db';
END
GO

IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'imeterrecorder_test_admin')
BEGIN
    CREATE LOGIN [imeterrecorder_test_admin] WITH PASSWORD = 'i55374C2Lzev*SAk2!i25PG939';
    PRINT 'Created login: imeterrecorder_test_admin';
END
GO

USE [imeterrecorder_test_db];
GO

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'imeterrecorder_test_admin')
BEGIN
    CREATE USER [imeterrecorder_test_admin] FOR LOGIN [imeterrecorder_test_admin];
    ALTER ROLE [db_owner] ADD MEMBER [imeterrecorder_test_admin];
END
GO

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'readonly_user')
BEGIN
    CREATE USER [readonly_user] FOR LOGIN [readonly_user];
    ALTER ROLE [db_datareader] ADD MEMBER [readonly_user];
END
GO

-- ******************************************************************************
-- DATABASE PROD: imeterrecorder_db (Production)

USE master;
GO

IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'imeterrecorder_db')
BEGIN
    CREATE DATABASE [imeterrecorder_db];
    PRINT 'Created database: imeterrecorder_db';
END
GO

IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'imeterrecorder_user')
BEGIN
    CREATE LOGIN [imeterrecorder_user] WITH PASSWORD = 'z8e@6La!7CU3u33ptHKwoyA9u8sk7!2mQsW6*4zkhqKmX*#7e69%oX';
    PRINT 'Created login: imeterrecorder_user';
END
GO

USE [imeterrecorder_db];
GO

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'imeterrecorder_user')
BEGIN
    CREATE USER [imeterrecorder_user] FOR LOGIN [imeterrecorder_user];
    ALTER ROLE [db_owner] ADD MEMBER [imeterrecorder_user];
END
GO

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'readonly_user')
BEGIN
    CREATE USER [readonly_user] FOR LOGIN [readonly_user];
    ALTER ROLE [db_datareader] ADD MEMBER [readonly_user];
END
GO

PRINT '============================================';
PRINT 'All databases initialized successfully!';
PRINT '============================================';
GO