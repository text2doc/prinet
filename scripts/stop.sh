#!/bin/bash
# scripts/stop.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "[X] Zatrzymywanie WAPRO Network Mock..."

# Sprawdz czy docker wymaga sudo
if docker info &>/dev/null 2>&1; then
    docker-compose down
elif sudo docker info &>/dev/null 2>&1; then
    sudo docker-compose down
else
    echo "[!] Docker nie dziala"
    exit 1
fi

echo "[+] Wszystkie serwisy zatrzymane"
