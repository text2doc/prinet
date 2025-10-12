-- MSSQL Database Migration Script z nadpisywaniem tabel i danych
-- Ten skrypt migruje dane z źródłowej bazy do docelowej z pełnym nadpisywaniem

SET NOCOUNT ON
SET XACT_ABORT ON

DECLARE @SourceDB NVARCHAR(100) = '$(SourceDatabase)'
DECLARE @TargetDB NVARCHAR(100) = '$(TargetDatabase)'
DECLARE @OverwriteMode NVARCHAR(20) = '$(OverwriteMode)' -- TRUNCATE, DROP_RECREATE, MERGE
DECLARE @BatchSize INT = $(BatchSize)

PRINT '=================================================='
PRINT 'WAPRO Database Migration - OVERWRITE MODE'
PRINT '=================================================='
PRINT 'Source Database: ' + @SourceDB
PRINT 'Target Database: ' + @TargetDB
PRINT 'Overwrite Mode: ' + @OverwriteMode
PRINT 'Batch Size: ' + CAST(@BatchSize AS NVARCHAR)
PRINT 'Started: ' + CONVERT(NVARCHAR, GETDATE(), 120)
PRINT '=================================================='

-- Tworzenie tabeli logów migracji
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

-- Lista tabel do migracji w odpowiedniej kolejności (uwzględniając klucze obce)
DECLARE @TablesToMigrate TABLE (
    OrderNum INT,
    TableName NVARCHAR(128),
    HasForeignKeys BIT
)

INSERT INTO @TablesToMigrate VALUES
(1, 'Kontrahenci', 0),           -- Baza - brak kluczy obcych
(2, 'Produkty', 0),              -- Baza - brak kluczy obcych  
(3, 'KonfiguracjaDrukarek', 0),  -- Baza - brak kluczy obcych
(4, 'SzablonyEtykiet', 0),       -- Baza - brak kluczy obcych
(5, 'DokumentyMagazynowe', 1),   -- Ma klucz obcy do Kontrahenci
(6, 'PozycjeDokumentowMagazynowych', 1), -- Ma klucze obce do DokumentyMagazynowe i Produkty
(7, 'StanyMagazynowe', 1),       -- Ma klucz obcy do Produkty
(8, 'LogiDrukowania', 1)         -- Ma klucze obce

-- Cursor do przetwarzania tabel
DECLARE @CurrentTable NVARCHAR(128)
DECLARE @HasForeignKeys BIT
DECLARE @StartTime DATETIME
DECLARE @RowsAffected INT
DECLARE @SQL NVARCHAR(MAX)

DECLARE table_cursor CURSOR FOR
SELECT TableName, HasForeignKeys 
FROM @TablesToMigrate 
ORDER BY OrderNum

OPEN table_cursor
FETCH NEXT FROM table_cursor INTO @CurrentTable, @HasForeignKeys

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @StartTime = GETDATE()
    SET @RowsAffected = 0
    
    PRINT '=================================================='
    PRINT 'Processing table: ' + @CurrentTable
    PRINT 'Overwrite mode: ' + @OverwriteMode
    PRINT '--------------------------------------------------'
    
    BEGIN TRY
        -- Sprawdź czy tabela istnieje w źródłowej bazie
        IF NOT EXISTS (SELECT 1 FROM sys.tables t 
                      JOIN sys.schemas s ON t.schema_id = s.schema_id 
                      WHERE s.name + '.' + t.name = 'dbo.' + @CurrentTable)
        BEGIN
            PRINT 'Table ' + @CurrentTable + ' not found in source database - skipping'
            GOTO NextTable
        END
        
        -- Tryb TRUNCATE - usuwa dane i wstawia nowe
        IF @OverwriteMode = 'TRUNCATE'
        BEGIN
            -- Wyłącz klucze obce tymczasowo dla tabel z relacjami
            IF @HasForeignKeys = 1
            BEGIN
                PRINT 'Disabling foreign key constraints...'
                SET @SQL = 'ALTER TABLE [' + @TargetDB + '].dbo.[' + @CurrentTable + '] NOCHECK CONSTRAINT ALL'
                EXEC sp_executesql @SQL
            END
            
            -- Usuń wszystkie dane z tabeli docelowej
            PRINT 'Truncating target table...'
            SET @SQL = 'TRUNCATE TABLE [' + @TargetDB + '].dbo.[' + @CurrentTable + ']'
            EXEC sp_executesql @SQL
            
            -- Przemigruj dane specyficznie dla każdej tabeli
            IF @CurrentTable = 'Kontrahenci'
            BEGIN
                SET @SQL = '
                INSERT INTO [' + @TargetDB + '].dbo.Kontrahenci 
                (Kod, Nazwa, NIP, REGON, Adres, KodPocztowy, Miasto, Telefon, Email, Dostawca, CzyAktywny, Uwagi)
                SELECT 
                    Kod, Nazwa, NIP, REGON, Adres, KodPocztowy, Miasto, Telefon, Email, 
                    Dostawca, ISNULL(CzyAktywny, 1), Uwagi
                FROM [' + @SourceDB + '].dbo.Kontrahenci'
            END
            ELSE IF @CurrentTable = 'Produkty'
            BEGIN
                SET @SQL = '
                INSERT INTO [' + @TargetDB + '].dbo.Produkty 
                (Kod, KodKreskowy, Nazwa, Kategoria, JednostkaMiary, CenaZakupu, CenaSprzedazy, 
                 StanMagazynowy, StanMinimalny, StanMaksymalny, Dostawca, CzyAktywny, Opis)
                SELECT 
                    Kod, KodKreskowy, Nazwa, ISNULL(Kategoria, ''INNE''), ISNULL(JednostkaMiary, ''szt''),
                    ISNULL(CenaZakupu, 0), ISNULL(CenaSprzedazy, 0), ISNULL(StanMagazynowy, 0),
                    ISNULL(StanMinimalny, 0), ISNULL(StanMaksymalny, 0), Dostawca, ISNULL(CzyAktywny, 1), Opis
                FROM [' + @SourceDB + '].dbo.Produkty'
            END
            ELSE IF @CurrentTable = 'DokumentyMagazynowe'
            BEGIN
                SET @SQL = '
                INSERT INTO [' + @TargetDB + '].dbo.DokumentyMagazynowe 
                (Numer, TypDokumentu, KontrahentID, DataWystawienia, DataOperacji, Magazyn, 
                 WartoscNetto, WartoscVAT, WartoscBrutto, Status, CzyZatwierdzona, Opis, UzytkownikID)
                SELECT 
                    s.Numer, s.TypDokumentu, t_k.ID, s.DataWystawienia, s.DataOperacji,
                    ISNULL(s.Magazyn, ''GŁÓWNY''), ISNULL(s.WartoscNetto, 0), ISNULL(s.WartoscVAT, 0),
                    ISNULL(s.WartoscBrutto, 0), ISNULL(s.Status, ''ROBOCZA''), ISNULL(s.CzyZatwierdzona, 0),
                    s.Opis, s.UzytkownikID
                FROM [' + @SourceDB + '].dbo.DokumentyMagazynowe s
                LEFT JOIN [' + @SourceDB + '].dbo.Kontrahenci s_k ON s.KontrahentID = s_k.ID
                LEFT JOIN [' + @TargetDB + '].dbo.Kontrahenci t_k ON s_k.Kod = t_k.Kod'
            END
            ELSE IF @CurrentTable = 'PozycjeDokumentowMagazynowych'
            BEGIN
                SET @SQL = '
                INSERT INTO [' + @TargetDB + '].dbo.PozycjeDokumentowMagazynowanych
                (DokumentID, ProduktID, Ilosc, CenaJednostkowa, WartoscNetto, StawkaVAT, WartoscVAT, WartoscBrutto)
                SELECT 
                    t_d.ID, t_p.ID, s.Ilosc, s.CenaJednostkowa, s.WartoscNetto, 
                    ISNULL(s.StawkaVAT, 23.00), s.WartoscVAT, s.WartoscBrutto
                FROM [' + @SourceDB + '].dbo.PozycjeDokumentowMagazynowych s
                LEFT JOIN [' + @SourceDB + '].dbo.DokumentyMagazynowe s_d ON s.DokumentID = s_d.ID
                LEFT JOIN [' + @TargetDB + '].dbo.DokumentyMagazynowe t_d ON s_d.Numer = t_d.Numer
                LEFT JOIN [' + @SourceDB + '].dbo.Produkty s_p ON s.ProduktID = s_p.ID
                LEFT JOIN [' + @TargetDB + '].dbo.Produkty t_p ON s_p.Kod = t_p.Kod
                WHERE t_d.ID IS NOT NULL AND t_p.ID IS NOT NULL'
            END
            ELSE IF @CurrentTable = 'StanyMagazynowe'
            BEGIN
                SET @SQL = '
                INSERT INTO [' + @TargetDB + '].dbo.StanyMagazynowe
                (ProduktID, Magazyn, Stan, StanRezerwacji, StanDostepny, DataOstatnejOperacji)
                SELECT 
                    t_p.ID, ISNULL(s.Magazyn, ''GŁÓWNY''), ISNULL(s.Stan, 0), 
                    ISNULL(s.StanRezerwacji, 0), ISNULL(s.StanDostepny, 0), 
                    ISNULL(s.DataOstatnejOperacji, GETDATE())
                FROM [' + @SourceDB + '].dbo.StanyMagazynowe s
                LEFT JOIN [' + @SourceDB + '].dbo.Produkty s_p ON s.ProduktID = s_p.ID
                LEFT JOIN [' + @TargetDB + '].dbo.Produkty t_p ON s_p.Kod = t_p.Kod
                WHERE t_p.ID IS NOT NULL'
            END
            ELSE
            BEGIN
                -- Generyczna migracja dla pozostałych tabel
                SET @SQL = '
                INSERT INTO [' + @TargetDB + '].dbo.[' + @CurrentTable + ']
                SELECT * FROM [' + @SourceDB + '].dbo.[' + @CurrentTable + ']'
            END
            
            -- Wykonaj migrację
            PRINT 'Migrating data...'
            EXEC sp_executesql @SQL
            SET @RowsAffected = @@ROWCOUNT
            
            -- Przywróć klucze obce
            IF @HasForeignKeys = 1
            BEGIN
                PRINT 'Re-enabling foreign key constraints...'
                SET @SQL = 'ALTER TABLE [' + @TargetDB + '].dbo.[' + @CurrentTable + '] WITH CHECK CHECK CONSTRAINT ALL'
                EXEC sp_executesql @SQL
            END
        END
        
        -- Zaloguj sukces
        INSERT INTO MigrationLog (TableName, Operation, RowsAffected, StartTime, EndTime, Duration_ms, Status)
        VALUES (@CurrentTable, @OverwriteMode, @RowsAffected, @StartTime, GETDATE(), DATEDIFF(ms, @StartTime, GETDATE()), 'SUCCESS')
        
        PRINT 'SUCCESS: Migrated ' + CAST(@RowsAffected AS NVARCHAR) + ' rows'
        
    END TRY
    BEGIN CATCH
        -- Przywróć klucze obce w przypadku błędu
        IF @HasForeignKeys = 1
        BEGIN
            SET @SQL = 'ALTER TABLE [' + @TargetDB + '].dbo.[' + @CurrentTable + '] WITH CHECK CHECK CONSTRAINT ALL'
            EXEC sp_executesql @SQL
        END
        
        -- Zaloguj błąd
        INSERT INTO MigrationLog (TableName, Operation, RowsAffected, StartTime, EndTime, Duration_ms, Status, ErrorMessage)
        VALUES (@CurrentTable, @OverwriteMode, 0, @StartTime, GETDATE(), DATEDIFF(ms, @StartTime, GETDATE()), 'ERROR', ERROR_MESSAGE())
        
        PRINT 'ERROR: ' + ERROR_MESSAGE()
    END CATCH
    
    NextTable:
    FETCH NEXT FROM table_cursor INTO @CurrentTable, @HasForeignKeys
END

CLOSE table_cursor
DEALLOCATE table_cursor

-- Podsumowanie migracji
PRINT '=================================================='
PRINT 'MIGRATION SUMMARY'
PRINT '=================================================='

SELECT 
    TableName,
    Operation,
    RowsAffected,
    Duration_ms,
    Status,
    CASE WHEN ErrorMessage IS NOT NULL THEN LEFT(ErrorMessage, 100) + '...' ELSE '' END as ErrorSummary
FROM MigrationLog 
WHERE StartTime >= DATEADD(MINUTE, -15, GETDATE())
ORDER BY StartTime

DECLARE @TotalRows INT = (SELECT SUM(RowsAffected) FROM MigrationLog WHERE StartTime >= DATEADD(MINUTE, -15, GETDATE()) AND Status = 'SUCCESS')
DECLARE @ErrorCount INT = (SELECT COUNT(*) FROM MigrationLog WHERE StartTime >= DATEADD(MINUTE, -15, GETDATE()) AND Status = 'ERROR')
DECLARE @SuccessCount INT = (SELECT COUNT(*) FROM MigrationLog WHERE StartTime >= DATEADD(MINUTE, -15, GETDATE()) AND Status = 'SUCCESS')

PRINT '=================================================='
PRINT 'Total tables processed: ' + CAST((@SuccessCount + @ErrorCount) AS NVARCHAR)
PRINT 'Successfully migrated: ' + CAST(@SuccessCount AS NVARCHAR) + ' tables'
PRINT 'Total rows migrated: ' + CAST(ISNULL(@TotalRows, 0) AS NVARCHAR)
PRINT 'Errors encountered: ' + CAST(ISNULL(@ErrorCount, 0) AS NVARCHAR) + ' tables'
PRINT 'Completed: ' + CONVERT(NVARCHAR, GETDATE(), 120)
PRINT '=================================================='

-- Sprawdź integralność danych po migracji
PRINT 'Checking data integrity...'
PRINT 'Kontrahenci: ' + CAST((SELECT COUNT(*) FROM [' + @TargetDB + '].dbo.Kontrahenci) AS NVARCHAR) + ' records'
PRINT 'Produkty: ' + CAST((SELECT COUNT(*) FROM [' + @TargetDB + '].dbo.Produkty) AS NVARCHAR) + ' records'
PRINT 'DokumentyMagazynowe: ' + CAST((SELECT COUNT(*) FROM [' + @TargetDB + '].dbo.DokumentyMagazynowe) AS NVARCHAR) + ' records'

PRINT '=================================================='
PRINT 'MIGRATION COMPLETED'
PRINT '=================================================='
