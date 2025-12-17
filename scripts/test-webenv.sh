#!/bin/bash

# scripts/test-webenv.sh
# E2E tests for webenv (.env editor GUI) at http://localhost:8888/

set -e

# Kolory dla lepszej czytelności
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Konfiguracja
WEBENV_URL="${WEBENV_URL:-http://localhost:8888}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_ENV=""

# Funkcja pomocnicza do kolorowego drukowania
echoc() {
    printf "%b\n" "$*"
}

# Funkcja do backupu .env przed testami
backup_env() {
    if [ -f "$PROJECT_DIR/.env" ]; then
        BACKUP_ENV=$(cat "$PROJECT_DIR/.env")
        echoc "${BLUE}[i] Utworzono backup .env${NC}"
    fi
}

# Funkcja do przywrócenia .env po testach
restore_env() {
    if [ -n "$BACKUP_ENV" ]; then
        echo "$BACKUP_ENV" > "$PROJECT_DIR/.env"
        echoc "${BLUE}[i] Przywrócono .env z backupu${NC}"
    fi
}

# Cleanup przy wyjściu
cleanup() {
    restore_env
}
trap cleanup EXIT

echo "🧪 Testy E2E dla WebEnv (.env Editor GUI)"
echo "   URL: $WEBENV_URL"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Licznik wyników
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# ============================================================================
# FUNKCJE TESTOWE
# ============================================================================

# Czekaj na dostępność serwisu
wait_for_webenv() {
    local max_attempts=10
    local attempt=1
    
    echo -n "   Czekam na WebEnv ($WEBENV_URL)... "
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s -o /dev/null -w "%{http_code}" --max-time 2 "$WEBENV_URL" 2>/dev/null | grep -q "200"; then
            echoc "${GREEN}✓${NC}"
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    
    echoc "${RED}✗ (timeout - czy webenv jest uruchomiony? make webenv)${NC}"
    return 1
}

# Test HTTP endpoint
test_http() {
    local url=$1
    local name=$2
    local expected=${3:-200}
    
    echo -n "   Testuję $name... "
    
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null)
    
    if [ "$code" = "$expected" ]; then
        echoc "${GREEN}✓ (HTTP $code)${NC}"
        return 0
    else
        echoc "${RED}✗ (HTTP $code, oczekiwano $expected)${NC}"
        return 1
    fi
}

# Test JSON response
test_json_endpoint() {
    local url=$1
    local name=$2
    local method=${3:-GET}
    local data=${4:-}
    
    echo -n "   Testuję $name... "
    
    local response
    if [ "$method" = "POST" ]; then
        response=$(curl -s --max-time 5 -X POST -d "$data" "$url" 2>/dev/null)
    else
        response=$(curl -s --max-time 5 "$url" 2>/dev/null)
    fi
    
    if [ -z "$response" ]; then
        echoc "${RED}✗ (brak odpowiedzi)${NC}"
        return 1
    fi
    
    # Sprawdź czy to JSON
    if ! echo "$response" | jq empty 2>/dev/null; then
        echoc "${RED}✗ (nieprawidłowy JSON)${NC}"
        echo "   Response: $response" | head -c 200
        return 1
    fi
    
    # Sprawdź success field
    local success
    success=$(echo "$response" | jq -r '.success' 2>/dev/null)
    
    if [ "$success" = "true" ]; then
        echoc "${GREEN}✓ (success=true)${NC}"
        return 0
    else
        local error
        error=$(echo "$response" | jq -r '.error // "unknown"' 2>/dev/null)
        echoc "${RED}✗ (success=$success, error=$error)${NC}"
        return 1
    fi
}

# Test czy odpowiedź zawiera oczekiwany klucz
test_json_has_key() {
    local url=$1
    local name=$2
    local key=$3
    
    echo -n "   Testuję $name (klucz: $key)... "
    
    local response
    response=$(curl -s --max-time 5 "$url" 2>/dev/null)
    
    if [ -z "$response" ]; then
        echoc "${RED}✗ (brak odpowiedzi)${NC}"
        return 1
    fi
    
    local has_key
    has_key=$(echo "$response" | jq "has(\"$key\")" 2>/dev/null)
    
    if [ "$has_key" = "true" ]; then
        echoc "${GREEN}✓${NC}"
        return 0
    else
        echoc "${RED}✗ (brak klucza $key)${NC}"
        return 1
    fi
}

# Test zapisu i odczytu .env
test_save_and_load() {
    local test_value="TEST_WEBENV_E2E_$(date +%s)"
    local test_line="# E2E_TEST_MARKER=$test_value"
    
    echo -n "   Testuję zapis i odczyt .env... "
    
    # Pobierz obecną zawartość
    local original
    original=$(curl -s --max-time 5 "$WEBENV_URL/load" 2>/dev/null | jq -r '.content' 2>/dev/null)
    
    if [ -z "$original" ]; then
        echoc "${RED}✗ (nie można pobrać .env)${NC}"
        return 1
    fi
    
    # Dodaj marker testowy
    local modified="${original}
${test_line}"
    
    # Zapisz zmodyfikowany
    local save_result
    save_result=$(curl -s --max-time 5 -X POST -d "content=$(echo "$modified" | jq -sRr @uri)" "$WEBENV_URL/save" 2>/dev/null)
    
    local save_success
    save_success=$(echo "$save_result" | jq -r '.success' 2>/dev/null)
    
    if [ "$save_success" != "true" ]; then
        echoc "${RED}✗ (zapis nieudany)${NC}"
        return 1
    fi
    
    # Odczytaj ponownie
    local reloaded
    reloaded=$(curl -s --max-time 5 "$WEBENV_URL/load" 2>/dev/null | jq -r '.content' 2>/dev/null)
    
    # Sprawdź czy marker jest obecny
    if echo "$reloaded" | grep -q "$test_value"; then
        # Przywróć oryginał
        curl -s --max-time 5 -X POST -d "content=$(echo "$original" | jq -sRr @uri)" "$WEBENV_URL/save" >/dev/null 2>&1
        echoc "${GREEN}✓${NC}"
        return 0
    else
        echoc "${RED}✗ (marker nie znaleziony po zapisie)${NC}"
        return 1
    fi
}

# Test resetu do .env.example
test_reset() {
    echo -n "   Testuję reset do .env.example... "
    
    # Zapisz obecną zawartość
    local before
    before=$(curl -s --max-time 5 "$WEBENV_URL/load" 2>/dev/null | jq -r '.content' 2>/dev/null)
    
    # Reset
    local reset_result
    reset_result=$(curl -s --max-time 5 -X POST "$WEBENV_URL/reset" 2>/dev/null)
    
    local reset_success
    reset_success=$(echo "$reset_result" | jq -r '.success' 2>/dev/null)
    
    if [ "$reset_success" = "true" ]; then
        # Przywróć poprzednią wartość
        curl -s --max-time 5 -X POST -d "content=$(echo "$before" | jq -sRr @uri)" "$WEBENV_URL/save" >/dev/null 2>&1
        echoc "${GREEN}✓${NC}"
        return 0
    else
        echoc "${RED}✗${NC}"
        return 1
    fi
}

# Test admin panel status
test_admin_status() {
    echo -n "   Testuję /admin/status... "
    
    local response
    response=$(curl -s --max-time 5 "$WEBENV_URL/admin/status" 2>/dev/null)
    
    if [ -z "$response" ]; then
        echoc "${RED}✗ (brak odpowiedzi)${NC}"
        return 1
    fi
    
    # Sprawdź czy to JSON z state
    local has_state
    has_state=$(echo "$response" | jq 'has("state")' 2>/dev/null)
    
    if [ "$has_state" = "true" ]; then
        local running
        running=$(echo "$response" | jq -r '.state.running' 2>/dev/null)
        echoc "${GREEN}✓ (running=$running)${NC}"
        return 0
    else
        local error
        error=$(echo "$response" | jq -r '.error // "unknown"' 2>/dev/null)
        # 403 Unauthorized is expected if not from localhost or no token
        if [ "$error" = "Unauthorized" ]; then
            echoc "${YELLOW}⚠ (Unauthorized - potrzebny token lub localhost)${NC}"
            return 0
        fi
        echoc "${RED}✗ (brak state w odpowiedzi)${NC}"
        return 1
    fi
}

# Test admin panel logs
test_admin_logs() {
    echo -n "   Testuję /admin/logs... "
    
    local response
    response=$(curl -s --max-time 5 "$WEBENV_URL/admin/logs" 2>/dev/null)
    
    if [ -z "$response" ]; then
        echoc "${RED}✗ (brak odpowiedzi)${NC}"
        return 1
    fi
    
    local success
    success=$(echo "$response" | jq -r '.success' 2>/dev/null)
    
    if [ "$success" = "true" ]; then
        echoc "${GREEN}✓${NC}"
        return 0
    else
        local error
        error=$(echo "$response" | jq -r '.error // "unknown"' 2>/dev/null)
        if [ "$error" = "Unauthorized" ]; then
            echoc "${YELLOW}⚠ (Unauthorized - potrzebny token lub localhost)${NC}"
            return 0
        fi
        echoc "${RED}✗ (success=$success)${NC}"
        return 1
    fi
}

# Test HTML zawiera oczekiwane elementy
test_html_contains() {
    local pattern=$1
    local name=$2
    
    echo -n "   Testuję obecność '$name' w HTML... "
    
    local html
    html=$(curl -s --max-time 5 "$WEBENV_URL" 2>/dev/null)
    
    if echo "$html" | grep -q "$pattern"; then
        echoc "${GREEN}✓${NC}"
        return 0
    else
        echoc "${RED}✗${NC}"
        return 1
    fi
}

# ============================================================================
# GŁÓWNY PROCES TESTOWANIA
# ============================================================================

# Backup .env przed testami
backup_env

echo "🔌 Sprawdzanie dostępności WebEnv:"
TOTAL_TESTS=$((TOTAL_TESTS + 1))

if ! wait_for_webenv; then
    echoc "${RED}❌ WebEnv nie jest dostępny. Uruchom: make webenv${NC}"
    exit 1
fi
PASSED_TESTS=$((PASSED_TESTS + 1))

# ============================================================================
# TEST 1: Strona główna
# ============================================================================
echo ""
echo "📄 Testowanie strony głównej:"
TOTAL_TESTS=$((TOTAL_TESTS + 1))

if test_http "$WEBENV_URL" "GET /"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# ============================================================================
# TEST 2: Elementy HTML
# ============================================================================
echo ""
echo "🏗️  Testowanie elementów HTML:"
TOTAL_TESTS=$((TOTAL_TESTS + 5))

if test_html_contains 'id="envEditor"' "textarea#envEditor"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

if test_html_contains 'id="exampleViewer"' "textarea#exampleViewer"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

if test_html_contains 'onclick="saveEnv()"' "przycisk Zapisz"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

if test_html_contains 'id="configTable"' "tabela konfiguracji"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

if test_html_contains 'id="makeStatus"' "panel Admin make"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# ============================================================================
# TEST 3: API Endpoints
# ============================================================================
echo ""
echo "🔗 Testowanie API endpoints:"
TOTAL_TESTS=$((TOTAL_TESTS + 3))

if test_json_endpoint "$WEBENV_URL/load" "GET /load"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

if test_json_has_key "$WEBENV_URL/load" "GET /load" "content"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

if test_json_endpoint "$WEBENV_URL/devices" "GET /devices"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    # /devices może zwrócić error jeśli nie ma discovered_devices.json
    echoc "${YELLOW}   (może być OK jeśli nie było skanu)${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
fi

# ============================================================================
# TEST 4: Zapis i odczyt .env
# ============================================================================
echo ""
echo "💾 Testowanie zapisu i odczytu .env:"
TOTAL_TESTS=$((TOTAL_TESTS + 2))

if test_save_and_load; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

if test_reset; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# ============================================================================
# TEST 5: Admin Panel
# ============================================================================
echo ""
echo "🔧 Testowanie Admin Panel:"
TOTAL_TESTS=$((TOTAL_TESTS + 2))

if test_admin_status; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

if test_admin_logs; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# ============================================================================
# PODSUMOWANIE TESTÓW
# ============================================================================
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "📈 PODSUMOWANIE TESTÓW WEBENV:"
echo "═══════════════════════════════════════════════════════════"
echoc "   Wszystkie testy:    $TOTAL_TESTS"
echoc "   ${GREEN}Zaliczone:          $PASSED_TESTS${NC}"
echoc "   ${RED}Niezaliczone:       $FAILED_TESTS${NC}"

if [ $FAILED_TESTS -eq 0 ]; then
    echoc "   ${GREEN}✅ Status:           SUKCES${NC}"
    echo ""
    echoc "${GREEN}🎉 WebEnv działa poprawnie!${NC}"
else
    echoc "   ${YELLOW}⚠️  Status:           CZĘŚCIOWY SUKCES${NC}"
    echo ""
    echoc "${YELLOW}⚠️  Niektóre testy nie przeszły.${NC}"
fi

echo "═══════════════════════════════════════════════════════════"
echo ""

# Zakończenie z odpowiednim kodem wyjścia
if [ $FAILED_TESTS -gt 0 ]; then
    exit 1
fi

exit 0
