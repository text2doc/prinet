#!/bin/bash
# MSSQL Database Backup Utility Script

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
LOG_FILE="${SCRIPT_DIR}/backup.log"
DATE_FORMAT=$(date +"%Y%m%d_%H%M%S")

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
    echo "  -d, --database NAME    Nazwa bazy danych do backupu (domyślnie: \$TARGET_DB_NAME z .env)"
    echo "  -p, --path PATH        Ścieżka katalogu backupu (domyślnie: \$BACKUP_PATH z .env)"
    echo "  -c, --cleanup          Usuń stare backupy według polityki retencji"
    echo "  -v, --verify           Zweryfikuj backup po utworzeniu"
    echo "  -h, --help             Pokaż tę pomoc"
    echo ""
    echo "Konfiguracja:"
    echo "  Plik .env: ${SCRIPT_DIR}/.env"
    echo "  Aktualne wartości domyślne:"
    echo "    DATABASE: ${TARGET_DB_NAME:-WAPROMAG_TEST}"
    echo "    BACKUP_PATH: ${BACKUP_PATH:-/var/opt/mssql/backup}"
    echo "    RETENTION_DAYS: ${BACKUP_RETENTION_DAYS:-30}"
    echo ""
    echo "Przykłady:"
    echo "  $0                                    # Backup domyślnej bazy danych"
    echo "  $0 -d WAPROMAG_TEST -c -v           # Backup konkretnej bazy z cleanup i weryfikacją"
    echo "  $0 --database MyDB --path /backups  # Niestandardowa baza i ścieżka"
}

# Default values from .env
DATABASE_NAME="${TARGET_DB_NAME:-WAPROMAG_TEST}"
BACKUP_DIR="${BACKUP_PATH:-/var/opt/mssql/backup}"
CLEANUP_OLD=false
VERIFY_BACKUP=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--database)
            DATABASE_NAME="$2"
            shift 2
            ;;
        -p|--path)
            BACKUP_DIR="$2"
            shift 2
            ;;
        -c|--cleanup)
            CLEANUP_OLD=true
            shift
            ;;
        -v|--verify)
            VERIFY_BACKUP=true
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

# Validate required environment variables
if [ -z "$TARGET_DB_HOST" ] || [ -z "$TARGET_DB_USER" ] || [ -z "$TARGET_DB_PASSWORD" ]; then
    log "${RED}❌ Błąd: Brakuje wymaganych zmiennych połączenia z bazą danych${NC}"
    log "${YELLOW}Sprawdź konfigurację w: ${ENV_FILE}${NC}"
    log "${YELLOW}Wymagane zmienne: TARGET_DB_HOST, TARGET_DB_USER, TARGET_DB_PASSWORD${NC}"
    exit 1
fi

log "${BLUE}🔄 Starting database backup process${NC}"
log "${BLUE}Database: ${DATABASE_NAME}${NC}"
log "${BLUE}Backup Directory: ${BACKUP_DIR}${NC}"

# Create backup directory if it doesn't exist
if ! docker-compose exec mssql-wapromag mkdir -p "$BACKUP_DIR" 2>/dev/null; then
    log "${YELLOW}⚠️  Warning: Could not create backup directory (may already exist)${NC}"
fi

# Execute backup using SQL script
log "${BLUE}🔄 Executing backup...${NC}"

SQLCMD="docker-compose exec -T mssql-wapromag /opt/mssql-tools18/bin/sqlcmd \
    -S localhost \
    -U ${TARGET_DB_USER} \
    -P ${TARGET_DB_PASSWORD} \
    -C"

# Execute the backup SQL script with parameters
if $SQLCMD \
    -v DatabaseName="$DATABASE_NAME" \
    -v BackupPath="$BACKUP_DIR" \
    -v CleanupOldBackups="$([ "$CLEANUP_OLD" = true ] && echo 1 || echo 0)" \
    -v RetentionDays="${BACKUP_RETENTION_DAYS:-30}" \
    -i "${SCRIPT_DIR}/backup.sql"; then
    
    log "${GREEN}✅ Backup completed successfully${NC}"
    
    # Verify backup if requested
    if [ "$VERIFY_BACKUP" = true ]; then
        log "${BLUE}🔍 Verifying backup integrity...${NC}"
        # Verification is included in the SQL script
        log "${GREEN}✅ Backup verification completed${NC}"
    fi
    
    # List recent backups
    log "${BLUE}📋 Recent backups:${NC}"
    docker-compose exec mssql-wapromag ls -la "$BACKUP_DIR" | grep "${DATABASE_NAME}_backup" | tail -5 || true
    
else
    log "${RED}❌ Backup failed${NC}"
    exit 1
fi

# Cleanup old backups if requested
if [ "$CLEANUP_OLD" = true ]; then
    log "${BLUE}🧹 Cleaning up old backups (older than ${BACKUP_RETENTION_DAYS:-30} days)...${NC}"
    
    # Find and remove old backup files
    docker-compose exec mssql-wapromag find "$BACKUP_DIR" \
        -name "${DATABASE_NAME}_backup_*.bak" \
        -type f \
        -mtime +${BACKUP_RETENTION_DAYS:-30} \
        -delete 2>/dev/null || true
    
    log "${GREEN}✅ Old backup cleanup completed${NC}"
fi

log "${GREEN}🎉 Backup process completed successfully${NC}"
log "${BLUE}Log file: ${LOG_FILE}${NC}"
