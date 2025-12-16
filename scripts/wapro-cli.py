#!/usr/bin/env python3
"""
WAPRO Network Mock - CLI DSL
Interactive command-line interface for managing the system.

Usage:
    python3 wapro-cli.py                    # Interactive mode
    python3 wapro-cli.py <command> [args]   # Single command mode
    
Commands:
    discover [--full]       Scan network for devices
    config list             List current configuration
    config get <key>        Get config value
    config set <key> <val>  Set config value
    config edit             Open interactive config editor
    start [--prod]          Start services
    stop [--prod]           Stop services
    restart [--prod]        Restart services
    status [--prod]         Show service status
    logs [service]          Show logs
    health                  Check health of all services
    help                    Show this help
    exit                    Exit interactive mode
"""

import os
import sys
import json
import subprocess
import readline
import shlex
from datetime import datetime

# Configuration
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
ENV_FILE = os.path.join(PROJECT_DIR, '.env')
ENV_EXAMPLE = os.path.join(PROJECT_DIR, '.env.example')
DEVICES_FILE = os.path.join(PROJECT_DIR, 'logs', 'discovered_devices.json')
HISTORY_FILE = os.path.join(PROJECT_DIR, '.wapro_history')

# Colors
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    CYAN = '\033[0;36m'
    MAGENTA = '\033[0;35m'
    BOLD = '\033[1m'
    NC = '\033[0m'

def color(text, c):
    return f"{c}{text}{Colors.NC}"

def print_header():
    print("")
    print(color("=" * 60, Colors.BLUE))
    print(color("     WAPRO Network Mock - CLI", Colors.BOLD))
    print(color("=" * 60, Colors.BLUE))
    print(color("  Type 'help' for commands, 'exit' to quit", Colors.CYAN))
    print("")

def print_success(msg):
    print(color(f"[+] {msg}", Colors.GREEN))

def print_error(msg):
    print(color(f"[X] {msg}", Colors.RED))

def print_info(msg):
    print(color(f"[i] {msg}", Colors.BLUE))

def print_warn(msg):
    print(color(f"[!] {msg}", Colors.YELLOW))


# =============================================================================
# CONFIG MANAGEMENT
# =============================================================================

def load_env():
    """Load .env file as dictionary"""
    config = {}
    try:
        with open(ENV_FILE, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#'):
                    if '=' in line:
                        key, value = line.split('=', 1)
                        config[key.strip()] = value.strip()
    except FileNotFoundError:
        pass
    return config

def save_env(config):
    """Save dictionary to .env file, preserving comments"""
    try:
        # Read original file to preserve comments
        lines = []
        try:
            with open(ENV_FILE, 'r') as f:
                lines = f.readlines()
        except FileNotFoundError:
            pass
        
        # Update values
        updated_keys = set()
        new_lines = []
        for line in lines:
            stripped = line.strip()
            if stripped and not stripped.startswith('#') and '=' in stripped:
                key = stripped.split('=', 1)[0].strip()
                if key in config:
                    new_lines.append(f"{key}={config[key]}\n")
                    updated_keys.add(key)
                else:
                    new_lines.append(line)
            else:
                new_lines.append(line)
        
        # Add new keys
        for key, value in config.items():
            if key not in updated_keys:
                new_lines.append(f"{key}={value}\n")
        
        with open(ENV_FILE, 'w') as f:
            f.writelines(new_lines)
        
        return True
    except Exception as e:
        print_error(f"Failed to save config: {e}")
        return False


def cmd_config(args):
    """Config management commands"""
    if not args:
        args = ['list']
    
    subcmd = args[0]
    
    if subcmd == 'list':
        config = load_env()
        if not config:
            print_warn("No configuration found. Run 'config edit' to create one.")
            return
        
        print_info("Current configuration:")
        print("")
        
        # Group by prefix
        groups = {}
        for key, value in sorted(config.items()):
            prefix = key.split('_')[0] if '_' in key else 'OTHER'
            if prefix not in groups:
                groups[prefix] = []
            groups[prefix].append((key, value))
        
        for group, items in sorted(groups.items()):
            print(color(f"  [{group}]", Colors.CYAN))
            for key, value in items:
                # Mask passwords
                display_value = '***' if 'PASSWORD' in key or 'SECRET' in key else value
                print(f"    {key} = {color(display_value, Colors.GREEN)}")
            print("")
    
    elif subcmd == 'get':
        if len(args) < 2:
            print_error("Usage: config get <key>")
            return
        key = args[1]
        config = load_env()
        if key in config:
            print(f"{key} = {color(config[key], Colors.GREEN)}")
        else:
            print_warn(f"Key '{key}' not found")
    
    elif subcmd == 'set':
        if len(args) < 3:
            print_error("Usage: config set <key> <value>")
            return
        key = args[1]
        value = ' '.join(args[2:])
        config = load_env()
        old_value = config.get(key, None)
        config[key] = value
        if save_env(config):
            if old_value:
                print_success(f"Updated {key}: {old_value} -> {value}")
            else:
                print_success(f"Set {key} = {value}")
    
    elif subcmd == 'edit':
        # Interactive config editor
        config = load_env()
        
        # Key parameters to edit
        keys = [
            ('MSSQL_HOST', 'MSSQL Server Host'),
            ('MSSQL_EXTERNAL_PORT', 'MSSQL Port'),
            ('MSSQL_USER', 'MSSQL User'),
            ('MSSQL_SA_PASSWORD', 'MSSQL Password'),
            ('MSSQL_DATABASE', 'MSSQL Database'),
            ('ZEBRA_1_HOST', 'Zebra 1 Host'),
            ('ZEBRA_1_SOCKET_PORT', 'Zebra 1 Port'),
            ('ZEBRA_2_HOST', 'Zebra 2 Host'),
            ('ZEBRA_2_SOCKET_PORT', 'Zebra 2 Port'),
            ('RPI_GUI_EXTERNAL_PORT', 'RPI GUI Port'),
            ('RPI_API_EXTERNAL_PORT', 'RPI API Port'),
        ]
        
        print_info("Interactive config editor (press Enter to keep current value)")
        print("")
        
        # Load suggestions from discovered devices
        suggestions = {}
        try:
            with open(DEVICES_FILE, 'r') as f:
                devices = json.load(f)
                if devices.get('devices', {}).get('mssql_servers'):
                    mssql = devices['devices']['mssql_servers'][0]
                    suggestions['MSSQL_HOST'] = mssql['host']
                    suggestions['MSSQL_EXTERNAL_PORT'] = str(mssql['port'])
                if devices.get('devices', {}).get('zebra_printers'):
                    for i, printer in enumerate(devices['devices']['zebra_printers'][:2]):
                        suggestions[f'ZEBRA_{i+1}_HOST'] = printer['host']
                        suggestions[f'ZEBRA_{i+1}_SOCKET_PORT'] = str(printer['port'])
        except:
            pass
        
        changed = False
        for key, label in keys:
            current = config.get(key, '')
            suggestion = suggestions.get(key, '')
            
            prompt = f"  {color(label, Colors.CYAN)} ({key})"
            if current:
                prompt += f" [{color(current, Colors.GREEN)}]"
            if suggestion and suggestion != current:
                prompt += f" (propozycja: {color(suggestion, Colors.YELLOW)})"
            prompt += ": "
            
            try:
                new_value = input(prompt).strip()
                if new_value == '?':
                    # Use suggestion
                    if suggestion:
                        config[key] = suggestion
                        changed = True
                        print_success(f"  -> {suggestion}")
                elif new_value:
                    config[key] = new_value
                    changed = True
            except (KeyboardInterrupt, EOFError):
                print("")
                return
        
        if changed:
            if save_env(config):
                print_success("Configuration saved!")
        else:
            print_info("No changes made")
    
    elif subcmd == 'suggest':
        # Apply all suggestions from discovered devices
        try:
            with open(DEVICES_FILE, 'r') as f:
                devices = json.load(f)
        except FileNotFoundError:
            print_warn("No discovered devices. Run 'discover' first.")
            return
        
        config = load_env()
        applied = 0
        
        if devices.get('devices', {}).get('mssql_servers'):
            mssql = devices['devices']['mssql_servers'][0]
            config['MSSQL_HOST'] = mssql['host']
            config['MSSQL_EXTERNAL_PORT'] = str(mssql['port'])
            print_success(f"MSSQL: {mssql['host']}:{mssql['port']}")
            applied += 1
        
        if devices.get('devices', {}).get('zebra_printers'):
            for i, printer in enumerate(devices['devices']['zebra_printers'][:2]):
                config[f'ZEBRA_{i+1}_HOST'] = printer['host']
                config[f'ZEBRA_{i+1}_SOCKET_PORT'] = str(printer['port'])
                print_success(f"Zebra {i+1}: {printer['host']}:{printer['port']}")
                applied += 1
        
        if applied > 0:
            save_env(config)
            print_success(f"Applied {applied} suggestions")
        else:
            print_warn("No suggestions to apply")
    
    else:
        print_error(f"Unknown config command: {subcmd}")
        print_info("Available: list, get, set, edit, suggest")


# =============================================================================
# DISCOVERY
# =============================================================================

def cmd_discover(args):
    """Discover network devices"""
    full = '--full' in args or '-f' in args
    
    print_info("Scanning network for devices...")
    
    script = os.path.join(SCRIPT_DIR, 'discover.py')
    cmd = ['python3', script]
    if not full:
        cmd.append('-q')
    
    try:
        result = subprocess.run(cmd, cwd=PROJECT_DIR)
        
        # Show summary
        try:
            with open(DEVICES_FILE, 'r') as f:
                devices = json.load(f)
            
            print("")
            print_info("Discovered devices:")
            
            printers = devices.get('devices', {}).get('zebra_printers', [])
            mssql = devices.get('devices', {}).get('mssql_servers', [])
            
            if printers:
                for p in printers:
                    print(f"  Zebra: {color(p['host'] + ':' + str(p['port']), Colors.GREEN)}")
            
            if mssql:
                for m in mssql:
                    print(f"  MSSQL: {color(m['host'] + ':' + str(m['port']), Colors.BLUE)}")
            
            if not printers and not mssql:
                print_warn("  No devices found")
            else:
                print("")
                print_info("Run 'config suggest' to apply discovered values")
        except:
            pass
    except Exception as e:
        print_error(f"Discovery failed: {e}")


# =============================================================================
# SERVICE MANAGEMENT
# =============================================================================

def run_docker_compose(args, prod=False):
    """Run docker-compose command"""
    cmd = ['docker-compose']
    if prod:
        cmd.extend(['-f', 'docker-compose.prod.yml'])
    else:
        cmd.extend(['--profile', 'full'])
    cmd.extend(args)
    
    # Try without sudo first
    try:
        result = subprocess.run(cmd, cwd=PROJECT_DIR, capture_output=True, text=True)
        if result.returncode == 0:
            if result.stdout:
                print(result.stdout)
            return True
        elif 'permission denied' in result.stderr.lower():
            # Try with sudo
            cmd = ['sudo'] + cmd
            result = subprocess.run(cmd, cwd=PROJECT_DIR)
            return result.returncode == 0
        else:
            if result.stderr:
                print(result.stderr)
            return False
    except Exception as e:
        print_error(f"Command failed: {e}")
        return False


def cmd_start(args):
    """Start services"""
    prod = '--prod' in args or '-p' in args
    
    if prod:
        print_info("Starting PRODUCTION mode (RPI Server only)...")
    else:
        print_info("Starting DEVELOPMENT mode (all services)...")
    
    if run_docker_compose(['up', '-d'], prod=prod):
        print_success("Services started")
        cmd_status(args)
    else:
        print_error("Failed to start services")


def cmd_stop(args):
    """Stop services"""
    prod = '--prod' in args or '-p' in args
    
    if prod:
        print_info("Stopping production services...")
    else:
        print_info("Stopping all services...")
    
    if run_docker_compose(['down'], prod=prod):
        print_success("Services stopped")
    else:
        print_error("Failed to stop services")


def cmd_restart(args):
    """Restart services"""
    cmd_stop(args)
    cmd_start(args)


def cmd_status(args):
    """Show service status"""
    prod = '--prod' in args or '-p' in args
    
    print_info("Service status:")
    print("")
    run_docker_compose(['ps'], prod=prod)
    
    # Show endpoints
    config = load_env()
    print("")
    print_info("Endpoints:")
    print(f"  RPI GUI:   {color('http://localhost:' + config.get('RPI_GUI_EXTERNAL_PORT', '8082'), Colors.GREEN)}")
    print(f"  RPI API:   {color('http://localhost:' + config.get('RPI_API_EXTERNAL_PORT', '8081'), Colors.GREEN)}")
    if not prod:
        print(f"  Zebra 1:   {color('http://localhost:' + config.get('ZEBRA_1_EXTERNAL_WEB_PORT', '8091'), Colors.CYAN)}")
        print(f"  Zebra 2:   {color('http://localhost:' + config.get('ZEBRA_2_EXTERNAL_WEB_PORT', '8092'), Colors.CYAN)}")
        print(f"  Grafana:   {color('http://localhost:' + config.get('GRAFANA_PORT', '3000'), Colors.MAGENTA)}")
        print(f"  MSSQL:     {color('localhost:' + config.get('MSSQL_EXTERNAL_PORT', '1433'), Colors.BLUE)}")


def cmd_logs(args):
    """Show logs"""
    prod = '--prod' in args or '-p' in args
    service = None
    for a in args:
        if not a.startswith('-'):
            service = a
            break
    
    cmd = ['logs', '-f', '--tail=100']
    if service:
        cmd.append(service)
    
    print_info(f"Showing logs{' for ' + service if service else ''}... (Ctrl+C to stop)")
    run_docker_compose(cmd, prod=prod)


def cmd_health(args):
    """Check health of services"""
    import urllib.request
    
    config = load_env()
    
    endpoints = [
        ('RPI GUI', f"http://localhost:{config.get('RPI_GUI_EXTERNAL_PORT', '8082')}/health"),
        ('RPI API', f"http://localhost:{config.get('RPI_API_EXTERNAL_PORT', '8081')}/health"),
        ('Zebra 1', f"http://localhost:{config.get('ZEBRA_1_EXTERNAL_WEB_PORT', '8091')}/api/status"),
        ('Zebra 2', f"http://localhost:{config.get('ZEBRA_2_EXTERNAL_WEB_PORT', '8092')}/api/status"),
    ]
    
    print_info("Health check:")
    print("")
    
    for name, url in endpoints:
        try:
            req = urllib.request.urlopen(url, timeout=3)
            if req.status == 200:
                print(f"  {name}: {color('OK', Colors.GREEN)}")
            else:
                print(f"  {name}: {color(f'HTTP {req.status}', Colors.YELLOW)}")
        except Exception as e:
            print(f"  {name}: {color('OFFLINE', Colors.RED)}")


# =============================================================================
# HELP
# =============================================================================

def cmd_help(args):
    """Show help"""
    print(color("""
WAPRO Network Mock - CLI Commands
==================================

DISCOVERY:
  discover [--full]         Scan network for devices (quick or full)

CONFIGURATION:
  config list               List all configuration values
  config get <key>          Get specific config value
  config set <key> <value>  Set config value
  config edit               Interactive config editor
  config suggest            Apply discovered device values

SERVICES (Development - all containers):
  start                     Start all services
  stop                      Stop all services
  restart                   Restart all services
  status                    Show service status
  logs [service]            Show logs (optional: specific service)
  health                    Check health of all services

SERVICES (Production - only RPI Server):
  start --prod              Start production mode
  stop --prod               Stop production mode
  status --prod             Show production status
  logs --prod               Show production logs

OTHER:
  help                      Show this help
  exit / quit               Exit CLI

SHORTCUTS:
  d                         discover
  c                         config list
  s                         status
  l                         logs
  h                         health
  ?                         help
""", Colors.CYAN))


# =============================================================================
# MAIN LOOP
# =============================================================================

COMMANDS = {
    'discover': cmd_discover,
    'd': cmd_discover,
    'config': cmd_config,
    'c': lambda args: cmd_config(['list']),
    'start': cmd_start,
    'stop': cmd_stop,
    'restart': cmd_restart,
    'status': cmd_status,
    's': cmd_status,
    'logs': cmd_logs,
    'l': cmd_logs,
    'health': cmd_health,
    'h': cmd_health,
    'help': cmd_help,
    '?': cmd_help,
}


def complete(text, state):
    """Tab completion"""
    commands = list(COMMANDS.keys()) + ['exit', 'quit']
    matches = [c for c in commands if c.startswith(text)]
    if state < len(matches):
        return matches[state]
    return None


def run_interactive():
    """Run interactive mode"""
    print_header()
    
    # Setup readline
    readline.set_completer(complete)
    readline.parse_and_bind('tab: complete')
    
    # Load history
    try:
        readline.read_history_file(HISTORY_FILE)
    except:
        pass
    
    while True:
        try:
            prompt = color("wapro> ", Colors.GREEN)
            line = input(prompt).strip()
            
            if not line:
                continue
            
            # Parse command
            try:
                parts = shlex.split(line)
            except:
                parts = line.split()
            
            cmd = parts[0].lower()
            args = parts[1:]
            
            if cmd in ('exit', 'quit', 'q'):
                print_info("Goodbye!")
                break
            
            if cmd in COMMANDS:
                COMMANDS[cmd](args)
            else:
                print_error(f"Unknown command: {cmd}")
                print_info("Type 'help' for available commands")
            
            print("")
            
        except KeyboardInterrupt:
            print("")
            continue
        except EOFError:
            print("")
            break
    
    # Save history
    try:
        readline.write_history_file(HISTORY_FILE)
    except:
        pass


def run_single(args):
    """Run single command"""
    cmd = args[0].lower()
    cmd_args = args[1:]
    
    if cmd in COMMANDS:
        COMMANDS[cmd](cmd_args)
    else:
        print_error(f"Unknown command: {cmd}")
        sys.exit(1)


def main():
    os.chdir(PROJECT_DIR)
    
    if len(sys.argv) > 1:
        run_single(sys.argv[1:])
    else:
        run_interactive()


if __name__ == '__main__':
    main()
