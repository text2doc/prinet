# Konfiguracja skryptów MSSQL

## 📋 Ładowanie konfiguracji

Wszystkie skrypty w folderze `mssql/` używają **hierarchicznej konfiguracji**:

1. **Domyślne wartości** - wbudowane w skrypt jako fallback
2. **Plik .env** - ładowany z katalogu `mssql/.env`
3. **Argumenty linii komend** - nadpisują wartości z .env

### 🔄 Kolejność priorytetów:
```
Argumenty CLI > Plik .env > Wartości domyślne
```

## 📁 Struktura pliku .env

Skopiuj `.env.example` do `.env` i dostosuj do swoich potrzeb:

```bash
cp .env.example .env
nano .env
```

### 🔧 Główne zmienne konfiguracyjne:

#### **Źródłowa baza danych (migration source):**
```bash
SOURCE_DB_HOST=localhost          # Host źródłowej bazy
SOURCE_DB_PORT=1433              # Port źródłowej bazy
SOURCE_DB_USER=sa                # Użytkownik źródłowej bazy
SOURCE_DB_PASSWORD=SourcePass123! # Hasło źródłowej bazy
SOURCE_DB_NAME=WAPRO_PRODUCTION   # Nazwa źródłowej bazy
```

#### **Docelowa baza danych (migration target):**
```bash
TARGET_DB_HOST=localhost          # Host docelowej bazy
TARGET_DB_PORT=1433              # Port docelowej bazy
TARGET_DB_USER=sa                # Użytkownik docelowej bazy
TARGET_DB_PASSWORD=WapromagPass123! # Hasło docelowej bazy
TARGET_DB_NAME=WAPROMAG_TEST      # Nazwa docelowej bazy
```

#### **Konfiguracja backupu:**
```bash
BACKUP_PATH=/var/opt/mssql/backup # Ścieżka do backupów
BACKUP_RETENTION_DAYS=30          # Dni retencji backupów
BACKUP_COMPRESS=true              # Kompresja backupów
```

#### **Ustawienia migracji:**
```bash
MIGRATION_BATCH_SIZE=1000         # Rozmiar batcha migracji
MIGRATION_TIMEOUT=300             # Timeout migracji (sekundy)
MIGRATION_LOG_LEVEL=INFO          # Poziom logowania
```

## 🚀 Przykłady użycia

### 1. Backup z domyślną konfiguracją:
```bash
./backup.sh
# Używa: TARGET_DB_NAME i BACKUP_PATH z .env
```

### 2. Backup z argumentami:
```bash
./backup.sh -d CUSTOM_DB -p /custom/backup/path -c -v
# Nadpisuje: database name i backup path
# Używa z .env: connection credentials
```

### 3. Migracja z nadpisywaniem - domyślna:
```bash
./migrate_overwrite.sh
# Używa: SOURCE_DB_NAME -> TARGET_DB_NAME z .env
```

### 4. Migracja z argumentami:
```bash
./migrate_overwrite.sh -s PROD_DB -t TEST_DB --source-host prod.server.com -b 2000
# Nadpisuje: source DB, target DB, source host, batch size
# Używa z .env: credentials, target host
```

### 5. Restore z niestandardowym plikiem:
```bash
./restore.sh -f /backups/custom.bak -d NEW_DB -r
# Nadpisuje: backup file, database name, replace flag
# Używa z .env: connection credentials
```

## 🔍 Sprawdzanie konfiguracji

Użyj test skryptu do sprawdzenia aktualnej konfiguracji:

```bash
# Pokaż aktualną konfigurację
./test_config.sh

# Przetestuj z argumentami
./test_config.sh -s PROD -t TEST --source-host remote.com

# Pokaż pomoc z aktualną konfiguracją
./test_config.sh --help
```

## 📝 Argumenty vs .env - mapowanie

### Backup (`backup.sh`):
| Argument | Zmienna .env | Domyślna wartość |
|----------|--------------|------------------|
| `-d, --database` | `TARGET_DB_NAME` | `WAPROMAG_TEST` |
| `-p, --path` | `BACKUP_PATH` | `/var/opt/mssql/backup` |
| (credentials) | `TARGET_DB_USER`, `TARGET_DB_PASSWORD` | `sa`, `WapromagPass123!` |

### Restore (`restore.sh`):
| Argument | Zmienna .env | Domyślna wartość |
|----------|--------------|------------------|
| `-d, --database` | `TARGET_DB_NAME` | `WAPROMAG_TEST` |
| (credentials) | `TARGET_DB_USER`, `TARGET_DB_PASSWORD` | `sa`, `WapromagPass123!` |

### Migracja (`migrate_overwrite.sh`):
| Argument | Zmienna .env | Domyślna wartość |
|----------|--------------|------------------|
| `-s, --source` | `SOURCE_DB_NAME` | `WAPRO_PRODUCTION` |
| `-t, --target` | `TARGET_DB_NAME` | `WAPROMAG_TEST` |
| `--source-host` | `SOURCE_DB_HOST` | `localhost` |
| `--target-host` | `TARGET_DB_HOST` | `localhost` |
| `-b, --batch-size` | `MIGRATION_BATCH_SIZE` | `1000` |

## 🔐 Bezpieczeństwo

### ⚠️ Ważne zasady:
1. **Nigdy nie commituj pliku `.env`** do repozytorium
2. **Ustaw odpowiednie uprawnienia** na plik `.env`: `chmod 600 .env`
3. **Używaj mocnych haseł** w zmiennych `*_PASSWORD`
4. **Regularnie rotuj hasła** w produkcyjnych środowiskach

### 📁 Ochrona pliku .env:
```bash
# Ustaw bezpieczne uprawnienia
chmod 600 /home/tom/github/text2doc/prinet/mssql/.env

# Sprawdź uprawnienia
ls -la /home/tom/github/text2doc/prinet/mssql/.env
```

## 🧪 Walidacja konfiguracji

Każdy skrypt automatycznie sprawdza:

1. **Istnienie pliku .env** - ostrzeżenie jeśli nie istnieje
2. **Wymagane zmienne** - błąd jeśli brakuje credentials
3. **Połączenie z bazą** - test connectivity przed operacją
4. **Poprawność argumentów** - walidacja wartości

### Przykład komunikatów:
```bash
📋 Ładowanie konfiguracji z: /path/to/mssql/.env
✅ Połączenie z bazą danych zweryfikowane
❌ Błąd: Brakuje wymaganych zmiennych połączenia z bazą danych
```

## 🔧 Debugging konfiguracji

### 1. Sprawdź zawartość .env:
```bash
cat /home/tom/github/text2doc/prinet/mssql/.env
```

### 2. Uruchom test konfiguracji:
```bash
./test_config.sh -v
```

### 3. Sprawdź logi skryptu:
```bash
tail -f backup.log
tail -f migration_overwrite.log
tail -f restore.log
```

### 4. Sprawdź połączenie z bazą:
```bash
docker-compose exec mssql-wapromag /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'WapromagPass123!' -Q "SELECT @@VERSION" -C
```

## 💡 Najlepsze praktyki

1. **Zawsze testuj** na środowisku rozwojowym przed produkcją
2. **Używaj --dry-run** do podglądu operacji przed wykonaniem
3. **Twórz backup** przed migracją z `--backup-first`
4. **Weryfikuj wyniki** z `--verify-after`
5. **Monitoruj logi** podczas długich operacji
6. **Dokumentuj zmiany** w konfiguracji

## 🚨 Rozwiązywanie problemów

### Problem: "Plik .env nie został znaleziony"
```bash
# Rozwiązanie:
cp .env.example .env
nano .env  # skonfiguruj swoje wartości
```

### Problem: "Brakuje wymaganych zmiennych"
```bash
# Sprawdź czy w .env są ustawione:
grep -E "(HOST|USER|PASSWORD)" .env
```

### Problem: "Cannot connect to database"
```bash
# Sprawdź czy Docker jest uruchomiony:
docker-compose ps

# Sprawdź połączenie:
docker-compose exec mssql-wapromag /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'TwojeHasło' -Q "SELECT 1" -C
```
