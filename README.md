### Uruchomienie monitoringu (Grafana + Prometheus)

Usługi monitoringu są w profilu `monitoring`. Aby je uruchomić i zweryfikować port 3000:

```bash
docker-compose --profile monitoring up -d grafana prometheus
curl -I http://localhost:3000
# Oczekiwany kod HTTP: 302 (redirect do /login)
```

# WAPRO Network Mock - Test Environment

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker](https://img.shields.io/badge/Docker-2CA5E0?style=flat&logo=docker&logoColor=white)](https://www.docker.com/)
[![Python](https://img.shields.io/badge/Python-3.8%2B-blue.svg)](https://www.python.org/)
[![Node.js](https://img.shields.io/badge/Node.js-16%2B-green.svg)](https://nodejs.org/)
[![MSSQL](https://img.shields.io/badge/MSSQL-2019-CC2927?logo=microsoft-sql-server&logoColor=white)](https://www.microsoft.com/sql-server/)

> Mock środowiska sieciowego do testowania integracji z systemem WAPRO, zawierający symulowane serwery RPI, drukarki ZEBRA i bazę danych MSSQL.

## 📚 Dokumentacja

- [API Dokumentacja](docs/API.md) - Opis dostępnych endpointów API
- [Schemat bazy danych](docs/SQL_Schema.md) - Struktura bazy danych WAPROMAG
- [Testowanie](docs/Testing.md) - Instrukcje dotyczące testowania
- [Testy E2E](docs/E2E_Testing.md) - Dokumentacja testów end-to-end
- [WebEnv Editor](docs/WebEnv.md) - Edytor konfiguracji .env
- [Komendy ZEBRA](docs/ZEBRA_Commands.md) - Obsługiwane komendy drukarek
- [Rozwiązywanie problemów](docs/Troubleshooting.md) - Typowe problemy i ich rozwiązania
- [Propozycje refaktoryzacji](docs/Refactoring.md) - Plan ulepszeń kodu

Kompletne środowisko testowe do symulacji sieci WAPRO z bazą danych MSSQL, serwerem RPI i drukarkami ZEBRA.

## 🚀 Szybki start

### Wymagania wstępne

- Docker 20.10+
- Docker Compose 1.29+
- Git

### Instalacja

```bash
git clone https://github.com/text2doc/prinet

# Konfiguracja środowiska
make setup

# Uruchomienie wszystkich serwisów z automatycznymi testami E2E
make start

# Sprawdzenie statusu
make status

# Uruchomienie testów E2E
make test-e2e

# Uruchomienie testów WebEnv
make test-webenv

# Uruchomienie wszystkich testów
make test

# (Opcjonalnie) Szybsze budowanie obrazów
# Lepsza wydajność: ustaw zmienną środowiskową i uruchom ponownie
# Tip: export COMPOSE_BAKE=true
```

## 🏗️ Architektura

```
wapro-network-mock/
├── docker-compose.yml          # Główna konfiguracja Docker
├── Makefile                   # Automatyzacja zadań
├── mssql-wapromag/           # Baza danych WAPROMAG
├── rpi-server/               # Serwer RPI z GUI i API
├── zebra-printer-1/          # Mock drukarki ZEBRA-001
├── zebra-printer-2/          # Mock drukarki ZEBRA-002
├── test-runner/              # Automatyczne testy
├── monitoring/               # Konfiguracja monitoringu (Grafana + Prometheus)
└── scripts/                  # Skrypty pomocnicze
```

## 🌐 Dostępne usługi

| Usługa | Port | Opis |
|--------|------|------|
| RPI Server GUI | 8082 | Interfejs użytkownika |
| RPI Server API | 8081 | API REST |
| ZEBRA Printer 1 | 8091 | Interfejs drukarki 1 |
| ZEBRA Printer 2 | 8092 | Interfejs drukarki 2 |
| ZEBRA Printer 3-6 | 8093-8096 | Interfejsy drukarek 3-6 |
| WebEnv Editor | 8888 | Edytor konfiguracji .env |
| Grafana | 3000 | Panel monitoringu |
| MSSQL Server | 1433 | Baza danych WAPROMAG |

## 🌐 Dostępne interfejsy

- **RPI Server GUI**: http://localhost:8082
- **RPI Server API**: http://localhost:8081
- **ZEBRA Printer 1**: http://localhost:8091
- **ZEBRA Printer 2**: http://localhost:8092
- **ZEBRA Printer 3-6**: http://localhost:8093-8096
- **WebEnv Editor**: http://localhost:8888 (edytor .env)
- **Monitoring**: http://localhost:3000
- **MSSQL WAPROMAG**: localhost:1433

## 🧪 Testowanie

### Uruchamianie testów

```bash
# Uruchomienie środowiska z automatycznymi testami E2E
./scripts/start.sh

# Uruchomienie tylko testów E2E (bez restartu środowiska)
./scripts/test-e2e.sh

# Wszystkie testy
make test

# Testy bazy danych
make test-sql

# Testy drukarek
make test-zebra

# Testy integracyjne
make test-integration
```

### Testy E2E (End-to-End)

Skrypt `start.sh` automatycznie uruchamia kompleksowe testy E2E, które sprawdzają:

1. **MSSQL WAPROMAG**
   - Dostępność portu 1433
   - Możliwość wykonania zapytań SQL

2. **RPI Server**
   - Dostępność GUI (port 8080)
   - Dostępność API (port 8081)
   - Endpoint `/health`

3. **ZEBRA Printer 1**
   - Interfejs web (port 8091)
   - Socket ZPL (port 9100)
   - API status

4. **ZEBRA Printer 2**
   - Interfejs web (port 8092)
   - Socket ZPL (port 9101)
   - API status

5. **Monitoring** (opcjonalne)
   - Grafana Dashboard (port 3000)
   - Prometheus (port 9090)

6. **Integracja**
   - Połączenie RPI → MSSQL

### Preflight i logowanie diagnostyczne

Przed testami wykonywane są preflight-checki i zbiory logów pomocnych w diagnozie:

- Walidacja `docker-compose.yml`
- Sprawdzenie dostępności Dockera i docker-compose
- Podgląd zajętych portów: 8080, 8081, 8091, 8092, 9100, 9101, 1433, 3000
- W przypadku timeoutów lub błędów HTTP, skrypty drukują nagłówki odpowiedzi i ostatnie linie logów z odpowiednich kontenerów

### Generowanie raportów

Wyniki testów są zapisywane w formacie JUnit XML w katalogu `test-results/`.

### Testowanie ręczne

1. **Testowanie drukarek**
   ```bash
   # Wysyłanie przykładowej komendy do drukarki 1
   echo "~HI" | nc localhost 9100
   
   # Wysyłanie etykiety testowej
   echo -e "^XA\n^FO50,50^A0N,50,50^FDTest Label^FS\n^XZ" | nc localhost 9100
   ```

2. **Testowanie bazy danych**
   ```bash
   # Połączenie z bazą danych
   sqlcmd -S localhost,1433 -U sa -P WapromagPass123!
   ```

## 🏥 Monitoring i diagnostyka

```bash
# Stan zdrowia systemu
make health

# Logi wszystkich serwisów
make logs

# Logi konkretnego serwisu
make logs-rpi
make logs-zebra1
make logs-sql
```

## 🛠️ Zarządzanie

```bash
# Restart systemu
make restart

# WebEnv - edytor konfiguracji .env
make webenv_start    # Uruchom w tle
make webenv_stop     # Zatrzymaj
make webenv          # Uruchom (blokujący)

# Czyszczenie środowiska
make clean

# Backup bazy danych
make backup-db

# Przywracanie bazy danych
make restore-db
```

## 📊 Funkcjonalności

### RPI Server
- ✅ Interfejs użytkownika do zarządzania systemem
- ✅ REST API do komunikacji zewnętrznej
- ✅ Integracja z bazą danych WAPROMAG
- ✅ Obsługa wielu drukarek ZEBRA
- ✅ Panel monitoringu w czasie rzeczywistym

### Monitorowanie
- 🚀 Pulpity nawigacyjne Grafana
- 📊 Metryki wydajności w czasie rzeczywistym
- 🔔 Alerty i powiadomienia
- 📈 Monitorowanie stanu drukarek

### Bezpieczeństwo
- 🔒 Uwierzytelnianie użytkowników
- 🔑 Bezpieczne przechowywanie haseł
- 🔄 Automatyczne kopie zapasowe bazy danych

## 🔄 Zarządzanie

### Uruchamianie i zatrzymywanie

```bash
# Uruchomienie wszystkich usług
make start

# Zatrzymanie wszystkich usług
make stop

# Restart usług
make restart

# Wyświetlenie statusu
make status
```

### Konserwacja

```bash
# Utworzenie kopii zapasowej bazy danych
make backup-db

# Przywrócenie bazy danych z kopii zapasowej
make restore-db

# Czyszczenie środowiska
make clean
```

## 🤝 Wsparcie

W przypadku problemów, zapoznaj się z sekcją [Rozwiązywanie problemów](docs/Troubleshooting.md) lub zgłoś nowy problem w zakładce Issues.

## 📄 Licencja

Ten projekt jest objęty licencją MIT. Szczegóły znajdują się w pliku [LICENSE](LICENSE).
- ✅ Testy połączeń z bazą danych
- ✅ Wysyłanie komend do drukarek ZEBRA
- ✅ Diagnostyka systemu
- ✅ Monitoring w czasie rzeczywistym

### Baza danych WAPROMAG
- ✅ Tabele: Kontrahenci, Produkty, Dokumenty Magazynowe
- ✅ Stany magazynowe i ruch magazynowy
- ✅ Konfiguracja drukarek
- ✅ Szablony etykiet ZPL
- ✅ Procedury magazynowe

### Drukarki ZEBRA Mock
- ✅ Symulacja protokołu ZPL
- ✅ Interfejs web do monitorowania
- ✅ Obsługa podstawowych komend (~HI, ~HS, PING)
- ✅ Drukowanie etykiet testowych
- ✅ Logi operacji

### System testowy
- ✅ Testy połączeń sieciowych
- ✅ Testy komunikacji RPI ↔ SQL
- ✅ Testy komunikacji RPI ↔ ZEBRA
- ✅ Testy integracyjne end-to-end
- ✅ Testy wydajnościowe
- ✅ Automatyczne raporty

## 🔧 Konfiguracja

Wszystkie ustawienia można zmienić w pliku `.env`:

```bash
# Database
MSSQL_WAPROMAG_PASSWORD=WapromagPass123!

# Printers
ZEBRA_1_NAME=ZEBRA-001
ZEBRA_2_NAME=ZEBRA-002

# Ports
RPI_GUI_PORT=8080
RPI_API_PORT=8081
```

## 🎯 Przypadki użycia

1. **Test komunikacji z WAPROMAG**: Weryfikacja połączeń i zapytań SQL
2. **Test drukarek ZEBRA**: Sprawdzenie dostępności i drukowania etykiet
3. **Test workflow**: Pobranie danych z bazy → generowanie etykiety → drukowanie
4. **Test wydajności**: Obciążenie systemu wieloma równoczesnymi operacjami
5. **Test diagnostyki**: Monitorowanie stanu wszystkich komponentów

## 📝 Wymagania

- Docker Engine 20.10+
- Docker Compose 2.0+
- 4GB RAM (zalecane 8GB)
- 10GB przestrzeni dyskowej

## 🆘 Rozwiązywanie problemów

```bash
# Sprawdzenie logów
make logs

# Reset środowiska
make clean && make setup && make start

# Test połączeń
make health

# Terminal do debugowania
make shell-rpi
make shell-sql
```
