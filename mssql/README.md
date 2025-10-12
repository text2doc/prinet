# MSSQL Database Management Tools

This directory contains utilities for MSSQL database backup, restore, and migration operations for the WAPRO Network system.

## 📁 Files Overview

| File | Description |
|------|-------------|
| `.env` | Environment configuration for database connections |
| `backup.sql` | SQL script for database backup operations |
| `restore.sql` | SQL script for database restore operations |
| `migrate.sql` | SQL script for data migration between databases |
| `backup.sh` | Shell script for automated database backups |
| `restore.sh` | Shell script for automated database restores |
| `migrate.sh` | Shell script for automated data migration |

## 🔧 Configuration

### Hierarchiczna konfiguracja

Skrypty używają **trzywarstwowej konfiguracji** (kolejność priorytetów):
1. **Argumenty CLI** - najwyższy priorytet
2. **Plik .env** - ładowany z katalogu `mssql/.env`
3. **Wartości domyślne** - fallback gdy brak konfiguracji

### Konfiguracja pliku .env

Skopiuj `.env.example` do `.env` i dostosuj do swoich potrzeb:

```bash
cd mssql/
cp .env.example .env
nano .env
```

**Przykład konfiguracji:**
```bash
# Source database (migration source)
SOURCE_DB_HOST=localhost
SOURCE_DB_PORT=1433
SOURCE_DB_USER=sa
SOURCE_DB_PASSWORD=SourcePassword123!
SOURCE_DB_NAME=WAPRO_PRODUCTION

# Target database (migration target)
TARGET_DB_HOST=localhost
TARGET_DB_PORT=1433
TARGET_DB_USER=sa
TARGET_DB_PASSWORD=WapromagPass123!
TARGET_DB_NAME=WAPROMAG_TEST

# Backup settings
BACKUP_PATH=/var/opt/mssql/backup
BACKUP_RETENTION_DAYS=30
BACKUP_COMPRESS=true

# Migration settings
MIGRATION_BATCH_SIZE=1000
MIGRATION_TIMEOUT=300
MIGRATION_LOG_LEVEL=INFO
```

### Test konfiguracji

Sprawdź aktualną konfigurację i test ładowania:
```bash
# Sprawdź aktualną konfigurację
./test_config.sh

# Przetestuj z argumentami
./test_config.sh -s PROD -t TEST --source-host remote.server.com

# Zobacz pełną dokumentację konfiguracji
cat KONFIGURACJA.md
```

## 🚀 Usage

### Database Backup

#### Podstawowy backup:
```bash
# Basic backup using .env defaults
./backup.sh

# Backup specific database with cleanup and verification
./backup.sh -d WAPROMAG_TEST -c -v

# Custom backup location
./backup.sh --database MyDB --path /custom/backup/path
```

#### Pełny backup wszystkich baz:
```bash
# Backup wszystkich baz danych z kompresją
./full_backup.sh -a -c -v

# Backup wybranych baz z cleanup
./full_backup.sh -d WAPROMAG_TEST,PROD_DB --cleanup 7

# Backup z pełnym schema
./full_backup.sh --all-databases --with-schema
```

**Options:**
- `-d, --database NAME`: Database name to backup
- `-p, --path PATH`: Backup directory path
- `-c, --cleanup`: Clean up old backups based on retention policy
- `-v, --verify`: Verify backup after creation

### Database Restore

```bash
# Basic restore
./restore.sh -f /backups/db_backup_20231012_143022.bak

# Restore to new database with replace
./restore.sh -f backup.bak -d NewDB -r

# Custom file paths
./restore.sh -f backup.bak --data-path /data --log-path /logs

# Show help
./restore.sh --help
```

**Options:**
- `-f, --file PATH`: Backup file path (required)
- `-d, --database NAME`: Target database name
- `--data-path PATH`: Data file path
- `--log-path PATH`: Log file path
- `-r, --replace`: Replace existing database
- `-v, --verify`: Verify database after restore

### Data Migration

#### Podstawowa migracja:
```bash
# Basic migration using .env defaults
./migrate.sh

# Migrate from production to test, clear target first
./migrate.sh -s PROD_DB -t TEST_DB -c

# Migrate only specific tables
./migrate.sh --tables Kontrahenci,Produkty

# Dry run to preview migration
./migrate.sh --dry-run -v
```

#### Migracja z nadpisywaniem tabel i danych:
```bash
# Migracja z pełnym nadpisywaniem (TRUNCATE)
./migrate_overwrite.sh -s PROD_DB -t TEST_DB

# Migracja z backupem przed nadpisywaniem
./migrate_overwrite.sh -s PROD_DB -t TEST_DB --backup-first --verify-after

# Tryb DROP_RECREATE - usuwa i odtwarza tabele
./migrate_overwrite.sh -m DROP_RECREATE --force

# Podgląd migracji z nadpisywaniem
./migrate_overwrite.sh --dry-run -v

# Wymuszona migracja bez pytań
./migrate_overwrite.sh --force -m TRUNCATE
```

**Options:**
- `-s, --source NAME`: Source database name
- `-t, --target NAME`: Target database name
- `-b, --batch-size N`: Batch size for migration
- `-c, --clear-target`: Clear target tables before migration
- `--dry-run`: Preview migration without executing
- `--tables LIST`: Comma-separated list of specific tables
- `-v, --verbose`: Verbose output

## 📊 Migration Process

The migration process handles the following tables in order:

1. **Kontrahenci** (Customers/Contractors)
2. **Produkty** (Products)
3. **DokumentyMagazynowe** (Warehouse Documents)
4. **PozycjeDokumentowMagazynowych** (Document Line Items)
5. **StanyMagazynowe** (Inventory States)

### Migration Features

- **Incremental Migration**: Only migrates new records not already in target
- **Foreign Key Mapping**: Properly maps relationships between tables
- **Data Validation**: Handles NULL values and provides defaults
- **Batch Processing**: Processes data in configurable batch sizes
- **Error Handling**: Comprehensive error logging and recovery
- **Progress Tracking**: Detailed logging of migration progress

## 📝 Logging

All operations create detailed log files:

- `backup.log` - Backup operation logs
- `restore.log` - Restore operation logs
- `migration.log` - Migration operation logs

Log files include:
- Timestamps for all operations
- Success/failure status
- Row counts and performance metrics
- Error messages and stack traces
- Database connection details

## 🔐 Security Considerations

1. **Environment Variables**: Store sensitive credentials in `.env` file
2. **File Permissions**: Restrict access to `.env` and log files
3. **Network Security**: Use encrypted connections when possible
4. **Backup Security**: Secure backup file storage location
5. **Access Control**: Limit database user permissions to necessary operations

## 🧪 Testing

Before running in production:

1. **Test with Dry Run**: Use `--dry-run` flag to preview operations
2. **Verify Backups**: Always use `-v` flag to verify backup integrity
3. **Small Batches**: Start with smaller batch sizes for large datasets
4. **Monitor Logs**: Check log files for warnings or errors

## 🚨 Troubleshooting

### Common Issues

**Connection Failures:**
- Verify database server is running
- Check connection credentials in `.env`
- Ensure network connectivity between source and target

**Permission Errors:**
- Verify database user has required permissions
- Check file system permissions for backup directory
- Ensure SQL Server Agent is running for advanced operations

**Performance Issues:**
- Adjust `MIGRATION_BATCH_SIZE` for optimal performance
- Monitor system resources during large migrations
- Consider running during off-peak hours

**Data Integrity:**
- Use foreign key mapping for related tables
- Verify data after migration with sample queries
- Check for duplicate records in target database

## 📞 Support

For issues or questions:

1. Check log files for detailed error messages
2. Verify environment configuration
3. Test with smaller datasets first
4. Review MSSQL Server logs for additional details

## 🔄 Version History

- **v1.0** - Initial release with backup, restore, and migration tools
- Support for WAPRO database schema
- Comprehensive error handling and logging
- Batch processing and performance optimization
