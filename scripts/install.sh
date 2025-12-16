#!/bin/bash
# scripts/install.sh
# Instalacja wymaganych programów dla WAPRO Network Mock
# Wspiera: Raspberry Pi OS, Debian, Ubuntu
set -e

# Kolory
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     WAPRO Network Mock - Instalacja zależności          ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Wykrywanie systemu
detect_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    elif [ -f /etc/debian_version ]; then
        OS="debian"
    else
        OS="unknown"
    fi
    
    # Wykrywanie architektury
    ARCH=$(uname -m)
    
    # Wykrywanie RPi
    IS_RPI=false
    if [ -f /proc/device-tree/model ]; then
        if grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
            IS_RPI=true
        fi
    fi
    
    echo -e "${BLUE}📋 Wykryte parametry systemu:${NC}"
    echo -e "   OS: ${GREEN}$OS${NC}"
    echo -e "   Architektura: ${GREEN}$ARCH${NC}"
    echo -e "   Raspberry Pi: ${GREEN}$IS_RPI${NC}"
    echo ""
}

# Sprawdzenie czy skrypt uruchomiony z sudo
check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}⚠️  Skrypt wymaga uprawnień root. Uruchamiam z sudo...${NC}"
        exec sudo "$0" "$@"
    fi
}

# Aktualizacja systemu
update_system() {
    echo -e "${BLUE}📦 Aktualizacja listy pakietów...${NC}"
    apt-get update -qq
    echo -e "${GREEN}✓ Lista pakietów zaktualizowana${NC}"
}

# Instalacja podstawowych narzędzi
install_base_tools() {
    echo -e "${BLUE}🔧 Instalacja podstawowych narzędzi...${NC}"
    
    local packages="curl wget git make jq netcat-openbsd ca-certificates gnupg lsb-release"
    
    for pkg in $packages; do
        if dpkg -l | grep -q "^ii  $pkg "; then
            echo -e "   ${GREEN}✓${NC} $pkg (już zainstalowany)"
        else
            echo -e "   ${YELLOW}→${NC} Instaluję $pkg..."
            apt-get install -y -qq $pkg > /dev/null 2>&1
            echo -e "   ${GREEN}✓${NC} $pkg zainstalowany"
        fi
    done
}

# Instalacja Docker
install_docker() {
    echo -e "${BLUE}🐳 Instalacja Docker...${NC}"
    
    if command -v docker &> /dev/null; then
        local docker_version=$(docker --version 2>/dev/null | cut -d ' ' -f 3 | tr -d ',')
        echo -e "   ${GREEN}✓${NC} Docker już zainstalowany (wersja: $docker_version)"
        return 0
    fi
    
    echo -e "   ${YELLOW}→${NC} Usuwam stare wersje Docker..."
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    if [ "$IS_RPI" = true ] || [ "$ARCH" = "armv7l" ] || [ "$ARCH" = "aarch64" ]; then
        echo -e "   ${YELLOW}→${NC} Instalacja Docker dla ARM (Raspberry Pi)..."
        curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
        sh /tmp/get-docker.sh
        rm /tmp/get-docker.sh
    else
        echo -e "   ${YELLOW}→${NC} Instalacja Docker dla x86_64..."
        
        # Dodanie klucza GPG Docker
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        
        # Dodanie repozytorium
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
          $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        apt-get update -qq
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
    
    echo -e "   ${GREEN}✓${NC} Docker zainstalowany"
}

# Instalacja Docker Compose
install_docker_compose() {
    echo -e "${BLUE}🔗 Instalacja Docker Compose...${NC}"
    
    # Sprawdzenie nowej wersji (docker compose)
    if docker compose version &> /dev/null; then
        local compose_version=$(docker compose version 2>/dev/null | cut -d ' ' -f 4)
        echo -e "   ${GREEN}✓${NC} Docker Compose plugin już zainstalowany (wersja: $compose_version)"
        
        # Tworzenie aliasu docker-compose jeśli nie istnieje
        if ! command -v docker-compose &> /dev/null; then
            echo -e "   ${YELLOW}→${NC} Tworzenie aliasu docker-compose..."
            cat > /usr/local/bin/docker-compose << 'EOF'
#!/bin/bash
docker compose "$@"
EOF
            chmod +x /usr/local/bin/docker-compose
            echo -e "   ${GREEN}✓${NC} Alias docker-compose utworzony"
        fi
        return 0
    fi
    
    # Sprawdzenie starej wersji (docker-compose)
    if command -v docker-compose &> /dev/null; then
        local compose_version=$(docker-compose --version 2>/dev/null | cut -d ' ' -f 4)
        echo -e "   ${GREEN}✓${NC} Docker Compose już zainstalowany (wersja: $compose_version)"
        return 0
    fi
    
    # Instalacja Docker Compose
    echo -e "   ${YELLOW}→${NC} Pobieranie Docker Compose..."
    
    # Określenie wersji dla architektury
    local COMPOSE_ARCH=""
    case "$ARCH" in
        x86_64)  COMPOSE_ARCH="x86_64" ;;
        aarch64) COMPOSE_ARCH="aarch64" ;;
        armv7l)  COMPOSE_ARCH="armv7" ;;
        *)       COMPOSE_ARCH="x86_64" ;;
    esac
    
    local COMPOSE_VERSION="v2.24.0"
    curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-${COMPOSE_ARCH}" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    echo -e "   ${GREEN}✓${NC} Docker Compose zainstalowany"
}

# Konfiguracja użytkownika
configure_user() {
    echo -e "${BLUE}👤 Konfiguracja użytkownika...${NC}"
    
    # Pobranie nazwy użytkownika (nie root)
    local REAL_USER="${SUDO_USER:-$USER}"
    
    if [ "$REAL_USER" != "root" ]; then
        if groups "$REAL_USER" | grep -q docker; then
            echo -e "   ${GREEN}✓${NC} Użytkownik $REAL_USER już w grupie docker"
        else
            echo -e "   ${YELLOW}→${NC} Dodawanie $REAL_USER do grupy docker..."
            usermod -aG docker "$REAL_USER"
            echo -e "   ${GREEN}✓${NC} Użytkownik $REAL_USER dodany do grupy docker"
            echo -e "   ${YELLOW}⚠️  Wyloguj się i zaloguj ponownie, aby zmiany zadziałały${NC}"
        fi
    fi
}

# Uruchomienie i włączenie Docker
enable_docker() {
    echo -e "${BLUE}🚀 Konfiguracja usługi Docker...${NC}"
    
    systemctl enable docker 2>/dev/null || true
    systemctl start docker 2>/dev/null || true
    
    if systemctl is-active --quiet docker; then
        echo -e "   ${GREEN}✓${NC} Docker daemon uruchomiony"
    else
        echo -e "   ${YELLOW}⚠️${NC} Docker daemon nie uruchomiony - spróbuj: sudo systemctl start docker"
    fi
}

# Weryfikacja instalacji
verify_installation() {
    echo ""
    echo -e "${BLUE}🔍 Weryfikacja instalacji...${NC}"
    
    local all_ok=true
    
    # Docker
    if command -v docker &> /dev/null; then
        local docker_ver=$(docker --version 2>/dev/null | cut -d ' ' -f 3 | tr -d ',')
        echo -e "   ${GREEN}✓${NC} Docker: $docker_ver"
    else
        echo -e "   ${RED}✗${NC} Docker: nie znaleziono"
        all_ok=false
    fi
    
    # Docker Compose
    if docker compose version &> /dev/null; then
        local compose_ver=$(docker compose version 2>/dev/null | cut -d ' ' -f 4)
        echo -e "   ${GREEN}✓${NC} Docker Compose: $compose_ver"
    elif command -v docker-compose &> /dev/null; then
        local compose_ver=$(docker-compose --version 2>/dev/null | cut -d ' ' -f 4)
        echo -e "   ${GREEN}✓${NC} Docker Compose: $compose_ver"
    else
        echo -e "   ${RED}✗${NC} Docker Compose: nie znaleziono"
        all_ok=false
    fi
    
    # Git
    if command -v git &> /dev/null; then
        local git_ver=$(git --version 2>/dev/null | cut -d ' ' -f 3)
        echo -e "   ${GREEN}✓${NC} Git: $git_ver"
    else
        echo -e "   ${RED}✗${NC} Git: nie znaleziono"
        all_ok=false
    fi
    
    # Make
    if command -v make &> /dev/null; then
        local make_ver=$(make --version 2>/dev/null | head -1 | cut -d ' ' -f 3)
        echo -e "   ${GREEN}✓${NC} Make: $make_ver"
    else
        echo -e "   ${RED}✗${NC} Make: nie znaleziono"
        all_ok=false
    fi
    
    # jq
    if command -v jq &> /dev/null; then
        local jq_ver=$(jq --version 2>/dev/null)
        echo -e "   ${GREEN}✓${NC} jq: $jq_ver"
    else
        echo -e "   ${RED}✗${NC} jq: nie znaleziono"
        all_ok=false
    fi
    
    # curl
    if command -v curl &> /dev/null; then
        echo -e "   ${GREEN}✓${NC} curl: zainstalowany"
    else
        echo -e "   ${RED}✗${NC} curl: nie znaleziono"
        all_ok=false
    fi
    
    # netcat
    if command -v nc &> /dev/null; then
        echo -e "   ${GREEN}✓${NC} netcat: zainstalowany"
    else
        echo -e "   ${RED}✗${NC} netcat: nie znaleziono"
        all_ok=false
    fi
    
    echo ""
    if [ "$all_ok" = true ]; then
        echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║     ✅ Wszystkie zależności zainstalowane poprawnie!     ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    else
        echo -e "${YELLOW}╔══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║     ⚠️  Niektóre zależności nie zostały zainstalowane    ║${NC}"
        echo -e "${YELLOW}╚══════════════════════════════════════════════════════════╝${NC}"
    fi
    
    echo ""
    echo -e "Następne kroki:"
    echo -e "  1. Wyloguj się i zaloguj ponownie (dla grupy docker)"
    echo -e "  2. Uruchom: ${GREEN}make setup${NC}"
    echo -e "  3. Uruchom: ${GREEN}make start${NC}"
    echo ""
}

# Główna funkcja
main() {
    detect_system
    check_sudo
    update_system
    install_base_tools
    install_docker
    install_docker_compose
    configure_user
    enable_docker
    verify_installation
}

main "$@"
