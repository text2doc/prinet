#!/bin/bash
# scripts/setup.sh
# Konfiguracja środowiska WAPRO Network Mock
# Obsługuje: Raspberry Pi OS, Debian, Ubuntu (Desktop i Server)

set -e

# ============================================================================
# KONFIGURACJA
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$PROJECT_DIR/logs/setup.log"
VERBOSE=${VERBOSE:-false}

# Kolory
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================================================
# SYSTEM LOGOWANIA
# ============================================================================
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Zapis do pliku
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
    
    # Wyświetlanie na ekranie (bez emoji dla kompatybilności)
    case "$level" in
        INFO)    echo -e "${BLUE}[i] $message${NC}" ;;
        SUCCESS) echo -e "${GREEN}[+] $message${NC}" ;;
        WARN)    echo -e "${YELLOW}[!] $message${NC}" ;;
        ERROR)   echo -e "${RED}[X] $message${NC}" ;;
        DEBUG)   [ "$VERBOSE" = true ] && echo -e "${CYAN}[D] $message${NC}" ;;
        STEP)    echo -e "${MAGENTA}[-] $message${NC}" ;;
        HEADER)  echo -e "\n${BOLD}${BLUE}=== $message ===${NC}\n" ;;
    esac
}

log_cmd() {
    local cmd="$1"
    log DEBUG "Wykonuję: $cmd"
    if eval "$cmd" >> "$LOG_FILE" 2>&1; then
        return 0
    else
        local exit_code=$?
        log DEBUG "Komenda zakończona kodem: $exit_code"
        return $exit_code
    fi
}

# ============================================================================
# WYKRYWANIE SYSTEMU
# ============================================================================
detect_system() {
    log HEADER "WYKRYWANIE SYSTEMU"
    
    # Podstawowe informacje
    KERNEL=$(uname -s)
    ARCH=$(uname -m)
    HOSTNAME=$(hostname)
    
    # Wykrywanie dystrybucji
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="${ID:-unknown}"
        DISTRO_NAME="${NAME:-Unknown}"
        DISTRO_VERSION="${VERSION_ID:-unknown}"
        DISTRO_CODENAME="${VERSION_CODENAME:-unknown}"
    elif [ -f /etc/debian_version ]; then
        DISTRO_ID="debian"
        DISTRO_NAME="Debian"
        DISTRO_VERSION=$(cat /etc/debian_version)
    else
        DISTRO_ID="unknown"
        DISTRO_NAME="Unknown"
        DISTRO_VERSION="unknown"
    fi
    
    # Wykrywanie Raspberry Pi
    IS_RPI=false
    RPI_MODEL=""
    if [ -f /proc/device-tree/model ]; then
        RPI_MODEL=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0')
        if echo "$RPI_MODEL" | grep -qi "raspberry"; then
            IS_RPI=true
        fi
    fi
    
    # Wykrywanie typu systemu
    IS_DESKTOP=false
    IS_SERVER=false
    IS_WSL=false
    IS_CONTAINER=false
    
    # WSL
    if grep -qi microsoft /proc/version 2>/dev/null; then
        IS_WSL=true
    fi
    
    # Kontener
    if [ -f /.dockerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null; then
        IS_CONTAINER=true
    fi
    
    # Desktop vs Server (sprawdzenie Display Manager)
    if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ] || \
       systemctl is-active --quiet gdm 2>/dev/null || \
       systemctl is-active --quiet lightdm 2>/dev/null || \
       systemctl is-active --quiet sddm 2>/dev/null; then
        IS_DESKTOP=true
    else
        IS_SERVER=true
    fi
    
    # Wykrywanie init systemu
    if command -v systemctl &>/dev/null && [ -d /run/systemd/system ]; then
        INIT_SYSTEM="systemd"
    elif command -v service &>/dev/null; then
        INIT_SYSTEM="sysvinit"
    elif command -v rc-service &>/dev/null; then
        INIT_SYSTEM="openrc"
    else
        INIT_SYSTEM="unknown"
    fi
    
    # Pamięć RAM (w MB)
    TOTAL_RAM_MB=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "0")
    
    # Dostępne miejsce na dysku (w GB)
    DISK_FREE_GB=$(df -BG "$PROJECT_DIR" 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G' || echo "0")
    
    # Liczba rdzeni CPU
    CPU_CORES=$(nproc 2>/dev/null || echo "1")
    
    # Logowanie wykrytych informacji
    log INFO "System: $DISTRO_NAME $DISTRO_VERSION ($DISTRO_ID)"
    log INFO "Architektura: $ARCH"
    log INFO "Kernel: $KERNEL $(uname -r)"
    log INFO "Init system: $INIT_SYSTEM"
    log INFO "RAM: ${TOTAL_RAM_MB}MB | Dysk: ${DISK_FREE_GB}GB | CPU: ${CPU_CORES} rdzeni"
    
    if [ "$IS_RPI" = true ]; then
        log INFO "Raspberry Pi: $RPI_MODEL"
    fi
    
    [ "$IS_DESKTOP" = true ] && log INFO "Typ: Desktop"
    [ "$IS_SERVER" = true ] && log INFO "Typ: Server"
    [ "$IS_WSL" = true ] && log INFO "Środowisko: WSL (Windows Subsystem for Linux)"
    [ "$IS_CONTAINER" = true ] && log INFO "Środowisko: Kontener Docker"
    
    # Zapisanie do logu
    log DEBUG "DISTRO_ID=$DISTRO_ID, ARCH=$ARCH, IS_RPI=$IS_RPI, INIT_SYSTEM=$INIT_SYSTEM"
}

# ============================================================================
# DETEKCJA ANOMALII
# ============================================================================
detect_anomalies() {
    log HEADER "DETEKCJA ANOMALII"
    
    local anomalies=0
    local warnings=0
    
    # Sprawdzenie RAM (minimum 512MB dla RPi, 1GB dla innych)
    local min_ram=1024
    [ "$IS_RPI" = true ] && min_ram=512
    
    if [ "$TOTAL_RAM_MB" -lt "$min_ram" ]; then
        log WARN "Mało RAM: ${TOTAL_RAM_MB}MB (zalecane: ${min_ram}MB+)"
        ((warnings++))
    else
        log SUCCESS "RAM: ${TOTAL_RAM_MB}MB OK"
    fi
    
    # Sprawdzenie miejsca na dysku (minimum 5GB)
    if [ "$DISK_FREE_GB" -lt 5 ]; then
        log ERROR "Za mało miejsca na dysku: ${DISK_FREE_GB}GB (wymagane: 5GB+)"
        ((anomalies++))
    else
        log SUCCESS "Dysk: ${DISK_FREE_GB}GB wolnego OK"
    fi
    
    # Sprawdzenie architektury
    case "$ARCH" in
        x86_64|amd64)
            log SUCCESS "Architektura x86_64 OK"
            ;;
        aarch64|arm64)
            log SUCCESS "Architektura ARM64 OK"
            ;;
        armv7l|armhf)
            log WARN "Architektura ARMv7 - ograniczone wsparcie dla MSSQL"
            ((warnings++))
            ;;
        *)
            log WARN "Nieznana architektura: $ARCH"
            ((warnings++))
            ;;
    esac
    
    # Sprawdzenie czy nie jesteśmy rootem (niezalecane)
    if [ "$EUID" -eq 0 ] && [ -z "$SUDO_USER" ]; then
        log WARN "Uruchomiono jako root - niezalecane"
        ((warnings++))
    fi
    
    # Sprawdzenie uprawnień do sudo
    if ! sudo -n true 2>/dev/null; then
        log WARN "Brak uprawnień sudo bez hasła - może być wymagane hasło"
    fi
    
    # Sprawdzenie połączenia internetowego
    if ping -c 1 -W 3 8.8.8.8 &>/dev/null || ping -c 1 -W 3 1.1.1.1 &>/dev/null; then
        log SUCCESS "Połączenie internetowe OK"
    else
        log ERROR "Brak połączenia internetowego"
        ((anomalies++))
    fi
    
    # Sprawdzenie DNS
    if host docker.com &>/dev/null || nslookup docker.com &>/dev/null 2>&1; then
        log SUCCESS "DNS OK"
    else
        log WARN "Problemy z DNS - może utrudnić pobieranie obrazów"
        ((warnings++))
    fi
    
    # Sprawdzenie portów
    check_port_available() {
        local port=$1
        local name=$2
        if ss -ltn 2>/dev/null | grep -q ":$port " || netstat -ltn 2>/dev/null | grep -q ":$port "; then
            log WARN "Port $port ($name) jest zajęty"
            ((warnings++))
            return 1
        fi
        return 0
    }
    
    log INFO "Sprawdzanie dostępności portów..."
    check_port_available 8081 "RPI API"
    check_port_available 8082 "RPI GUI"
    check_port_available 1433 "MSSQL"
    check_port_available 9100 "ZEBRA-1"
    check_port_available 9101 "ZEBRA-2"
    
    # Podsumowanie
    echo ""
    if [ $anomalies -gt 0 ]; then
        log ERROR "Wykryto $anomalies krytycznych problemów i $warnings ostrzeżeń"
        return 1
    elif [ $warnings -gt 0 ]; then
        log WARN "Wykryto $warnings ostrzeżeń (można kontynuować)"
        return 0
    else
        log SUCCESS "Nie wykryto anomalii"
        return 0
    fi
}

# ============================================================================
# DRZEWO DECYZYJNE - INSTALACJA DOCKER
# ============================================================================
install_docker_decision_tree() {
    log HEADER "INSTALACJA DOCKER"
    
    # Sprawdzenie czy Docker jest zainstalowany
    if command -v docker &>/dev/null; then
        local docker_version=$(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',')
        log SUCCESS "Docker zainstalowany: $docker_version"
        
        # Sprawdzenie czy daemon działa
        if docker info &>/dev/null; then
            log SUCCESS "Docker daemon działa"
            return 0
        else
            log WARN "Docker daemon nie działa"
            return $(fix_docker_daemon)
        fi
    fi
    
    log INFO "Docker nie jest zainstalowany - rozpoczynam instalację"
    
    # Drzewo decyzyjne instalacji
    case "$DISTRO_ID" in
        raspbian|debian)
            install_docker_debian
            ;;
        ubuntu)
            install_docker_ubuntu
            ;;
        *)
            install_docker_generic
            ;;
    esac
}

install_docker_debian() {
    log STEP "Instalacja Docker dla Debian/Raspbian"
    
    # Metoda 1: Oficjalny skrypt (najprostsza dla RPi)
    if [ "$IS_RPI" = true ]; then
        log INFO "Raspberry Pi wykryte - używam skryptu convenience"
        if curl -fsSL https://get.docker.com -o /tmp/get-docker.sh; then
            if sudo sh /tmp/get-docker.sh >> "$LOG_FILE" 2>&1; then
                log SUCCESS "Docker zainstalowany przez get.docker.com"
                rm -f /tmp/get-docker.sh
                post_docker_install
                return 0
            fi
        fi
        log WARN "Skrypt convenience nie zadziałał - próbuję alternatywnej metody"
    fi
    
    # Metoda 2: Repozytorium Docker
    log INFO "Instalacja z oficjalnego repozytorium Docker"
    
    # Usunięcie starych wersji
    sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Instalacja zależności
    sudo apt-get update -qq
    sudo apt-get install -y -qq \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Dodanie klucza GPG
    sudo install -m 0755 -d /etc/apt/keyrings
    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
        curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
    fi
    
    # Dodanie repozytorium
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Instalacja
    sudo apt-get update -qq
    if sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        log SUCCESS "Docker zainstalowany z repozytorium"
        post_docker_install
        return 0
    fi
    
    # Metoda 3: Fallback - pakiety systemowe
    log WARN "Repozytorium Docker nie zadziałało - próbuję pakietów systemowych"
    if sudo apt-get install -y docker.io docker-compose; then
        log SUCCESS "Docker zainstalowany z pakietów systemowych"
        post_docker_install
        return 0
    fi
    
    log ERROR "Nie udało się zainstalować Docker"
    return 1
}

install_docker_ubuntu() {
    log STEP "Instalacja Docker dla Ubuntu"
    
    # Usunięcie starych wersji
    sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Instalacja zależności
    sudo apt-get update -qq
    sudo apt-get install -y -qq \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Dodanie klucza GPG
    sudo install -m 0755 -d /etc/apt/keyrings
    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
    fi
    
    # Dodanie repozytorium
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Instalacja
    sudo apt-get update -qq
    if sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        log SUCCESS "Docker zainstalowany"
        post_docker_install
        return 0
    fi
    
    # Fallback
    log WARN "Próbuję pakietów snap..."
    if sudo snap install docker; then
        log SUCCESS "Docker zainstalowany przez snap"
        return 0
    fi
    
    log ERROR "Nie udało się zainstalować Docker"
    return 1
}

install_docker_generic() {
    log STEP "Instalacja Docker - metoda uniwersalna"
    
    if curl -fsSL https://get.docker.com -o /tmp/get-docker.sh; then
        if sudo sh /tmp/get-docker.sh >> "$LOG_FILE" 2>&1; then
            log SUCCESS "Docker zainstalowany"
            rm -f /tmp/get-docker.sh
            post_docker_install
            return 0
        fi
    fi
    
    log ERROR "Nie udało się zainstalować Docker"
    log INFO "Spróbuj ręcznie: https://docs.docker.com/engine/install/"
    return 1
}

post_docker_install() {
    log INFO "Konfiguracja post-instalacyjna Docker"
    
    # Dodanie użytkownika do grupy docker
    local current_user="${SUDO_USER:-$USER}"
    if [ "$current_user" != "root" ]; then
        if ! groups "$current_user" | grep -q docker; then
            sudo usermod -aG docker "$current_user"
            log SUCCESS "Użytkownik $current_user dodany do grupy docker"
            log WARN "Wyloguj się i zaloguj ponownie aby zmiany zadziałały"
        fi
    fi
    
    # Uruchomienie i włączenie usługi
    start_docker_service
}

# ============================================================================
# DRZEWO DECYZYJNE - NAPRAWA DOCKER DAEMON
# ============================================================================
fix_docker_daemon() {
    log HEADER "NAPRAWA DOCKER DAEMON"
    
    # Metoda 1: Systemd
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        log STEP "Próba uruchomienia przez systemd"
        
        # Sprawdzenie statusu usługi
        local status=$(systemctl is-active docker 2>/dev/null || echo "unknown")
        log DEBUG "Status usługi docker: $status"
        
        case "$status" in
            active)
                log SUCCESS "Docker daemon już działa"
                return 0
                ;;
            inactive|dead)
                log INFO "Docker nieaktywny - uruchamiam"
                if sudo systemctl start docker; then
                    sleep 2
                    if docker info &>/dev/null; then
                        log SUCCESS "Docker daemon uruchomiony"
                        sudo systemctl enable docker 2>/dev/null || true
                        return 0
                    fi
                fi
                ;;
            failed)
                log WARN "Usługa docker w stanie failed - resetuję"
                sudo systemctl reset-failed docker 2>/dev/null || true
                sudo systemctl start docker
                sleep 2
                if docker info &>/dev/null; then
                    log SUCCESS "Docker daemon uruchomiony po resecie"
                    return 0
                fi
                ;;
        esac
        
        # Sprawdzenie logów
        log WARN "Sprawdzam logi Docker..."
        sudo journalctl -u docker --no-pager -n 20 >> "$LOG_FILE" 2>&1
        
        # Próba naprawy typowych problemów
        fix_docker_common_issues
        
        # Ponowna próba
        sudo systemctl daemon-reload
        sudo systemctl start docker
        sleep 3
        
        if docker info &>/dev/null; then
            log SUCCESS "Docker daemon uruchomiony po naprawie"
            return 0
        fi
    fi
    
    # Metoda 2: SysVinit / Service
    if command -v service &>/dev/null; then
        log STEP "Próba uruchomienia przez service"
        if sudo service docker start; then
            sleep 2
            if docker info &>/dev/null; then
                log SUCCESS "Docker daemon uruchomiony przez service"
                return 0
            fi
        fi
    fi
    
    # Metoda 3: Ręczne uruchomienie dockerd
    log STEP "Próba ręcznego uruchomienia dockerd"
    if sudo dockerd &>/dev/null & then
        sleep 3
        if docker info &>/dev/null; then
            log SUCCESS "Docker daemon uruchomiony ręcznie"
            log WARN "Daemon działa w tle - restart systemu go zatrzyma"
            return 0
        fi
    fi
    
    log ERROR "Nie udało się uruchomić Docker daemon"
    log INFO "Sprawdź logi: sudo journalctl -u docker -n 50"
    log INFO "Lub plik: $LOG_FILE"
    return 1
}

fix_docker_common_issues() {
    log INFO "Naprawianie typowych problemów Docker..."
    
    # Problem 1: Brak pliku konfiguracyjnego
    if [ ! -f /etc/docker/daemon.json ]; then
        log DEBUG "Tworzę domyślną konfigurację Docker"
        sudo mkdir -p /etc/docker
        echo '{}' | sudo tee /etc/docker/daemon.json > /dev/null
    fi
    
    # Problem 2: Uprawnienia do socketu
    if [ -S /var/run/docker.sock ]; then
        sudo chmod 666 /var/run/docker.sock 2>/dev/null || true
    fi
    
    # Problem 3: Brak grupy docker
    if ! getent group docker &>/dev/null; then
        sudo groupadd docker 2>/dev/null || true
    fi
    
    # Problem 4: Czyszczenie starych kontenerów/sieci
    log DEBUG "Czyszczenie pozostałości Docker..."
    sudo rm -rf /var/lib/docker/network/files/local-kv.db 2>/dev/null || true
    
    # Problem 5: Konflikty iptables (częste na RPi)
    if [ "$IS_RPI" = true ]; then
        log DEBUG "Aktualizacja reguł iptables..."
        sudo iptables -t nat -F 2>/dev/null || true
        sudo iptables -F DOCKER 2>/dev/null || true
        sudo iptables -F DOCKER-ISOLATION-STAGE-1 2>/dev/null || true
        sudo iptables -F DOCKER-ISOLATION-STAGE-2 2>/dev/null || true
    fi
}

# ============================================================================
# INSTALACJA DOCKER COMPOSE
# ============================================================================
install_docker_compose() {
    log HEADER "DOCKER COMPOSE"
    
    # Sprawdzenie nowej wersji (plugin)
    if docker compose version &>/dev/null; then
        local version=$(docker compose version 2>/dev/null | grep -oP 'v[\d.]+' | head -1)
        log SUCCESS "Docker Compose plugin: $version"
        create_compose_alias
        return 0
    fi
    
    # Sprawdzenie starej wersji (standalone)
    if command -v docker-compose &>/dev/null; then
        local version=$(docker-compose --version 2>/dev/null | grep -oP '[\d.]+' | head -1)
        log SUCCESS "Docker Compose standalone: $version"
        return 0
    fi
    
    log INFO "Docker Compose nie jest zainstalowany - instaluję"
    
    # Metoda 1: Plugin (preferowana)
    if sudo apt-get install -y docker-compose-plugin 2>/dev/null; then
        if docker compose version &>/dev/null; then
            log SUCCESS "Docker Compose plugin zainstalowany"
            create_compose_alias
            return 0
        fi
    fi
    
    # Metoda 2: Pobranie binarne
    log INFO "Instalacja Docker Compose z GitHub..."
    
    local COMPOSE_VERSION="v2.24.0"
    local COMPOSE_ARCH=""
    
    case "$ARCH" in
        x86_64|amd64) COMPOSE_ARCH="x86_64" ;;
        aarch64|arm64) COMPOSE_ARCH="aarch64" ;;
        armv7l|armhf) COMPOSE_ARCH="armv7" ;;
        *) COMPOSE_ARCH="x86_64" ;;
    esac
    
    local COMPOSE_URL="https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-${COMPOSE_ARCH}"
    
    if sudo curl -SL "$COMPOSE_URL" -o /usr/local/bin/docker-compose 2>/dev/null; then
        sudo chmod +x /usr/local/bin/docker-compose
        if docker-compose --version &>/dev/null; then
            log SUCCESS "Docker Compose zainstalowany"
            return 0
        fi
    fi
    
    # Metoda 3: pip
    log INFO "Próba instalacji przez pip..."
    if command -v pip3 &>/dev/null; then
        if pip3 install docker-compose 2>/dev/null; then
            log SUCCESS "Docker Compose zainstalowany przez pip"
            return 0
        fi
    fi
    
    log ERROR "Nie udało się zainstalować Docker Compose"
    return 1
}

create_compose_alias() {
    # Tworzenie aliasu docker-compose dla kompatybilności
    if ! command -v docker-compose &>/dev/null; then
        log DEBUG "Tworzenie aliasu docker-compose"
        sudo tee /usr/local/bin/docker-compose > /dev/null << 'EOF'
#!/bin/bash
docker compose "$@"
EOF
        sudo chmod +x /usr/local/bin/docker-compose
    fi
}

# ============================================================================
# INSTALACJA NARZĘDZI POMOCNICZYCH
# ============================================================================
install_tools() {
    log HEADER "NARZĘDZIA POMOCNICZE"
    
    local tools_to_install=""
    
    # Lista wymaganych narzędzi
    local required_tools="curl wget git make jq nc"
    
    for tool in $required_tools; do
        if ! command -v $tool &>/dev/null; then
            case $tool in
                nc) tools_to_install="$tools_to_install netcat-openbsd" ;;
                *) tools_to_install="$tools_to_install $tool" ;;
            esac
            log WARN "Brak: $tool"
        else
            log SUCCESS "$tool OK"
        fi
    done
    
    if [ -n "$tools_to_install" ]; then
        log INFO "Instaluję brakujące narzędzia:$tools_to_install"
        sudo apt-get update -qq
        sudo apt-get install -y -qq $tools_to_install
        log SUCCESS "Narzędzia zainstalowane"
    fi
}

# ============================================================================
# KONFIGURACJA PROJEKTU
# ============================================================================
setup_project() {
    log HEADER "KONFIGURACJA PROJEKTU"
    
    cd "$PROJECT_DIR"
    
    # Plik .env
    if [ ! -f .env ]; then
        if [ -f .env.example ]; then
            cp .env.example .env
            log SUCCESS "Utworzono .env z szablonu"
        else
            log ERROR "Brak pliku .env.example"
            return 1
        fi
    else
        log SUCCESS "Plik .env istnieje"
    fi
    
    # Katalogi
    log INFO "Tworzenie katalogów..."
    mkdir -p logs reports tests \
             monitoring/prometheus \
             monitoring/grafana/dashboards \
             monitoring/grafana/datasources
    log SUCCESS "Katalogi utworzone"
    
    # Uprawnienia skryptów
    chmod +x scripts/*.sh 2>/dev/null || true
    log SUCCESS "Uprawnienia skryptów OK"
    
    # Budowanie obrazów
    log INFO "Budowanie obrazów Docker (może potrwać kilka minut)..."
    if docker-compose build >> "$LOG_FILE" 2>&1; then
        log SUCCESS "Obrazy Docker zbudowane"
    else
        log WARN "Problemy z budowaniem - sprawdź logi: $LOG_FILE"
    fi
}

start_docker_service() {
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        sudo systemctl start docker 2>/dev/null || true
        sudo systemctl enable docker 2>/dev/null || true
    elif command -v service &>/dev/null; then
        sudo service docker start 2>/dev/null || true
    fi
    sleep 2
}

# ============================================================================
# PODSUMOWANIE
# ============================================================================
print_summary() {
    log HEADER "PODSUMOWANIE"
    
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}     [OK] KONFIGURACJA ZAKONCZONA POMYSLNIE!${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""
    
    # Informacje o systemie
    echo -e "${BOLD}System:${NC}"
    echo -e "  $DISTRO_NAME $DISTRO_VERSION ($ARCH)"
    [ "$IS_RPI" = true ] && echo -e "  Raspberry Pi: $RPI_MODEL"
    echo ""
    
    # Wersje
    echo -e "${BOLD}Zainstalowane komponenty:${NC}"
    echo -e "  Docker:         $(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',' || echo 'N/A')"
    echo -e "  Docker Compose: $(docker-compose --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo 'N/A')"
    echo ""
    
    # Nastepne kroki
    echo -e "${BOLD}Nastepne kroki:${NC}"
    echo -e "  1. ${YELLOW}Wyloguj sie i zaloguj${NC} (dla grupy docker)"
    echo -e "  2. Uruchom: ${GREEN}make start${NC}"
    echo ""
    
    # Logi
    echo -e "${BOLD}Logi:${NC} $LOG_FILE"
    echo ""
}

# ============================================================================
# GŁÓWNA FUNKCJA
# ============================================================================
main() {
    echo -e "${BOLD}${BLUE}"
    echo "============================================================"
    echo "       WAPRO Network Mock - Setup"
    echo "       $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================================"
    echo -e "${NC}"
    
    log INFO "Rozpoczecie konfiguracji..."
    log DEBUG "Katalog projektu: $PROJECT_DIR"
    log DEBUG "Plik logów: $LOG_FILE"
    
    # 1. Wykrywanie systemu
    detect_system
    
    # 2. Detekcja anomalii
    if ! detect_anomalies; then
        log ERROR "Wykryto krytyczne problemy - przerwanie"
        exit 1
    fi
    
    # 3. Instalacja narzędzi
    install_tools
    
    # 4. Docker
    if ! install_docker_decision_tree; then
        log ERROR "Instalacja Docker nie powiodła się"
        exit 1
    fi
    
    # 5. Docker Compose
    if ! install_docker_compose; then
        log ERROR "Instalacja Docker Compose nie powiodła się"
        exit 1
    fi
    
    # 6. Konfiguracja projektu
    setup_project
    
    # 7. Podsumowanie
    print_summary
    
    log INFO "Konfiguracja zakończona pomyślnie"
    exit 0
}

# Uruchomienie
main "$@"
