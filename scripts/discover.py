#!/usr/bin/env python3
"""
Network Device Discovery for WAPRO Network Mock
Discovers: Zebra printers, MSSQL servers, HTTP services
Outputs: JSON file with discovered devices
"""

import os
import sys
import json
import socket
import subprocess
import threading
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed

# Configuration
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
RESULTS_FILE = os.path.join(PROJECT_DIR, 'logs', 'discovered_devices.json')
ENV_FILE = os.path.join(PROJECT_DIR, '.env')

# Ports to scan
ZEBRA_PORTS = [9100, 6101]
MSSQL_PORT = 1433
HTTP_PORTS = [80, 8080, 8081, 8082, 8091, 8092]

# Timeouts
SCAN_TIMEOUT = 1
MAX_WORKERS = 50


def get_local_ips():
    """Get local IP addresses - only first network interface (eth/wlan)"""
    ips = []
    try:
        # Method 1: ip command - get source IP from default route
        result = subprocess.run(['ip', 'route', 'get', '8.8.8.8'], capture_output=True, text=True)
        # Parse: "8.8.8.8 via 192.168.188.1 dev wlan0 src 192.168.188.212 uid 1000"
        # We need the IP after "src"
        parts = result.stdout.split()
        for i, part in enumerate(parts):
            if part == 'src' and i + 1 < len(parts):
                ips = [parts[i + 1]]
                break
        
        if not ips:
            # Fallback: get first non-loopback IP from interface
            result = subprocess.run(['ip', '-4', 'addr', 'show'], capture_output=True, text=True)
            for line in result.stdout.split('\n'):
                if 'inet ' in line and '127.' not in line:
                    parts = line.strip().split()
                    for i, p in enumerate(parts):
                        if p == 'inet' and i + 1 < len(parts):
                            ip_cidr = parts[i + 1]
                            ip = ip_cidr.split('/')[0]
                            ips.append(ip)
                            break  # Only first IP
                    if ips:
                        break
    except:
        pass
    
    if not ips:
        try:
            # Method 2: hostname
            hostname = socket.gethostname()
            ips = [socket.gethostbyname(hostname)]
        except:
            ips = ['192.168.1.1']
    
    return ips[:1]  # Return only first IP


def get_network_range(ip):
    """Get network range from IP (first 3 octets)"""
    parts = ip.split('.')
    if len(parts) >= 3:
        return '.'.join(parts[:3])
    return None


def scan_port(host, port, timeout=SCAN_TIMEOUT):
    """Scan a single port on a host"""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        result = sock.connect_ex((host, port))
        sock.close()
        return result == 0
    except:
        return False


def identify_zebra_printer(host, port):
    """Try to identify Zebra printer model"""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(2)
        sock.connect((host, port))
        # Send ZPL status command
        sock.send(b'~HS\r\n')
        response = sock.recv(1024).decode('utf-8', errors='ignore')
        sock.close()
        
        if 'ZT' in response or 'ZD' in response or 'GK' in response:
            return response.strip()[:50]
    except:
        pass
    return None


def scan_network(network_range, ports, device_type='generic'):
    """Scan a network range for open ports"""
    devices = []
    hosts_to_scan = []
    
    # Generate host list (1-254)
    for i in range(1, 255):
        hosts_to_scan.append(f"{network_range}.{i}")
    
    def check_host_port(host, port):
        if scan_port(host, port):
            device = {
                'host': host,
                'port': port,
                'type': device_type,
                'discovered_at': datetime.now().isoformat()
            }
            
            # Try to identify Zebra printer
            if device_type == 'zebra' and port == 9100:
                model = identify_zebra_printer(host, port)
                if model:
                    device['model'] = model
            
            return device
        return None
    
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = []
        for host in hosts_to_scan:
            for port in ports:
                futures.append(executor.submit(check_host_port, host, port))
        
        for future in as_completed(futures):
            result = future.result()
            if result:
                devices.append(result)
                print(f"  [+] Found {device_type}: {result['host']}:{result['port']}")
    
    return devices


def discover_all(quick=False):
    """Discover all devices"""
    print("")
    print("=" * 60)
    print("     WAPRO Network Mock - Device Discovery")
    print("=" * 60)
    print("")
    
    results = {
        'scan_date': datetime.now().isoformat(),
        'local_ips': [],
        'networks': [],
        'devices': {
            'zebra_printers': [],
            'mssql_servers': [],
            'http_services': []
        }
    }
    
    # Get local IPs
    print("[i] Detecting local network...")
    local_ips = get_local_ips()
    results['local_ips'] = local_ips
    
    for ip in local_ips:
        print(f"    Local IP: {ip}")
    print("")
    
    # Get network ranges
    networks = set()
    for ip in local_ips:
        network = get_network_range(ip)
        if network:
            networks.add(network)
    
    results['networks'] = list(networks)
    
    # Scan each network
    for network in networks:
        print(f"[i] Scanning network: {network}.0/24")
        print("")
        
        # Quick scan addresses - common device IPs
        quick_addresses = list(range(1, 51)) + list(range(100, 151)) + list(range(200, 255))
        
        # Zebra printers
        print("[i] Looking for Zebra printers (ports 9100, 6101)...")
        if quick:
            # Quick scan with threading
            from concurrent.futures import ThreadPoolExecutor, as_completed
            def check_zebra(i):
                host = f"{network}.{i}"
                for port in ZEBRA_PORTS:
                    if scan_port(host, port):
                        return {'host': host, 'port': port, 'type': 'zebra'}
                return None
            
            with ThreadPoolExecutor(max_workers=30) as executor:
                futures = [executor.submit(check_zebra, i) for i in quick_addresses]
                for future in as_completed(futures):
                    result = future.result()
                    if result:
                        results['devices']['zebra_printers'].append(result)
                        print(f"  [+] Found Zebra: {result['host']}:{result['port']}")
        else:
            printers = scan_network(network, ZEBRA_PORTS, 'zebra')
            results['devices']['zebra_printers'].extend(printers)
        print("")
        
        # MSSQL servers
        print("[i] Looking for MSSQL servers (port 1433)...")
        if quick:
            def check_mssql(i):
                host = f"{network}.{i}"
                if scan_port(host, MSSQL_PORT):
                    return {'host': host, 'port': MSSQL_PORT, 'type': 'mssql'}
                return None
            
            with ThreadPoolExecutor(max_workers=30) as executor:
                futures = [executor.submit(check_mssql, i) for i in quick_addresses]
                for future in as_completed(futures):
                    result = future.result()
                    if result:
                        results['devices']['mssql_servers'].append(result)
                        print(f"  [+] Found MSSQL: {result['host']}:{result['port']}")
        else:
            servers = scan_network(network, [MSSQL_PORT], 'mssql')
            results['devices']['mssql_servers'].extend(servers)
        print("")
        
        # HTTP services (only in full scan)
        if not quick:
            print("[i] Looking for HTTP services...")
            services = scan_network(network, HTTP_PORTS, 'http')
            results['devices']['http_services'].extend(services)
            print("")
    
    # Save results
    os.makedirs(os.path.dirname(RESULTS_FILE), exist_ok=True)
    with open(RESULTS_FILE, 'w') as f:
        json.dump(results, f, indent=2)
    
    print(f"[+] Results saved to: {RESULTS_FILE}")
    print("")
    
    # Summary
    print("=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"  Zebra printers: {len(results['devices']['zebra_printers'])}")
    print(f"  MSSQL servers:  {len(results['devices']['mssql_servers'])}")
    print(f"  HTTP services:  {len(results['devices']['http_services'])}")
    print("")
    
    return results


def main():
    quick = '-q' in sys.argv or '--quick' in sys.argv
    discover_all(quick=quick)
    
    print("Next steps:")
    print("  1. Run: make webenv")
    print("  2. Configure discovered devices in .env")
    print("  3. Run: make start")
    print("")


if __name__ == '__main__':
    main()
