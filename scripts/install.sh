#!/bin/bash
# scripts/install.sh
# Instalacja wymaganych programów dla WAPRO Network Mock
# Wspiera: Raspberry Pi OS, Debian, Ubuntu (Desktop i Server)

# Nie przerywaj przy błędach - obsługujemy je ręcznie
set +e

# Kolory
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Katalog skryptu i projektu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$PROJECT_DIR/logs/install.log"

# Tworzenie katalogu logów
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

# Funkcja logowania (bez emoji dla kompatybilności z RPi)
log() {
    local level="$1"
    local msg="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $msg" >> "$LOG_FILE" 2>/dev/null || true
    
    case "$level" in
        INFO)    echo -e "${BLUE}[i] $msg${NC}" ;;
        OK)      echo -e "${GREEN}[+] $msg${NC}" ;;
        WARN)    echo -e "${YELLOW}[!] $msg${NC}" ;;
        ERROR)   echo -e "${RED}[X] $msg${NC}" ;;
        STEP)    echo -e "${CYAN}[-] $msg${NC}" ;;
    esac
}

echo -e "${BOLD}${BLUE}"
echo "============================================================"
echo "     WAPRO Network Mock - Instalacja zaleznosci"
echo "     $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo -e "${NC}"

# Wykrywanie systemu
detect_system() {
    log INFO "Wykrywanie systemu..."
    
    # Dystrybucja
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS="${ID:-unknown}"
        OS_NAME="${NAME:-Unknown}"
        VERSION="${VERSION_ID:-unknown}"
        CODENAME="${VERSION_CODENAME:-unknown}"
    elif [ -f /etc/debian_version ]; then
        OS="debian"
        OS_NAME="Debian"
        VERSION=$(cat /etc/debian_version)
        CODENAME="unknown"
    else
        OS="unknown"
        OS_NAME="Unknown"
        VERSION="unknown"
        CODENAME="unknown"
    fi
    
    # Architektura
    ARCH=$(uname -m)
    
    # Raspberry Pi
    IS_RPI=false
    RPI_MODEL=""
    if [ -f /proc/device-tree/model ]; then
        RPI_MODEL=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo "")
        if echo "$RPI_MODEL" | grep -qi "raspberry"; then
            IS_RPI=true
        fi
    fi
    
    # Init system
    if command -v systemctl &>/dev/null && [ -d /run/systemd/system ]; then
        INIT_SYSTEM="systemd"
    elif command -v service &>/dev/null; then
        INIT_SYSTEM="sysvinit"
    else
        INIT_SYSTEM="unknown"
    fi
    
    # Desktop vs Server
    IS_DESKTOP=false
    if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ] || \
       command -v startx &>/dev/null || \
       dpkg -l 2>/dev/null | grep -qE "(gnome-shell|kde-plasma|xfce4|lxde)" 2>/dev/null; then
        IS_DESKTOP=true
    fi
    
    echo ""
    log INFO "System: $OS_NAME $VERSION ($OS)"
    log INFO "Architektura: $ARCH"
    log INFO "Init: $INIT_SYSTEM"
    [ "$IS_RPI" = true ] && log INFO "Raspberry Pi: $RPI_MODEL"
    [ "$IS_DESKTOP" = true ] && log INFO "Typ: Desktop" || log INFO "Typ: Server/Headless"
    echo ""
}

# Sprawdzenie sudo
check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        log WARN "Skrypt wymaga uprawnień root"
        if command -v sudo &>/dev/null; then
            log INFO "Uruchamiam ponownie z sudo..."
            exec sudo bash "$0" "$@"
        else
            log ERROR "Brak sudo - zainstaluj: apt-get install sudo"
            exit 1
        fi
    fi
    
    # Zachowaj SUDO_USER do późniejszego użycia
    REAL_USER="${SUDO_USER:-$USER}"
    log INFO "Użytkownik: $REAL_USER (wykonuję jako root)"
}

# Aktualizacja systemu
update_system() {
    log STEP "Aktualizacja listy pakietów..."
    if apt-get update -qq >> "$LOG_FILE" 2>&1; then
        log OK "Lista pakietów zaktualizowana"
    else
        log WARN "Problemy z aktualizacją pakietów - kontynuuję"
    fi
}

# Konfiguracja polskiego środowiska (locale)
configure_polish_locale() {
    echo ""
    log INFO "═══ KONFIGURACJA JĘZYKA POLSKIEGO ═══"
    
    # Sprawdzenie czy locale pl_PL.UTF-8 jest już skonfigurowane
    if locale -a 2>/dev/null | grep -qi "pl_PL.utf8"; then
        log OK "Locale pl_PL.UTF-8 już dostępne"
    else
        log STEP "Instalacja pakietu locales..."
        apt-get install -y -qq locales >> "$LOG_FILE" 2>&1 || true
        
        log STEP "Generowanie locale pl_PL.UTF-8..."
        
        # Odkomentowanie pl_PL.UTF-8 w /etc/locale.gen
        if [ -f /etc/locale.gen ]; then
            sed -i 's/^# *pl_PL.UTF-8/pl_PL.UTF-8/' /etc/locale.gen 2>/dev/null || true
            # Dodaj jeśli nie ma
            if ! grep -q "^pl_PL.UTF-8" /etc/locale.gen; then
                echo "pl_PL.UTF-8 UTF-8" >> /etc/locale.gen
            fi
        fi
        
        # Generowanie locale
        if command -v locale-gen &>/dev/null; then
            locale-gen pl_PL.UTF-8 >> "$LOG_FILE" 2>&1 || true
            log OK "Locale pl_PL.UTF-8 wygenerowane"
        elif command -v localedef &>/dev/null; then
            localedef -i pl_PL -c -f UTF-8 -A /usr/share/locale/locale.alias pl_PL.UTF-8 >> "$LOG_FILE" 2>&1 || true
            log OK "Locale pl_PL.UTF-8 utworzone"
        fi
    fi
    
    # Ustawienie domyślnego locale
    log STEP "Konfiguracja domyślnego locale..."
    
    # Metoda 1: update-locale (Debian/Ubuntu)
    if command -v update-locale &>/dev/null; then
        update-locale LANG=pl_PL.UTF-8 >> "$LOG_FILE" 2>&1 || true
        update-locale LC_ALL=pl_PL.UTF-8 >> "$LOG_FILE" 2>&1 || true
    fi
    
    # Metoda 2: Bezpośredni zapis do /etc/default/locale
    if [ -d /etc/default ]; then
        cat > /etc/default/locale << 'EOFLOCALE'
LANG=pl_PL.UTF-8
LC_ALL=pl_PL.UTF-8
LC_CTYPE=pl_PL.UTF-8
LC_MESSAGES=pl_PL.UTF-8
LC_TIME=pl_PL.UTF-8
LC_NUMERIC=pl_PL.UTF-8
LC_MONETARY=pl_PL.UTF-8
EOFLOCALE
        log OK "Zapisano /etc/default/locale"
    fi
    
    # Metoda 3: /etc/locale.conf (niektóre systemy)
    if [ -d /etc ] && [ ! -f /etc/default/locale ]; then
        cat > /etc/locale.conf << 'EOFLOCALE2'
LANG=pl_PL.UTF-8
LC_ALL=pl_PL.UTF-8
EOFLOCALE2
    fi
    
    # Eksport dla bieżącej sesji
    export LANG=pl_PL.UTF-8
    export LC_ALL=pl_PL.UTF-8
    
    # Konfiguracja strefy czasowej
    log STEP "Konfiguracja strefy czasowej (Europe/Warsaw)..."
    if [ -f /usr/share/zoneinfo/Europe/Warsaw ]; then
        ln -sf /usr/share/zoneinfo/Europe/Warsaw /etc/localtime 2>/dev/null || true
        echo "Europe/Warsaw" > /etc/timezone 2>/dev/null || true
        
        # dpkg-reconfigure dla Debian/Ubuntu
        if command -v dpkg-reconfigure &>/dev/null; then
            dpkg-reconfigure -f noninteractive tzdata >> "$LOG_FILE" 2>&1 || true
        fi
        log OK "Strefa czasowa: Europe/Warsaw"
    fi
    
    # Instalacja polskich tłumaczeń dla popularnych pakietów
    log STEP "Instalacja polskich tłumaczeń..."
    apt-get install -y -qq language-pack-pl 2>/dev/null >> "$LOG_FILE" 2>&1 || true
    apt-get install -y -qq manpages-pl 2>/dev/null >> "$LOG_FILE" 2>&1 || true
    
    # Weryfikacja
    local current_lang=$(locale 2>/dev/null | grep "^LANG=" | cut -d= -f2)
    if echo "$current_lang" | grep -qi "pl_PL"; then
        log OK "Język polski skonfigurowany: $current_lang"
    else
        log WARN "Locale zostanie aktywowane po ponownym zalogowaniu"
    fi
}

# Instalacja podstawowych narzędzi
install_base_tools() {
    echo ""
    log INFO "═══ INSTALACJA NARZĘDZI ═══"
    
    # Lista pakietów do zainstalowania
    local packages="curl wget git make jq ca-certificates gnupg apt-transport-https"
    
    # Netcat - różne nazwy w różnych dystrybucjach
    if apt-cache show netcat-openbsd &>/dev/null; then
        packages="$packages netcat-openbsd"
    elif apt-cache show netcat &>/dev/null; then
        packages="$packages netcat"
    fi
    
    # lsb-release
    if apt-cache show lsb-release &>/dev/null; then
        packages="$packages lsb-release"
    fi
    
    for pkg in $packages; do
        if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
            log OK "$pkg (już zainstalowany)"
        else
            log STEP "Instaluję $pkg..."
            if apt-get install -y -qq "$pkg" >> "$LOG_FILE" 2>&1; then
                log OK "$pkg zainstalowany"
            else
                log WARN "$pkg - nie udało się zainstalować"
            fi
        fi
    done
}

# Instalacja Docker - wielometodowa
install_docker() {
    echo ""
    log INFO "═══ INSTALACJA DOCKER ═══"
    
    # Sprawdzenie czy Docker jest już zainstalowany
    if command -v docker &>/dev/null; then
        local docker_version=$(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',')
        log OK "Docker już zainstalowany: $docker_version"
        return 0
    fi
    
    # Usunięcie starych wersji
    log STEP "Usuwanie starych wersji Docker..."
    apt-get remove -y docker docker-engine docker.io containerd runc >> "$LOG_FILE" 2>&1 || true
    
    # Wybór metody instalacji
    local install_success=false
    
    # Metoda 1: Convenience script (najlepsza dla RPi i ARM)
    if [ "$IS_RPI" = true ] || [ "$ARCH" = "armv7l" ] || [ "$ARCH" = "aarch64" ]; then
        log STEP "Metoda 1: Skrypt get.docker.com (ARM/RPi)..."
        if install_docker_convenience; then
            install_success=true
        fi
    fi
    
    # Metoda 2: Oficjalne repozytorium Docker
    if [ "$install_success" = false ]; then
        log STEP "Metoda 2: Oficjalne repozytorium Docker..."
        if install_docker_repo; then
            install_success=true
        fi
    fi
    
    # Metoda 3: Pakiety systemowe (fallback)
    if [ "$install_success" = false ]; then
        log STEP "Metoda 3: Pakiety systemowe (docker.io)..."
        if install_docker_system; then
            install_success=true
        fi
    fi
    
    # Metoda 4: Snap (Ubuntu)
    if [ "$install_success" = false ] && [ "$OS" = "ubuntu" ]; then
        log STEP "Metoda 4: Snap..."
        if install_docker_snap; then
            install_success=true
        fi
    fi
    
    if [ "$install_success" = true ]; then
        log OK "Docker zainstalowany pomyślnie"
        return 0
    else
        log ERROR "Nie udało się zainstalować Docker żadną metodą"
        log INFO "Sprawdź logi: $LOG_FILE"
        return 1
    fi
}

# Metoda 1: Convenience script
install_docker_convenience() {
    log INFO "Pobieranie skryptu get.docker.com..."
    
    if ! curl -fsSL https://get.docker.com -o /tmp/get-docker.sh 2>> "$LOG_FILE"; then
        log WARN "Nie udało się pobrać skryptu"
        return 1
    fi
    
    log INFO "Uruchamianie skryptu instalacyjnego..."
    if sh /tmp/get-docker.sh >> "$LOG_FILE" 2>&1; then
        rm -f /tmp/get-docker.sh
        return 0
    else
        rm -f /tmp/get-docker.sh
        log WARN "Skrypt instalacyjny nie powiódł się"
        return 1
    fi
}

# Metoda 2: Oficjalne repozytorium
install_docker_repo() {
    # Określ dystrybucję dla repozytorium Docker
    local docker_distro="$OS"
    case "$OS" in
        raspbian) docker_distro="debian" ;;
        linuxmint|pop) docker_distro="ubuntu" ;;
    esac
    
    # Sprawdź czy dystrybucja jest wspierana
    if [ "$docker_distro" != "debian" ] && [ "$docker_distro" != "ubuntu" ]; then
        log WARN "Dystrybucja $OS nie jest wspierana przez repozytorium Docker"
        return 1
    fi
    
    log INFO "Konfiguracja repozytorium Docker dla $docker_distro..."
    
    # Tworzenie katalogu keyrings
    install -m 0755 -d /etc/apt/keyrings 2>/dev/null || mkdir -p /etc/apt/keyrings
    
    # Usunięcie starego klucza
    rm -f /etc/apt/keyrings/docker.gpg 2>/dev/null || true
    
    # Pobranie klucza GPG
    if ! curl -fsSL "https://download.docker.com/linux/${docker_distro}/gpg" 2>> "$LOG_FILE" | \
         gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>> "$LOG_FILE"; then
        log WARN "Nie udało się pobrać klucza GPG"
        return 1
    fi
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Określ codename
    local release_codename="$CODENAME"
    if [ "$release_codename" = "unknown" ] || [ -z "$release_codename" ]; then
        release_codename=$(lsb_release -cs 2>/dev/null || echo "stable")
    fi
    
    # Dodanie repozytorium
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${docker_distro} ${release_codename} stable" > /etc/apt/sources.list.d/docker.list
    
    # Aktualizacja i instalacja
    if ! apt-get update -qq >> "$LOG_FILE" 2>&1; then
        log WARN "Nie udało się zaktualizować listy pakietów"
        return 1
    fi
    
    if apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >> "$LOG_FILE" 2>&1; then
        return 0
    else
        log WARN "Nie udało się zainstalować pakietów Docker CE"
        return 1
    fi
}

# Metoda 3: Pakiety systemowe
install_docker_system() {
    log INFO "Instalacja docker.io z pakietów systemowych..."
    
    if apt-get install -y docker.io >> "$LOG_FILE" 2>&1; then
        return 0
    else
        log WARN "Nie udało się zainstalować docker.io"
        return 1
    fi
}

# Metoda 4: Snap
install_docker_snap() {
    if ! command -v snap &>/dev/null; then
        log WARN "Snap nie jest dostępny"
        return 1
    fi
    
    log INFO "Instalacja Docker przez snap..."
    if snap install docker >> "$LOG_FILE" 2>&1; then
        return 0
    else
        log WARN "Snap install nie powiódł się"
        return 1
    fi
}

# Instalacja MSSQL Tools (sqlcmd)
install_mssql_tools() {
    echo ""
    log INFO "=== INSTALACJA MSSQL TOOLS ==="
    
    # Sprawdzenie czy sqlcmd jest już zainstalowany
    if command -v sqlcmd &>/dev/null; then
        log OK "MSSQL Tools już zainstalowane"
        return 0
    fi
    
    # Sprawdzenie czy jest w PATH z mssql-tools18 lub mssql-tools
    if [ -f /opt/mssql-tools18/bin/sqlcmd ] || [ -f /opt/mssql-tools/bin/sqlcmd ]; then
        log OK "MSSQL Tools już zainstalowane (w /opt)"
        return 0
    fi
    
    log STEP "Instalacja zależności..."
    apt-get install -y -qq curl gnupg2 apt-transport-https >> "$LOG_FILE" 2>&1 || true
    
    # Określ wersję Debiana/Ubuntu
    local os_version="$VERSION"
    local distro_path=""
    
    case "$OS" in
        debian)
            case "$os_version" in
                12*) distro_path="debian/12" ;;
                11*) distro_path="debian/11" ;;
                10*) distro_path="debian/10" ;;
                *) distro_path="debian/12" ;;  # domyślnie najnowszy
            esac
            ;;
        ubuntu)
            case "$os_version" in
                24*) distro_path="ubuntu/24.04" ;;
                22*) distro_path="ubuntu/22.04" ;;
                20*) distro_path="ubuntu/20.04" ;;
                *) distro_path="ubuntu/22.04" ;;  # domyślnie LTS
            esac
            ;;
        raspbian)
            # Raspbian bazuje na Debianie
            distro_path="debian/12"
            ;;
        *)
            log WARN "Nieobsługiwana dystrybucja: $OS - próbuję Debian 12"
            distro_path="debian/12"
            ;;
    esac
    
    log STEP "Dodawanie klucza Microsoft GPG..."
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc 2>> "$LOG_FILE" | apt-key add - >> "$LOG_FILE" 2>&1 || {
        log WARN "Nie udało się dodać klucza GPG (stara metoda)"
        # Nowa metoda z gpg
        curl -fsSL https://packages.microsoft.com/keys/microsoft.asc 2>> "$LOG_FILE" | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg 2>> "$LOG_FILE" || true
    }
    
    log STEP "Dodawanie repozytorium Microsoft ($distro_path)..."
    curl -fsSL "https://packages.microsoft.com/config/${distro_path}/prod.list" 2>> "$LOG_FILE" | tee /etc/apt/sources.list.d/mssql-release.list >> "$LOG_FILE" 2>&1 || {
        log WARN "Nie udało się pobrać listy repozytoriów"
        return 1
    }
    
    log STEP "Aktualizacja listy pakietów..."
    apt-get update -qq >> "$LOG_FILE" 2>&1 || true
    
    log STEP "Instalacja mssql-tools i unixodbc-dev..."
    # ACCEPT_EULA=Y jest wymagane dla mssql-tools
    
    # Najpierw zainstaluj unixodbc-dev
    apt-get install -y -qq unixodbc-dev >> "$LOG_FILE" 2>&1 || true
    
    # Próba instalacji mssql-tools18 (nowsza wersja)
    if ACCEPT_EULA=Y apt-get install -y mssql-tools18 >> "$LOG_FILE" 2>&1; then
        log OK "mssql-tools18 zainstalowane"
    # Próba instalacji mssql-tools (starsza wersja)
    elif ACCEPT_EULA=Y apt-get install -y mssql-tools >> "$LOG_FILE" 2>&1; then
        log OK "mssql-tools zainstalowane"
    else
        # Debian 12 może wymagać libssl1.1 - próba instalacji z Ubuntu repo
        log WARN "Standardowa instalacja nie powiodła się"
        log STEP "Próba instalacji libssl1.1 (wymagane dla mssql-tools)..."
        
        # Sprawdź architekturę
        local arch=$(dpkg --print-architecture)
        local libssl_url=""
        case "$arch" in
            amd64) libssl_url="http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_amd64.deb" ;;
            arm64) libssl_url="http://ports.ubuntu.com/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_arm64.deb" ;;
            armhf) libssl_url="http://ports.ubuntu.com/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_armhf.deb" ;;
        esac
        
        if [ -n "$libssl_url" ]; then
            curl -fsSL "$libssl_url" -o /tmp/libssl1.1.deb >> "$LOG_FILE" 2>&1 && \
            dpkg -i /tmp/libssl1.1.deb >> "$LOG_FILE" 2>&1 && \
            rm -f /tmp/libssl1.1.deb
            
            # Ponowna próba instalacji
            if ACCEPT_EULA=Y apt-get install -y mssql-tools18 >> "$LOG_FILE" 2>&1; then
                log OK "mssql-tools18 zainstalowane (z libssl1.1)"
            elif ACCEPT_EULA=Y apt-get install -y mssql-tools >> "$LOG_FILE" 2>&1; then
                log OK "mssql-tools zainstalowane (z libssl1.1)"
            else
                log WARN "Nie udało się zainstalować MSSQL Tools"
                log INFO "Możesz użyć Docker do testowania MSSQL: docker exec -it wapromag-mssql /opt/mssql-tools/bin/sqlcmd ..."
                return 1
            fi
        else
            log WARN "Nieobsługiwana architektura dla libssl1.1: $arch"
            log INFO "Możesz użyć Docker do testowania MSSQL: docker exec -it wapromag-mssql /opt/mssql-tools/bin/sqlcmd ..."
            return 1
        fi
    fi
    
    # Dodanie do PATH
    log STEP "Konfiguracja PATH..."
    local mssql_path=""
    if [ -d /opt/mssql-tools18/bin ]; then
        mssql_path="/opt/mssql-tools18/bin"
    elif [ -d /opt/mssql-tools/bin ]; then
        mssql_path="/opt/mssql-tools/bin"
    fi
    
    if [ -n "$mssql_path" ]; then
        # Dodaj do /etc/profile.d dla wszystkich użytkowników
        echo "export PATH=\"\$PATH:$mssql_path\"" > /etc/profile.d/mssql-tools.sh
        chmod +x /etc/profile.d/mssql-tools.sh
        
        # Dodaj do .bashrc użytkownika
        if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ]; then
            local user_home=$(eval echo ~$REAL_USER)
            if [ -f "$user_home/.bashrc" ]; then
                if ! grep -q "mssql-tools" "$user_home/.bashrc" 2>/dev/null; then
                    echo "" >> "$user_home/.bashrc"
                    echo "# MSSQL Tools" >> "$user_home/.bashrc"
                    echo "export PATH=\"\$PATH:$mssql_path\"" >> "$user_home/.bashrc"
                fi
            fi
        fi
        
        # Eksport dla bieżącej sesji
        export PATH="$PATH:$mssql_path"
        
        log OK "MSSQL Tools zainstalowane"
        log INFO "PATH zaktualizowany: $mssql_path"
        log WARN "Wyloguj się i zaloguj ponownie, aby PATH zadziałał"
    fi
    
    return 0
}

# Instalacja Docker Compose
install_docker_compose() {
    echo ""
    log INFO "═══ INSTALACJA DOCKER COMPOSE ═══"
    
    # Sprawdzenie nowej wersji (docker compose plugin)
    if docker compose version &>/dev/null; then
        local compose_version=$(docker compose version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        log OK "Docker Compose plugin: $compose_version"
        create_compose_alias
        return 0
    fi
    
    # Sprawdzenie starej wersji (docker-compose standalone)
    if command -v docker-compose &>/dev/null; then
        local compose_version=$(docker-compose --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        log OK "Docker Compose standalone: $compose_version"
        return 0
    fi
    
    log INFO "Docker Compose nie jest zainstalowany"
    
    # Metoda 1: Plugin apt
    log STEP "Metoda 1: docker-compose-plugin z apt..."
    if apt-get install -y docker-compose-plugin >> "$LOG_FILE" 2>&1; then
        if docker compose version &>/dev/null; then
            log OK "Docker Compose plugin zainstalowany"
            create_compose_alias
            return 0
        fi
    fi
    
    # Metoda 2: Pobranie binarne z GitHub
    log STEP "Metoda 2: Pobieranie z GitHub..."
    
    local COMPOSE_VERSION="v2.24.0"
    local COMPOSE_ARCH=""
    case "$ARCH" in
        x86_64|amd64) COMPOSE_ARCH="x86_64" ;;
        aarch64|arm64) COMPOSE_ARCH="aarch64" ;;
        armv7l|armhf) COMPOSE_ARCH="armv7" ;;
        *) COMPOSE_ARCH="x86_64" ;;
    esac
    
    local COMPOSE_URL="https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-${COMPOSE_ARCH}"
    
    if curl -SL "$COMPOSE_URL" -o /usr/local/bin/docker-compose 2>> "$LOG_FILE"; then
        chmod +x /usr/local/bin/docker-compose
        if docker-compose --version &>/dev/null; then
            log OK "Docker Compose zainstalowany z GitHub"
            return 0
        fi
    fi
    
    # Metoda 3: docker-compose z apt (starsza wersja)
    log STEP "Metoda 3: docker-compose z apt..."
    if apt-get install -y docker-compose >> "$LOG_FILE" 2>&1; then
        if command -v docker-compose &>/dev/null; then
            log OK "Docker Compose zainstalowany z apt"
            return 0
        fi
    fi
    
    # Metoda 4: pip
    log STEP "Metoda 4: pip..."
    if command -v pip3 &>/dev/null; then
        if pip3 install docker-compose >> "$LOG_FILE" 2>&1; then
            log OK "Docker Compose zainstalowany przez pip"
            return 0
        fi
    fi
    
    log ERROR "Nie udało się zainstalować Docker Compose"
    return 1
}

# Tworzenie aliasu docker-compose
create_compose_alias() {
    if ! command -v docker-compose &>/dev/null; then
        log STEP "Tworzenie aliasu docker-compose..."
        cat > /usr/local/bin/docker-compose << 'EOFCOMPOSE'
#!/bin/bash
docker compose "$@"
EOFCOMPOSE
        chmod +x /usr/local/bin/docker-compose
        log OK "Alias docker-compose utworzony"
    fi
}

# Konfiguracja użytkownika
configure_user() {
    echo ""
    log INFO "═══ KONFIGURACJA UŻYTKOWNIKA ═══"
    
    # Upewnienie się że grupa docker istnieje
    if ! getent group docker &>/dev/null; then
        log STEP "Tworzenie grupy docker..."
        groupadd docker 2>/dev/null || true
    fi
    
    if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ]; then
        if groups "$REAL_USER" 2>/dev/null | grep -q docker; then
            log OK "Użytkownik $REAL_USER już w grupie docker"
        else
            log STEP "Dodawanie $REAL_USER do grupy docker..."
            usermod -aG docker "$REAL_USER" 2>/dev/null || true
            log OK "Użytkownik $REAL_USER dodany do grupy docker"
            log WARN "Wyloguj się i zaloguj ponownie, aby zmiany zadziałały"
        fi
    fi
}

# Uruchomienie i włączenie Docker
enable_docker() {
    echo ""
    log INFO "═══ URUCHAMIANIE DOCKER ═══"
    
    # Systemd
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        log STEP "Włączanie usługi Docker (systemd)..."
        systemctl enable docker >> "$LOG_FILE" 2>&1 || true
        systemctl start docker >> "$LOG_FILE" 2>&1 || true
        
        sleep 2
        
        if systemctl is-active --quiet docker; then
            log OK "Docker daemon uruchomiony"
        else
            log WARN "Docker daemon nie uruchomiony"
            log INFO "Spróbuj: sudo systemctl start docker"
        fi
    # SysVinit
    elif [ "$INIT_SYSTEM" = "sysvinit" ]; then
        log STEP "Włączanie usługi Docker (sysvinit)..."
        service docker start >> "$LOG_FILE" 2>&1 || true
        update-rc.d docker defaults >> "$LOG_FILE" 2>&1 || true
        
        sleep 2
        
        if service docker status &>/dev/null; then
            log OK "Docker daemon uruchomiony"
        else
            log WARN "Docker daemon nie uruchomiony"
        fi
    else
        log WARN "Nieznany init system - spróbuj ręcznie uruchomić Docker"
    fi
}

# Weryfikacja instalacji
verify_installation() {
    echo ""
    log INFO "═══ WERYFIKACJA INSTALACJI ═══"
    
    local all_ok=true
    local warnings=0
    
    # Docker
    if command -v docker &>/dev/null; then
        local docker_ver=$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        log OK "Docker: $docker_ver"
        
        # Test Docker daemon
        if docker info &>/dev/null; then
            log OK "Docker daemon: działa"
        else
            log WARN "Docker daemon: nie odpowiada"
            ((warnings++))
        fi
    else
        log ERROR "Docker: nie znaleziono"
        all_ok=false
    fi
    
    # Docker Compose
    if docker compose version &>/dev/null; then
        local compose_ver=$(docker compose version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        log OK "Docker Compose: $compose_ver"
    elif command -v docker-compose &>/dev/null; then
        local compose_ver=$(docker-compose --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        log OK "Docker Compose: $compose_ver"
    else
        log ERROR "Docker Compose: nie znaleziono"
        all_ok=false
    fi
    
    # Git
    if command -v git &>/dev/null; then
        log OK "Git: $(git --version 2>/dev/null | cut -d' ' -f3)"
    else
        log ERROR "Git: nie znaleziono"
        all_ok=false
    fi
    
    # Make
    if command -v make &>/dev/null; then
        log OK "Make: zainstalowany"
    else
        log ERROR "Make: nie znaleziono"
        all_ok=false
    fi
    
    # jq
    if command -v jq &>/dev/null; then
        log OK "jq: $(jq --version 2>/dev/null)"
    else
        log WARN "jq: nie znaleziono (opcjonalne)"
        ((warnings++))
    fi
    
    # curl
    if command -v curl &>/dev/null; then
        log OK "curl: zainstalowany"
    else
        log ERROR "curl: nie znaleziono"
        all_ok=false
    fi
    
    # netcat
    if command -v nc &>/dev/null; then
        log OK "netcat: zainstalowany"
    else
        log WARN "netcat: nie znaleziono (opcjonalne)"
        ((warnings++))
    fi
    
    # MSSQL Tools (sqlcmd)
    if command -v sqlcmd &>/dev/null; then
        log OK "sqlcmd: zainstalowany"
    elif [ -f /opt/mssql-tools18/bin/sqlcmd ]; then
        log OK "sqlcmd: /opt/mssql-tools18/bin/sqlcmd"
    elif [ -f /opt/mssql-tools/bin/sqlcmd ]; then
        log OK "sqlcmd: /opt/mssql-tools/bin/sqlcmd"
    else
        log WARN "sqlcmd: nie znaleziono (opcjonalne dla testów MSSQL)"
        ((warnings++))
    fi
    
    # Podsumowanie
    echo ""
    if [ "$all_ok" = true ] && [ "$warnings" -eq 0 ]; then
        echo -e "${GREEN}============================================================${NC}"
        echo -e "${GREEN}     [OK] INSTALACJA ZAKONCZONA POMYSLNIE!${NC}"
        echo -e "${GREEN}============================================================${NC}"
    elif [ "$all_ok" = true ]; then
        echo -e "${YELLOW}============================================================${NC}"
        echo -e "${YELLOW}     [!] INSTALACJA ZAKONCZONA Z OSTRZEZENIAMI${NC}"
        echo -e "${YELLOW}============================================================${NC}"
    else
        echo -e "${RED}============================================================${NC}"
        echo -e "${RED}     [X] INSTALACJA NIEPELNA${NC}"
        echo -e "${RED}============================================================${NC}"
        echo ""
        log INFO "Sprawdz logi: $LOG_FILE"
    fi
    
    echo ""
    echo -e "${BOLD}Następne kroki:${NC}"
    echo -e "  1. ${YELLOW}Wyloguj się i zaloguj ponownie${NC} (dla grupy docker)"
    echo -e "  2. Uruchom: ${GREEN}make setup${NC}"
    echo -e "  3. Uruchom: ${GREEN}make start${NC}"
    echo ""
    echo -e "${BOLD}Logi instalacji:${NC} $LOG_FILE"
    echo ""
}

# Główna funkcja
main() {
    # Wykryj system przed sprawdzeniem sudo
    detect_system
    
    # Sprawdź/uzyskaj uprawnienia root
    check_sudo
    
    # Aktualizacja pakietów
    update_system
    
    # Konfiguracja polskiego środowiska
    configure_polish_locale
    
    # Instalacja narzędzi
    install_base_tools
    
    # Instalacja Docker
    if ! install_docker; then
        log ERROR "Instalacja Docker nie powiodła się"
        log INFO "Sprawdź logi: $LOG_FILE"
        exit 1
    fi
    
    # Instalacja Docker Compose
    if ! install_docker_compose; then
        log WARN "Instalacja Docker Compose nie powiodła się (można kontynuować)"
    fi
    
    # Instalacja MSSQL Tools
    install_mssql_tools || log WARN "Instalacja MSSQL Tools nie powiodła się (opcjonalne)"
    
    # Konfiguracja użytkownika
    configure_user
    
    # Uruchomienie Docker
    enable_docker
    
    # Weryfikacja
    verify_installation
    
    log INFO "Instalacja zakończona"
}

main "$@"
