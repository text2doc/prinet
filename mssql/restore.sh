#!/bin/bash
# MSSQL Database Restore Utility Script

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
LOG_FILE="${SCRIPT_DIR}/restore.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Usage function
usage() {
    echo "Użycie: $0 [OPCJE]"
    echo ""
    echo "Opcje:"
    echo "  -f, --file PATH        Ścieżka pliku backupu (wymagane)"
    echo "  -d, --database NAME    Nazwa docelowej bazy danych (domyślnie: \$TARGET_DB_NAME z .env)"
    echo "  --data-path PATH       Ścieżka pliku danych (opcjonalne)"
    echo "  --log-path PATH        Ścieżka pliku logów (opcjonalne)"
    echo "  -r, --replace          Zastąp istniejącą bazę danych"
    echo "  -v, --verify           Zweryfikuj bazę danych po restore"
    echo "  -h, --help             Pokaż tę pomoc"
    echo ""
    echo "Konfiguracja:"
    echo "  Plik .env: ${SCRIPT_DIR}/.env"
    echo "  Aktualne wartości domyślne:"
    echo "    TARGET_DB: ${TARGET_DB_NAME:-WAPROMAG_TEST}"
    echo "    TARGET_HOST: ${TARGET_DB_HOST:-localhost}"
    echo "    TARGET_USER: ${TARGET_DB_USER:-sa}"
    echo ""
    echo "Przykłady:"
    echo "  $0 -f /backups/db_backup.bak                    # Podstawowy restore"
    echo "  $0 -f backup.bak -d NewDB -r                    # Restore do nowej bazy z zastąpieniem"
    echo "  $0 -f backup.bak --data-path /data --log-path /logs  # Niestandardowe ścieżki plików"
}

# Default values
DATABASE_NAME="${TARGET_DB_NAME:-WAPROMAG_TEST}"
BACKUP_FILE=""
DATA_PATH=""
LOG_PATH=""
REPLACE_DB=false
VERIFY_DB=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--file)
            BACKUP_FILE="$2"
            shift 2
            ;;
        -d|--database)
            DATABASE_NAME="$2"
            shift 2
            ;;
        --data-path)
            DATA_PATH="$2"
            shift 2
            ;;
        --log-path)
            LOG_PATH="$2"
            shift 2
            ;;
        -r|--replace)
            REPLACE_DB=true
            shift
            ;;
        -v|--verify)
            VERIFY_DB=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$BACKUP_FILE" ]; then
    log "${RED}❌ Error: Backup file path is required${NC}"
    usage
    exit 1
fi

if [ -z "$TARGET_DB_HOST" ] || [ -z "$TARGET_DB_USER" ] || [ -z "$TARGET_DB_PASSWORD" ]; then
    log "${RED}❌ Error: Missing required database connection variables in .env${NC}"
    exit 1
fi

log "${BLUE}🔄 Starting database restore process${NC}"
log "${BLUE}Backup File: ${BACKUP_FILE}${NC}"
log "${BLUE}Target Database: ${DATABASE_NAME}${NC}"
log "${BLUE}Replace Existing: $([ "$REPLACE_DB" = true ] && echo "Yes" || echo "No")${NC}"

# Check if backup file exists in container
log "${BLUE}🔍 Checking backup file existence...${NC}"
if ! docker-compose exec mssql-wapromag test -f "$BACKUP_FILE"; then
    log "${RED}❌ Error: Backup file not found: ${BACKUP_FILE}${NC}"
    exit 1
fi

# Prepare SQL command
SQLCMD="docker-compose exec -T mssql-wapromag /opt/mssql-tools18/bin/sqlcmd \
    -S localhost \
    -U ${TARGET_DB_USER} \
    -P ${TARGET_DB_PASSWORD} \
    -C"

# Check if database exists
DB_EXISTS=$($SQLCMD -Q "SELECT COUNT(*) FROM sys.databases WHERE name='$DATABASE_NAME'" -h -1 -W | tr -d ' \r\n')

if [ "$DB_EXISTS" -gt 0 ] && [ "$REPLACE_DB" = false ]; then
    log "${YELLOW}⚠️  Warning: Database ${DATABASE_NAME} already exists${NC}"
    log "${YELLOW}Use -r/--replace flag to replace existing database${NC}"
    exit 1
fi

# Execute restore using SQL script
log "${BLUE}🔄 Executing restore...${NC}"

# Build SQL parameters
SQL_PARAMS="-v BackupFile=\"$BACKUP_FILE\" -v DatabaseName=\"$DATABASE_NAME\" -v Replace=$([ "$REPLACE_DB" = true ] && echo 1 || echo 0)"

if [ -n "$DATA_PATH" ]; then
    SQL_PARAMS="$SQL_PARAMS -v DataPath=\"$DATA_PATH\""
else
    SQL_PARAMS="$SQL_PARAMS -v DataPath=NULL"
fi

if [ -n "$LOG_PATH" ]; then
    SQL_PARAMS="$SQL_PARAMS -v LogPath=\"$LOG_PATH\""
else
    SQL_PARAMS="$SQL_PARAMS -v LogPath=NULL"
fi

# Execute the restore SQL script
if eval $SQLCMD $SQL_PARAMS -i "${SCRIPT_DIR}/restore.sql"; then
    log "${GREEN}✅ Database restore completed successfully${NC}"
    
    # Verify database if requested
    if [ "$VERIFY_DB" = true ]; then
        log "${BLUE}🔍 Verifying database integrity...${NC}"
        if $SQLCMD -Q "DBCC CHECKDB([$DATABASE_NAME]) WITH NO_INFOMSGS"; then
            log "${GREEN}✅ Database verification completed - no errors found${NC}"
        else
            log "${YELLOW}⚠️  Database verification completed with warnings${NC}"
        fi
    fi
    
    # Show database status
    log "${BLUE}📋 Database status:${NC}"
    $SQLCMD -Q "SELECT name, state_desc, user_access_desc FROM sys.databases WHERE name='$DATABASE_NAME'"
    
else
    log "${RED}❌ Database restore failed${NC}"
    exit 1
fi

log "${GREEN}🎉 Restore process completed successfully${NC}"
log "${BLUE}Database: ${DATABASE_NAME} is now available${NC}"
log "${BLUE}Log file: ${LOG_FILE}${NC}"
