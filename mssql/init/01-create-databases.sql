-- Initialize SQL Server with server_driven_ui_dev_db database
-- This script runs after SQL Server starts up
USE master;
GO

-- Create the application database
CREATE DATABASE [server_driven_ui_dev_db];
GO

-- Create service user for the application
CREATE LOGIN [server_driven_ui_dev_user] WITH PASSWORD = '8fd2SSSvf3fp3tL8p!Bkdd!d8GGh#2j8YjS6L#msPnsmLkt2fKwDs58oP3';
GO

-- Create read-only user for reporting/monitoring
CREATE LOGIN [readonly_user] WITH PASSWORD = 'sddg23dfAdsd!d8GGh#2j8YjS6L#msPnsmLkt2fKwDs58oP3';
GO

-- Configure server_driven_ui_dev_db
USE [server_driven_ui_dev_db];
GO

-- Add service user with full permissions
CREATE USER [server_driven_ui_dev_user] FOR LOGIN [server_driven_ui_dev_user];
GO

ALTER ROLE [db_owner] ADD MEMBER [server_driven_ui_dev_user];
GO

-- Add readonly user with read-only permissions
CREATE USER [readonly_user] FOR LOGIN [readonly_user];
GO

ALTER ROLE [db_datareader] ADD MEMBER [readonly_user];
GO

PRINT 'Database server_driven_ui_dev_db created successfully!';
GO