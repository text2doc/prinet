# test-runner/tests/test_rpi_zebra.py
"""
Testy integracji RPI Server z drukarkami ZEBRA
"""
import pytest
import requests
import socket


class TestRPIZebraIntegration:
    """Testy integracji RPI z drukarkami ZEBRA"""
    
    @pytest.fixture
    def rpi_url(self):
        """URL do RPI Server"""
        return "http://rpi-server:8081"
    
    @pytest.fixture
    def zebra1_host(self):
        """Host drukarki ZEBRA-001"""
        return ("zebra-printer-1", 9100)
    
    @pytest.fixture
    def zebra2_host(self):
        """Host drukarki ZEBRA-002"""
        return ("zebra-printer-2", 9100)
    
    def test_rpi_can_reach_zebra1(self, zebra1_host):
        """Test czy można połączyć się z ZEBRA Printer 1"""
        host, port = zebra1_host
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        
        try:
            result = sock.connect_ex((host, port))
            assert result == 0, f"Nie można połączyć się z {host}:{port}"
        finally:
            sock.close()
    
    def test_rpi_can_reach_zebra2(self, zebra2_host):
        """Test czy można połączyć się z ZEBRA Printer 2"""
        host, port = zebra2_host
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5)
        
        try:
            result = sock.connect_ex((host, port))
            assert result == 0, f"Nie można połączyć się z {host}:{port}"
        finally:
            sock.close()
    
    def test_rpi_health_endpoint(self, rpi_url):
        """Test endpointu health RPI Server"""
        response = requests.get(f"{rpi_url}/health", timeout=10)
        assert response.status_code == 200
        
        data = response.json()
        assert 'status' in data
        assert data['status'] == 'ok'
    
    def test_zebra1_status_api(self):
        """Test API statusu ZEBRA Printer 1"""
        response = requests.get("http://zebra-printer-1:8080/api/status", timeout=10)
        assert response.status_code == 200
        
        data = response.json()
        assert 'name' in data
        assert 'status' in data
    
    def test_zebra2_status_api(self):
        """Test API statusu ZEBRA Printer 2"""
        response = requests.get("http://zebra-printer-2:8080/api/status", timeout=10)
        assert response.status_code == 200
        
        data = response.json()
        assert 'name' in data
        assert 'status' in data
