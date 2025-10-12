#!/bin/bash
# Test skrypt do sprawdzania ładowania konfiguracji z argumentów i .env

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

# Kolory
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Funkcja pomocy
usage() {
    echo "Użycie: $0 [OPCJE]"
    echo ""
    echo "Opcje:"
    echo "  -s, --source NAME      Nazwa źródłowej bazy danych"
    echo "  -t, --target NAME      Nazwa docelowej bazy danych"
    echo "  --source-host HOST     Host źródłowej bazy"
    echo "  --target-host HOST     Host docelowej bazy"
    echo "  -b, --batch-size N     Rozmiar batcha"
    echo "  -h, --help             Pokaż pomoc"
    echo ""
    echo "Konfiguracja:"
    echo "  Plik .env: ${SCRIPT_DIR}/.env"
    echo "  Wartości z .env:"
    echo "    SOURCE_DB_NAME: ${SOURCE_DB_NAME:-'(nie ustawione)'}"
    echo "    TARGET_DB_NAME: ${TARGET_DB_NAME:-'(nie ustawione)'}"
    echo "    SOURCE_DB_HOST: ${SOURCE_DB_HOST:-'(nie ustawione)'}"
    echo "    TARGET_DB_HOST: ${TARGET_DB_HOST:-'(nie ustawione)'}"
    echo "    MIGRATION_BATCH_SIZE: ${MIGRATION_BATCH_SIZE:-'(nie ustawione)'}"
}

# Wartości domyślne z .env (z fallback jeśli .env nie istnieje)
SOURCE_DB="${SOURCE_DB_NAME:-WAPRO_PRODUCTION}"
TARGET_DB="${TARGET_DB_NAME:-WAPROMAG_TEST}"
SOURCE_HOST="${SOURCE_DB_HOST:-localhost}"
TARGET_HOST="${TARGET_DB_HOST:-localhost}"
BATCH_SIZE="${MIGRATION_BATCH_SIZE:-1000}"

# Parsowanie argumentów linii komend
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--source)
            SOURCE_DB="$2"
            echo "🔧 Argument: SOURCE_DB ustawione na: $2"
            shift 2
            ;;
        -t|--target)
            TARGET_DB="$2"
            echo "🔧 Argument: TARGET_DB ustawione na: $2"
            shift 2
            ;;
        --source-host)
            SOURCE_HOST="$2"
            echo "🔧 Argument: SOURCE_HOST ustawione na: $2"
            shift 2
            ;;
        --target-host)
            TARGET_HOST="$2"
            echo "🔧 Argument: TARGET_HOST ustawione na: $2"
            shift 2
            ;;
        -b|--batch-size)
            BATCH_SIZE="$2"
            echo "🔧 Argument: BATCH_SIZE ustawione na: $2"
            shift 2
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

echo ""
echo "=================================================="
echo -e "${BLUE}TEST KONFIGURACJI SKRYPTÓW MSSQL${NC}"
echo "=================================================="
echo ""

echo -e "${BLUE}📁 Lokalizacja skryptu:${NC}"
echo "   SCRIPT_DIR: $SCRIPT_DIR"
echo "   ENV_FILE: $ENV_FILE"
echo ""

if [ -f "$ENV_FILE" ]; then
    echo -e "${GREEN}✅ Plik .env znaleziony${NC}"
    echo -e "${BLUE}📋 Zawartość pliku .env:${NC}"
    echo "---"
    cat "$ENV_FILE" | grep -v '^#' | grep -v '^$' | head -10
    echo "---"
else
    echo -e "${YELLOW}⚠️  Plik .env nie znaleziony${NC}"
fi

echo ""
echo -e "${BLUE}🔧 Finalne wartości konfiguracji:${NC}"
echo "   SOURCE_DB: $SOURCE_DB"
echo "   TARGET_DB: $TARGET_DB"
echo "   SOURCE_HOST: $SOURCE_HOST"
echo "   TARGET_HOST: $TARGET_HOST"
echo "   BATCH_SIZE: $BATCH_SIZE"

echo ""
echo -e "${BLUE}🌍 Zmienne środowiskowe z .env:${NC}"
echo "   SOURCE_DB_NAME: ${SOURCE_DB_NAME:-'(nie ustawione)'}"
echo "   TARGET_DB_NAME: ${TARGET_DB_NAME:-'(nie ustawione)'}"
echo "   SOURCE_DB_HOST: ${SOURCE_DB_HOST:-'(nie ustawione)'}"
echo "   TARGET_DB_HOST: ${TARGET_DB_HOST:-'(nie ustawione)'}"
echo "   SOURCE_DB_USER: ${SOURCE_DB_USER:-'(nie ustawione)'}"
echo "   TARGET_DB_USER: ${TARGET_DB_USER:-'(nie ustawione)'}"
echo "   MIGRATION_BATCH_SIZE: ${MIGRATION_BATCH_SIZE:-'(nie ustawione)'}"
echo "   BACKUP_PATH: ${BACKUP_PATH:-'(nie ustawione)'}"
echo "   BACKUP_RETENTION_DAYS: ${BACKUP_RETENTION_DAYS:-'(nie ustawione)'}"

echo ""
echo -e "${GREEN}✅ Test konfiguracji zakończony${NC}"
echo ""
echo -e "${YELLOW}💡 Przykłady użycia:${NC}"
echo "   $0 -s PROD_DB -t TEST_DB"
echo "   $0 --source-host prod.server.com --target-host localhost"
echo "   $0 -b 5000 -s MySource -t MyTarget"
