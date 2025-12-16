-- mssql-wapromag/init.sql
-- Inicjalizacja bazy danych WAPROMAG

USE master;
GO

IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'WAPROMAG_TEST')
BEGIN
    CREATE DATABASE WAPROMAG_TEST;
END
GO

USE WAPROMAG_TEST;
GO

-- Tabela produktów (musi być przed innymi tabelami które ją referencjonują)
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='Produkty' AND xtype='U')
BEGIN
    CREATE TABLE Produkty (
        ID int IDENTITY(1,1) PRIMARY KEY,
        Kod nvarchar(30) NOT NULL UNIQUE,
        KodKreskowy nvarchar(50),
        Nazwa nvarchar(200) NOT NULL,
        Opis nvarchar(500),
        Kategoria nvarchar(50),
        JednostkaMiary nvarchar(10) DEFAULT 'szt',
        CenaZakupu decimal(10,2) DEFAULT 0,
        CenaSprzedazy decimal(10,2) DEFAULT 0,
        StanMagazynowy decimal(10,3) DEFAULT 0,
        StanMinimalny decimal(10,3) DEFAULT 0,
        StawkaVAT decimal(5,2) DEFAULT 23.00,
        DataUtworzenia datetime DEFAULT GETDATE(),
        DataModyfikacji datetime DEFAULT GETDATE(),
        CzyAktywny bit DEFAULT 1,
        Dostawca nvarchar(100),
        Uwagi nvarchar(500)
    );
END
GO

-- Tabela kontrahentów
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='Kontrahenci' AND xtype='U')
BEGIN
    CREATE TABLE Kontrahenci (
        ID int IDENTITY(1,1) PRIMARY KEY,
        Kod nvarchar(20) NOT NULL UNIQUE,
        Nazwa nvarchar(200) NOT NULL,
        NIP nvarchar(15),
        REGON nvarchar(14),
        Adres nvarchar(300),
        KodPocztowy nvarchar(10),
        Miasto nvarchar(100),
        Telefon nvarchar(50),
        Email nvarchar(100),
        DataUtworzenia datetime DEFAULT GETDATE(),
        DataModyfikacji datetime DEFAULT GETDATE(),
        CzyAktywny bit DEFAULT 1,
        Dostawca nvarchar(100),
        Uwagi nvarchar(500)
    );
END
GO

-- Tabela dokumentów magazynowych
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='DokumentyMagazynowe' AND xtype='U')
BEGIN
    CREATE TABLE DokumentyMagazynowe (
        ID int IDENTITY(1,1) PRIMARY KEY,
        Numer nvarchar(50) NOT NULL UNIQUE,
        TypDokumentu nvarchar(10) NOT NULL, -- PZ, WZ, MM, PW, RW
        KontrahentID int FOREIGN KEY REFERENCES Kontrahenci(ID),
        DataWystawienia datetime DEFAULT GETDATE(),
        DataOperacji datetime DEFAULT GETDATE(),
        Magazyn nvarchar(50) DEFAULT 'GŁÓWNY',
        WartoscNetto decimal(12,2) DEFAULT 0,
        WartoscVAT decimal(12,2) DEFAULT 0,
        WartoscBrutto decimal(12,2) DEFAULT 0,
        Status nvarchar(20) DEFAULT 'ROBOCZA',
        Opis nvarchar(300),
        DataModyfikacji datetime DEFAULT GETDATE(),
        UzytkownikID nvarchar(50),
        CzyZatwierdzona bit DEFAULT 0
    );
END
GO

-- Tabela pozycji dokumentów magazynowych
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='PozycjeDokumentowMagazynowych' AND xtype='U')
BEGIN
    CREATE TABLE PozycjeDokumentowMagazynowych (
        ID int IDENTITY(1,1) PRIMARY KEY,
        DokumentID int FOREIGN KEY REFERENCES DokumentyMagazynowe(ID),
        ProduktID int FOREIGN KEY REFERENCES Produkty(ID),
        Ilosc decimal(10,3) NOT NULL,
        CenaJednostkowa decimal(10,2) NOT NULL,
        WartoscNetto decimal(12,2) NOT NULL,
        StawkaVAT decimal(5,2) DEFAULT 23.00,
        WartoscVAT decimal(12,2),
        WartoscBrutto decimal(12,2),
        NumerPartii nvarchar(50),
        DataWaznosci datetime,
        Uwagi nvarchar(200)
    );
END
GO

-- Tabela stanów magazynowych
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='StanyMagazynowe' AND xtype='U')
BEGIN
    CREATE TABLE StanyMagazynowe (
        ID int IDENTITY(1,1) PRIMARY KEY,
        ProduktID int FOREIGN KEY REFERENCES Produkty(ID),
        Magazyn nvarchar(50) DEFAULT 'GŁÓWNY',
        Stan decimal(10,3) DEFAULT 0,
        StanRezerwacji decimal(10,3) DEFAULT 0,
        StanDostepny decimal(10,3) DEFAULT 0,
        DataOstatnejOperacji datetime DEFAULT GETDATE(),
        UNIQUE(ProduktID, Magazyn)
    );
END
GO

-- Tabela ruchu magazynowego
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='RuchMagazynowy' AND xtype='U')
BEGIN
    CREATE TABLE RuchMagazynowy (
        ID int IDENTITY(1,1) PRIMARY KEY,
        ProduktID int FOREIGN KEY REFERENCES Produkty(ID),
        DokumentID int FOREIGN KEY REFERENCES DokumentyMagazynowe(ID),
        PozycjaID int FOREIGN KEY REFERENCES PozycjeDokumentowMagazynowych(ID),
        Magazyn nvarchar(50) DEFAULT 'GŁÓWNY',
        TypRuchu nvarchar(10) NOT NULL, -- PRZYCHÓD, ROZCHÓD
        Ilosc decimal(10,3) NOT NULL,
        StanPo decimal(10,3) NOT NULL,
        DataOperacji datetime DEFAULT GETDATE(),
        UzytkownikID nvarchar(50)
    );
END
GO

-- Tabela konfiguracji drukarek
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='KonfiguracjaDrukarek' AND xtype='U')
BEGIN
    CREATE TABLE KonfiguracjaDrukarek (
        ID int IDENTITY(1,1) PRIMARY KEY,
        NazwaDrukarki nvarchar(50) NOT NULL,
        AdresIP nvarchar(15) NOT NULL,
        Port int DEFAULT 9100,
        ModelDrukarki nvarchar(50),
        TypDrukarki nvarchar(20) DEFAULT 'ZEBRA',
        Lokalizacja nvarchar(100),
        Magazyn nvarchar(50),
        CzyAktywna bit DEFAULT 1,
        CzyDomyslna bit DEFAULT 0,
        FormatEtyket nvarchar(50) DEFAULT 'STANDARD',
        UstawieniaZPL nvarchar(1000),
        DataOstatniegoBadania datetime,
        StatusPolaczenia nvarchar(20) DEFAULT 'NIEZNANY',
        DataUtworzenia datetime DEFAULT GETDATE(),
        DataModyfikacji datetime DEFAULT GETDATE()
    );
END
GO

-- Tabela szablonów etykiet
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='SzablonyEtykiet' AND xtype='U')
BEGIN
    CREATE TABLE SzablonyEtykiet (
        ID int IDENTITY(1,1) PRIMARY KEY,
        Nazwa nvarchar(100) NOT NULL,
        Typ nvarchar(50) NOT NULL, -- PRODUKT, PALETA, WYSYŁKA
        SzerokoscMM int DEFAULT 100,
        WysokoscMM int DEFAULT 150,
        KodZPL nvarchar(MAX) NOT NULL,
        Opis nvarchar(300),
        CzyAktywny bit DEFAULT 1,
        DataUtworzenia datetime DEFAULT GETDATE(),
        DataModyfikacji datetime DEFAULT GETDATE()
    );
END
GO

-- Tabela logów drukowania
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='LogiDrukowania' AND xtype='U')
BEGIN
    CREATE TABLE LogiDrukowania (
        ID int IDENTITY(1,1) PRIMARY KEY,
        DrukarkaID int FOREIGN KEY REFERENCES KonfiguracjaDrukarek(ID),
        SzablonID int FOREIGN KEY REFERENCES SzablonyEtykiet(ID),
        ProduktID int,
        DokumentID int,
        LiczbaEtykiet int DEFAULT 1,
        StatusDrukowania nvarchar(20) DEFAULT 'WYSŁANO',
        KomunikatBledu nvarchar(500),
        DataDrukowania datetime DEFAULT GETDATE(),
        UzytkownikID nvarchar(50),
        AdresIP nvarchar(15),
        DaneEtykiety nvarchar(MAX)
    );
END
GO

-- Dane testowe - Kontrahenci
INSERT INTO Kontrahenci (Kod, Nazwa, NIP, REGON, Adres, KodPocztowy, Miasto, Telefon, Email)
VALUES
    ('KONT001', 'ABC Sp. z o.o.', '1234567890', '123456789', 'ul. Przykładowa 1', '00-001', 'Warszawa', '123456789', 'abc@example.com'),
    ('KONT002', 'XYZ S.A.', '0987654321', '987654321', 'ul. Testowa 15', '30-001', 'Kraków', '987654321', 'xyz@example.com'),
    ('KONT003', 'Dostawca Główny Sp. z o.o.', '1122334455', '112233445', 'ul. Magazynowa 5', '80-001', 'Gdańsk', '111222333', 'dostawca@example.com');

-- Dane testowe - Produkty
INSERT INTO Produkty (Kod, KodKreskowy, Nazwa, Kategoria, JednostkaMiary, CenaZakupu, CenaSprzedazy, StanMagazynowy, StanMinimalny, Dostawca)
VALUES
    ('PRD001', '1234567890123', 'Laptop Dell Inspiron 15', 'ELEKTRONIKA', 'szt', 2500.00, 3200.00, 15, 5, 'ABC Sp. z o.o.'),
    ('PRD002', '2345678901234', 'Monitor Samsung 24"', 'ELEKTRONIKA', 'szt', 800.00, 1200.00, 8, 3, 'ABC Sp. z o.o.'),
    ('PRD003', '3456789012345', 'Klawiatura Logitech MX', 'AKCESORIA', 'szt', 150.00, 250.00, 25, 10, 'XYZ S.A.'),
    ('PRD004', '4567890123456', 'Mysz bezprzewodowa', 'AKCESORIA', 'szt', 50.00, 89.00, 40, 15, 'XYZ S.A.'),
    ('PRD005', '5678901234567', 'Słuchawki Sony WH-1000XM4', 'AUDIO', 'szt', 900.00, 1400.00, 12, 5, 'Dostawca Główny Sp. z o.o.');

-- Dane testowe - Konfiguracja drukarek
INSERT INTO KonfiguracjaDrukarek (NazwaDrukarki, AdresIP, Port, ModelDrukarki, Lokalizacja, Magazyn, CzyAktywna, CzyDomyslna, FormatEtyket)
VALUES
    ('ZEBRA-001', 'zebra-printer-1', 9100, 'ZT230', 'Magazyn Główny - Sektor A', 'GŁÓWNY', 1, 1, 'STANDARD'),
    ('ZEBRA-002', 'zebra-printer-2', 9100, 'ZT410', 'Magazyn Główny - Sektor B', 'GŁÓWNY', 1, 0, 'WYSOKA_ROZDZIELCZOŚĆ');

-- Dane testowe - Szablony etykiet
INSERT INTO SzablonyEtykiet (Nazwa, Typ, SzerokoscMM, WysokoscMM, KodZPL, Opis)
VALUES
    ('Etykieta Produktu Standard', 'PRODUKT', 100, 150,
     '^XA^FO50,50^A0N,50,50^FD{NAZWA}^FS^FO50,120^A0N,30,30^FD{KOD}^FS^FO50,170^BY3^BCN,100,Y,N,N^FD{KOD_KRESKOWY}^FS^XZ',
     'Standardowa etykieta produktu z nazwą, kodem i kodem kreskowym'),
    ('Etykieta Magazynowa', 'PRODUKT', 100, 100,
     '^XA^FO20,20^A0N,30,30^FD{KOD}^FS^FO20,60^A0N,25,25^FD{STAN}: {ILOSC}^FS^XZ',
     'Etykieta magazynowa ze stanem produktu'),
    ('Etykieta Wysyłkowa', 'WYSYŁKA', 150, 100,
     '^XA^FO20,20^A0N,40,40^FDWYSYŁKA^FS^FO20,70^A0N,30,30^FD{NUMER_DOKUMENTU}^FS^XZ',
     'Etykieta do dokumentów wysyłkowych');

-- Utworzenie stanów magazynowych dla produktów
INSERT INTO StanyMagazynowe (ProduktID, Magazyn, Stan, StanDostepny)
SELECT
    ID,
    'GŁÓWNY',
    StanMagazynowy,
    StanMagazynowy
FROM Produkty;

-- Dane testowe - Dokumenty magazynowe
INSERT INTO DokumentyMagazynowe (Numer, TypDokumentu, KontrahentID, DataWystawienia, DataOperacji, WartoscNetto, WartoscVAT, WartoscBrutto, Status, Opis, CzyZatwierdzona, UzytkownikID)
VALUES
    ('PZ/001/2025', 'PZ', 3, '2025-06-01', '2025-06-01', 25000.00, 5750.00, 30750.00, 'ZATWIERDZONA', 'Dostawa sprzętu komputerowego', 1, 'admin'),
    ('WZ/001/2025', 'WZ', 1, '2025-06-15', '2025-06-15', 8500.00, 1955.00, 10455.00, 'ZATWIERDZONA', 'Sprzedaż laptopów i monitorów', 1, 'admin'),
    ('PZ/002/2025', 'PZ', 2, '2025-06-16', '2025-06-16', 3500.00, 805.00, 4305.00, 'ROBOCZA', 'Dostawa akcesoriów', 0, 'user1');

-- Dane testowe - Pozycje dokumentów
INSERT INTO PozycjeDokumentowMagazynowych (DokumentID, ProduktID, Ilosc, CenaJednostkowa, WartoscNetto, StawkaVAT, WartoscVAT, WartoscBrutto)
VALUES
    -- PZ/001/2025
    (1, 1, 10, 2500.00, 25000.00, 23.00, 5750.00, 30750.00),
    -- WZ/001/2025
    (2, 1, 2, 3200.00, 6400.00, 23.00, 1472.00, 7872.00),
    (2, 2, 1, 1200.00, 1200.00, 23.00, 276.00, 1476.00),
    (2, 3, 3, 250.00, 750.00, 23.00, 172.50, 922.50),
    (2, 4, 2, 89.00, 178.00, 23.00, 40.94, 218.94),
    -- PZ/002/2025
    (3, 3, 15, 150.00, 2250.00, 23.00, 517.50, 2767.50),
    (3, 4, 25, 50.00, 1250.00, 23.00, 287.50, 1537.50);

-- Dane testowe - Ruch magazynowy
INSERT INTO RuchMagazynowy (ProduktID, DokumentID, PozycjaID, TypRuchu, Ilosc, StanPo, DataOperacji, UzytkownikID)
VALUES
    (1, 1, 1, 'PRZYCHÓD', 10, 25, '2025-06-01', 'admin'),
    (1, 2, 2, 'ROZCHÓD', 2, 23, '2025-06-15', 'admin'),
    (2, 2, 3, 'ROZCHÓD', 1, 7, '2025-06-15', 'admin'),
    (3, 2, 4, 'ROZCHÓD', 3, 37, '2025-06-15', 'admin'),
    (4, 2, 5, 'ROZCHÓD', 2, 63, '2025-06-15', 'admin'),
    (3, 3, 6, 'PRZYCHÓD', 15, 52, '2025-06-16', 'user1'),
    (4, 3, 7, 'PRZYCHÓD', 25, 88, '2025-06-16', 'user1');

-- Aktualizacja stanów magazynowych na podstawie ruchu
UPDATE sm SET
    Stan = rm.StanPo,
    StanDostepny = rm.StanPo,
    DataOstatnejOperacji = rm.DataOperacji
FROM StanyMagazynowe sm
INNER JOIN (
    SELECT
        ProduktID,
        MAX(StanPo) as StanPo,
        MAX(DataOperacji) as DataOperacji
    FROM RuchMagazynowy
    GROUP BY ProduktID
) rm ON sm.ProduktID = rm.ProduktID;

-- Utworzenie indeksów dla lepszej wydajności
CREATE INDEX IX_Produkty_Kod ON Produkty(Kod);
CREATE INDEX IX_Produkty_KodKreskowy ON Produkty(KodKreskowy);
CREATE INDEX IX_DokumentyMagazynowe_Numer ON DokumentyMagazynowe(Numer);
CREATE INDEX IX_DokumentyMagazynowe_DataWystawienia ON DokumentyMagazynowe(DataWystawienia);
CREATE INDEX IX_RuchMagazynowy_ProduktID_DataOperacji ON RuchMagazynowy(ProduktID, DataOperacji);
CREATE INDEX IX_StanyMagazynowe_ProduktID_Magazyn ON StanyMagazynowe(ProduktID, Magazyn);

-- Procedura do aktualizacji stanu magazynowego
IF OBJECT_ID('dbo.AktualizujStanMagazynowy', 'P') IS NOT NULL
    DROP PROCEDURE dbo.AktualizujStanMagazynowy;
GO

CREATE PROCEDURE dbo.AktualizujStanMagazynowy
    @ProduktID int,
    @Magazyn nvarchar(50) = 'GŁÓWNY',
    @TypRuchu nvarchar(10),
    @Ilosc decimal(10,3),
    @DokumentID int = NULL,
    @PozycjaID int = NULL,
    @UzytkownikID nvarchar(50) = 'system'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StanAktualny decimal(10,3) = 0;
    DECLARE @StanNowy decimal(10,3) = 0;

    -- Pobierz aktualny stan
    SELECT @StanAktualny = ISNULL(Stan, 0)
    FROM StanyMagazynowe
    WHERE ProduktID = @ProduktID AND Magazyn = @Magazyn;

    -- Oblicz nowy stan
    IF @TypRuchu = 'PRZYCHÓD'
        SET @StanNowy = @StanAktualny + @Ilosc;
    ELSE IF @TypRuchu = 'ROZCHÓD'
        SET @StanNowy = @StanAktualny - @Ilosc;

    -- Sprawdź czy stan nie będzie ujemny
    IF @StanNowy < 0
    BEGIN
        RAISERROR('Stan magazynowy nie może być ujemny', 16, 1);
        RETURN;
    END

    -- Aktualizuj stan magazynowy
    IF EXISTS(SELECT 1 FROM StanyMagazynowe WHERE ProduktID = @ProduktID AND Magazyn = @Magazyn)
    BEGIN
        UPDATE StanyMagazynowe
        SET Stan = @StanNowy,
            StanDostepny = @StanNowy,
            DataOstatnejOperacji = GETDATE()
        WHERE ProduktID = @ProduktID AND Magazyn = @Magazyn;
    END
    ELSE
    BEGIN
        INSERT INTO StanyMagazynowe (ProduktID, Magazyn, Stan, StanDostepny)
        VALUES (@ProduktID, @Magazyn, @StanNowy, @StanNowy);
    END

    -- Dodaj wpis do ruchu magazynowego
    INSERT INTO RuchMagazynowy (ProduktID, DokumentID, PozycjaID, Magazyn, TypRuchu, Ilosc, StanPo, UzytkownikID)
    VALUES (@ProduktID, @DokumentID, @PozycjaID, @Magazyn, @TypRuchu, @Ilosc, @StanNowy, @UzytkownikID);
END
GO

PRINT 'Baza danych WAPROMAG_TEST została pomyślnie utworzona i wypełniona danymi testowymi';