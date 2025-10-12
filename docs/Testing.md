# docs/Testing.md

## Uruchamianie testów

### Wszystkie testy
```bash
- `make test` – uruchamia testy pytest w kontenerze `test-runner`
- `make test-e2e` – uruchamia testy E2E bez restartu usług

## Preflight (weryfikacja środowiska przed testami)

Skrypty `scripts/start.sh` i `scripts/test-e2e.sh` wykonują preflight-checki:

- Walidacja `docker-compose.yml`
- Sprawdzenie dostępności Dockera i docker-compose
- Podgląd zajętości portów (8080, 8081, 8091, 8092, 9100, 9101, 1433, 3000)
- W przypadku timeoutów lub błędów HTTP – wyświetlenie nagłówków odpowiedzi i ostatnich linii logów z kontenerów

To pozwala szybko zdiagnozować problemy zanim testy zasadnicze wystartują.

## Lepsza wydajność budowania

Włącz szybsze budowanie obrazów Docker:

```bash
export COMPOSE_BAKE=true
```

## Monitoring (Grafana + Prometheus)
### test_zebra_connectivity.py
- Testy połączeń socket
- Testy komend ZPL
- Testy interfejsów web

### test_integration.py
- Testy end-to-end workflow
- Testy równoczesnej pracy
- Testy obsługi błędów

## Raporty testów

Raporty generowane w katalogu `reports/`:
- `test_report_YYYYMMDD_HHMMSS.html` - Raport HTML
- `test_results_YYYYMMDD_HHMMSS.json` - Wyniki JSON
- `summary_YYYYMMDD_HHMMSS.json` - Podsumowanie
- `health_report.json` - Stan systemu
