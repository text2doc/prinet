-- MSSQL Database Restore Script
-- This script restores a database from a backup file

DECLARE @BackupFile NVARCHAR(500) = '$(BackupFile)'
DECLARE @DatabaseName NVARCHAR(100) = '$(DatabaseName)'
DECLARE @DataPath NVARCHAR(500) = '$(DataPath)'
DECLARE @LogPath NVARCHAR(500) = '$(LogPath)'
DECLARE @Replace BIT = $(Replace)

PRINT 'Starting restore of database: ' + @DatabaseName
PRINT 'From backup file: ' + @BackupFile

-- Check if backup file exists and is valid
RESTORE VERIFYONLY FROM DISK = @BackupFile
IF @@ERROR <> 0
BEGIN
    PRINT 'ERROR: Backup file verification failed!'
    RETURN
END

-- Get logical file names from backup
DECLARE @DataLogicalName NVARCHAR(128)
DECLARE @LogLogicalName NVARCHAR(128)

SELECT 
    @DataLogicalName = MAX(CASE WHEN [type] = 'D' THEN logical_name END),
    @LogLogicalName = MAX(CASE WHEN [type] = 'L' THEN logical_name END)
FROM msdb.dbo.backupfile bf
INNER JOIN msdb.dbo.backupset bs ON bf.backup_set_id = bs.backup_set_id
WHERE bs.database_name = @DatabaseName
    AND bs.backup_finish_date = (
        SELECT MAX(backup_finish_date) 
        FROM msdb.dbo.backupset 
        WHERE database_name = @DatabaseName
    )

-- Set database to single user mode if it exists and we need to replace
IF @Replace = 1 AND EXISTS(SELECT 1 FROM sys.databases WHERE name = @DatabaseName)
BEGIN
    PRINT 'Setting database to SINGLE_USER mode...'
    EXEC('ALTER DATABASE [' + @DatabaseName + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE')
END

-- Perform the restore
DECLARE @RestoreSQL NVARCHAR(MAX)
SET @RestoreSQL = 'RESTORE DATABASE [' + @DatabaseName + '] FROM DISK = ''' + @BackupFile + ''' WITH '

-- Add file relocation if paths are specified
IF @DataPath IS NOT NULL AND @DataLogicalName IS NOT NULL
    SET @RestoreSQL = @RestoreSQL + 'MOVE ''' + @DataLogicalName + ''' TO ''' + @DataPath + '\' + @DatabaseName + '.mdf'', '

IF @LogPath IS NOT NULL AND @LogLogicalName IS NOT NULL
    SET @RestoreSQL = @RestoreSQL + 'MOVE ''' + @LogLogicalName + ''' TO ''' + @LogPath + '\' + @DatabaseName + '_Log.ldf'', '

-- Add common restore options
SET @RestoreSQL = @RestoreSQL + 'CHECKSUM, STATS = 10'

IF @Replace = 1
    SET @RestoreSQL = @RestoreSQL + ', REPLACE'

PRINT 'Executing restore command:'
PRINT @RestoreSQL

EXEC sp_executesql @RestoreSQL

-- Set database back to multi-user mode
IF @Replace = 1
BEGIN
    PRINT 'Setting database to MULTI_USER mode...'
    EXEC('ALTER DATABASE [' + @DatabaseName + '] SET MULTI_USER')
END

-- Verify database integrity
PRINT 'Verifying database integrity...'
EXEC('DBCC CHECKDB([' + @DatabaseName + ']) WITH NO_INFOMSGS')

PRINT 'Database restore completed successfully!'
PRINT 'Database: ' + @DatabaseName
PRINT 'Status: ONLINE'
