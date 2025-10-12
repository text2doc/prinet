-- MSSQL Database Migration Script
-- This script migrates data from source database to target database

-- Enable error handling
SET NOCOUNT ON
SET XACT_ABORT ON

DECLARE @SourceDB NVARCHAR(100) = '$(SourceDatabase)'
DECLARE @TargetDB NVARCHAR(100) = '$(TargetDatabase)'
DECLARE @BatchSize INT = $(BatchSize)
DECLARE @LogLevel NVARCHAR(10) = '$(LogLevel)'

PRINT '=================================================='
PRINT 'WAPRO Database Migration Tool'
PRINT '=================================================='
PRINT 'Source Database: ' + @SourceDB
PRINT 'Target Database: ' + @TargetDB
PRINT 'Batch Size: ' + CAST(@BatchSize AS NVARCHAR)
PRINT 'Started: ' + CONVERT(NVARCHAR, GETDATE(), 120)
PRINT '=================================================='

-- Create migration log table if it doesn't exist
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE name = 'MigrationLog' AND type = 'U')
BEGIN
    CREATE TABLE MigrationLog (
        ID INT IDENTITY(1,1) PRIMARY KEY,
        TableName NVARCHAR(128),
        Operation NVARCHAR(50),
        RowsAffected INT,
        StartTime DATETIME,
        EndTime DATETIME,
        Duration_ms INT,
        Status NVARCHAR(20),
        ErrorMessage NVARCHAR(MAX)
    )
END

-- Migration function for each table
-- 1. Migrate Kontrahenci (Customers)
DECLARE @StartTime DATETIME = GETDATE()
DECLARE @RowsAffected INT = 0
DECLARE @TableName NVARCHAR(128) = 'Kontrahenci'

BEGIN TRY
    PRINT 'Migrating table: ' + @TableName
    
    -- Clear target table if specified
    IF '$(ClearTarget)' = '1'
    BEGIN
        EXEC('DELETE FROM [' + @TargetDB + '].dbo.' + @TableName)
        PRINT 'Target table cleared'
    END
    
    -- Insert data in batches
    DECLARE @SQL NVARCHAR(MAX) = '
    INSERT INTO [' + @TargetDB + '].dbo.' + @TableName + ' 
    (Kod, Nazwa, NIP, REGON, Adres, KodPocztowy, Miasto, Telefon, Email, Dostawca, CzyAktywny)
    SELECT TOP (' + CAST(@BatchSize AS NVARCHAR) + ')
        Kod, Nazwa, NIP, REGON, Adres, KodPocztowy, Miasto, Telefon, Email, Dostawca, 
        ISNULL(CzyAktywny, 1)
    FROM [' + @SourceDB + '].dbo.' + @TableName + ' s
    WHERE NOT EXISTS (
        SELECT 1 FROM [' + @TargetDB + '].dbo.' + @TableName + ' t 
        WHERE t.Kod = s.Kod
    )'
    
    EXEC sp_executesql @SQL
    SET @RowsAffected = @@ROWCOUNT
    
    -- Log the migration
    INSERT INTO MigrationLog (TableName, Operation, RowsAffected, StartTime, EndTime, Duration_ms, Status)
    VALUES (@TableName, 'INSERT', @RowsAffected, @StartTime, GETDATE(), DATEDIFF(ms, @StartTime, GETDATE()), 'SUCCESS')
    
    PRINT 'Migrated ' + CAST(@RowsAffected AS NVARCHAR) + ' rows from ' + @TableName
    
END TRY
BEGIN CATCH
    INSERT INTO MigrationLog (TableName, Operation, RowsAffected, StartTime, EndTime, Duration_ms, Status, ErrorMessage)
    VALUES (@TableName, 'INSERT', 0, @StartTime, GETDATE(), DATEDIFF(ms, @StartTime, GETDATE()), 'ERROR', ERROR_MESSAGE())
    
    PRINT 'ERROR migrating ' + @TableName + ': ' + ERROR_MESSAGE()
END CATCH

-- 2. Migrate Produkty (Products)
SET @StartTime = GETDATE()
SET @TableName = 'Produkty'

BEGIN TRY
    PRINT 'Migrating table: ' + @TableName
    
    IF '$(ClearTarget)' = '1'
    BEGIN
        EXEC('DELETE FROM [' + @TargetDB + '].dbo.' + @TableName)
    END
    
    SET @SQL = '
    INSERT INTO [' + @TargetDB + '].dbo.' + @TableName + ' 
    (Kod, KodKreskowy, Nazwa, Kategoria, JednostkaMiary, CenaZakupu, CenaSprzedazy, StanMagazynowy, StanMinimalny, Dostawca, CzyAktywny)
    SELECT TOP (' + CAST(@BatchSize AS NVARCHAR) + ')
        Kod, KodKreskowy, Nazwa, 
        ISNULL(Kategoria, ''INNE''), 
        ISNULL(JednostkaMiary, ''szt''),
        ISNULL(CenaZakupu, 0), 
        ISNULL(CenaSprzedazy, 0), 
        ISNULL(StanMagazynowy, 0), 
        ISNULL(StanMinimalny, 0), 
        Dostawca,
        ISNULL(CzyAktywny, 1)
    FROM [' + @SourceDB + '].dbo.' + @TableName + ' s
    WHERE NOT EXISTS (
        SELECT 1 FROM [' + @TargetDB + '].dbo.' + @TableName + ' t 
        WHERE t.Kod = s.Kod
    )'
    
    EXEC sp_executesql @SQL
    SET @RowsAffected = @@ROWCOUNT
    
    INSERT INTO MigrationLog (TableName, Operation, RowsAffected, StartTime, EndTime, Duration_ms, Status)
    VALUES (@TableName, 'INSERT', @RowsAffected, @StartTime, GETDATE(), DATEDIFF(ms, @StartTime, GETDATE()), 'SUCCESS')
    
    PRINT 'Migrated ' + CAST(@RowsAffected AS NVARCHAR) + ' rows from ' + @TableName
    
END TRY
BEGIN CATCH
    INSERT INTO MigrationLog (TableName, Operation, RowsAffected, StartTime, EndTime, Duration_ms, Status, ErrorMessage)
    VALUES (@TableName, 'INSERT', 0, @StartTime, GETDATE(), DATEDIFF(ms, @StartTime, GETDATE()), 'ERROR', ERROR_MESSAGE())
    
    PRINT 'ERROR migrating ' + @TableName + ': ' + ERROR_MESSAGE()
END CATCH

-- 3. Migrate DokumentyMagazynowe (Warehouse Documents)
SET @StartTime = GETDATE()
SET @TableName = 'DokumentyMagazynowe'

BEGIN TRY
    PRINT 'Migrating table: ' + @TableName
    
    IF '$(ClearTarget)' = '1'
    BEGIN
        EXEC('DELETE FROM [' + @TargetDB + '].dbo.' + @TableName)
    END
    
    SET @SQL = '
    INSERT INTO [' + @TargetDB + '].dbo.' + @TableName + ' 
    (Numer, TypDokumentu, KontrahentID, DataWystawienia, DataOperacji, Magazyn, WartoscNetto, WartoscVAT, WartoscBrutto, Status, CzyZatwierdzona)
    SELECT TOP (' + CAST(@BatchSize AS NVARCHAR) + ')
        s.Numer, s.TypDokumentu, 
        t_k.ID, -- Map to target kontrahent ID
        s.DataWystawienia, s.DataOperacji,
        ISNULL(s.Magazyn, ''GŁÓWNY''),
        ISNULL(s.WartoscNetto, 0),
        ISNULL(s.WartoscVAT, 0), 
        ISNULL(s.WartoscBrutto, 0),
        ISNULL(s.Status, ''ROBOCZA''),
        ISNULL(s.CzyZatwierdzona, 0)
    FROM [' + @SourceDB + '].dbo.' + @TableName + ' s
    LEFT JOIN [' + @SourceDB + '].dbo.Kontrahenci s_k ON s.KontrahentID = s_k.ID
    LEFT JOIN [' + @TargetDB + '].dbo.Kontrahenci t_k ON s_k.Kod = t_k.Kod
    WHERE NOT EXISTS (
        SELECT 1 FROM [' + @TargetDB + '].dbo.' + @TableName + ' t 
        WHERE t.Numer = s.Numer
    )'
    
    EXEC sp_executesql @SQL
    SET @RowsAffected = @@ROWCOUNT
    
    INSERT INTO MigrationLog (TableName, Operation, RowsAffected, StartTime, EndTime, Duration_ms, Status)
    VALUES (@TableName, 'INSERT', @RowsAffected, @StartTime, GETDATE(), DATEDIFF(ms, @StartTime, GETDATE()), 'SUCCESS')
    
    PRINT 'Migrated ' + CAST(@RowsAffected AS NVARCHAR) + ' rows from ' + @TableName
    
END TRY
BEGIN CATCH
    INSERT INTO MigrationLog (TableName, Operation, RowsAffected, StartTime, EndTime, Duration_ms, Status, ErrorMessage)
    VALUES (@TableName, 'INSERT', 0, @StartTime, GETDATE(), DATEDIFF(ms, @StartTime, GETDATE()), 'ERROR', ERROR_MESSAGE())
    
    PRINT 'ERROR migrating ' + @TableName + ': ' + ERROR_MESSAGE()
END CATCH

-- Show migration summary
PRINT '=================================================='
PRINT 'Migration Summary:'
PRINT '=================================================='

SELECT 
    TableName,
    Operation,
    RowsAffected,
    Duration_ms,
    Status,
    CASE WHEN ErrorMessage IS NOT NULL THEN LEFT(ErrorMessage, 100) + '...' ELSE '' END as ErrorMessage
FROM MigrationLog 
WHERE StartTime >= DATEADD(MINUTE, -5, GETDATE())
ORDER BY StartTime

DECLARE @TotalRows INT = (SELECT SUM(RowsAffected) FROM MigrationLog WHERE StartTime >= DATEADD(MINUTE, -5, GETDATE()) AND Status = 'SUCCESS')
DECLARE @ErrorCount INT = (SELECT COUNT(*) FROM MigrationLog WHERE StartTime >= DATEADD(MINUTE, -5, GETDATE()) AND Status = 'ERROR')

PRINT 'Total rows migrated: ' + CAST(ISNULL(@TotalRows, 0) AS NVARCHAR)
PRINT 'Errors encountered: ' + CAST(ISNULL(@ErrorCount, 0) AS NVARCHAR)
PRINT 'Completed: ' + CONVERT(NVARCHAR, GETDATE(), 120)
PRINT '=================================================='
