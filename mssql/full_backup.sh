#!/bin/bash
# Kompletny backup wszystkich baz danych z metadanymi

set -e

# Załaduj zmienne środowiskowe
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
else
    echo "❌ Błąd: Plik .env nie został znaleziony"
    exit 1
fi

# Konfiguracja skryptu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/full_backup.log"
DATE_FORMAT=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="${BACKUP_PATH:-/var/opt/mssql/backup}"

# Kolory
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Funkcja logowania
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Funkcja pomocy
usage() {
    echo "Użycie: $0 [OPCJE]"
    echo ""
    echo "Opcje:"
    echo "  -d, --databases LIST   Lista baz danych do backupu (oddzielone przecinkami)"
    echo "  -a, --all-databases    Backup wszystkich baz danych"
    echo "  -p, --path PATH        Ścieżka do katalogu backupu"
    echo "  -c, --compress         Kompresja backupu"
    echo "  --with-schema          Includeuj schema w backupie"
    echo "  --with-data            Includeuj dane w backupie (domyślnie)"
    echo "  --cleanup DAYS         Usuń backupy starsze niż DAYS dni"
    echo "  -v, --verify           Zweryfikuj backup po utworzeniu"
    echo "  -h, --help             Pokaż tę pomoc"
    echo ""
    echo "Przykłady:"
    echo "  $0 -a -c -v                           # Backup wszystkich baz z kompresją i weryfikacją"
    echo "  $0 -d WAPROMAG_TEST,PROD_DB --cleanup 7  # Backup wybranych baz z cleanup"
    echo "  $0 --all-databases --with-schema      # Backup z pełnym schema"
}

# Wartości domyślne
DATABASES=""
ALL_DATABASES=false
COMPRESS=false
WITH_SCHEMA=true
WITH_DATA=true
CLEANUP_DAYS=""
VERIFY=false

# Parsowanie argumentów
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--databases)
            DATABASES="$2"
            shift 2
            ;;
        -a|--all-databases)
            ALL_DATABASES=true
            shift
            ;;
        -p|--path)
            BACKUP_DIR="$2"
            shift 2
            ;;
        -c|--compress)
            COMPRESS=true
            shift
            ;;
        --with-schema)
            WITH_SCHEMA=true
            shift
            ;;
        --with-data)
            WITH_DATA=true
            shift
            ;;
        --cleanup)
            CLEANUP_DAYS="$2"
            shift 2
            ;;
        -v|--verify)
            VERIFY=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "❌ Nieznana opcja: $1"
            usage
            exit 1
            ;;
    esac
done

log "${BLUE}🔄 Rozpoczynanie pełnego backupu${NC}"
log "${BLUE}Katalog backupu: ${BACKUP_DIR}${NC}"
log "${BLUE}Data/czas: ${DATE_FORMAT}${NC}"

# Przygotuj komendę SQL
SQLCMD="docker-compose exec -T mssql-wapromag /opt/mssql-tools18/bin/sqlcmd \
    -S localhost \
    -U ${TARGET_DB_USER} \
    -P ${TARGET_DB_PASSWORD} \
    -C"

# Utwórz katalog backupu
log "${BLUE}📁 Tworzenie katalogu backupu...${NC}"
docker-compose exec mssql-wapromag mkdir -p "$BACKUP_DIR" 2>/dev/null || true

# Pobierz listę baz danych
if [ "$ALL_DATABASES" = true ]; then
    log "${BLUE}🔍 Pobieranie listy wszystkich baz danych...${NC}"
    DB_LIST=$($SQLCMD -Q "SELECT name FROM sys.databases WHERE name NOT IN ('master', 'tempdb', 'model', 'msdb')" -h -1 -W | tr -d '\r' | grep -v '^$')
else
    if [ -z "$DATABASES" ]; then
        DATABASES="${TARGET_DB_NAME:-WAPROMAG_TEST}"
    fi
    DB_LIST=$(echo "$DATABASES" | tr ',' '\n')
fi

log "${BLUE}📋 Bazy danych do backupu:${NC}"
echo "$DB_LIST" | while read db; do
    [ -n "$db" ] && log "${BLUE}  - $db${NC}"
done

# Backup każdej bazy danych
echo "$DB_LIST" | while read db; do
    if [ -n "$db" ]; then
        log "${BLUE}🔄 Backup bazy danych: $db${NC}"
        
        # Nazwa pliku backupu
        BACKUP_FILE="${db}_full_backup_${DATE_FORMAT}.bak"
        BACKUP_PATH_FULL="${BACKUP_DIR}/${BACKUP_FILE}"
        
        # Przygotuj opcje backupu
        BACKUP_OPTIONS="FORMAT, CHECKSUM, STATS = 10"
        if [ "$COMPRESS" = true ]; then
            BACKUP_OPTIONS="$BACKUP_OPTIONS, COMPRESSION"
        fi
        
        # Wykonaj backup
        BACKUP_SQL="
        DECLARE @BackupPath NVARCHAR(500) = '$BACKUP_PATH_FULL'
        DECLARE @DatabaseName NVARCHAR(100) = '$db'
        
        PRINT 'Starting backup of database: ' + @DatabaseName
        PRINT 'Backup file: ' + @BackupPath
        
        BACKUP DATABASE @DatabaseName 
        TO DISK = @BackupPath
        WITH $BACKUP_OPTIONS,
            NAME = @DatabaseName + ' Full Backup - $DATE_FORMAT',
            DESCRIPTION = 'Full backup of ' + @DatabaseName + ' created on ' + CONVERT(NVARCHAR, GETDATE(), 120)
        
        PRINT 'Backup completed: ' + @BackupPath
        
        -- Pokaż rozmiar backupu
        SELECT 
            database_name as 'Database',
            CAST(backup_size/1024/1024 AS INT) as 'Size_MB',
            backup_finish_date as 'Completed'
        FROM msdb.dbo.backupset 
        WHERE database_name = @DatabaseName 
            AND backup_finish_date = (
                SELECT MAX(backup_finish_date) 
                FROM msdb.dbo.backupset 
                WHERE database_name = @DatabaseName
            )
        "
        
        if $SQLCMD -Q "$BACKUP_SQL"; then
            log "${GREEN}✅ Backup zakończony pomyślnie: $db${NC}"
            
            # Weryfikacja backupu
            if [ "$VERIFY" = true ]; then
                log "${BLUE}🔍 Weryfikacja backupu: $db${NC}"
                if $SQLCMD -Q "RESTORE VERIFYONLY FROM DISK = '$BACKUP_PATH_FULL'"; then
                    log "${GREEN}✅ Weryfikacja pomyślna: $db${NC}"
                else
                    log "${RED}❌ Weryfikacja nieudana: $db${NC}"
                fi
            fi
        else
            log "${RED}❌ Backup nieudany: $db${NC}"
        fi
    fi
done

# Cleanup starych backupów
if [ -n "$CLEANUP_DAYS" ]; then
    log "${BLUE}🧹 Usuwanie backupów starszych niż $CLEANUP_DAYS dni...${NC}"
    
    # Znajdź i usuń stare pliki backupu
    DELETED_COUNT=$(docker-compose exec mssql-wapromag find "$BACKUP_DIR" \
        -name "*_backup_*.bak" \
        -type f \
        -mtime +$CLEANUP_DAYS \
        -delete \
        -print | wc -l)
    
    log "${GREEN}✅ Usunięto $DELETED_COUNT starych backupów${NC}"
fi

# Podsumowanie backupów
log "${BLUE}📊 Podsumowanie backupów:${NC}"
docker-compose exec mssql-wapromag ls -la "$BACKUP_DIR" | grep "_backup_${DATE_FORMAT}" || true

# Pokaż całkowity rozmiar backupów
TOTAL_SIZE=$(docker-compose exec mssql-wapromag du -sh "$BACKUP_DIR" | cut -f1)
log "${BLUE}💾 Całkowity rozmiar backupów: ${TOTAL_SIZE}${NC}"

# Export metadanych do pliku JSON
METADATA_FILE="${BACKUP_DIR}/backup_metadata_${DATE_FORMAT}.json"
log "${BLUE}📋 Tworzenie metadanych backupu...${NC}"

METADATA_SQL="
SELECT 
    bs.database_name,
    bs.backup_start_date,
    bs.backup_finish_date,
    CAST(bs.backup_size/1024/1024 AS INT) as backup_size_mb,
    bs.backup_set_id,
    bf.physical_device_name,
    bs.name as backup_name,
    bs.description
FROM msdb.dbo.backupset bs
JOIN msdb.dbo.backupmediafamily bf ON bs.media_set_id = bf.media_set_id
WHERE bs.backup_start_date >= DATEADD(HOUR, -1, GETDATE())
    AND bs.type = 'D'
FOR JSON AUTO
"

$SQLCMD -Q "$METADATA_SQL" -o "$METADATA_FILE" 2>/dev/null || true

log "${GREEN}🎉 Pełny backup zakończony pomyślnie${NC}"
log "${BLUE}Katalog backupu: ${BACKUP_DIR}${NC}"
log "${BLUE}Metadane: ${METADATA_FILE}${NC}"
log "${BLUE}Plik logów: ${LOG_FILE}${NC}"

# Pokaż statystyki końcowe
log "${BLUE}📈 Statystyki końcowe:${NC}"
$SQLCMD -Q "
SELECT 
    COUNT(*) as 'Total_Backups_Today',
    SUM(CAST(backup_size/1024/1024 AS BIGINT)) as 'Total_Size_MB'
FROM msdb.dbo.backupset 
WHERE backup_start_date >= CAST(GETDATE() AS DATE)
    AND type = 'D'
" 2>/dev/null || true
