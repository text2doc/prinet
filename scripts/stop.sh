#!/bin/bash
# scripts/stop.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "[X] Zatrzymywanie WAPRO Network Mock..."

# 1. Zatrzymaj Docker containers
echo "[i] Zatrzymywanie kontenerow Docker..."
if docker info &>/dev/null 2>&1; then
    docker-compose --profile full down 2>/dev/null || true
    docker-compose -f docker-compose.prod.yml down 2>/dev/null || true
elif sudo docker info &>/dev/null 2>&1; then
    sudo docker-compose --profile full down 2>/dev/null || true
    sudo docker-compose -f docker-compose.prod.yml down 2>/dev/null || true
fi

# 2. Zatrzymaj webenv (port 8888)
echo "[i] Zatrzymywanie webenv..."
pkill -f "webenv.py" 2>/dev/null || true
pkill -f "python3.*webenv" 2>/dev/null || true

# 3. Zatrzymaj CLI
echo "[i] Zatrzymywanie CLI..."
pkill -f "wapro-cli.py" 2>/dev/null || true

# 4. Zatrzymaj discover
pkill -f "discover.py" 2>/dev/null || true

# 5. Zwolnij porty projektu
PORTS="8080 8081 8082 8091 8092 8888 9100 9101 1433 3000 9090"
echo "[i] Sprawdzanie portow: $PORTS"

for port in $PORTS; do
    # Znajdz PID procesu na porcie
    pid=$(lsof -ti :$port 2>/dev/null || true)
    if [ -n "$pid" ]; then
        echo "  [!] Port $port zajety przez PID $pid - zamykam..."
        kill $pid 2>/dev/null || sudo kill $pid 2>/dev/null || true
    fi
done

# 6. Poczekaj chwile i sprawdz
sleep 1

# 7. Sprawdz czy porty sa wolne
occupied=""
for port in $PORTS; do
    if lsof -ti :$port &>/dev/null; then
        occupied="$occupied $port"
    fi
done

if [ -n "$occupied" ]; then
    echo "[!] Porty nadal zajete:$occupied"
    echo "[!] Uzyj: sudo lsof -i :<port> aby sprawdzic"
else
    echo "[+] Wszystkie porty zwolnione"
fi

echo "[+] Wszystkie serwisy zatrzymane"
