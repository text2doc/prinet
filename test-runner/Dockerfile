# test-runner/Dockerfile
FROM python:3.9-slim

# Instalacja narzędzi systemowych
RUN apt-get update && apt-get install -y \
    curl \
    netcat-openbsd \
    telnet \
    iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# Utworzenie katalogu aplikacji
WORKDIR /app

# Kopiowanie requirements.txt
COPY requirements.txt .

# Instalacja wymaganych pakietów Python
RUN pip install --no-cache-dir -r requirements.txt

# Utworzenie użytkownika
RUN useradd -m -u 1001 tester

# Kopiowanie plików testowych
COPY --chown=tester:tester . .

# Utworzenie katalogów
RUN mkdir -p reports logs && \
    chown -R tester:tester reports logs

# Przełączenie na użytkownika tester
USER tester

# Zmienne środowiskowe
ENV PYTHONPATH=/app
ENV TEST_REPORTS_DIR=/app/reports

# Health check
HEALTHCHECK --interval=60s --timeout=30s --start-period=10s --retries=3 \
  CMD python -c "import sys; sys.exit(0)"

# Uruchomienie testów
CMD ["python", "test_suite.py"]