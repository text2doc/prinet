#!/bin/bash
# scripts/setup_simple.sh
# Prosta konfiguracja projektu WAPRO Network Mock

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Kolory
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}       WAPRO Network Mock - Setup${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""

cd "$PROJECT_DIR"

# 1. Plik .env
echo -e "${BLUE}[1/5]${NC} Konfiguracja .env..."
if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        cp .env.example .env
        echo -e "  ${GREEN}[+]${NC} Utworzono .env z szablonu"
    else
        echo -e "  ${RED}[X]${NC} Brak pliku .env.example!"
        exit 1
    fi
else
    echo -e "  ${GREEN}[+]${NC} Plik .env juz istnieje"
fi

# 2. Katalogi
echo -e "${BLUE}[2/5]${NC} Tworzenie katalogow..."
mkdir -p logs reports tests
mkdir -p monitoring/prometheus
mkdir -p monitoring/grafana/dashboards
mkdir -p monitoring/grafana/datasources
echo -e "  ${GREEN}[+]${NC} Katalogi utworzone"

# 3. Uprawnienia
echo -e "${BLUE}[3/5]${NC} Ustawianie uprawnien..."
chmod +x scripts/*.sh 2>/dev/null || true
chmod +x scripts/*.py 2>/dev/null || true
echo -e "  ${GREEN}[+]${NC} Uprawnienia OK"

# 4. Sprawdzenie Docker
echo -e "${BLUE}[4/5]${NC} Sprawdzanie Docker..."
if command -v docker &>/dev/null; then
    docker_ver=$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
    echo -e "  ${GREEN}[+]${NC} Docker: $docker_ver"
else
    echo -e "  ${YELLOW}[!]${NC} Docker nie zainstalowany - uruchom: make install"
fi

if docker compose version &>/dev/null; then
    compose_ver=$(docker compose version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
    echo -e "  ${GREEN}[+]${NC} Docker Compose: $compose_ver"
elif command -v docker-compose &>/dev/null; then
    compose_ver=$(docker-compose --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
    echo -e "  ${GREEN}[+]${NC} Docker Compose: $compose_ver"
else
    echo -e "  ${YELLOW}[!]${NC} Docker Compose nie zainstalowany"
fi

# 5. Budowanie obrazow (opcjonalne)
echo -e "${BLUE}[5/5]${NC} Budowanie obrazow Docker..."
if docker info &>/dev/null; then
    if docker-compose build 2>&1 | tail -5; then
        echo -e "  ${GREEN}[+]${NC} Obrazy zbudowane"
    else
        echo -e "  ${YELLOW}[!]${NC} Problemy z budowaniem - sprawdz logi"
    fi
else
    echo -e "  ${YELLOW}[!]${NC} Docker daemon nie dziala - pominam budowanie"
    echo -e "  ${YELLOW}[!]${NC} Uruchom: sudo systemctl start docker"
fi

# Podsumowanie
echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}     [OK] KONFIGURACJA ZAKONCZONA${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "Nastepne kroki:"
echo -e "  1. ${GREEN}make start${NC}  - uruchom uslugi"
echo -e "  2. ${GREEN}make webenv${NC} - edytuj .env w przegladarce"
echo -e "  3. ${GREEN}make status${NC} - sprawdz status"
echo ""
