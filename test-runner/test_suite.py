# test-runner/test_suite.py
import sys
import os
import pytest
import json
import yaml
from datetime import datetime
import logging
from pathlib import Path

# Konfiguracja loggingu
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/test_suite.log'),
        logging.StreamHandler(sys.stdout)
    ]
)

logger = logging.getLogger(__name__)


class TestSuiteRunner:
    def __init__(self):
        self.config = self.load_config()
        self.results_dir = Path('reports')
        self.results_dir.mkdir(exist_ok=True)

    def load_config(self):
        """Ładuje konfigurację testów"""
        config_file = Path('config/test_config.yaml')
        if config_file.exists():
            with open(config_file, 'r', encoding='utf-8') as f:
                return yaml.safe_load(f)

        # Domyślna konfiguracja
        return {
            'environment': os.getenv('TEST_ENVIRONMENT', 'docker'),
            'endpoints': {
                'rpi_server': 'http://rpi-server:8081',
                'mssql_wapromag': 'mssql-wapromag:1433',
                'zebra_printer_1': 'zebra-printer-1:9100',
                'zebra_printer_2': 'zebra-printer-2:9100'
            },
            'database': {
                'host': 'mssql-wapromag',
                'port': 1433,
                'database': 'WAPROMAG_TEST',
                'username': 'sa',
                'password': 'WapromagPass123!'
            },
            'timeouts': {
                'connection': 10,
                'response': 30,
                'long_operation': 60
            },
            'test_data': {
                'test_product_code': 'TEST001',
                'test_contractor_code': 'TESTK001',
                'test_document_number': 'TEST/001/2025'
            }
        }

    def run_tests(self):
        """Uruchamia wszystkie testy i generuje raporty"""
        logger.info("🧪 Rozpoczynanie testów WAPRO Network Mock")

        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')

        # Argumenty dla pytest
        pytest_args = [
            'tests/',
            '-v',
            '--tb=short',
            f'--html=reports/test_report_{timestamp}.html',
            '--self-contained-html',
            f'--json-report-file=reports/test_results_{timestamp}.json',
            '--json-report-summary'
        ]

        # Dodatkowe opcje w zależności od środowiska
        if self.config.get('environment') == 'ci':
            pytest_args.extend(['--maxfail=5', '--strict-markers'])

        try:
            # Uruchomienie testów
            exit_code = pytest.main(pytest_args)

            # Generowanie dodatkowych raportów
            self.generate_summary_report(timestamp)
            self.generate_health_report()

            if exit_code == 0:
                logger.info("✅ Wszystkie testy zakończone pomyślnie")
            else:
                logger.warning(f"⚠️ Testy zakończone z błędami (kod: {exit_code})")

            return exit_code

        except Exception as e:
            logger.error(f"❌ Błąd podczas uruchamiania testów: {e}")
            return 1

    def generate_summary_report(self, timestamp):
        """Generuje podsumowanie wyników testów"""
        try:
            json_report_path = f'reports/test_results_{timestamp}.json'
            if not os.path.exists(json_report_path):
                return

            with open(json_report_path, 'r') as f:
                results = json.load(f)

            summary = {
                'timestamp': timestamp,
                'environment': self.config.get('environment'),
                'total_tests': results['summary']['total'],
                'passed': results['summary'].get('passed', 0),
                'failed': results['summary'].get('failed', 0),
                'skipped': results['summary'].get('skipped', 0),
                'errors': results['summary'].get('errors', 0),
                'duration': results['summary']['duration'],
                'success_rate': 0
            }

            if summary['total_tests'] > 0:
                summary['success_rate'] = (summary['passed'] / summary['total_tests']) * 100

            # Grupowanie wyników po kategoriach
            categories = {
                'database': [],
                'printers': [],
                'integration': [],
                'performance': []
            }

            for test in results['tests']:
                test_name = test['nodeid']
                if 'test_rpi_sql' in test_name or 'database' in test_name:
                    categories['database'].append(test)
                elif 'zebra' in test_name or 'printer' in test_name:
                    categories['printers'].append(test)
                elif 'integration' in test_name:
                    categories['integration'].append(test)
                elif 'performance' in test_name:
                    categories['performance'].append(test)

            summary['categories'] = {}
            for category, tests in categories.items():
                passed = len([t for t in tests if t['outcome'] == 'passed'])
                total = len(tests)
                summary['categories'][category] = {
                    'total': total,
                    'passed': passed,
                    'success_rate': (passed / total * 100) if total > 0 else 0
                }

            # Zapisanie podsumowania
            with open(f'reports/summary_{timestamp}.json', 'w') as f:
                json.dump(summary, f, indent=2)

            logger.info(f"📊 Podsumowanie testów zapisane: summary_{timestamp}.json")
            logger.info(f"✅ Zaliczonych: {summary['passed']}/{summary['total_tests']} ({summary['success_rate']:.1f}%)")

        except Exception as e:
            logger.error(f"Błąd podczas generowania podsumowania: {e}")

    def generate_health_report(self):
        """Generuje raport zdrowia systemu"""
        try:
            import requests
            from datetime import datetime
            
            health_data = {
                'timestamp': datetime.now().isoformat(),
                'components': {}
            }
            
            # Testowanie komponentów
            components = [
                ('RPI Server', 'http://rpi-server:8081/health'),
                ('ZEBRA Printer 1', 'http://zebra-printer-1:8080/api/status'),
                ('ZEBRA Printer 2', 'http://zebra-printer-2:8080/api/status')
            ]
            
            healthy_components = 0
            total_components = len(components)
            
            for name, url in components:
                try:
                    response = requests.get(url, timeout=5)
                    is_healthy = response.status_code == 200
                    health_data['components'][name] = {
                        'status': 'healthy' if is_healthy else 'unhealthy',
                        'http_code': response.status_code
                    }
                    if is_healthy:
                        healthy_components += 1
                except Exception as e:
                    health_data['components'][name] = {
                        'status': 'error',
                        'error': str(e)
                    }
            
            health_percentage = (healthy_components / total_components * 100) if total_components > 0 else 0
            health_data['overall_health'] = health_percentage
            
            # Zapisanie raportu
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            with open(f'reports/health_{timestamp}.json', 'w') as f:
                json.dump(health_data, f, indent=2)
            
            logger.info(
                f"🏥 Stan zdrowia systemu: {health_percentage:.1f}% ({healthy_components}/{total_components} komponentów)")

        except Exception as e:
            logger.error(f"Błąd podczas generowania raportu zdrowia: {e}")


def main():
    """Główna funkcja uruchamiająca testy"""
    runner = TestSuiteRunner()
    exit_code = runner.run_tests()
    sys.exit(exit_code)


if __name__ == '__main__':
    main()
