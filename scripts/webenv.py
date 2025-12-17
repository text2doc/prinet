#!/usr/bin/env python3
"""
Web-based .env editor for WAPRO Network Mock
Usage: python3 webenv.py [port]
Default port: 8888
"""

import os
import sys
import json
import threading
import subprocess
from datetime import datetime
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlparse

# Configuration
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
ENV_FILE = os.path.join(PROJECT_DIR, '.env')
ENV_EXAMPLE = os.path.join(PROJECT_DIR, '.env.example')
DEFAULT_PORT = 8888

ADMIN_TOKEN = os.getenv('WEBENV_ADMIN_TOKEN', '')
ALLOWED_MAKE_TARGETS = [
    'start',
    'stop',
    'restart',
    'status',
    'discover',
    'discover-full',
    'health',
    'prod',
    'prod-stop',
    'prod-status',
    'prod-build',
]
MAKE_LOG_FILE = os.path.join(PROJECT_DIR, 'logs', 'webenv_make.log')
MAKE_STATE_LOCK = threading.Lock()
MAKE_STATE = {
    'running': False,
    'target': None,
    'pid': None,
    'exit_code': None,
    'started_at': None,
    'ended_at': None,
}
MAKE_PROCESS = None


def _append_make_log(text: str) -> None:
    os.makedirs(os.path.dirname(MAKE_LOG_FILE), exist_ok=True)
    with open(MAKE_LOG_FILE, 'a', encoding='utf-8', errors='replace') as f:
        f.write(text)


def _read_make_log_tail(max_bytes: int = 20000) -> str:
    try:
        with open(MAKE_LOG_FILE, 'rb') as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            f.seek(max(0, size - max_bytes))
            data = f.read()
        return data.decode('utf-8', errors='replace')
    except FileNotFoundError:
        return ''
    except Exception as e:
        return f'[webenv] Error reading log: {e}'


def _run_make_target_in_background(target: str) -> None:
    global MAKE_PROCESS

    started_at = datetime.now().isoformat(timespec='seconds')
    _append_make_log(f"\n===== {started_at} | make {target} =====\n")

    try:
        proc = subprocess.Popen(
            ['make', target],
            cwd=PROJECT_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )

        with MAKE_STATE_LOCK:
            MAKE_PROCESS = proc
            MAKE_STATE['pid'] = proc.pid

        if proc.stdout:
            for line in proc.stdout:
                _append_make_log(line)

        exit_code = proc.wait()

        ended_at = datetime.now().isoformat(timespec='seconds')
        _append_make_log(f"\n===== {ended_at} | exit={exit_code} =====\n")

        with MAKE_STATE_LOCK:
            MAKE_STATE['running'] = False
            MAKE_STATE['exit_code'] = exit_code
            MAKE_STATE['ended_at'] = ended_at
            MAKE_STATE['pid'] = None
            MAKE_PROCESS = None

    except Exception as e:
        ended_at = datetime.now().isoformat(timespec='seconds')
        _append_make_log(f"\n===== {ended_at} | ERROR: {e} =====\n")
        with MAKE_STATE_LOCK:
            MAKE_STATE['running'] = False
            MAKE_STATE['exit_code'] = 1
            MAKE_STATE['ended_at'] = ended_at
            MAKE_STATE['pid'] = None
            MAKE_PROCESS = None

HTML_TEMPLATE = '''<!DOCTYPE html>
<html lang="pl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>WAPRO Network Mock - Konfiguracja .env</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            min-height: 100vh;
            color: #e4e4e4;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }
        header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
            border-radius: 10px;
            margin-bottom: 20px;
            box-shadow: 0 4px 15px rgba(0,0,0,0.3);
        }
        header h1 {
            font-size: 1.5rem;
            margin-bottom: 5px;
        }
        header p {
            opacity: 0.8;
            font-size: 0.9rem;
        }
        .editor-container {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 20px;
        }
        @media (max-width: 900px) {
            .editor-container { grid-template-columns: 1fr; }
        }
        .panel {
            background: #1e1e2e;
            border-radius: 10px;
            overflow: hidden;
            box-shadow: 0 4px 15px rgba(0,0,0,0.3);
        }
        .panel-header {
            background: #2d2d3d;
            padding: 15px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            border-bottom: 1px solid #3d3d4d;
        }
        .panel-header h2 {
            font-size: 1rem;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .panel-body {
            padding: 15px;
        }
        textarea {
            width: 100%;
            height: 500px;
            background: #0d0d1a;
            border: 1px solid #3d3d4d;
            border-radius: 5px;
            color: #e4e4e4;
            font-family: 'Courier New', monospace;
            font-size: 13px;
            padding: 15px;
            resize: vertical;
            line-height: 1.5;
        }
        textarea:focus {
            outline: none;
            border-color: #667eea;
            box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.2);
        }
        .btn {
            padding: 10px 20px;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            font-weight: 600;
            font-size: 0.9rem;
            transition: all 0.2s;
            display: inline-flex;
            align-items: center;
            gap: 8px;
        }
        .btn-primary {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .btn-primary:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 15px rgba(102, 126, 234, 0.4);
        }
        .btn-secondary {
            background: #3d3d4d;
            color: #e4e4e4;
        }
        .btn-secondary:hover {
            background: #4d4d5d;
        }
        .btn-success {
            background: #22c55e;
            color: white;
        }
        .btn-danger {
            background: #ef4444;
            color: white;
        }
        .actions {
            display: flex;
            gap: 10px;
            margin-top: 15px;
            flex-wrap: wrap;
        }
        .status {
            padding: 10px 15px;
            border-radius: 5px;
            margin-top: 15px;
            display: none;
        }
        .status.success {
            background: rgba(34, 197, 94, 0.2);
            border: 1px solid #22c55e;
            color: #22c55e;
            display: block;
        }
        .status.error {
            background: rgba(239, 68, 68, 0.2);
            border: 1px solid #ef4444;
            color: #ef4444;
            display: block;
        }
        .info-box {
            background: rgba(102, 126, 234, 0.1);
            border: 1px solid #667eea;
            border-radius: 5px;
            padding: 15px;
            margin-top: 20px;
        }
        .info-box h3 {
            font-size: 0.9rem;
            margin-bottom: 10px;
            color: #667eea;
        }
        .info-box ul {
            list-style: none;
            font-size: 0.85rem;
        }
        .info-box li {
            padding: 5px 0;
            border-bottom: 1px solid rgba(102, 126, 234, 0.2);
        }
        .info-box li:last-child { border-bottom: none; }
        .info-box code {
            background: #0d0d1a;
            padding: 2px 6px;
            border-radius: 3px;
            font-size: 0.8rem;
        }
        .badge {
            background: #667eea;
            color: white;
            padding: 2px 8px;
            border-radius: 10px;
            font-size: 0.75rem;
            margin-left: 8px;
        }
        footer {
            text-align: center;
            padding: 20px;
            opacity: 0.6;
            font-size: 0.85rem;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>WAPRO Network Mock - Konfiguracja</h1>
            <p>Edytor pliku .env - zmien konfiguracje i zapisz</p>
        </header>
        
        <div class="editor-container">
            <div class="panel">
                <div class="panel-header">
                    <h2>.env <span class="badge">edytowalny</span></h2>
                    <span id="fileStatus"></span>
                </div>
                <div class="panel-body">
                    <textarea id="envEditor" placeholder="Ladowanie...">{{env_content}}</textarea>
                    <div class="actions">
                        <button class="btn btn-primary" onclick="saveEnv()">Zapisz .env</button>
                        <button class="btn btn-secondary" onclick="reloadEnv()">Odswierz</button>
                        <button class="btn btn-danger" onclick="resetEnv()">Reset do .env.example</button>
                    </div>
                    <div id="status" class="status"></div>
                </div>
            </div>
            
            <div class="panel">
                <div class="panel-header">
                    <h2>.env.example <span class="badge">tylko odczyt</span></h2>
                </div>
                <div class="panel-body">
                    <textarea id="exampleViewer" readonly style="opacity: 0.7;">{{example_content}}</textarea>
                </div>
            </div>
        </div>
        
        <div class="panel" style="margin-top: 20px;">
            <div class="panel-header">
                <h2>Wykryte urzadzenia <span class="badge" id="deviceCount">0</span></h2>
                <button class="btn btn-primary" onclick="discoverDevices()">Skanuj siec</button>
            </div>
            <div class="panel-body">
                <div id="devicesList" style="max-height: 200px; overflow-y: auto;">
                    <p style="opacity: 0.6;">Kliknij "Skanuj siec" aby wykryc urzadzenia.</p>
                </div>
                <div class="actions" style="margin-top: 10px;">
                    <button class="btn btn-secondary" onclick="loadDevices()">Zaladuj poprzednie</button>
                </div>
            </div>
        </div>
        
        <div class="panel" style="margin-top: 20px;">
            <div class="panel-header">
                <h2>Edytor konfiguracji <span class="badge">formularz</span></h2>
                <div>
                    <button class="btn btn-success" onclick="applyAllSuggestions()">Zastosuj wszystkie propozycje</button>
                    <button class="btn btn-primary" onclick="saveFromForm()">Zapisz zmiany</button>
                </div>
            </div>
            <div class="panel-body">
                <div style="overflow-x: auto;">
                    <table id="configTable" style="width: 100%; border-collapse: collapse; font-size: 0.85rem;">
                        <thead>
                            <tr style="background: #2d2d3d;">
                                <th style="padding: 10px; text-align: left; border-bottom: 1px solid #3d3d4d;">Parametr</th>
                                <th style="padding: 10px; text-align: left; border-bottom: 1px solid #3d3d4d;">Aktualna wartosc</th>
                                <th style="padding: 10px; text-align: left; border-bottom: 1px solid #3d3d4d;">Domyslna (.env.example)</th>
                                <th style="padding: 10px; text-align: left; border-bottom: 1px solid #3d3d4d;">Propozycja ze skanu</th>
                                <th style="padding: 10px; text-align: center; border-bottom: 1px solid #3d3d4d;">Akcja</th>
                            </tr>
                        </thead>
                        <tbody id="configTableBody">
                            <tr><td colspan="5" style="padding: 20px; text-align: center; opacity: 0.6;">Ladowanie konfiguracji...</td></tr>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>

        <div class="panel" style="margin-top: 20px;">
            <div class="panel-header">
                <h2>Admin: make <span class="badge" id="makeStatus">idle</span></h2>
                <div>
                    <button class="btn btn-secondary" onclick="refreshMakePanel()">Odswiez</button>
                </div>
            </div>
            <div class="panel-body">
                <div class="actions" style="margin-top: 0;">
                    <button class="btn btn-primary" onclick="runMake('start')">make start</button>
                    <button class="btn btn-secondary" onclick="runMake('stop')">make stop</button>
                    <button class="btn btn-secondary" onclick="runMake('restart')">make restart</button>
                    <button class="btn btn-secondary" onclick="runMake('status')">make status</button>
                    <button class="btn btn-primary" onclick="runMake('discover')">make discover</button>
                    <button class="btn btn-secondary" onclick="runMake('discover-full')">make discover-full</button>
                    <button class="btn btn-secondary" onclick="runMake('health')">make health</button>
                </div>
                <div style="margin-top: 10px; display: flex; gap: 10px; flex-wrap: wrap;">
                    <input type="password" id="adminToken" placeholder="Admin token (opcjonalnie)" style="flex: 1; min-width: 260px; padding: 8px; background: #0d0d1a; border: 1px solid #3d3d4d; border-radius: 4px; color: #e4e4e4;">
                    <button class="btn btn-secondary" onclick="saveAdminToken()">Zapisz token</button>
                </div>
                <textarea id="makeLog" readonly style="height: 220px; margin-top: 10px; opacity: 0.9;"></textarea>
            </div>
        </div>
        
        <div class="info-box">
            <h3>Szybkie komendy</h3>
            <ul>
                <li><code>make start</code> - Uruchom wszystkie uslugi</li>
                <li><code>make stop</code> - Zatrzymaj wszystkie uslugi</li>
                <li><code>make restart</code> - Restartuj uslugi</li>
                <li><code>make status</code> - Sprawdz status uslug</li>
                <li><code>make discover</code> - Wykryj urzadzenia w sieci</li>
                <li><code>Ctrl+C</code> - Zamknij ten edytor</li>
            </ul>
        </div>
        
        <footer>
            WAPRO Network Mock | Port: {{port}} | Plik: {{env_path}}
        </footer>
    </div>
    
    <script>
        // Global variables
        let currentConfig = {};
        let defaultConfig = {};
        let suggestions = {};
        let discoveredData = null;
        
        // Parse .env.example content for defaults
        (function() {
            const exampleContent = document.getElementById('exampleViewer').value;
            const config = {};
            exampleContent.split('\\n').forEach(line => {
                line = line.trim();
                if (line && !line.startsWith('#')) {
                    const eqIndex = line.indexOf('=');
                    if (eqIndex > 0) {
                        const key = line.substring(0, eqIndex).trim();
                        const value = line.substring(eqIndex + 1).trim();
                        config[key] = value;
                    }
                }
            });
            defaultConfig = config;
        })();

        function getAdminToken() {
            return localStorage.getItem('webenv_admin_token') || '';
        }

        function saveAdminToken() {
            const input = document.getElementById('adminToken');
            const token = (input && input.value) ? input.value.trim() : '';
            if (token) {
                localStorage.setItem('webenv_admin_token', token);
                showStatus('Zapisano token admina', 'success');
            } else {
                localStorage.removeItem('webenv_admin_token');
                showStatus('Usunieto token admina', 'success');
            }
            refreshMakePanel();
        }

        async function fetchMakeStatus() {
            const token = getAdminToken();
            const headers = token ? { 'X-Admin-Token': token } : {};
            const response = await fetch('/admin/status', { headers });
            return await response.json();
        }

        async function fetchMakeLogs() {
            const token = getAdminToken();
            const headers = token ? { 'X-Admin-Token': token } : {};
            const response = await fetch('/admin/logs', { headers });
            return await response.json();
        }

        async function refreshMakePanel() {
            try {
                const statusResult = await fetchMakeStatus();
                const badge = document.getElementById('makeStatus');
                if (badge && statusResult && statusResult.success) {
                    const st = statusResult.state;
                    let label = st.running ? 'running' : 'idle';
                    if (st.target) label += ' (' + st.target + ')';
                    badge.textContent = label;
                }

                const logsResult = await fetchMakeLogs();
                const logEl = document.getElementById('makeLog');
                if (logEl && logsResult && logsResult.success) {
                    logEl.value = logsResult.log || '';
                    logEl.scrollTop = logEl.scrollHeight;
                }
            } catch (e) {
                console.error('[webenv] Make panel error:', e);
            }
        }

        async function runMake(target) {
            const token = getAdminToken();
            const headers = { 'Content-Type': 'application/x-www-form-urlencoded' };
            if (token) headers['X-Admin-Token'] = token;

            try {
                const response = await fetch('/admin/run', {
                    method: 'POST',
                    headers,
                    body: 'target=' + encodeURIComponent(target)
                });
                const result = await response.json();
                if (result.success) {
                    showStatus('Uruchomiono: make ' + target, 'success');
                } else {
                    showStatus('Blad: ' + (result.error || 'unknown'), 'error');
                }
            } catch (e) {
                showStatus('Blad: ' + e.message, 'error');
            }

            refreshMakePanel();
        }
        
        function showStatus(message, type) {
            const status = document.getElementById('status');
            status.textContent = message;
            status.className = 'status ' + type;
            setTimeout(() => { status.className = 'status'; }, 5000);
        }
        
        // Discovery functions - must be defined early for onclick handlers
        async function loadDevices() {
            console.log('[webenv] Loading devices...');
            try {
                const response = await fetch('/devices');
                const result = await response.json();
                console.log('[webenv] Devices response:', result);
                if (result.success) {
                    displayDevices(result.devices);
                    updateSuggestionsFromDevices(result.devices);
                } else {
                    document.getElementById('devicesList').innerHTML = 
                        '<p style="color: #ef4444;">' + result.error + '</p>';
                }
            } catch (e) {
                console.error('[webenv] Error:', e);
                document.getElementById('devicesList').innerHTML = 
                    '<p style="color: #ef4444;">Blad: ' + e.message + '</p>';
            }
        }
        
        async function discoverDevices() {
            console.log('[webenv] Starting discovery...');
            document.getElementById('devicesList').innerHTML = 
                '<p style="color: #667eea;">Skanowanie sieci... (moze potrwac do 60 sekund)</p>';
            try {
                const response = await fetch('/discover');
                const result = await response.json();
                console.log('[webenv] Discovery response:', result);
                if (result.success) {
                    displayDevices(result.devices);
                    updateSuggestionsFromDevices(result.devices);
                    showStatus('Skanowanie zakonczone!', 'success');
                } else {
                    document.getElementById('devicesList').innerHTML = 
                        '<p style="color: #ef4444;">' + result.error + '</p>';
                }
            } catch (e) {
                console.error('[webenv] Discovery error:', e);
                document.getElementById('devicesList').innerHTML = 
                    '<p style="color: #ef4444;">Blad: ' + e.message + '</p>';
            }
        }
        
        async function saveEnv() {
            const content = document.getElementById('envEditor').value;
            try {
                const response = await fetch('/save', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                    body: 'content=' + encodeURIComponent(content)
                });
                const result = await response.json();
                if (result.success) {
                    showStatus('Zapisano pomyslnie!', 'success');
                } else {
                    showStatus('Blad: ' + result.error, 'error');
                }
            } catch (e) {
                showStatus('Blad polaczenia: ' + e.message, 'error');
            }
        }
        
        async function reloadEnv() {
            try {
                const response = await fetch('/load');
                const result = await response.json();
                if (result.success) {
                    document.getElementById('envEditor').value = result.content;
                    showStatus('Odswiezono!', 'success');
                } else {
                    showStatus('Blad: ' + result.error, 'error');
                }
            } catch (e) {
                showStatus('Blad polaczenia: ' + e.message, 'error');
            }
        }
        
        async function resetEnv() {
            if (!confirm('Czy na pewno chcesz zresetowac .env do wartosci z .env.example?')) return;
            try {
                const response = await fetch('/reset', { method: 'POST' });
                const result = await response.json();
                if (result.success) {
                    document.getElementById('envEditor').value = result.content;
                    showStatus('Zresetowano do .env.example!', 'success');
                } else {
                    showStatus('Blad: ' + result.error, 'error');
                }
            } catch (e) {
                showStatus('Blad polaczenia: ' + e.message, 'error');
            }
        }
        
        // Keyboard shortcut: Ctrl+S to save
        document.addEventListener('keydown', function(e) {
            if (e.ctrlKey && e.key === 's') {
                e.preventDefault();
                saveEnv();
            }
        });
        
        // Device discovery functions - defined later with suggestions support
        
        function selectDevice(type, index) {
            if (!discoveredData || !discoveredData.devices) return;
            
            let device = null;
            let deviceNum = 1;
            
            if (type === 'zebra') {
                if (discoveredData.devices.zebra_printers && discoveredData.devices.zebra_printers[index]) {
                    device = discoveredData.devices.zebra_printers[index];
                    deviceNum = index + 1;
                }
            } else if (type === 'mssql') {
                if (discoveredData.devices.mssql_servers && discoveredData.devices.mssql_servers[index]) {
                    device = discoveredData.devices.mssql_servers[index];
                }
            }
            
            if (device) {
                applyDevice(type, deviceNum, device.host, device.port);
            }
        }

        function displayDevices(data) {
            discoveredData = data;
            let html = '';
            let total = 0;
            
            // Zebra printers
            if (data.devices && data.devices.zebra_printers && data.devices.zebra_printers.length > 0) {
                html += '<h4 style="color: #22c55e; margin: 10px 0;">Drukarki Zebra</h4>';
                html += '<div style="display: flex; flex-wrap: wrap; gap: 10px;">';
                data.devices.zebra_printers.forEach((p, i) => {
                    html += '<div style="background: #2d2d3d; padding: 10px; border-radius: 5px; cursor: pointer;" onclick="selectDevice(\\'zebra\\', ' + i + ')">';
                    html += '<strong>' + p.host + ':' + p.port + '</strong>';
                    if (p.model) html += '<br><small>' + p.model + '</small>';
                    html += '<br><small style="color: #667eea;">Kliknij aby uzyc</small>';
                    html += '</div>';
                    total++;
                });
                html += '</div>';
            }
            
            // MSSQL servers
            if (data.devices && data.devices.mssql_servers && data.devices.mssql_servers.length > 0) {
                html += '<h4 style="color: #3b82f6; margin: 10px 0;">Serwery MSSQL</h4>';
                html += '<div style="display: flex; flex-wrap: wrap; gap: 10px;">';
                data.devices.mssql_servers.forEach((s, i) => {
                    html += '<div style="background: #2d2d3d; padding: 10px; border-radius: 5px; cursor: pointer;" onclick="selectDevice(\\'mssql\\', ' + i + ')">';
                    html += '<strong>' + s.host + ':' + s.port + '</strong>';
                    html += '<br><small style="color: #667eea;">Kliknij aby uzyc</small>';
                    html += '</div>';
                    total++;
                });
                html += '</div>';
            }
            
            // HTTP services
            if (data.devices && data.devices.http_services && data.devices.http_services.length > 0) {
                html += '<h4 style="color: #f59e0b; margin: 10px 0;">Serwisy HTTP</h4>';
                html += '<div style="display: flex; flex-wrap: wrap; gap: 10px;">';
                data.devices.http_services.forEach(h => {
                    html += '<div style="background: #2d2d3d; padding: 10px; border-radius: 5px;">';
                    html += '<a href="http://' + h.host + ':' + h.port + '" target="_blank" style="color: #f59e0b;">' + h.host + ':' + h.port + '</a>';
                    html += '</div>';
                    total++;
                });
                html += '</div>';
            }
            
            if (total === 0) {
                html = '<p style="opacity: 0.6;">Nie znaleziono urzadzen. Sprobuj pelne skanowanie: make discover-full</p>';
            }
            
            document.getElementById('devicesList').innerHTML = html;
            document.getElementById('deviceCount').textContent = total;
            
            if (data.scan_date) {
                html += '<p style="opacity: 0.5; font-size: 0.8rem; margin-top: 10px;">Ostatnie skanowanie: ' + data.scan_date + '</p>';
                document.getElementById('devicesList').innerHTML = html;
            }
        }
        
        function applyDevice(type, num, host, port) {
            const editor = document.getElementById('envEditor');
            let content = editor.value;
            
            if (type === 'zebra') {
                // Update or add Zebra config
                const hostKey = 'ZEBRA_' + num + '_HOST=';
                const portKey = 'ZEBRA_' + num + '_SOCKET_PORT=';
                const enabledKey = 'ZEBRA_' + num + '_ENABLED=';
                
                if (content.includes(hostKey)) {
                    content = content.replace(new RegExp(hostKey + '.*'), hostKey + host);
                }
                if (content.includes(portKey)) {
                    content = content.replace(new RegExp(portKey + '.*'), portKey + port);
                }
                if (content.includes(enabledKey)) {
                    content = content.replace(new RegExp(enabledKey + '.*'), enabledKey + 'false');
                }
            } else if (type === 'mssql') {
                const hostKey = 'MSSQL_HOST=';
                const portKey = 'MSSQL_EXTERNAL_PORT=';
                const enabledKey = 'MSSQL_ENABLED=';
                
                if (content.includes(hostKey)) {
                    content = content.replace(new RegExp(hostKey + '.*'), hostKey + host);
                }
                if (content.includes(portKey)) {
                    content = content.replace(new RegExp(portKey + '.*'), portKey + port);
                }
                if (content.includes(enabledKey)) {
                    content = content.replace(new RegExp(enabledKey + '.*'), enabledKey + 'false');
                }
            }
            
            editor.value = content;
            showStatus('Zastosowano ' + host + ':' + port + ' - pamietaj zapisac!', 'success');
        }
        
        // ============================================
        // CONFIG TABLE FUNCTIONS (Universal/Dynamic)
        // ============================================
        
        // Base prefix grouping configuration
        const basePrefixGroups = {
            'COMPOSE_': { label: 'Docker Compose', order: 1 },
            'NETWORK_': { label: 'Siec', order: 2 },
            'MSSQL_': { label: 'Baza danych MSSQL', order: 3 },
            'RPI_': { label: 'Serwer RPI', order: 4 },
            'GRAFANA_': { label: 'Grafana', order: 50 },
            'PROMETHEUS_': { label: 'Prometheus', order: 51 },
            'TEST_': { label: 'Testy', order: 60 },
            'NODE_': { label: 'Node.js', order: 61 },
            'DEBUG': { label: 'Debug', order: 62 },
            'LOG_': { label: 'Logowanie', order: 63 },
            'GENERATE_': { label: 'Generowanie', order: 64 }
        };
        
        // Dynamic prefix groups - will be populated from keys
        let prefixGroups = {};
        
        function buildDynamicPrefixGroups(keys) {
            // Start with base groups
            prefixGroups = { ...basePrefixGroups };
            
            // Find all ZEBRA_N_ patterns dynamically
            const zebraPattern = /^ZEBRA_(\\d+)_/;
            const zebraNumbers = new Set();
            
            keys.forEach(key => {
                const match = key.match(zebraPattern);
                if (match) {
                    zebraNumbers.add(parseInt(match[1]));
                }
            });
            
            // Add dynamic ZEBRA groups sorted by number
            Array.from(zebraNumbers).sort((a, b) => a - b).forEach((num, idx) => {
                prefixGroups['ZEBRA_' + num + '_'] = { 
                    label: 'Drukarka Zebra ' + num, 
                    order: 10 + idx 
                };
            });
        }
        
        function parseEnvContent(content) {
            const config = {};
            const keyOrder = [];
            content.split('\\n').forEach(line => {
                line = line.trim();
                if (line && !line.startsWith('#')) {
                    const eqIndex = line.indexOf('=');
                    if (eqIndex > 0) {
                        const key = line.substring(0, eqIndex).trim();
                        const value = line.substring(eqIndex + 1).trim();
                        config[key] = value;
                        keyOrder.push(key);
                    }
                }
            });
            config._keyOrder = keyOrder;
            return config;
        }
        
        function getKeyGroup(key) {
            // Check prefixes in order of specificity (longer first)
            const sortedPrefixes = Object.keys(prefixGroups).sort((a, b) => b.length - a.length);
            for (const prefix of sortedPrefixes) {
                if (key.startsWith(prefix) || key === prefix.replace('_', '')) {
                    return { prefix, ...prefixGroups[prefix] };
                }
            }
            return { prefix: '_OTHER_', label: 'Inne', order: 999 };
        }
        
        function groupKeysByPrefix(keys) {
            const groups = {};
            keys.forEach(key => {
                const group = getKeyGroup(key);
                if (!groups[group.prefix]) {
                    groups[group.prefix] = { label: group.label, order: group.order, keys: [] };
                }
                groups[group.prefix].keys.push(key);
            });
            // Sort groups by order
            return Object.entries(groups)
                .sort((a, b) => a[1].order - b[1].order)
                .map(([prefix, data]) => ({ prefix, ...data }));
        }
        
        function escapeHtml(str) {
            if (!str) return '';
            return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
        }
        
        function buildConfigTable() {
            const content = document.getElementById('envEditor').value;
            currentConfig = parseEnvContent(content);
            const keys = currentConfig._keyOrder || Object.keys(currentConfig).filter(k => k !== '_keyOrder');
            
            // Build dynamic prefix groups based on actual keys (e.g., ZEBRA_1_, ZEBRA_2_, etc.)
            buildDynamicPrefixGroups(keys);
            
            const groups = groupKeysByPrefix(keys);
            
            let html = '';
            
            groups.forEach(group => {
                // Section header
                html += '<tr style="background: #1a1a2e;"><td colspan="5" style="padding: 10px; font-weight: bold; color: #667eea;">' + escapeHtml(group.label) + ' <small style="opacity: 0.5;">(' + group.keys.length + ')</small></td></tr>';
                
                group.keys.forEach(key => {
                    const currentValue = currentConfig[key] || '';
                    const defaultValue = defaultConfig[key] || '';
                    const suggestion = suggestions[key] || '';
                    const hasSuggestion = suggestion && suggestion !== currentValue;
                    const isPassword = key.toLowerCase().includes('password') || key.toLowerCase().includes('secret') || key.toLowerCase().includes('token');
                    const inputType = isPassword ? 'password' : 'text';
                    const isDifferentFromDefault = currentValue !== defaultValue;
                    
                    html += '<tr style="border-bottom: 1px solid #2d2d3d;">';
                    html += '<td style="padding: 8px;"><code style="background: #0d0d1a; padding: 2px 6px; border-radius: 3px;">' + escapeHtml(key) + '</code></td>';
                    html += '<td style="padding: 8px;"><input type="' + inputType + '" id="cfg_' + escapeHtml(key) + '" value="' + escapeHtml(currentValue) + '" style="width: 100%; padding: 8px; background: #0d0d1a; border: 1px solid ' + (isDifferentFromDefault ? '#f59e0b' : '#3d3d4d') + '; border-radius: 4px; color: #e4e4e4;" onchange="markChanged(this)"></td>';
                    
                    // Default value column
                    if (defaultValue) {
                        const defaultStyle = isDifferentFromDefault ? 'color: #f59e0b; opacity: 0.8;' : 'opacity: 0.5;';
                        html += '<td style="padding: 8px; ' + defaultStyle + '">' + (isPassword ? '••••••' : escapeHtml(defaultValue)) + '</td>';
                    } else {
                        html += '<td style="padding: 8px; opacity: 0.3;">-</td>';
                    }
                    
                    if (hasSuggestion) {
                        html += '<td style="padding: 8px;"><span style="color: #22c55e; font-weight: bold;">' + escapeHtml(suggestion) + '</span></td>';
                        html += '<td style="padding: 8px; text-align: center;"><button class="btn btn-success" style="padding: 5px 10px; font-size: 0.75rem;" onclick="applySuggestion(\\'' + escapeHtml(key) + '\\', \\'' + escapeHtml(suggestion) + '\\')">Uzyj</button></td>';
                    } else if (suggestion) {
                        html += '<td style="padding: 8px; opacity: 0.5;">' + escapeHtml(suggestion) + ' (bez zmian)</td>';
                        html += '<td style="padding: 8px;"></td>';
                    } else {
                        html += '<td style="padding: 8px; opacity: 0.3;">-</td>';
                        html += '<td style="padding: 8px;"></td>';
                    }
                    
                    html += '</tr>';
                });
            });
            
            if (groups.length === 0) {
                html = '<tr><td colspan="5" style="padding: 20px; text-align: center; opacity: 0.6;">Brak zmiennych w pliku .env</td></tr>';
            }
            
            document.getElementById('configTableBody').innerHTML = html;
        }
        
        function markChanged(input) {
            input.style.borderColor = '#f59e0b';
        }
        
        function applySuggestion(key, value) {
            const input = document.getElementById('cfg_' + key);
            if (input) {
                input.value = value;
                input.style.borderColor = '#22c55e';
            }
        }
        
        function applyAllSuggestions() {
            let applied = 0;
            Object.keys(suggestions).forEach(key => {
                const suggestion = suggestions[key];
                const currentValue = currentConfig[key] || '';
                if (suggestion && suggestion !== currentValue) {
                    applySuggestion(key, suggestion);
                    applied++;
                }
            });
            showStatus('Zastosowano ' + applied + ' propozycji - kliknij "Zapisz zmiany"', 'success');
        }
        
        function saveFromForm() {
            // Build new config from form - iterate all keys from currentConfig
            let content = document.getElementById('envEditor').value;
            const keys = currentConfig._keyOrder || Object.keys(currentConfig).filter(k => k !== '_keyOrder');
            
            keys.forEach(key => {
                const input = document.getElementById('cfg_' + key);
                if (input) {
                    const newValue = input.value;
                    // Escape special regex characters in key
                    const escapedKey = key.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&');
                    const regex = new RegExp('^' + escapedKey + '=.*$', 'm');
                    if (content.match(regex)) {
                        content = content.replace(regex, key + '=' + newValue);
                    }
                }
            });
            
            document.getElementById('envEditor').value = content;
            saveEnv();
            buildConfigTable();
        }
        
        function updateSuggestionsFromDevices(data) {
            suggestions = {};
            
            if (data.devices) {
                // MSSQL suggestions
                if (data.devices.mssql_servers && data.devices.mssql_servers.length > 0) {
                    const mssql = data.devices.mssql_servers[0];
                    suggestions['MSSQL_HOST'] = mssql.host;
                    suggestions['MSSQL_EXTERNAL_PORT'] = String(mssql.port);
                }
                
                // Zebra suggestions
                if (data.devices.zebra_printers) {
                    data.devices.zebra_printers.forEach((printer, i) => {
                        if (i === 0) {
                            suggestions['ZEBRA_1_HOST'] = printer.host;
                            suggestions['ZEBRA_1_SOCKET_PORT'] = String(printer.port);
                        } else if (i === 1) {
                            suggestions['ZEBRA_2_HOST'] = printer.host;
                            suggestions['ZEBRA_2_SOCKET_PORT'] = String(printer.port);
                        }
                    });
                }
            }
            
            buildConfigTable();
        }
        
        // Initialize on page load
        console.log('[webenv] Initializing...');
        buildConfigTable();
        loadDevices();
        const tokenInput = document.getElementById('adminToken');
        if (tokenInput) tokenInput.value = getAdminToken();
        refreshMakePanel();
        setInterval(refreshMakePanel, 3000);
    </script>
</body>
</html>
'''

class EnvEditorHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        print(f"[{self.log_date_time_string()}] {args[0]}")
    
    def send_json(self, data, status=200):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def is_admin_authorized(self, token=''):
        client_ip = self.client_address[0]
        header_token = self.headers.get('X-Admin-Token', '')
        provided = token or header_token

        if ADMIN_TOKEN:
            return provided == ADMIN_TOKEN

        return client_ip in ('127.0.0.1', '::1')
    
    def send_html(self, html):
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.end_headers()
        self.wfile.write(html.encode())
    
    def read_file(self, path):
        try:
            with open(path, 'r', encoding='utf-8') as f:
                return f.read()
        except FileNotFoundError:
            return ''
        except Exception as e:
            return f'# Error reading file: {e}'
    
    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)
        token = query.get('token', [''])[0]

        if path == '/':
            env_content = self.read_file(ENV_FILE)
            example_content = self.read_file(ENV_EXAMPLE)
            
            html = HTML_TEMPLATE.replace(
                '{{env_content}}', env_content
            ).replace(
                '{{example_content}}', example_content
            ).replace(
                '{{port}}', str(self.server.server_port)
            ).replace(
                '{{env_path}}', ENV_FILE
            )
            self.send_html(html)

        elif path == '/load':
            content = self.read_file(ENV_FILE)
            self.send_json({'success': True, 'content': content})

        elif path == '/devices':
            # Load discovered devices from JSON
            devices_file = os.path.join(PROJECT_DIR, 'logs', 'discovered_devices.json')
            try:
                with open(devices_file, 'r') as f:
                    devices = json.load(f)
                self.send_json({'success': True, 'devices': devices})
            except FileNotFoundError:
                self.send_json({'success': False, 'error': 'No devices discovered yet. Run: make discover'})
            except Exception as e:
                self.send_json({'success': False, 'error': str(e)})

        elif path == '/discover':
            # Run discovery script
            import subprocess
            try:
                result = subprocess.run(
                    ['python3', os.path.join(SCRIPT_DIR, 'discover.py'), '-q'],
                    capture_output=True, text=True, timeout=60
                )
                devices_file = os.path.join(PROJECT_DIR, 'logs', 'discovered_devices.json')
                with open(devices_file, 'r') as f:
                    devices = json.load(f)
                self.send_json({'success': True, 'devices': devices, 'output': result.stdout})
            except Exception as e:
                self.send_json({'success': False, 'error': str(e)})

        elif path == '/admin/status':
            if not self.is_admin_authorized(token=token):
                self.send_json({'success': False, 'error': 'Unauthorized'}, 403)
                return

            with MAKE_STATE_LOCK:
                state = dict(MAKE_STATE)
            self.send_json({'success': True, 'state': state})

        elif path == '/admin/logs':
            if not self.is_admin_authorized(token=token):
                self.send_json({'success': False, 'error': 'Unauthorized'}, 403)
                return

            self.send_json({'success': True, 'log': _read_make_log_tail()})

        else:
            self.send_response(404)
            self.end_headers()
    
    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path

        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length).decode('utf-8')
        params = parse_qs(post_data)

        if path == '/save':
            try:
                content = params.get('content', [''])[0]
                with open(ENV_FILE, 'w', encoding='utf-8') as f:
                    f.write(content)
                self.send_json({'success': True})
                print(f"[+] Saved .env file")
            except Exception as e:
                self.send_json({'success': False, 'error': str(e)}, 500)

        elif path == '/reset':
            try:
                content = self.read_file(ENV_EXAMPLE)
                with open(ENV_FILE, 'w', encoding='utf-8') as f:
                    f.write(content)
                self.send_json({'success': True, 'content': content})
                print(f"[+] Reset .env to .env.example")
            except Exception as e:
                self.send_json({'success': False, 'error': str(e)}, 500)

        elif path == '/admin/run':
            token = params.get('token', [''])[0]
            if not self.is_admin_authorized(token=token):
                self.send_json({'success': False, 'error': 'Unauthorized'}, 403)
                return

            target = params.get('target', [''])[0]
            if target not in ALLOWED_MAKE_TARGETS:
                self.send_json({'success': False, 'error': 'Target not allowed'}, 400)
                return
            with MAKE_STATE_LOCK:
                if MAKE_STATE['running']:
                    self.send_json({'success': False, 'error': 'Make already running'}, 409)
                    return

                MAKE_STATE['running'] = True
                MAKE_STATE['target'] = target
                MAKE_STATE['exit_code'] = None
                MAKE_STATE['started_at'] = datetime.now().isoformat(timespec='seconds')
                MAKE_STATE['ended_at'] = None
                MAKE_STATE['pid'] = None

            thread = threading.Thread(target=_run_make_target_in_background, args=(target,), daemon=True)
            thread.start()
            self.send_json({'success': True, 'target': target})

        else:
            self.send_response(404)
            self.end_headers()


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PORT
    
    print("============================================================")
    print("     WAPRO Network Mock - Web .env Editor")
    print("============================================================")
    print(f"")
    print(f"  [i] Port: {port}")
    print(f"  [i] Plik: {ENV_FILE}")
    print(f"")
    print(f"  Otworz przegladarke: http://localhost:{port}")
    print(f"  lub: http://<IP_RASPBERRY>:{port}")
    print(f"")
    print(f"  Ctrl+C aby zakonczyc")
    print("============================================================")
    
    server = ThreadingHTTPServer(('0.0.0.0', port), EnvEditorHandler)
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[i] Zamykanie serwera...")
        server.shutdown()


if __name__ == '__main__':
    main()
