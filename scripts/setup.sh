#!/bin/bash
# scripts/setup.sh
# Konfiguracja środowiska WAPRO Network Mock
set -e

# Kolory
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Konfiguracja środowiska WAPRO Network Mock...${NC}"

# Sprawdzenie czy docker jest zainstalowany
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker nie jest zainstalowany. Uruchom 'make install' najpierw.${NC}"
    exit 1
fi

# Sprawdzenie czy docker-compose jest zainstalowany
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo -e "${RED}❌ Docker Compose nie jest zainstalowany. Uruchom 'make install' najpierw.${NC}"
    exit 1
fi

# Sprawdzenie czy docker daemon działa
if ! docker info &> /dev/null; then
    echo -e "${YELLOW}⚠️  Docker daemon nie działa. Próbuję uruchomić...${NC}"
    
    # Próba uruchomienia Docker
    if sudo systemctl start docker 2>/dev/null; then
        sleep 2
        if docker info &> /dev/null; then
            echo -e "${GREEN}✓ Docker daemon uruchomiony${NC}"
            # Włącz autostart
            sudo systemctl enable docker 2>/dev/null || true
        else
            echo -e "${RED}❌ Nie udało się uruchomić Docker daemon${NC}"
            echo -e "${YELLOW}Spróbuj ręcznie: sudo systemctl start docker${NC}"
            exit 1
        fi
    else
        echo -e "${RED}❌ Docker daemon nie działa${NC}"
        echo -e "${YELLOW}Uruchom: sudo systemctl start docker${NC}"
        echo -e "${YELLOW}Lub zainstaluj Docker: make install${NC}"
        exit 1
    fi
fi

# Tworzenie pliku .env jeśli nie istnieje
if [ ! -f .env ]; then
    echo -e "${YELLOW}📝 Tworzenie pliku .env z szablonu...${NC}"
    if [ -f .env.example ]; then
        cp .env.example .env
        echo -e "${GREEN}✓ Plik .env utworzony${NC}"
    else
        echo -e "${RED}❌ Brak pliku .env.example${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ Plik .env już istnieje${NC}"
fi

# Tworzenie katalogów
echo -e "${BLUE}📁 Tworzenie katalogów...${NC}"
mkdir -p reports tests monitoring/prometheus monitoring/grafana/dashboards monitoring/grafana/datasources
echo -e "${GREEN}✓ Katalogi utworzone${NC}"

# Nadanie uprawnień skryptom
echo -e "${BLUE}🔧 Nadawanie uprawnień skryptom...${NC}"
chmod +x scripts/*.sh 2>/dev/null || true
echo -e "${GREEN}✓ Uprawnienia nadane${NC}"

# Budowanie obrazów
echo -e "${BLUE}🔨 Budowanie obrazów Docker...${NC}"
docker-compose build

echo ""
echo -e "${GREEN}✅ Konfiguracja zakończona pomyślnie!${NC}"
echo ""
echo -e "Następne kroki:"
echo -e "  1. Sprawdź konfigurację w pliku ${YELLOW}.env${NC}"
echo -e "  2. Uruchom środowisko: ${GREEN}make start${NC}"
echo -e "  3. Lub uruchom z profilem: ${GREEN}docker-compose --profile full up -d${NC}"
echo ""
