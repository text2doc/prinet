# Testy E2E (End-to-End) - Dokumentacja

## Przegląd

System WAPRO Network Mock posiada zintegrowane testy E2E, które automatycznie weryfikują poprawność działania wszystkich komponentów po uruchomieniu środowiska Docker Compose.

## Dostępne skrypty testowe

### 1. `scripts/start.sh` - Uruchomienie z testami

Główny skrypt startowy, który:
1. Uruchamia wszystkie kontenery Docker
2. Czeka na inicjalizację usług
3. Automatycznie przeprowadza testy E2E
4. Wyświetla podsumowanie wyników

```bash
./scripts/start.sh
```

**Funkcje:**
- ✅ Automatyczne uruchamianie kontenerów
- ✅ Inteligentne czekanie na dostępność usług
- ✅ Kompleksowe testy wszystkich komponentów
- ✅ Kolorowe raporty z wynikami
- ✅ Zwraca kod wyjścia 1 jeśli jakikolwiek test nie przeszedł

### 2. `scripts/test-e2e.sh` - Tylko testy

Skrypt dedykowany tylko do testowania (bez restartu kontenerów):

```bash
./scripts/test-e2e.sh
```

**Zastosowanie:**
- Testowanie już uruchomionego środowiska
- Weryfikacja po zmianach konfiguracji
- Diagnostyka problemów
- CI/CD pipelines

### 3. Makefile - Szybkie komendy

```bash
# Uruchomienie z testami
make start

# Tylko testy E2E
make test-e2e

# Status środowiska
make status
```

## Komponenty testowane

### 1. MSSQL WAPROMAG Database

**Testy wykonywane:**
- ✅ Dostępność portu 1433
- ✅ Możliwość wykonania zapytań SQL
- ✅ Połączenie z użytkownikiem `sa`

**Przykład wyniku:**
```
💾 Testowanie MSSQL WAPROMAG Database:
   Czekam na MSSQL Server Port (localhost:1433)... ✓
   Testuję MSSQL WAPROMAG... ✓
```

### 2. RPI Mock Server

**Testy wykonywane:**
- ✅ Dostępność GUI (port 8080)
- ✅ Dostępność API (port 8081)
- ✅ Health endpoint `/health`
- ✅ Odpowiedź HTTP 200

**Przykład wyniku:**
```
🖥️  Testowanie RPI Mock Server:
   Czekam na RPI GUI Port (localhost:8080)... ✓
   Czekam na RPI API Port (localhost:8081)... ✓
   Testuję RPI GUI Interface (http://localhost:8080)... ✓ (HTTP 200)
   Testuję RPI API Health (http://localhost:8081/health)... ✓ (HTTP 200)
```

### 3. ZEBRA Printer 1

**Testy wykonywane:**
- ✅ Interfejs web (port 8091)
- ✅ Socket ZPL (port 9100)
- ✅ API endpoint `/api/status`
- ✅ Walidacja odpowiedzi JSON

**Przykład wyniku:**
```
🖨️  Testowanie ZEBRA Printer 1:
   Testuję ZEBRA Printer 1 Web UI (http://localhost:8091)... ✓ (HTTP 200)
   Testuję ZEBRA Printer 1 ZPL Socket (localhost:9100)... ✓
   Testuję ZEBRA Printer 1 Status API (http://localhost:8091/api/status)... ✓ (valid JSON)
   ✅ Wszystkie testy przeszły pomyślnie
```

### 4. ZEBRA Printer 2

**Testy wykonywane:**
- ✅ Interfejs web (port 8092)
- ✅ Socket ZPL (port 9101)
- ✅ API endpoint `/api/status`
- ✅ Walidacja odpowiedzi JSON

**Przykład wyniku:**
```
🖨️  Testowanie ZEBRA Printer 2:
   Testuję ZEBRA Printer 2 Web UI (http://localhost:8092)... ✓ (HTTP 200)
   Testuję ZEBRA Printer 2 ZPL Socket (localhost:9101)... ✓
   Testuję ZEBRA Printer 2 Status API (http://localhost:8092/api/status)... ✓ (valid JSON)
   ✅ Wszystkie testy przeszły pomyślnie
```

### 5. Monitoring Services (Opcjonalne)

**Testy wykonywane:**
- ✅ Grafana Dashboard (port 3000, HTTP 302)
- ✅ Prometheus (port 9090)

**Uwaga:** Te testy są wykonywane tylko jeśli usługi są uruchomione (profil `monitoring`).

```bash
# Uruchomienie z monitoringiem
docker-compose --profile monitoring up -d
./scripts/test-e2e.sh
```

### 6. Testy integracyjne

**Testy wykonywane:**
- ✅ Połączenie RPI Server → MSSQL (wewnętrzna sieć Docker)

## Podsumowanie wyników

Po zakończeniu wszystkich testów wyświetlane jest szczegółowe podsumowanie:

```
═══════════════════════════════════════════════════════════
📈 PODSUMOWANIE TESTÓW E2E:
═══════════════════════════════════════════════════════════
   Wszystkie testy:    14
   Zaliczone:          14
   Niezaliczone:       0
   ✅ Status:           SUKCES
═══════════════════════════════════════════════════════════
```

## Interpretacja wyników

### ✅ Sukces (wszystkie testy przeszły)
- Kod wyjścia: `0`
- Wszystkie usługi działają poprawnie
- Środowisko gotowe do użycia

### ⚠️ Częściowy sukces (niektóre testy nie przeszły)
- Kod wyjścia: `1`
- Przynajmniej jedna usługa ma problemy
- Sprawdź logi problematycznej usługi:
  ```bash
  docker-compose logs <service_name>
  ```

### ❌ Pełna porażka (wszystkie testy nie przeszły)
- Kod wyjścia: `1`
- Prawdopodobnie problem z Docker Compose
- Wykonaj:
  ```bash
  docker-compose ps
  docker-compose logs
  ```

## Kody kolorów w wynikach

- 🟢 **Zielony (✓)** - Test przeszedł pomyślnie
- 🔴 **Czerwony (✗)** - Test nie przeszedł
- 🟡 **Żółty (⚠)** - Ostrzeżenie (np. odpowiedź nie jest JSON, ale endpoint działa)

## Funkcje pomocnicze

### `wait_for_service(host, port, service_name)`
Czeka maksymalnie 30 sekund na dostępność portu.

```bash
wait_for_service "localhost" "1433" "MSSQL Server Port"
```

### `test_http_endpoint(url, service_name, expected_status)`
Testuje endpoint HTTP i sprawdza kod odpowiedzi.

```bash
test_http_endpoint "http://localhost:8080" "RPI GUI" "200"
```

### `test_tcp_socket(host, port, service_name)`
Testuje dostępność socketu TCP.

```bash
test_tcp_socket "localhost" "9100" "ZEBRA Socket"
```

### `test_api_endpoint(url, service_name)`
Testuje endpoint API i waliduje format JSON.

```bash
test_api_endpoint "http://localhost:8091/api/status" "ZEBRA Status"
```

### `test_zebra_printer(web_port, socket_port, printer_name)`
Kompleksowy test drukarki ZEBRA (web + socket + API).

```bash
test_zebra_printer "8091" "9100" "ZEBRA Printer 1"
```

### `test_mssql()`
Test połączenia z bazą danych MSSQL.

```bash
test_mssql
```

## Wymagania systemowe dla testów

### Narzędzia wymagane na hoście
- `curl` - testowanie HTTP endpoints
- `nc` (netcat) - testowanie socketów TCP
- `jq` - walidacja JSON (opcjonalne, ale zalecane)
- `docker` - dostęp do kontenerów

### Instalacja narzędzi (Debian/Ubuntu)
```bash
sudo apt-get install curl netcat-openbsd jq docker.io
```

### Instalacja narzędzi (Alpine/Docker)
```bash
apk add curl netcat-openbsd jq
```

## Integracja z CI/CD

### GitHub Actions

```yaml
name: E2E Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup environment
        run: ./scripts/setup.sh
      
      - name: Start services with E2E tests
        run: ./scripts/start.sh
      
      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: test-results
          path: test-results/
```

### GitLab CI

```yaml
e2e_tests:
  stage: test
  image: docker:latest
  services:
    - docker:dind
  script:
    - ./scripts/setup.sh
    - ./scripts/start.sh
  artifacts:
    paths:
      - test-results/
    when: always
```

## Debugowanie testów

### Test pojedynczego komponentu

```bash
# Tylko MSSQL
docker exec wapromag-mssql /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "WapromagPass123!" -Q "SELECT 1"

# Tylko RPI Server
curl -v http://localhost:8080/health

# Tylko ZEBRA Printer
echo -e "\n" | nc -v localhost 9100
```

### Logi w czasie rzeczywistym

```bash
# Wszystkie usługi
docker-compose logs -f

# Konkretna usługa
docker-compose logs -f rpi-server
```

### Restart problematycznej usługi

```bash
docker-compose restart rpi-server
./scripts/test-e2e.sh
```

## Najlepsze praktyki

1. **Zawsze uruchamiaj testy po zmianach** - Użyj `./scripts/start.sh` zamiast `docker-compose up -d`

2. **Sprawdzaj logi przy błędach** - Każdy nieudany test powinien być zdiagnozowany z logów

3. **Używaj health checków** - Docker Compose health checks są komplementarne do testów E2E

4. **Timeout jest Twoim przyjacielem** - Jeśli test nie przeszedł z timeout, usługa prawdopodobnie się nie uruchomiła

5. **Testuj integrację** - Nie tylko pojedyncze komponenty, ale także komunikację między nimi

## Rozszerzanie testów

Aby dodać nowy test:

1. Otwórz `scripts/start.sh` lub `scripts/test-e2e.sh`
2. Dodaj nową sekcję testową
3. Zwiększ licznik `TOTAL_TESTS`
4. Wywołaj funkcję testową
5. Zaktualizuj liczniki `PASSED_TESTS` i `FAILED_TESTS`

**Przykład:**

```bash
# ============================================================================
# TEST X: NOWY KOMPONENT
# ============================================================================
echo ""
echo "🔧 Testowanie Nowego Komponentu:"
TOTAL_TESTS=$((TOTAL_TESTS + 1))

if test_http_endpoint "http://localhost:9999" "Nowy Komponent"; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
```

## FAQ

**Q: Dlaczego testy nie przechodzą od razu po `docker-compose up`?**  
A: Kontenery potrzebują czasu na inicjalizację. Funkcja `wait_for_service()` czeka do 30 sekund.

**Q: Co zrobić jeśli test przeszedł ale usługa nie działa?**  
A: Sprawdź logi (`docker-compose logs`) - może być problem z aplikacją mimo że port jest otwarty.

**Q: Czy mogę uruchomić testy bez restartu środowiska?**  
A: Tak! Użyj `./scripts/test-e2e.sh` zamiast `./scripts/start.sh`.

**Q: Jak dodać custom timeout?**  
A: Edytuj parametr `max_attempts` w funkcji `wait_for_service()`.

**Q: Czy testy E2E działają na Windows?**  
A: Tak, ale potrzebujesz WSL2 lub Git Bash z narzędziami (curl, nc).

## Wsparcie

W przypadku problemów:
1. Sprawdź [Troubleshooting.md](Troubleshooting.md)
2. Uruchom `make health` dla szybkiej diagnostyki
3. Sprawdź logi: `make logs`
4. Zgłoś problem w Issues na GitHubie
