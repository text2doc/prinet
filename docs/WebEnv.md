# WebEnv - Edytor konfiguracji .env

## Przegląd

WebEnv to webowy edytor pliku `.env` dostępny pod adresem `http://localhost:8888`. Umożliwia edycję konfiguracji środowiska bez konieczności edytowania plików bezpośrednio.

## Uruchamianie

```bash
# Uruchomienie w tle (zalecane)
make webenv_start

# Zatrzymanie
make webenv_stop

# Uruchomienie blokujące (foreground)
make webenv
```

## Funkcjonalności

### 1. Edytor .env
- Edycja pliku `.env` w textarea
- Podgląd `.env.example` (tylko odczyt)
- Zapisywanie zmian
- Reset do wartości domyślnych z `.env.example`

### 2. Edytor konfiguracji (tabela)
- **Dynamiczne grupowanie** - zmienne są automatycznie grupowane po prefixie:
  - `COMPOSE_` → Docker Compose
  - `NETWORK_` → Sieć
  - `MSSQL_` → Baza danych MSSQL
  - `RPI_` → Serwer RPI
  - `ZEBRA_1_`, `ZEBRA_2_`, ... → Drukarki Zebra (wykrywane dynamicznie)
  - `GRAFANA_`, `PROMETHEUS_` → Monitoring
  - `TEST_` → Testy
  - Inne → sekcja "Inne"

- **Kolumny tabeli**:
  - Parametr (nazwa zmiennej)
  - Aktualna wartość (edytowalna)
  - Domyślna wartość z `.env.example` (do porównania)
  - Propozycja ze skanu sieci
  - Akcja (przycisk "Użyj" dla propozycji)

- **Wizualne podświetlenie różnic**:
  - Pomarańczowa ramka = wartość różni się od domyślnej
  - Pola z `PASSWORD`, `SECRET`, `TOKEN` → ukryte (type="password")

### 3. Skanowanie sieci
- Wykrywanie drukarek Zebra w sieci
- Wykrywanie serwerów MSSQL
- Propozycje konfiguracji na podstawie wykrytych urządzeń

### 4. Panel Admin (make)
- Uruchamianie komend `make` z poziomu GUI
- Dostępne komendy: `start`, `stop`, `restart`, `status`, `discover`, `health`
- Podgląd logów wykonania
- Opcjonalna autoryzacja tokenem

## API Endpoints

| Endpoint | Metoda | Opis |
|----------|--------|------|
| `/` | GET | Strona główna (HTML) |
| `/load` | GET | Pobierz zawartość .env |
| `/save` | POST | Zapisz .env (content=...) |
| `/reset` | POST | Reset do .env.example |
| `/devices` | GET | Pobierz wykryte urządzenia |
| `/admin/status` | GET | Status wykonywania make |
| `/admin/logs` | GET | Logi make |
| `/admin/run` | POST | Uruchom make (target=...) |

## Testy E2E

```bash
# Uruchomienie testów WebEnv
make test-webenv

# Lub bezpośrednio
./scripts/test-webenv.sh
```

### Testowane funkcjonalności:
- ✅ Dostępność strony (HTTP 200)
- ✅ Obecność elementów HTML (textarea, przyciski)
- ✅ API `/load` - pobieranie .env
- ✅ API `/save` - zapisywanie .env
- ✅ API `/reset` - reset do domyślnych
- ✅ API `/devices` - wykryte urządzenia
- ✅ Admin panel `/admin/status`
- ✅ Admin panel `/admin/logs`

## Autoryzacja Admin Panel

Jeśli zmienna `WEBENV_ADMIN_TOKEN` jest ustawiona, dostęp do endpointów `/admin/*` wymaga tokena:

```bash
# Ustawienie tokena
export WEBENV_ADMIN_TOKEN=my-secret-token

# Wywołanie z tokenem
curl -H "X-Admin-Token: my-secret-token" http://localhost:8888/admin/status
```

Bez tokena, dostęp jest dozwolony tylko z localhost.

## Logi

Logi WebEnv są zapisywane do `logs/webenv.log` przy uruchomieniu przez `make webenv_start`.

Logi wykonania komend make są zapisywane do `logs/webenv_make.log`.

## Rozwiązywanie problemów

### WebEnv nie uruchamia się
```bash
# Sprawdź czy port 8888 jest wolny
fuser 8888/tcp

# Zabij proces na porcie
make webenv_stop

# Uruchom ponownie
make webenv_start
```

### Tabela nie pokazuje wszystkich zmiennych
- Odśwież stronę z wyczyszczeniem cache: `Ctrl+Shift+R`
- Sprawdź czy `.env` zawiera wszystkie zmienne

### Admin panel zwraca "Unauthorized"
- Ustaw token w GUI lub usuń zmienną `WEBENV_ADMIN_TOKEN`
- Upewnij się, że łączysz się z localhost
