-- Initialize SQL Server with server_driven_ui_db database
-- This script runs after SQL Server starts up
USE master;
GO

-- Create the application database
CREATE DATABASE [server_driven_ui_db];
GO

-- Create service user for the application
CREATE LOGIN [server_driven_ui_user] WITH PASSWORD = 'ServerDrivenUI@2024!Pass';
GO

-- Create read-only user for reporting/monitoring
CREATE LOGIN [readonly_user] WITH PASSWORD = 'ReadOnly@2024!Pass';
GO

-- Configure server_driven_ui_db
USE [server_driven_ui_db];
GO

-- Add service user with full permissions
CREATE USER [server_driven_ui_user] FOR LOGIN [server_driven_ui_user];
GO

ALTER ROLE [db_owner] ADD MEMBER [server_driven_ui_user];
GO

-- Add readonly user with read-only permissions
CREATE USER [readonly_user] FOR LOGIN [readonly_user];
GO

ALTER ROLE [db_datareader] ADD MEMBER [readonly_user];
GO

PRINT 'Database server_driven_ui_db created successfully!';
GO