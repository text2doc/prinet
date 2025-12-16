#!/bin/bash
# scripts/start.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Przejdz do katalogu projektu
cd "$PROJECT_DIR"

# Kolory dla lepszej czytelności
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funkcja pomocnicza do kolorowego drukowania (zamiennik echoc)
echoc() {
    printf "%b\n" "$*"
}

echo "[*] Uruchamianie WAPRO Network Mock..."
echo "[i] Katalog: $PROJECT_DIR"

# Funkcja naprawy Docker
fix_docker_quick() {
    # Czy Docker daemon dziala?
    if ! docker info &>/dev/null 2>&1; then
        # Sprobuj z sudo
        if sudo docker info &>/dev/null 2>&1; then
            echoc "${YELLOW}[!] Docker wymaga sudo - uruchamiam z sudo...${NC}"
            USE_SUDO="sudo"
        else
            # Sprobuj uruchomic daemon
            echoc "${YELLOW}[!] Docker daemon nie dziala - probuje uruchomic...${NC}"
            sudo systemctl start docker 2>/dev/null || sudo service docker start 2>/dev/null || true
            sleep 2
            
            if docker info &>/dev/null 2>&1; then
                USE_SUDO=""
            elif sudo docker info &>/dev/null 2>&1; then
                USE_SUDO="sudo"
            else
                echoc "${RED}[X] Nie mozna uruchomic Docker${NC}"
                echoc "${YELLOW}[!] Sprawdz: sudo systemctl status docker${NC}"
                exit 1
            fi
        fi
    else
        USE_SUDO=""
    fi
}

# Sprawdzenie konfiguracji
if [ ! -f .env ]; then
    echoc "${RED}[X] Brak pliku .env - uruchom 'make setup' najpierw${NC}"
    exit 1
fi

# Napraw Docker jesli potrzeba
fix_docker_quick

# Załaduj zmienne z .env
set -a
source .env 2>/dev/null || true
set +a

# Preflight checks: docker/compose availability, port occupancy
preflight() {
    echoc "${BLUE}[i] Preflight: sprawdzam srodowisko...${NC}"
    if ! $USE_SUDO docker info >/dev/null 2>&1; then
        echoc "${RED}[X] Docker nie jest uruchomiony${NC}"; exit 1; fi
    if ! $USE_SUDO docker-compose version >/dev/null 2>&1; then
        echoc "${RED}[X] Brak docker-compose w PATH${NC}"; exit 1; fi
    if ! $USE_SUDO docker-compose config >/dev/null 2>&1; then
        echoc "${RED}[X] Blad walidacji docker-compose.yml${NC}"; exit 1; fi
    if [ -n "${COMPOSE_BAKE}" ]; then
        echoc "${GREEN}[i] COMPOSE_BAKE=${COMPOSE_BAKE}${NC}"
    fi
    if command -v ss >/dev/null 2>&1; then
        echoc "${BLUE}[i] Otwarte porty docelowe:${NC}"
        ss -lnt | awk 'NR==1 || /:(8080|8081|8091|8092|9100|9101|1433|3000)\s/' || true
    fi
}

preflight

# Uruchomienie wszystkich serwisów
echo "[*] Uruchamianie kontenerow..."

# Uzyj profilu full jesli nie ustawiono innego
COMPOSE_PROFILES="${COMPOSE_PROFILES:-full}"
export COMPOSE_PROFILES

$USE_SUDO docker-compose --profile full up -d

# Sprawdzenie statusu
echo "[i] Status serwisow:"
$USE_SUDO docker-compose --profile full ps

echo ""
echo "[.] Oczekiwanie na uruchomienie serwisów..."

# ============================================================================
# FUNKCJE TESTOWE E2E
# ============================================================================

# Funkcja pomocnicza do czekania na dostępność portu
wait_for_service() {
    local host=$1
    local port=$2
    local service_name=$3
    local max_attempts=30
    local attempt=1
    
    echo -n "   Czekam na $service_name ($host:$port)... "
    
    while [ $attempt -le $max_attempts ]; do
        if nc -z -w 2 $host $port 2>/dev/null; then
            echoc "${GREEN}[+]${NC}"
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    
    echoc "${RED}[-] (timeout)${NC}"
    # Debug logs for common services
    case "$service_name" in
        "RPI GUI Port"|"RPI API Port") docker-compose logs --tail 80 rpi-server || true ;;
        "MSSQL Server Port") docker-compose logs --tail 80 mssql-wapromag || true ;;
        "ZEBRA Printer 1"*|"ZEBRA Printer 1 ZPL Socket") docker-compose logs --tail 80 zebra-printer-1 || true ;;
        "ZEBRA Printer 2"*|"ZEBRA Printer 2 ZPL Socket") docker-compose logs --tail 80 zebra-printer-2 || true ;;
    esac
    return 1
}

# Test HTTP endpoint
test_http_endpoint() {
    local url=$1
    local service_name=$2
    local expected_status=${3:-200}
    
    echo -n "   Testuję $service_name ($url)... "
    
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null)
    
    # Jeśli curl się nie powiódł, ustaw kod na 000
    if [ -z "$http_code" ] || [ "$http_code" = "000" ]; then
        http_code="000"
    fi
    
    if [ "$http_code" = "$expected_status" ]; then
        echoc "${GREEN}[+] (HTTP $http_code)${NC}"
        return 0
    else
        echoc "${RED}[-] (HTTP $http_code, oczekiwano $expected_status)${NC}"
        echoc "${YELLOW}— Debug (${service_name}) response headers:${NC}"
        curl -sI --max-time 5 "$url" 2>/dev/null | sed 's/^/     /'
        echoc "${YELLOW}— Debug (${service_name}) last log lines:${NC}"
        case "$service_name" in
            *RPI* ) docker-compose logs --tail 80 rpi-server || true ;;
            *MSSQL* ) docker-compose logs --tail 80 mssql-wapromag || true ;;
            *ZEBRA*1* ) docker-compose logs --tail 80 zebra-printer-1 || true ;;
            *ZEBRA*2* ) docker-compose logs --tail 80 zebra-printer-2 || true ;;
        esac
        return 1
    fi
}

# Test TCP socket (dla drukarek ZEBRA)
test_tcp_socket() {
    local host=$1
    local port=$2
    local service_name=$3
    
    echo -n "   Testuję $service_name socket ($host:$port)... "
    
    if printf "\n" | nc -w 2 $host $port 2>/dev/null; then
        echoc "${GREEN}[+]${NC}"
        return 0
    else
        echoc "${RED}[-]${NC}"
        return 1
    fi
}

# Test MSSQL Server
test_mssql() {
    local service_name="MSSQL WAPROMAG"
    echo -n "   Testuję $service_name... "
    
    # Sprawdzenie czy kontener działa (obsługa zarówno mssql-tools jak i mssql-tools18)
    if docker exec wapromag-mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "WapromagPass123!" -Q "SELECT 1" -C &>/dev/null; then
        echoc "${GREEN}[+]${NC}"
        return 0
    elif docker exec wapromag-mssql /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "WapromagPass123!" -Q "SELECT 1" &>/dev/null; then
        echoc "${GREEN}[+]${NC}"
        return 0
    else
        echoc "${RED}[-]${NC}"
        return 1
    fi
}

# Test API endpoint z JSONem
test_api_endpoint() {
    local url=$1
    local service_name=$2
    
    echo -n "   Testuję $service_name API ($url)... "
    
    response=$(curl -s --max-time 5 "$url" 2>/dev/null || echo "")
    
    if [ -n "$response" ]; then
        # Sprawdzenie czy odpowiedź wygląda jak JSON
        if echo "$response" | jq empty 2>/dev/null; then
            echoc "${GREEN}[+] (valid JSON)${NC}"
            return 0
        else
            echoc "${YELLOW}⚠ (not JSON)${NC}"
            return 0
        fi
    else
        echoc "${RED}[-] (no response)${NC}"
        return 1
    fi
}

# Test kompletności drukarki ZEBRA
test_zebra_printer() {
    local web_port=$1
    local socket_port=$2
    local printer_name=$3
    local success=0
    
    echo "[P]  Testowanie $printer_name:"
    
    # Test interfejsu web
    if test_http_endpoint "http://localhost:$web_port" "$printer_name Web UI"; then
        success=$((success + 1))
    fi
    
    # Test socketu ZPL
    if test_tcp_socket "localhost" "$socket_port" "$printer_name ZPL Socket"; then
        success=$((success + 1))
    fi
    
    # Test API status
    if test_api_endpoint "http://localhost:$web_port/api/status" "$printer_name Status"; then
        success=$((success + 1))
    fi
    
    if [ $success -eq 3 ]; then
        echoc "   ${GREEN}[OK] Wszystkie testy przeszły pomyślnie${NC}"
        return 0
    else
        echoc "   ${YELLOW}[!]  Przeszło $success/3 testów${NC}"
        return 1
    fi
}

# ============================================================================
# GŁÓWNY PROCES TESTOWANIA
# ============================================================================

echo ""
echo "[T] Rozpoczynam testy E2E wszystkich usług..."
echo "═══════════════════════════════════════════════════════════"

# Licznik wyników
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# ============================================================================
# TEST 1: MSSQL WAPROMAG
# ============================================================================
echo ""
echo "[D] Testowanie MSSQL WAPROMAG Database:"
TOTAL_TESTS=$((TOTAL_TESTS + 2))

if wait_for_service "localhost" "1433" "MSSQL Server Port"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

sleep 2

if test_mssql; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# ============================================================================
# TEST 2: RPI SERVER
# ============================================================================
echo ""
echo "[S]  Testowanie RPI Mock Server:"
TOTAL_TESTS=$((TOTAL_TESTS + 4))

# Porty z .env lub domyślne
RPI_GUI_PORT=${RPI_GUI_EXTERNAL_PORT:-8082}
RPI_API_PORT=${RPI_API_EXTERNAL_PORT:-8081}

if wait_for_service "localhost" "$RPI_GUI_PORT" "RPI GUI Port"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

if wait_for_service "localhost" "$RPI_API_PORT" "RPI API Port"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

if test_http_endpoint "http://localhost:$RPI_GUI_PORT" "RPI GUI Interface"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

if test_http_endpoint "http://localhost:$RPI_API_PORT/health" "RPI API Health"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# ============================================================================
# TEST 3: ZEBRA PRINTER 1
# ============================================================================
echo ""
TOTAL_TESTS=$((TOTAL_TESTS + 3))
if test_zebra_printer "8091" "9100" "ZEBRA Printer 1"; then
    PASSED_TESTS=$((PASSED_TESTS + 3))
else
    # Funkcja już liczy ile testów przeszło - policz ręcznie dla częściowych sukcesów
    printer1_web=0
    printer1_socket=0
    printer1_api=0
    
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:8091 2>/dev/null | grep -q "200"; then
        printer1_web=1
    fi
    
    if printf "\n" | nc -w 2 localhost 9100 2>/dev/null; then
        printer1_socket=1
    fi
    
    if curl -s http://localhost:8091/api/status 2>/dev/null | jq empty 2>/dev/null; then
        printer1_api=1
    fi
    
    partial=$((printer1_web + printer1_socket + printer1_api))
    PASSED_TESTS=$((PASSED_TESTS + partial))
    FAILED_TESTS=$((FAILED_TESTS + 3 - partial))
fi

# ============================================================================
# TEST 4: ZEBRA PRINTER 2
# ============================================================================
echo ""
TOTAL_TESTS=$((TOTAL_TESTS + 3))
if test_zebra_printer "8092" "9101" "ZEBRA Printer 2"; then
    PASSED_TESTS=$((PASSED_TESTS + 3))
else
    # Funkcja już liczy ile testów przeszło - policz ręcznie dla częściowych sukcesów
    printer2_web=0
    printer2_socket=0
    printer2_api=0
    
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:8092 2>/dev/null | grep -q "200"; then
        printer2_web=1
    fi
    
    if printf "\n" | nc -w 2 localhost 9101 2>/dev/null; then
        printer2_socket=1
    fi
    
    if curl -s http://localhost:8092/api/status 2>/dev/null | jq empty 2>/dev/null; then
        printer2_api=1
    fi
    
    partial=$((printer2_web + printer2_socket + printer2_api))
    PASSED_TESTS=$((PASSED_TESTS + partial))
    FAILED_TESTS=$((FAILED_TESTS + 3 - partial))
fi

# ============================================================================
# TEST 5: MONITORING (jeśli uruchomione)
# ============================================================================
echo ""
echo "[i] Testowanie Monitoring Services (opcjonalne):"

if docker ps --format '{{.Names}}' | grep -q "wapro-grafana"; then
    echo "   Wykryto uruchomioną Grafanę..."
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if test_http_endpoint "http://localhost:3000" "Grafana Dashboard" "302"; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
fi

if docker ps --format '{{.Names}}' | grep -q "wapro-prometheus"; then
    echo "   Wykryto uruchomiony Prometheus..."
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if test_http_endpoint "http://localhost:9090" "Prometheus"; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
fi

# ============================================================================
# PODSUMOWANIE TESTÓW
# ============================================================================
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "📈 PODSUMOWANIE TESTÓW E2E:"
echo "═══════════════════════════════════════════════════════════"
echoc "   Wszystkie testy:    $TOTAL_TESTS"
echoc "   ${GREEN}Zaliczone:          $PASSED_TESTS${NC}"
echoc "   ${RED}Niezaliczone:       $FAILED_TESTS${NC}"

if [ $FAILED_TESTS -eq 0 ]; then
    echoc "   ${GREEN}[OK] Status:           SUKCES${NC}"
else
    echoc "   ${YELLOW}[!]  Status:           CZĘŚCIOWY SUKCES${NC}"
fi

echo "═══════════════════════════════════════════════════════════"

# ============================================================================
# INFORMACJE O DOSTĘPNYCH INTERFEJSACH
# ============================================================================
echo ""
echo "[i] Dostępne interfejsy:"
echo "   RPI Server GUI:      http://localhost:${RPI_GUI_EXTERNAL_PORT:-8082}"
echo "   RPI Server API:      http://localhost:${RPI_API_EXTERNAL_PORT:-8081}"
echo "   ZEBRA Printer 1:     http://localhost:${ZEBRA_1_EXTERNAL_WEB_PORT:-8091}"
echo "   ZEBRA Printer 2:     http://localhost:${ZEBRA_2_EXTERNAL_WEB_PORT:-8092}"
echo "   Monitoring:          http://localhost:${GRAFANA_PORT:-3000}"
echo "   MSSQL WAPROMAG:      localhost:${MSSQL_EXTERNAL_PORT:-1433}"

echo ""
if [ $FAILED_TESTS -eq 0 ]; then
    echoc "${GREEN}[OK] Środowisko uruchomione i przetestowane pomyślnie!${NC}"
else
    echoc "${YELLOW}[!]  Środowisko uruchomione z ostrzeżeniami (niektóre testy nie przeszły)${NC}"
    echoc "${YELLOW}[i] Sprawdź logi usług, które nie przeszły testów: docker-compose logs <service_name>${NC}"
fi

echo "[i] Sprawdź wszystkie logi: docker-compose logs -f"
echo ""

# Zakończenie z odpowiednim kodem wyjścia
if [ $FAILED_TESTS -gt 0 ]; then
    exit 1
fi

exit 0
