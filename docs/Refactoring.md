# Propozycje Refaktoryzacji

## Przegląd

Ten dokument zawiera propozycje refaktoryzacji projektu WAPRO Network Mock w celu poprawy jakości kodu, utrzymywalności i testowalności.

---

## 1. Wyodrębnienie HTML/CSS/JS z webenv.py

### Problem
Plik `scripts/webenv.py` zawiera ~1200 linii kodu z osadzonym HTML, CSS i JavaScript w zmiennej `HTML_TEMPLATE`. To utrudnia:
- Edycję i formatowanie kodu frontend
- Podświetlanie składni w IDE
- Testowanie jednostkowe JavaScript
- Współpracę frontend/backend developerów

### Rozwiązanie
Wyodrębnić zasoby do osobnych plików:

```
scripts/
├── webenv.py                    # Tylko logika serwera
└── webenv_assets/
    ├── index.html               # Szablon HTML
    ├── webenv.css               # Style CSS
    └── webenv.js                # Logika JavaScript
```

### Implementacja
```python
# webenv.py - po refaktoryzacji
def load_template():
    assets_dir = Path(__file__).parent / 'webenv_assets'
    html = (assets_dir / 'index.html').read_text()
    css = (assets_dir / 'webenv.css').read_text()
    js = (assets_dir / 'webenv.js').read_text()
    return html.replace('{{CSS}}', css).replace('{{JS}}', js)
```

### Priorytet: **Wysoki**
### Szacowany czas: 2-3h

---

## 2. Wyodrębnienie HTML z zebra_mock.py

### Problem
Pliki `zebra-printer-1/zebra_mock.py` i `zebra-printer-2/zebra_mock.py` zawierają osadzony HTML w `render_template_string()`.

### Rozwiązanie
Użyć Flask templates:

```
zebra-printer-1/
├── zebra_mock.py
└── templates/
    └── index.html
```

### Priorytet: **Średni**
### Szacowany czas: 1-2h

---

## 3. Centralizacja konfiguracji drukarek Zebra

### Problem
Konfiguracja drukarek ZEBRA_1_ do ZEBRA_6_ jest zduplikowana w:
- `.env` / `.env.example`
- `docker-compose.yml`
- Skrypty testowe

### Rozwiązanie
Stworzyć generator konfiguracji:

```python
# scripts/generate_zebra_config.py
def generate_zebra_config(count=6, base_port=9100, base_web_port=8091):
    """Generuje konfigurację dla N drukarek Zebra"""
    config = {}
    for i in range(1, count + 1):
        prefix = f"ZEBRA_{i}_"
        config[f"{prefix}ENABLED"] = "true"
        config[f"{prefix}SOCKET_PORT"] = "9100"
        config[f"{prefix}EXTERNAL_SOCKET_PORT"] = str(base_port + i - 1)
        config[f"{prefix}EXTERNAL_WEB_PORT"] = str(base_web_port + i - 1)
        # ...
    return config
```

### Priorytet: **Średni**
### Szacowany czas: 2h

---

## 4. Ujednolicenie testów E2E

### Problem
Testy są rozproszone w różnych formatach:
- `scripts/test-e2e.sh` - bash
- `scripts/test-webenv.sh` - bash
- `test-runner/tests/*.py` - pytest

### Rozwiązanie
Ujednolicić podejście:

**Opcja A**: Wszystko w pytest
```python
# tests/e2e/test_webenv.py
import pytest
import requests

class TestWebEnv:
    def test_page_loads(self, webenv_url):
        response = requests.get(webenv_url)
        assert response.status_code == 200
```

**Opcja B**: Bash dla szybkich smoke testów, pytest dla szczegółowych

### Priorytet: **Niski**
### Szacowany czas: 4-6h

---

## 5. Dodanie typowania (Type Hints)

### Problem
Pliki Python nie mają type hints, co utrudnia:
- Autouzupełnianie w IDE
- Wykrywanie błędów
- Dokumentację

### Rozwiązanie
Dodać type hints do kluczowych funkcji:

```python
# Przed
def load_env_file(path):
    with open(path) as f:
        return f.read()

# Po
def load_env_file(path: str | Path) -> str:
    with open(path) as f:
        return f.read()
```

### Priorytet: **Niski**
### Szacowany czas: 2-3h

---

## 6. Refaktoryzacja discover.py

### Problem
`scripts/discover.py` ma długie funkcje i mieszaną odpowiedzialność.

### Rozwiązanie
Podzielić na moduły:

```
scripts/
├── discover.py              # CLI entry point
└── discovery/
    ├── __init__.py
    ├── scanner.py           # NetworkScanner class
    ├── zebra.py             # ZebraDiscovery
    ├── mssql.py             # MSSQLDiscovery
    └── output.py            # Formatowanie wyników
```

### Priorytet: **Niski**
### Szacowany czas: 3-4h

---

## 7. Dodanie health checks do docker-compose

### Problem
Kontenery nie mają zdefiniowanych health checks, co utrudnia:
- Automatyczne restartowanie
- Oczekiwanie na gotowość
- Monitoring

### Rozwiązanie
Dodać healthcheck do każdego serwisu:

```yaml
# docker-compose.yml
services:
  rpi-server:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

### Priorytet: **Średni**
### Szacowany czas: 1h

---

## 8. Dodanie pre-commit hooks

### Problem
Brak automatycznej walidacji kodu przed commitem.

### Rozwiązanie
Dodać `.pre-commit-config.yaml`:

```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.4.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-json
  
  - repo: https://github.com/psf/black
    rev: 23.3.0
    hooks:
      - id: black
  
  - repo: https://github.com/pycqa/flake8
    rev: 6.0.0
    hooks:
      - id: flake8
```

### Priorytet: **Średni**
### Szacowany czas: 30min

---

## Podsumowanie priorytetów

| Priorytet | Zadanie | Czas |
|-----------|---------|------|
| 🔴 Wysoki | Wyodrębnienie HTML/CSS/JS z webenv.py | 2-3h |
| 🟡 Średni | Wyodrębnienie HTML z zebra_mock.py | 1-2h |
| 🟡 Średni | Centralizacja konfiguracji Zebra | 2h |
| 🟡 Średni | Health checks w docker-compose | 1h |
| 🟡 Średni | Pre-commit hooks | 30min |
| 🟢 Niski | Ujednolicenie testów E2E | 4-6h |
| 🟢 Niski | Type hints | 2-3h |
| 🟢 Niski | Refaktoryzacja discover.py | 3-4h |

**Łączny szacowany czas**: ~16-22h

---

## Następne kroki

1. Rozpocząć od wyodrębnienia HTML/CSS/JS z `webenv.py` (najwyższy priorytet)
2. Dodać pre-commit hooks (szybka wygrana)
3. Dodać health checks do docker-compose
4. Kontynuować z pozostałymi zadaniami według priorytetów
