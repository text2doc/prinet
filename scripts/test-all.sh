#!/bin/bash
set -e

echo "🧪 Uruchamianie testów sieci WAPRO..."

# Uruchomienie testów w kontenerze
docker-compose --profile testing up --build test-runner

echo "📊 Wyniki testów dostępne w katalogu reports/"