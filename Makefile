# Makefile
.PHONY: help setup start stop restart clean test test-e2e logs build rebuild status

# Kolory dla output
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
BLUE := \033[34m
RESET := \033[0m

help: ## Wyświetla pomoc
	@echo "$(BLUE)WAPRO Network Mock - Dostępne komendy:$(RESET)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-15s$(RESET) %s\n", $$1, $$2}'

setup: ## Konfiguruje środowisko (pierwsza instalacja)
	@echo "$(YELLOW)🚀 Konfiguracja środowiska...$(RESET)"
	@chmod +x scripts/*.sh
	@./scripts/setup.sh

start: ## Uruchamia wszystkie serwisy
	@echo "$(GREEN)🚀 Uruchamianie serwisów...$(RESET)"
	@./scripts/start.sh

stop: ## Zatrzymuje wszystkie serwisy
	@echo "$(RED)🛑 Zatrzymywanie serwisów...$(RESET)"
	@./scripts/stop.sh

restart: stop start ## Restartuje wszystkie serwisy

clean: ## Czyści środowisko (usuwa kontenery, obrazy, wolumeny)
	@echo "$(RED)🧹 Czyszczenie środowiska...$(RESET)"
	@docker-compose down -v --remove-orphans
	@docker system prune -f
	@docker volume prune -f

test: ## Uruchamia wszystkie testy
	@echo "$(BLUE)🧪 Uruchamianie testów...$(RESET)"
	@./scripts/test-all.sh

test-e2e: ## Uruchamia testy E2E wszystkich usług
	@echo "$(BLUE)🧪 Uruchamianie testów E2E...$(RESET)"
	@./scripts/test-e2e.sh

test-zebra: ## Testuje tylko drukarki ZEBRA
	@echo "$(BLUE)🖨️  Testowanie drukarek ZEBRA...$(RESET)"
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
	@echo "$(YELLOW)🔨 Budowanie obrazów...$(RESET)"
	@docker-compose build

rebuild: ## Przebudowuje wszystkie obrazy (bez cache)
	@echo "$(YELLOW)🔨 Przebudowywanie obrazów...$(RESET)"
	@docker-compose build --no-cache

status: ## Pokazuje status wszystkich serwisów
	@echo "$(BLUE)📊 Status serwisów:$(RESET)"
	@docker-compose ps
	@echo ""
	@echo "$(BLUE)🌐 Dostępne interfejsy:$(RESET)"
	@echo "  RPI Server GUI:      $(GREEN)http://localhost:8080$(RESET)"
	@echo "  RPI Server API:      $(GREEN)http://localhost:8081$(RESET)"
	@echo "  ZEBRA Printer 1:     $(GREEN)http://localhost:8091$(RESET)"
	@echo "  ZEBRA Printer 2:     $(GREEN)http://localhost:8092$(RESET)"
	@echo "  Monitoring:          $(GREEN)http://localhost:3000$(RESET)"
	@echo "  MSSQL WAPROMAG:      $(GREEN)localhost:1433$(RESET)"

health: ## Sprawdza stan zdrowia wszystkich serwisów
	@echo "$(BLUE)🏥 Health Check:$(RESET)"
	@curl -s http://localhost:8080/health | jq . || echo "RPI Server: $(RED)OFFLINE$(RESET)"
	@curl -s http://localhost:8091/api/status | jq . || echo "ZEBRA-1: $(RED)OFFLINE$(RESET)"
	@curl -s http://localhost:8092/api/status | jq . || echo "ZEBRA-2: $(RED)OFFLINE$(RESET)"

backup-db: ## Tworzy backup bazy danych
	@echo "$(YELLOW)💾 Tworzenie backupu bazy danych...$(RESET)"
	@./scripts/backup-db.sh

restore-db: ## Przywraca backup bazy danych
	@echo "$(YELLOW)🔄 Przywracanie bazy danych...$(RESET)"
	@./scripts/restore-db.sh

shell-rpi: ## Łączy z terminalem RPI Server
	@docker-compose exec rpi-server /bin/sh

shell-zebra1: ## Łączy z terminalem ZEBRA Printer 1
	@docker-compose exec zebra-printer-1 /bin/sh

shell-sql: ## Łączy z terminalem SQL Server
	@docker-compose exec mssql-wapromag /bin/bash

monitor: ## Otwiera monitoring w przeglądarce
	@echo "$(GREEN)📊 Otwieranie monitoringu...$(RESET)"
	@xdg-open http://localhost:3000 2>/dev/null || open http://localhost:3000 2>/dev/null || echo "Otwórz http://localhost:3000"

dev: ## Tryb deweloperski (rebuild + start + logs)
	@make rebuild
	@make start
	@sleep 5
	@make logs