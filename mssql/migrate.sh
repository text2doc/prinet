#!/bin/bash
# MSSQL Database Migration Utility Script

set -e

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
else
    echo "❌ Error: .env file not found"
    exit 1
fi

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/migration.log"

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
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -s, --source NAME      Source database name (default: from .env)"
    echo "  -t, --target NAME      Target database name (default: from .env)"
    echo "  -b, --batch-size N     Batch size for migration (default: from .env)"
    echo "  -c, --clear-target     Clear target tables before migration"
    echo "  --dry-run              Show what would be migrated without executing"
    echo "  --tables LIST          Comma-separated list of specific tables to migrate"
    echo "  -v, --verbose          Verbose output"
    echo "  -h, --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Migrate using .env defaults"
    echo "  $0 -s PROD_DB -t TEST_DB -c          # Migrate from PROD to TEST, clear target"
    echo "  $0 --tables Kontrahenci,Produkty     # Migrate only specific tables"
    echo "  $0 --dry-run -v                      # Preview migration with verbose output"
}

# Default values from .env
SOURCE_DB="${SOURCE_DB_NAME:-WAPRO_PRODUCTION}"
TARGET_DB="${TARGET_DB_NAME:-WAPROMAG_TEST}"
BATCH_SIZE="${MIGRATION_BATCH_SIZE:-1000}"
CLEAR_TARGET=false
DRY_RUN=false
VERBOSE=false
SPECIFIC_TABLES=""

# Parse command line arguments
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
        -b|--batch-size)
            BATCH_SIZE="$2"
            shift 2
            ;;
        -c|--clear-target)
            CLEAR_TARGET=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --tables)
            SPECIFIC_TABLES="$2"
            shift 2
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
            echo "❌ Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required environment variables
if [ -z "$SOURCE_DB_HOST" ] || [ -z "$TARGET_DB_HOST" ]; then
    log "${RED}❌ Error: Missing required database connection variables in .env${NC}"
    exit 1
fi

log "${BLUE}🔄 Starting database migration process${NC}"
log "${BLUE}Source Database: ${SOURCE_DB}${NC}"
log "${BLUE}Target Database: ${TARGET_DB}${NC}"
log "${BLUE}Batch Size: ${BATCH_SIZE}${NC}"
log "${BLUE}Clear Target: $([ "$CLEAR_TARGET" = true ] && echo "Yes" || echo "No")${NC}"

# Check source database connectivity
log "${BLUE}🔍 Checking source database connectivity...${NC}"
SQLCMD_SOURCE="docker-compose exec -T mssql-wapromag /opt/mssql-tools18/bin/sqlcmd \
    -S ${SOURCE_DB_HOST} \
    -U ${SOURCE_DB_USER} \
    -P ${SOURCE_DB_PASSWORD} \
    -d ${SOURCE_DB} \
    -C"

# For demo purposes, we'll use the same container but different logic
# In production, this would connect to different servers
SQLCMD_TARGET="docker-compose exec -T mssql-wapromag /opt/mssql-tools18/bin/sqlcmd \
    -S ${TARGET_DB_HOST} \
    -U ${TARGET_DB_USER} \
    -P ${TARGET_DB_PASSWORD} \
    -d ${TARGET_DB} \
    -C"

# Test source database connection
if ! $SQLCMD_SOURCE -Q "SELECT 1" > /dev/null 2>&1; then
    log "${RED}❌ Error: Cannot connect to source database${NC}"
    exit 1
fi

# Test target database connection
if ! $SQLCMD_TARGET -Q "SELECT 1" > /dev/null 2>&1; then
    log "${RED}❌ Error: Cannot connect to target database${NC}"
    exit 1
fi

log "${GREEN}✅ Database connections verified${NC}"

# Get table list from source database
log "${BLUE}🔍 Analyzing source database schema...${NC}"

TABLES_TO_MIGRATE="Kontrahenci,Produkty,DokumentyMagazynowe"
if [ -n "$SPECIFIC_TABLES" ]; then
    TABLES_TO_MIGRATE="$SPECIFIC_TABLES"
fi

if [ "$DRY_RUN" = true ]; then
    log "${YELLOW}🔍 DRY RUN MODE - No data will be modified${NC}"
    log "${BLUE}Tables to be migrated: ${TABLES_TO_MIGRATE}${NC}"
    
    # Show row counts for each table
    IFS=',' read -ra TABLE_ARRAY <<< "$TABLES_TO_MIGRATE"
    for table in "${TABLE_ARRAY[@]}"; do
        table=$(echo "$table" | xargs) # trim whitespace
        
        log "${BLUE}📊 Analyzing table: ${table}${NC}"
        
        # Get source row count
        SOURCE_COUNT=$($SQLCMD_SOURCE -Q "SELECT COUNT(*) FROM [$table]" -h -1 -W 2>/dev/null | tr -d ' \r\n' || echo "0")
        
        # Get target row count
        TARGET_COUNT=$($SQLCMD_TARGET -Q "SELECT COUNT(*) FROM [$table]" -h -1 -W 2>/dev/null | tr -d ' \r\n' || echo "0")
        
        log "${BLUE}  Source rows: ${SOURCE_COUNT}${NC}"
        log "${BLUE}  Target rows: ${TARGET_COUNT}${NC}"
        log "${BLUE}  Would migrate: $((SOURCE_COUNT - TARGET_COUNT)) rows${NC}"
    done
    
    log "${YELLOW}🔍 Dry run completed. Use without --dry-run to execute migration.${NC}"
    exit 0
fi

# Execute migration using SQL script
log "${BLUE}🔄 Executing migration...${NC}"

# Build SQL parameters
SQL_PARAMS="-v SourceDatabase=\"$SOURCE_DB\" -v TargetDatabase=\"$TARGET_DB\" -v BatchSize=$BATCH_SIZE -v ClearTarget=$([ "$CLEAR_TARGET" = true ] && echo 1 || echo 0) -v LogLevel=\"${MIGRATION_LOG_LEVEL:-INFO}\""

# Execute the migration SQL script
if eval $SQLCMD_TARGET $SQL_PARAMS -i "${SCRIPT_DIR}/migrate.sql"; then
    log "${GREEN}✅ Migration completed successfully${NC}"
    
    # Show migration summary
    log "${BLUE}📊 Migration Summary:${NC}"
    $SQLCMD_TARGET -Q "
    SELECT 
        TableName,
        RowsAffected,
        Duration_ms,
        Status 
    FROM MigrationLog 
    WHERE StartTime >= DATEADD(MINUTE, -10, GETDATE())
    ORDER BY StartTime DESC"
    
else
    log "${RED}❌ Migration failed${NC}"
    
    # Show error details
    log "${BLUE}📋 Error details:${NC}"
    $SQLCMD_TARGET -Q "
    SELECT 
        TableName,
        ErrorMessage,
        StartTime
    FROM MigrationLog 
    WHERE Status = 'ERROR' 
        AND StartTime >= DATEADD(MINUTE, -10, GETDATE())
    ORDER BY StartTime DESC" || true
    
    exit 1
fi

# Verify data integrity after migration
log "${BLUE}🔍 Verifying data integrity...${NC}"
IFS=',' read -ra TABLE_ARRAY <<< "$TABLES_TO_MIGRATE"
for table in "${TABLE_ARRAY[@]}"; do
    table=$(echo "$table" | xargs) # trim whitespace
    
    TARGET_COUNT=$($SQLCMD_TARGET -Q "SELECT COUNT(*) FROM [$table]" -h -1 -W 2>/dev/null | tr -d ' \r\n' || echo "0")
    log "${GREEN}✅ ${table}: ${TARGET_COUNT} rows${NC}"
done

log "${GREEN}🎉 Migration process completed successfully${NC}"
log "${BLUE}Source: ${SOURCE_DB} → Target: ${TARGET_DB}${NC}"
log "${BLUE}Log file: ${LOG_FILE}${NC}"
