# Makefile
.PHONY: help install setup start stop restart clean test test-e2e logs build rebuild status

# Kolory dla output
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
BLUE := \033[34m
RESET := \033[0m

help: ## Wyświetla pomoc
	@echo "$(BLUE)WAPRO Network Mock - Dostępne komendy:$(RESET)"
	@echo ""
	@echo "$(YELLOW)Instalacja i konfiguracja:$(RESET)"
	@echo "  $(GREEN)install$(RESET)        Instaluje Docker i zależności (wymaga sudo)"
	@echo "  $(GREEN)setup$(RESET)          Konfiguruje środowisko (po instalacji)"
	@echo ""
	@echo "$(YELLOW)Uruchamianie:$(RESET)"
	@echo "  $(GREEN)start$(RESET)          Uruchamia wszystkie serwisy"
	@echo "  $(GREEN)stop$(RESET)           Zatrzymuje wszystkie serwisy"
	@echo "  $(GREEN)restart$(RESET)        Restartuje wszystkie serwisy"
	@echo ""
	@echo "$(YELLOW)Inne komendy:$(RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | grep -v "install\|setup\|start\|stop\|restart" | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-15s$(RESET) %s\n", $$1, $$2}'

install: ## Instaluje Docker i wszystkie zależności (dla RPi/Debian/Ubuntu)
	@echo "$(YELLOW)[i] Instalacja zależności systemowych...$(RESET)"
	@chmod +x scripts/*.sh 2>/dev/null || true
	@sudo ./scripts/install.sh

setup: ## Konfiguruje srodowisko (tworzy .env, buduje obrazy)
	@chmod +x scripts/*.sh 2>/dev/null || true
	@./scripts/setup_simple.sh

start: ## Uruchamia wszystkie serwisy
	@echo "$(GREEN)[*] Uruchamianie serwisów...$(RESET)"
	@./scripts/start.sh

stop: ## Zatrzymuje wszystkie serwisy
	@echo "$(RED)[X] Zatrzymywanie serwisów...$(RESET)"
	@./scripts/stop.sh

restart: stop start ## Restartuje wszystkie serwisy

# =============================================================================
# PRODUCTION (tylko RPI Server, zewnetrzne MSSQL i Zebra)
# =============================================================================

prod: ## Uruchamia tryb produkcyjny (tylko RPI Server)
	@echo "$(GREEN)[*] Uruchamianie trybu PRODUKCYJNEGO...$(RESET)"
	@echo "$(YELLOW)[!] Uzywa zewnetrznych: MSSQL, Zebra printers$(RESET)"
	@docker-compose -f docker-compose.prod.yml up -d
	@echo ""
	@echo "$(GREEN)[+] RPI Server uruchomiony$(RESET)"
	@docker-compose -f docker-compose.prod.yml ps

prod-stop: ## Zatrzymuje tryb produkcyjny
	@echo "$(RED)[X] Zatrzymywanie trybu produkcyjnego...$(RESET)"
	@docker-compose -f docker-compose.prod.yml down

prod-logs: ## Logi trybu produkcyjnego
	@docker-compose -f docker-compose.prod.yml logs -f

prod-restart: prod-stop prod ## Restartuje tryb produkcyjny

prod-status: ## Status trybu produkcyjnego
	@echo "$(BLUE)[i] Status produkcyjny:$(RESET)"
	@docker-compose -f docker-compose.prod.yml ps
	@echo ""
	@echo "$(BLUE)[i] Konfiguracja zewnetrzna:$(RESET)"
	@echo "  MSSQL:   $${MSSQL_HOST:-nie ustawiono}:$${MSSQL_PORT:-1433}"
	@echo "  Zebra 1: $${ZEBRA_1_HOST:-nie ustawiono}:$${ZEBRA_1_SOCKET_PORT:-9100}"
	@echo "  Zebra 2: $${ZEBRA_2_HOST:-nie ustawiono}:$${ZEBRA_2_SOCKET_PORT:-9100}"

prod-build: ## Buduje obraz produkcyjny
	@echo "$(YELLOW)[B] Budowanie obrazu produkcyjnego...$(RESET)"
	@docker-compose -f docker-compose.prod.yml build

clean: ## Czyści środowisko (usuwa kontenery, obrazy, wolumeny)
	@echo "$(RED)[-] Czyszczenie środowiska...$(RESET)"
	@docker-compose down -v --remove-orphans
	@docker system prune -f
	@docker volume prune -f

test: ## Uruchamia wszystkie testy
	@echo "$(BLUE)[T] Uruchamianie testów...$(RESET)"
	@./scripts/test-all.sh

test-e2e: ## Uruchamia testy E2E wszystkich usług
	@echo "$(BLUE)[T] Uruchamianie testów E2E...$(RESET)"
	@./scripts/test-e2e.sh

test-docker: ## Testuje konfigurację Docker
	@echo "$(BLUE)[T] Testowanie Docker...$(RESET)"
	@echo -n "  Docker daemon: "; docker info >/dev/null 2>&1 && echo "$(GREEN)[+] OK$(RESET)" || echo "$(RED)[-] FAIL$(RESET)"
	@echo -n "  Docker Compose: "; docker-compose version >/dev/null 2>&1 && echo "$(GREEN)[+] OK$(RESET)" || echo "$(RED)[-] FAIL$(RESET)"
	@echo -n "  Network (192.168.8.0/24): "; docker network inspect prinet_wapro-network >/dev/null 2>&1 && echo "$(GREEN)[+] OK$(RESET)" || echo "$(YELLOW)[?] Nie istnieje$(RESET)"
	@echo "$(BLUE)[i] Kontenery:$(RESET)"
	@docker ps --format "  {{.Names}}: {{.Status}}" 2>/dev/null | grep -E "rpi|zebra|mssql" || echo "  Brak uruchomionych kontenerów"

test-app: ## Testuje działanie aplikacji (health checks)
	@echo "$(BLUE)[T] Testowanie aplikacji...$(RESET)"
	@echo -n "  RPI Server GUI (8082): "; curl -sf http://localhost:$${RPI_GUI_EXTERNAL_PORT:-8082}/health >/dev/null && echo "$(GREEN)[+] OK$(RESET)" || echo "$(RED)[-] FAIL$(RESET)"
	@echo -n "  RPI Server API (8081): "; curl -sf http://localhost:$${RPI_API_EXTERNAL_PORT:-8081}/health >/dev/null && echo "$(GREEN)[+] OK$(RESET)" || echo "$(RED)[-] FAIL$(RESET)"
	@echo -n "  ZEBRA-1 Web (8091): "; curl -sf http://localhost:$${ZEBRA_1_EXTERNAL_WEB_PORT:-8091}/ >/dev/null && echo "$(GREEN)[+] OK$(RESET)" || echo "$(RED)[-] FAIL$(RESET)"
	@echo -n "  ZEBRA-1 Socket (9100): "; nc -z localhost $${ZEBRA_1_EXTERNAL_SOCKET_PORT:-9100} 2>/dev/null && echo "$(GREEN)[+] OK$(RESET)" || echo "$(RED)[-] FAIL$(RESET)"
	@echo -n "  ZEBRA-2 Web (8092): "; curl -sf http://localhost:$${ZEBRA_2_EXTERNAL_WEB_PORT:-8092}/ >/dev/null && echo "$(GREEN)[+] OK$(RESET)" || echo "$(RED)[-] FAIL$(RESET)"
	@echo -n "  ZEBRA-2 Socket (9101): "; nc -z localhost $${ZEBRA_2_EXTERNAL_SOCKET_PORT:-9101} 2>/dev/null && echo "$(GREEN)[+] OK$(RESET)" || echo "$(RED)[-] FAIL$(RESET)"
	@echo -n "  MSSQL (1433): "; nc -z localhost $${MSSQL_EXTERNAL_PORT:-1433} 2>/dev/null && echo "$(GREEN)[+] OK$(RESET)" || echo "$(RED)[-] FAIL$(RESET)"

test-network: ## Testuje konfigurację sieci Docker
	@echo "$(BLUE)[T] Testowanie sieci Docker...$(RESET)"
	@docker network inspect prinet_wapro-network --format '{{range .IPAM.Config}}Subnet: {{.Subnet}}{{end}}' 2>/dev/null || echo "$(RED)[-] Sieć nie istnieje$(RESET)"
	@echo "$(BLUE)[i] Przypisane adresy IP:$(RESET)"
	@docker network inspect prinet_wapro-network --format '{{range .Containers}}  {{.Name}}: {{.IPv4Address}}{{println}}{{end}}' 2>/dev/null || true

test-zebra: ## Testuje tylko drukarki ZEBRA
	@echo "$(BLUE)[P] Testowanie drukarek ZEBRA...$(RESET)"
	@docker-compose exec test-runner python -m pytest tests/test_zebra_connectivity.py -v

test-sql: ## Testuje tylko połączenie SQL
	@echo "$(BLUE)🗄️  Testowanie bazy danych...$(RESET)"
	@docker-compose exec test-runner python -m pytest tests/test_rpi_sql.py -v

test-integration: ## Uruchamia testy integracyjne
	@echo "$(BLUE)🔗 Testy integracyjne...$(RESET)"
	@docker-compose exec test-runner python -m pytest tests/test_integration.py -v

logs: ## Wyświetla logi wszystkich serwisów
	@docker-compose logs -f

logs-rpi: ## Wyświetla logi RPI Server
	@docker-compose logs -f rpi-server

logs-zebra1: ## Wyświetla logi ZEBRA Printer 1
	@docker-compose logs -f zebra-printer-1

logs-zebra2: ## Wyświetla logi ZEBRA Printer 2
	@docker-compose logs -f zebra-printer-2

logs-sql: ## Wyświetla logi SQL Server
	@docker-compose logs -f mssql-wapromag

build: ## Buduje wszystkie obrazy
	@echo "$(YELLOW)[B] Budowanie obrazów...$(RESET)"
	@docker-compose build

rebuild: ## Przebudowuje wszystkie obrazy (bez cache)
	@echo "$(YELLOW)[B] Przebudowywanie obrazów...$(RESET)"
	@docker-compose build --no-cache

status: ## Pokazuje status wszystkich serwisow
	@echo "$(BLUE)[i] Status serwisow:$(RESET)"
	@docker-compose --profile full ps 2>/dev/null || sudo docker-compose --profile full ps
	@echo ""
	@echo "$(BLUE)[i] Dostepne interfejsy (porty z .env):$(RESET)"
	@echo "  RPI Server GUI:      $(GREEN)http://localhost:$${RPI_GUI_EXTERNAL_PORT:-8082}$(RESET)"
	@echo "  RPI Server API:      $(GREEN)http://localhost:$${RPI_API_EXTERNAL_PORT:-8081}$(RESET)"
	@echo "  ZEBRA Printer 1:     $(GREEN)http://localhost:$${ZEBRA_1_EXTERNAL_WEB_PORT:-8091}$(RESET)"
	@echo "  ZEBRA Printer 2:     $(GREEN)http://localhost:$${ZEBRA_2_EXTERNAL_WEB_PORT:-8092}$(RESET)"
	@echo "  Monitoring:          $(GREEN)http://localhost:$${GRAFANA_PORT:-3000}$(RESET)"
	@echo "  MSSQL WAPROMAG:      $(GREEN)localhost:$${MSSQL_EXTERNAL_PORT:-1433}$(RESET)"

health: ## Sprawdza stan zdrowia wszystkich serwisów
	@echo "$(BLUE)[H] Health Check:$(RESET)"
	@curl -s http://localhost:$${RPI_GUI_EXTERNAL_PORT:-8082}/health | jq . || echo "RPI Server: $(RED)OFFLINE$(RESET)"
	@curl -s http://localhost:$${ZEBRA_1_EXTERNAL_WEB_PORT:-8091}/api/status | jq . || echo "ZEBRA-1: $(RED)OFFLINE$(RESET)"
	@curl -s http://localhost:$${ZEBRA_2_EXTERNAL_WEB_PORT:-8092}/api/status | jq . || echo "ZEBRA-2: $(RED)OFFLINE$(RESET)"

backup-db: ## Tworzy backup bazy danych
	@echo "$(YELLOW)[D] Tworzenie backupu bazy danych...$(RESET)"
	@./scripts/backup-db.sh

restore-db: ## Przywraca backup bazy danych
	@echo "$(YELLOW)[R] Przywracanie bazy danych...$(RESET)"
	@./scripts/restore-db.sh

shell-rpi: ## Łączy z terminalem RPI Server
	@docker-compose exec rpi-server /bin/sh

shell-zebra1: ## Łączy z terminalem ZEBRA Printer 1
	@docker-compose exec zebra-printer-1 /bin/sh

shell-sql: ## Łączy z terminalem SQL Server
	@docker-compose exec mssql-wapromag /bin/bash

monitor: ## Otwiera monitoring w przegladarce
	@echo "$(GREEN)[i] Otwieranie monitoringu...$(RESET)"
	@xdg-open http://localhost:3000 2>/dev/null || open http://localhost:3000 2>/dev/null || echo "Otworz http://localhost:3000"

webenv: ## Uruchamia webowy edytor pliku .env (port 8888)
	@echo "$(BLUE)[i] Uruchamianie edytora .env...$(RESET)"
	@fuser -k 8888/tcp 2>/dev/null || true
	@sleep 1
	@python3 scripts/webenv.py 8888

discover: ## Wykrywa urzadzenia sieciowe (drukarki Zebra, MSSQL)
	@python3 scripts/discover.py -q

discover-full: ## Pelne skanowanie sieci
	@python3 scripts/discover.py

cli: ## Uruchamia interaktywny CLI DSL
	@python3 scripts/wapro-cli.py

dev: ## Tryb deweloperski (rebuild + start + logs)
	@make rebuild
	@make start
	@sleep 5
	@make logs