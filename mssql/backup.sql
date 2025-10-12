-- MSSQL Database Backup Script
-- This script creates a full backup of the specified database

DECLARE @BackupPath NVARCHAR(500)
DECLARE @DatabaseName NVARCHAR(100) = '$(DatabaseName)'
DECLARE @BackupFileName NVARCHAR(500)
DECLARE @Timestamp NVARCHAR(20)

-- Generate timestamp for backup file
SET @Timestamp = FORMAT(GETDATE(), 'yyyyMMdd_HHmmss')
SET @BackupFileName = @DatabaseName + '_backup_' + @Timestamp + '.bak'
SET @BackupPath = '$(BackupPath)' + '\' + @BackupFileName

PRINT 'Starting backup of database: ' + @DatabaseName
PRINT 'Backup file: ' + @BackupPath

-- Perform the backup
BACKUP DATABASE @DatabaseName 
TO DISK = @BackupPath
WITH 
    FORMAT,
    COMPRESSION,
    CHECKSUM,
    STATS = 10,
    NAME = @DatabaseName + ' Full Backup - ' + @Timestamp,
    DESCRIPTION = 'Full backup of ' + @DatabaseName + ' created on ' + CONVERT(NVARCHAR, GETDATE(), 120)

-- Verify the backup
RESTORE VERIFYONLY FROM DISK = @BackupPath

PRINT 'Backup completed successfully!'
PRINT 'Backup file: ' + @BackupPath
PRINT 'Backup size: ' + CAST((SELECT backup_size/1024/1024 as backup_size_mb FROM msdb.dbo.backupset WHERE database_name = @DatabaseName AND backup_finish_date = (SELECT MAX(backup_finish_date) FROM msdb.dbo.backupset WHERE database_name = @DatabaseName)) AS NVARCHAR) + ' MB'

-- Clean up old backups (optional)
IF '$(CleanupOldBackups)' = '1'
BEGIN
    DECLARE @RetentionDays INT = $(RetentionDays)
    DECLARE @CutoffDate DATETIME = DATEADD(DAY, -@RetentionDays, GETDATE())
    
    PRINT 'Cleaning up backups older than ' + CAST(@RetentionDays AS NVARCHAR) + ' days...'
    
    -- This would need to be implemented with xp_cmdshell or external script
    -- as SQL Server cannot directly delete files from disk
    PRINT 'Note: Manual cleanup of backup files older than ' + CONVERT(NVARCHAR, @CutoffDate, 120) + ' required'
END
