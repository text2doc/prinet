#!/bin/bash
# scripts/discover.sh
# Wykrywanie urzadzen sieciowych dla WAPRO Network Mock
# Wykrywa: drukarki Zebra, serwery MSSQL, inne uslugi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Kolory
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Konfiguracja
TIMEOUT=1
SCAN_TIMEOUT=2
RESULTS_FILE="$PROJECT_DIR/logs/discovered_devices.json"

# Porty do skanowania
ZEBRA_PORTS="9100 6101"
MSSQL_PORT="1433"
HTTP_PORTS="80 8080 8081 8082 8091 8092"

echo ""
echo -e "${BOLD}${BLUE}============================================================${NC}"
echo -e "${BOLD}${BLUE}     WAPRO Network Mock - Wykrywanie urzadzen${NC}"
echo -e "${BOLD}${BLUE}============================================================${NC}"
echo ""

# Wykryj interfejsy sieciowe i zakresy IP
detect_network() {
    echo -e "${BLUE}[i]${NC} Wykrywanie sieci lokalnej..."
    
    # Pobierz adresy IP i maski
    if command -v ip &>/dev/null; then
        LOCAL_IPS=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+' | grep -v '^127\.')
    elif command -v ifconfig &>/dev/null; then
        LOCAL_IPS=$(ifconfig | grep -oE 'inet (addr:)?([0-9]+\.){3}[0-9]+' | grep -oE '([0-9]+\.){3}[0-9]+' | grep -v '^127\.')
    else
        echo -e "  ${RED}[X]${NC} Brak narzedzi do wykrywania sieci (ip/ifconfig)"
        return 1
    fi
    
    echo -e "  ${GREEN}[+]${NC} Lokalne adresy IP:"
    for ip in $LOCAL_IPS; do
        echo -e "      $ip"
    done
    echo ""
}

# Pobierz zakres sieci do skanowania
get_network_range() {
    local ip=$1
    # Wyciagnij pierwsze 3 oktety
    echo "$ip" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' 
}

# Skanuj pojedynczy host:port
scan_port() {
    local host=$1
    local port=$2
    local timeout=${3:-$TIMEOUT}
    
    if command -v nc &>/dev/null; then
        nc -z -w $timeout "$host" "$port" 2>/dev/null
        return $?
    elif command -v timeout &>/dev/null; then
        timeout $timeout bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null
        return $?
    else
        return 1
    fi
}

# Wykryj drukarki Zebra (port 9100)
discover_zebra_printers() {
    echo -e "${BLUE}[i]${NC} Szukam drukarek Zebra (porty: $ZEBRA_PORTS)..."
    
    local found=0
    local printers=()
    
    # Pobierz zakres sieci
    for local_ip in $LOCAL_IPS; do
        local network=$(get_network_range "$local_ip")
        if [ -z "$network" ]; then continue; fi
        
        echo -e "  ${CYAN}[-]${NC} Skanuje siec: ${network}.0/24"
        
        # Skanuj popularne adresy (1-50, 100-150, 200-254)
        for i in $(seq 1 50) $(seq 100 150) $(seq 200 254); do
            local host="${network}.${i}"
            
            for port in $ZEBRA_PORTS; do
                if scan_port "$host" "$port" $SCAN_TIMEOUT 2>/dev/null; then
                    echo -e "  ${GREEN}[+]${NC} Znaleziono drukarka: ${BOLD}$host:$port${NC}"
                    printers+=("$host:$port")
                    ((found++))
                fi
            done
        done &
    done
    wait
    
    if [ $found -eq 0 ]; then
        echo -e "  ${YELLOW}[!]${NC} Nie znaleziono drukarek Zebra"
    else
        echo -e "  ${GREEN}[+]${NC} Znaleziono $found drukarek"
    fi
    
    DISCOVERED_PRINTERS=("${printers[@]}")
    echo ""
}

# Wykryj serwery MSSQL (port 1433)
discover_mssql_servers() {
    echo -e "${BLUE}[i]${NC} Szukam serwerow MSSQL (port: $MSSQL_PORT)..."
    
    local found=0
    local servers=()
    
    for local_ip in $LOCAL_IPS; do
        local network=$(get_network_range "$local_ip")
        if [ -z "$network" ]; then continue; fi
        
        echo -e "  ${CYAN}[-]${NC} Skanuje siec: ${network}.0/24"
        
        for i in $(seq 1 50) $(seq 100 150) $(seq 200 254); do
            local host="${network}.${i}"
            
            if scan_port "$host" "$MSSQL_PORT" $SCAN_TIMEOUT 2>/dev/null; then
                echo -e "  ${GREEN}[+]${NC} Znaleziono MSSQL: ${BOLD}$host:$MSSQL_PORT${NC}"
                servers+=("$host:$MSSQL_PORT")
                ((found++))
            fi
        done &
    done
    wait
    
    if [ $found -eq 0 ]; then
        echo -e "  ${YELLOW}[!]${NC} Nie znaleziono serwerow MSSQL"
    else
        echo -e "  ${GREEN}[+]${NC} Znaleziono $found serwerow"
    fi
    
    DISCOVERED_MSSQL=("${servers[@]}")
    echo ""
}

# Wykryj serwisy HTTP
discover_http_services() {
    echo -e "${BLUE}[i]${NC} Szukam serwisow HTTP (porty: $HTTP_PORTS)..."
    
    local found=0
    
    for local_ip in $LOCAL_IPS; do
        local network=$(get_network_range "$local_ip")
        if [ -z "$network" ]; then continue; fi
        
        echo -e "  ${CYAN}[-]${NC} Skanuje siec: ${network}.0/24"
        
        for i in $(seq 1 50) $(seq 100 150) $(seq 200 254); do
            local host="${network}.${i}"
            
            for port in $HTTP_PORTS; do
                if scan_port "$host" "$port" $SCAN_TIMEOUT 2>/dev/null; then
                    # Sprobuj pobrac tytul strony
                    local title=""
                    if command -v curl &>/dev/null; then
                        title=$(curl -s --connect-timeout 2 "http://$host:$port/" 2>/dev/null | grep -oP '(?<=<title>)[^<]+' | head -1)
                    fi
                    
                    if [ -n "$title" ]; then
                        echo -e "  ${GREEN}[+]${NC} HTTP: ${BOLD}$host:$port${NC} - $title"
                    else
                        echo -e "  ${GREEN}[+]${NC} HTTP: ${BOLD}$host:$port${NC}"
                    fi
                    ((found++))
                fi
            done
        done &
    done
    wait
    
    if [ $found -eq 0 ]; then
        echo -e "  ${YELLOW}[!]${NC} Nie znaleziono serwisow HTTP"
    fi
    echo ""
}

# Szybkie skanowanie - tylko popularne adresy
quick_scan() {
    echo -e "${BLUE}[i]${NC} Szybkie skanowanie (popularne adresy)..."
    
    local common_hosts=""
    
    for local_ip in $LOCAL_IPS; do
        local network=$(get_network_range "$local_ip")
        if [ -z "$network" ]; then continue; fi
        
        # Popularne adresy: .1, .10, .50, .100, .200, .254
        for i in 1 10 50 100 200 254; do
            common_hosts="$common_hosts ${network}.${i}"
        done
    done
    
    echo ""
    echo -e "${BOLD}Drukarki Zebra (9100):${NC}"
    for host in $common_hosts; do
        if scan_port "$host" 9100 $TIMEOUT 2>/dev/null; then
            echo -e "  ${GREEN}[+]${NC} $host:9100"
        fi
    done
    
    echo ""
    echo -e "${BOLD}Serwery MSSQL (1433):${NC}"
    for host in $common_hosts; do
        if scan_port "$host" 1433 $TIMEOUT 2>/dev/null; then
            echo -e "  ${GREEN}[+]${NC} $host:1433"
        fi
    done
    
    echo ""
}

# Generuj konfiguracje .env
generate_env_config() {
    echo -e "${BLUE}[i]${NC} Generowanie konfiguracji..."
    
    echo ""
    echo -e "${BOLD}${GREEN}Przykladowa konfiguracja .env:${NC}"
    echo -e "${CYAN}----------------------------------------${NC}"
    
    local printer_num=1
    for printer in "${DISCOVERED_PRINTERS[@]}"; do
        local host=$(echo "$printer" | cut -d: -f1)
        local port=$(echo "$printer" | cut -d: -f2)
        echo -e "# Drukarka Zebra $printer_num"
        echo -e "ZEBRA_${printer_num}_HOST=$host"
        echo -e "ZEBRA_${printer_num}_PORT=$port"
        echo -e "ZEBRA_${printer_num}_ENABLED=false  # Uzyj zewnetrznej drukarki"
        echo ""
        ((printer_num++))
    done
    
    for server in "${DISCOVERED_MSSQL[@]}"; do
        local host=$(echo "$server" | cut -d: -f1)
        echo -e "# Serwer MSSQL"
        echo -e "MSSQL_HOST=$host"
        echo -e "MSSQL_PORT=1433"
        echo -e "MSSQL_ENABLED=false  # Uzyj zewnetrznego serwera"
        echo ""
    done
    
    echo -e "${CYAN}----------------------------------------${NC}"
    echo ""
}

# Zapisz wyniki do JSON
save_results() {
    mkdir -p "$(dirname "$RESULTS_FILE")"
    
    cat > "$RESULTS_FILE" << EOF
{
  "scan_date": "$(date -Iseconds)",
  "local_ips": [$(echo "$LOCAL_IPS" | tr '\n' ',' | sed 's/,$//' | sed 's/,/", "/g' | sed 's/^/"/' | sed 's/$/"/')],
  "printers": [$(printf '"%s",' "${DISCOVERED_PRINTERS[@]}" | sed 's/,$//')],
  "mssql_servers": [$(printf '"%s",' "${DISCOVERED_MSSQL[@]}" | sed 's/,$//')]
}
EOF
    
    echo -e "${GREEN}[+]${NC} Wyniki zapisane do: $RESULTS_FILE"
}

# Pomoc
show_help() {
    echo "Uzycie: $0 [opcje]"
    echo ""
    echo "Opcje:"
    echo "  -q, --quick     Szybkie skanowanie (tylko popularne adresy)"
    echo "  -f, --full      Pelne skanowanie sieci"
    echo "  -p, --printers  Szukaj tylko drukarek"
    echo "  -m, --mssql     Szukaj tylko serwerow MSSQL"
    echo "  -h, --help      Pokaz pomoc"
    echo ""
}

# Glowna funkcja
main() {
    local mode="quick"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -q|--quick) mode="quick"; shift ;;
            -f|--full) mode="full"; shift ;;
            -p|--printers) mode="printers"; shift ;;
            -m|--mssql) mode="mssql"; shift ;;
            -h|--help) show_help; exit 0 ;;
            *) shift ;;
        esac
    done
    
    detect_network
    
    case $mode in
        quick)
            quick_scan
            ;;
        full)
            discover_zebra_printers
            discover_mssql_servers
            discover_http_services
            generate_env_config
            save_results
            ;;
        printers)
            discover_zebra_printers
            ;;
        mssql)
            discover_mssql_servers
            ;;
    esac
    
    echo ""
    echo -e "${BOLD}${BLUE}============================================================${NC}"
    echo -e "${BOLD}Nastepne kroki:${NC}"
    echo -e "  1. Edytuj .env z wykrytymi adresami: ${GREEN}make webenv${NC}"
    echo -e "  2. Ustaw *_ENABLED=false dla zewnetrznych urzadzen"
    echo -e "  3. Uruchom: ${GREEN}make start${NC}"
    echo -e "${BOLD}${BLUE}============================================================${NC}"
    echo ""
}

main "$@"
