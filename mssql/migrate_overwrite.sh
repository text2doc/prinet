#!/bin/bash
# MSSQL Database Migration z nadpisywaniem tabel i danych

set -e

# Konfiguracja skryptu - ustaw katalog skryptu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Załaduj zmienne środowiskowe z katalogu skryptu
ENV_FILE="${SCRIPT_DIR}/.env"
if [ -f "$ENV_FILE" ]; then
    echo "📋 Ładowanie konfiguracji z: $ENV_FILE"
    # Bezpieczne ładowanie zmiennych środowiskowych
    set -a  # automatycznie exportuj zmienne
    source "$ENV_FILE"
    set +a  # wyłącz automatyczny export
else
    echo "⚠️  Ostrzeżenie: Plik .env nie został znaleziony w: $ENV_FILE"
    echo "📝 Używanie domyślnych wartości. Skopiuj .env.example do .env i skonfiguruj."
fi
LOG_FILE="${SCRIPT_DIR}/migration_overwrite.log"
DATE_FORMAT=$(date +"%Y%m%d_%H%M%S")

# Kolory dla outputu
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
    echo "  -s, --source NAME      Nazwa źródłowej bazy danych (domyślnie: \$SOURCE_DB_NAME z .env)"
    echo "  -t, --target NAME      Nazwa docelowej bazy danych (domyślnie: \$TARGET_DB_NAME z .env)"
    echo "  -m, --mode MODE        Tryb nadpisywania: TRUNCATE, DROP_RECREATE, MERGE"
    echo "  -b, --batch-size N     Rozmiar batcha dla migracji (domyślnie: \$MIGRATION_BATCH_SIZE z .env)"
    echo "  --source-host HOST     Host źródłowej bazy (domyślnie: \$SOURCE_DB_HOST z .env)"
    echo "  --target-host HOST     Host docelowej bazy (domyślnie: \$TARGET_DB_HOST z .env)"
    echo "  --backup-first         Utwórz backup przed migracją"
    echo "  --verify-after         Sprawdź integralność po migracji"
    echo "  --dry-run              Pokaż co zostanie zmigrowane bez wykonywania"
    echo "  --force                Wymuś migrację bez potwierdzenia"
    echo "  -v, --verbose          Szczegółowy output"
    echo "  -h, --help             Pokaż tę pomoc"
    echo ""
    echo "Konfiguracja:"
    echo "  Plik .env: ${SCRIPT_DIR}/.env"
    echo "  Aktualne wartości domyślne:"
    echo "    SOURCE_DB: ${SOURCE_DB}"
    echo "    TARGET_DB: ${TARGET_DB}"
    echo "    SOURCE_HOST: ${SOURCE_HOST}"
    echo "    TARGET_HOST: ${TARGET_HOST}"
    echo "    BATCH_SIZE: ${BATCH_SIZE}"
    echo ""
    echo "Tryby nadpisywania:"
    echo "  TRUNCATE      - Usuwa wszystkie dane i wstawia nowe (domyślny)"
    echo "  DROP_RECREATE - Usuwa i odtwarza tabele"
    echo "  MERGE         - Scalanie danych z aktualizacją"
    echo ""
    echo "Przykłady:"
    echo "  $0 -s PROD_DB -t TEST_DB                     # Podstawowa migracja z nadpisywaniem"
    echo "  $0 -s PROD_DB -t TEST_DB -m TRUNCATE --backup-first  # Z backupem przed migracją"
    echo "  $0 --dry-run -v                             # Podgląd migracji ze szczegółami"
    echo "  $0 --force -m DROP_RECREATE                 # Wymuszone odtworzenie tabel"
}

# Wartości domyślne z .env (z fallback jeśli .env nie istnieje)
SOURCE_DB="${SOURCE_DB_NAME:-WAPRO_PRODUCTION}"
TARGET_DB="${TARGET_DB_NAME:-WAPROMAG_TEST}"
OVERWRITE_MODE="TRUNCATE"
BATCH_SIZE="${MIGRATION_BATCH_SIZE:-1000}"
SOURCE_HOST="${SOURCE_DB_HOST:-localhost}"
SOURCE_USER="${SOURCE_DB_USER:-sa}"
SOURCE_PASSWORD="${SOURCE_DB_PASSWORD:-SourcePassword123!}"
TARGET_HOST="${TARGET_DB_HOST:-localhost}"
TARGET_USER="${TARGET_DB_USER:-sa}"
TARGET_PASSWORD="${TARGET_DB_PASSWORD:-WapromagPass123!}"
BACKUP_FIRST=false
VERIFY_AFTER=false
DRY_RUN=false
FORCE=false
VERBOSE=false

# Parsowanie argumentów linii komend
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--source)
            SOURCE_DB="$2"
            shift 2
            ;;
        -t|--target)
            TARGET_DB="$2"
            shift 2
            ;;
        -m|--mode)
            OVERWRITE_MODE="$2"
            shift 2
            ;;
        -b|--batch-size)
            BATCH_SIZE="$2"
            shift 2
            ;;
        --source-host)
            SOURCE_HOST="$2"
            shift 2
            ;;
        --target-host)
            TARGET_HOST="$2"
            shift 2
            ;;
        --backup-first)
            BACKUP_FIRST=true
            shift
            ;;
        --verify-after)
            VERIFY_AFTER=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
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

# Walidacja wymaganych zmiennych środowiskowych
if [ -z "$TARGET_HOST" ] || [ -z "$TARGET_USER" ] || [ -z "$TARGET_PASSWORD" ]; then
    log "${RED}❌ Błąd: Brakuje wymaganych zmiennych połączenia z bazą danych${NC}"
    log "${YELLOW}Sprawdź konfigurację w: ${ENV_FILE}${NC}"
    log "${YELLOW}Wymagane zmienne: TARGET_DB_HOST, TARGET_DB_USER, TARGET_DB_PASSWORD${NC}"
    exit 1
fi

# Walidacja trybu nadpisywania
if [[ ! "$OVERWRITE_MODE" =~ ^(TRUNCATE|DROP_RECREATE|MERGE)$ ]]; then
    log "${RED}❌ Błąd: Nieprawidłowy tryb nadpisywania: $OVERWRITE_MODE${NC}"
    log "${YELLOW}Dostępne tryby: TRUNCATE, DROP_RECREATE, MERGE${NC}"
    exit 1
fi

log "${BLUE}🔄 Rozpoczynanie migracji bazy danych z nadpisywaniem${NC}"
log "${BLUE}Źródłowa baza: ${SOURCE_DB} @ ${SOURCE_HOST}${NC}"
log "${BLUE}Docelowa baza: ${TARGET_DB} @ ${TARGET_HOST}${NC}"
log "${BLUE}Tryb nadpisywania: ${OVERWRITE_MODE}${NC}"
log "${BLUE}Rozmiar batcha: ${BATCH_SIZE}${NC}"
log "${BLUE}Konfiguracja z: ${ENV_FILE}${NC}"

# Sprawdź połączenie z docelową bazą danych
log "${BLUE}🔍 Sprawdzanie połączenia z docelową bazą danych...${NC}"
SQLCMD_TARGET="docker-compose exec -T mssql-wapromag /opt/mssql-tools18/bin/sqlcmd \
    -S ${TARGET_HOST} \
    -U ${TARGET_USER} \
    -P ${TARGET_PASSWORD} \
    -d ${TARGET_DB} \
    -C"

if ! $SQLCMD_TARGET -Q "SELECT 1" > /dev/null 2>&1; then
    log "${RED}❌ Błąd: Cannot connect to target database${NC}"
    exit 1
fi

log "${GREEN}✅ Połączenie z bazą danych zweryfikowane${NC}"

# Sprawdź czy źródłowa baza istnieje
log "${BLUE}🔍 Sprawdzanie źródłowej bazy danych...${NC}"
SOURCE_EXISTS=$($SQLCMD_TARGET -Q "SELECT COUNT(*) FROM sys.databases WHERE name='$SOURCE_DB'" -h -1 -W | tr -d ' \r\n')

if [ "$SOURCE_EXISTS" -eq 0 ]; then
    log "${RED}❌ Błąd: Źródłowa baza danych '$SOURCE_DB' nie istnieje${NC}"
    exit 1
fi

# Sprawdź tabele w źródłowej bazie
log "${BLUE}🔍 Analizowanie tabel do migracji...${NC}"
TABLES_COUNT=$($SQLCMD_TARGET -Q "SELECT COUNT(*) FROM [$SOURCE_DB].INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE'" -h -1 -W | tr -d ' \r\n')
log "${BLUE}Znaleziono ${TABLES_COUNT} tabel do migracji${NC}"

if [ "$DRY_RUN" = true ]; then
    log "${YELLOW}🔍 TRYB PODGLĄDU - Żadne dane nie zostaną zmodyfikowane${NC}"
    
    # Pokaż co zostanie zmigrowane
    log "${BLUE}Tabele do migracji:${NC}"
    $SQLCMD_TARGET -Q "
    SELECT 
        TABLE_NAME as 'Tabela',
        (SELECT COUNT(*) FROM [$SOURCE_DB].dbo.[' + TABLE_NAME + ']) as 'Rekordów_Źródło',
        (SELECT COUNT(*) FROM [$TARGET_DB].dbo.[' + TABLE_NAME + ']) as 'Rekordów_Cel'
    FROM [$SOURCE_DB].INFORMATION_SCHEMA.TABLES 
    WHERE TABLE_TYPE='BASE TABLE' 
        AND TABLE_NAME IN ('Kontrahenci', 'Produkty', 'DokumentyMagazynowe', 'PozycjeDokumentowMagazynowych', 'StanyMagazynowe')
    ORDER BY TABLE_NAME" 2>/dev/null || true
    
    log "${YELLOW}🔍 Podgląd zakończony. Użyj bez --dry-run aby wykonać migrację.${NC}"
    exit 0
fi

# Ostrzeżenie o nadpisywaniu danych
if [ "$FORCE" = false ]; then
    log "${YELLOW}⚠️  UWAGA: Ta operacja nadpisze wszystkie dane w docelowej bazie!${NC}"
    log "${YELLOW}Tryb: ${OVERWRITE_MODE}${NC}"
    log "${YELLOW}Docelowa baza: ${TARGET_DB}${NC}"
    echo ""
    read -p "Czy chcesz kontynuować? (tak/nie): " -r
    if [[ ! $REPLY =~ ^(tak|TAK|yes|YES|y|Y)$ ]]; then
        log "${YELLOW}Migracja anulowana przez użytkownika${NC}"
        exit 0
    fi
fi

# Utwórz backup przed migracją jeśli wymagane
if [ "$BACKUP_FIRST" = true ]; then
    log "${BLUE}💾 Tworzenie backupu przed migracją...${NC}"
    BACKUP_FILE="${TARGET_DB}_pre_migration_${DATE_FORMAT}.bak"
    
    if ./backup.sh -d "$TARGET_DB" -p "/var/opt/mssql/backup" -v; then
        log "${GREEN}✅ Backup utworzony: ${BACKUP_FILE}${NC}"
    else
        log "${RED}❌ Błąd tworzenia backupu. Migracja przerwana.${NC}"
        exit 1
    fi
fi

# Wykonanie migracji z nadpisywaniem
log "${BLUE}🔄 Wykonywanie migracji z nadpisywaniem...${NC}"

# Przygotuj parametry SQL
SQL_PARAMS="-v SourceDatabase=\"$SOURCE_DB\" -v TargetDatabase=\"$TARGET_DB\" -v OverwriteMode=\"$OVERWRITE_MODE\" -v BatchSize=$BATCH_SIZE"

# Wykonaj skrypt migracji
if eval $SQLCMD_TARGET $SQL_PARAMS -i "${SCRIPT_DIR}/migrate_overwrite.sql"; then
    log "${GREEN}✅ Migracja z nadpisywaniem zakończona pomyślnie${NC}"
    
    # Pokaż podsumowanie migracji
    log "${BLUE}📊 Podsumowanie migracji:${NC}"
    $SQLCMD_TARGET -Q "
    SELECT 
        TableName as 'Tabela',
        RowsAffected as 'Rekordów',
        Duration_ms as 'Czas_ms',
        Status
    FROM MigrationLog 
    WHERE StartTime >= DATEADD(MINUTE, -15, GETDATE())
    ORDER BY StartTime DESC"
    
else
    log "${RED}❌ Migracja z nadpisywaniem nie powiodła się${NC}"
    
    # Pokaż szczegóły błędów
    log "${BLUE}📋 Szczegóły błędów:${NC}"
    $SQLCMD_TARGET -Q "
    SELECT 
        TableName as 'Tabela',
        LEFT(ErrorMessage, 100) as 'Błąd',
        StartTime as 'Czas'
    FROM MigrationLog 
    WHERE Status = 'ERROR' 
        AND StartTime >= DATEADD(MINUTE, -15, GETDATE())
    ORDER BY StartTime DESC" || true
    
    exit 1
fi

# Weryfikacja integralności po migracji
if [ "$VERIFY_AFTER" = true ]; then
    log "${BLUE}🔍 Weryfikacja integralności danych...${NC}"
    
    # Sprawdź podstawowe tabele
    TABLES=("Kontrahenci" "Produkty" "DokumentyMagazynowe" "PozycjeDokumentowMagazynowych" "StanyMagazynowe")
    
    for table in "${TABLES[@]}"; do
        COUNT=$($SQLCMD_TARGET -Q "SELECT COUNT(*) FROM [$table]" -h -1 -W 2>/dev/null | tr -d ' \r\n' || echo "0")
        log "${GREEN}✅ ${table}: ${COUNT} rekordów${NC}"
    done
    
    # Sprawdź klucze obce
    log "${BLUE}🔍 Sprawdzanie kluczy obcych...${NC}"
    $SQLCMD_TARGET -Q "
    SELECT 
        OBJECT_NAME(parent_object_id) as 'Tabela',
        COUNT(*) as 'Klucze_obce'
    FROM sys.foreign_keys 
    GROUP BY parent_object_id" 2>/dev/null || true
    
    log "${GREEN}✅ Weryfikacja integralności zakończona${NC}"
fi

# Podsumowanie końcowe
log "${GREEN}🎉 Migracja z nadpisywaniem zakończona pomyślnie${NC}"
log "${BLUE}Źródło: ${SOURCE_DB} → Cel: ${TARGET_DB}${NC}"
log "${BLUE}Tryb: ${OVERWRITE_MODE}${NC}"
log "${BLUE}Plik logów: ${LOG_FILE}${NC}"

if [ "$BACKUP_FIRST" = true ]; then
    log "${BLUE}Backup przed migracją: ${BACKUP_FILE}${NC}"
fi

log "${YELLOW}💡 Tip: Sprawdź aplikację RPI Server GUI na http://localhost:8080${NC}"
