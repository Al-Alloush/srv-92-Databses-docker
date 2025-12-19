-- Configure SQL Server instance settings
USE master;
GO

-- Enable contained databases (for better isolation)
EXEC sp_configure 'contained database authentication', 1;
GO
RECONFIGURE;
GO

-- Configure memory settings (adjust based on your server)
EXEC sp_configure 'show advanced options', 1;
GO
RECONFIGURE;
GO

EXEC sp_configure 'max server memory (MB)', 2048;
GO
RECONFIGURE;
GO

-- Enable SQL Server Agent (if using Standard/Enterprise)
-- Note: Not available in Express edition
-- EXEC xp_servicecontrol N'START', N'SQLServerAGENT';

-- Configure backup compression (reduces backup size)
EXEC sp_configure 'backup compression default', 1;
GO
RECONFIGURE;
GO

-- Configure remote access for services
EXEC sp_configure 'remote access', 1;
GO
RECONFIGURE;
GO

-- Create maintenance indexes and statistics update job
-- This would normally be done via SQL Agent, but for Express edition
-- you might want to handle this in your application

PRINT 'SQL Server configuration completed!';
GO