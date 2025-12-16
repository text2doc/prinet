#!/usr/bin/env python3
"""
Web-based .env editor for WAPRO Network Mock
Usage: python3 webenv.py [port]
Default port: 8888
"""

import os
import sys
import json
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs

# Configuration
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
ENV_FILE = os.path.join(PROJECT_DIR, '.env')
ENV_EXAMPLE = os.path.join(PROJECT_DIR, '.env.example')
DEFAULT_PORT = 8888

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
        
        <div class="info-box">
            <h3>Szybkie komendy</h3>
            <ul>
                <li><code>make start</code> - Uruchom wszystkie uslugi</li>
                <li><code>make stop</code> - Zatrzymaj wszystkie uslugi</li>
                <li><code>make restart</code> - Restartuj uslugi</li>
                <li><code>make status</code> - Sprawdz status uslug</li>
                <li><code>make logs</code> - Pokaz logi</li>
                <li><code>Ctrl+C</code> - Zamknij ten edytor</li>
            </ul>
        </div>
        
        <footer>
            WAPRO Network Mock | Port: {{port}} | Plik: {{env_path}}
        </footer>
    </div>
    
    <script>
        function showStatus(message, type) {
            const status = document.getElementById('status');
            status.textContent = message;
            status.className = 'status ' + type;
            setTimeout(() => { status.className = 'status'; }, 5000);
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
        if self.path == '/':
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
        
        elif self.path == '/load':
            content = self.read_file(ENV_FILE)
            self.send_json({'success': True, 'content': content})
        
        else:
            self.send_response(404)
            self.end_headers()
    
    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length).decode('utf-8')
        params = parse_qs(post_data)
        
        if self.path == '/save':
            try:
                content = params.get('content', [''])[0]
                with open(ENV_FILE, 'w', encoding='utf-8') as f:
                    f.write(content)
                self.send_json({'success': True})
                print(f"[+] Saved .env file")
            except Exception as e:
                self.send_json({'success': False, 'error': str(e)}, 500)
        
        elif self.path == '/reset':
            try:
                content = self.read_file(ENV_EXAMPLE)
                with open(ENV_FILE, 'w', encoding='utf-8') as f:
                    f.write(content)
                self.send_json({'success': True, 'content': content})
                print(f"[+] Reset .env to .env.example")
            except Exception as e:
                self.send_json({'success': False, 'error': str(e)}, 500)
        
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
    
    server = HTTPServer(('0.0.0.0', port), EnvEditorHandler)
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[i] Zamykanie serwera...")
        server.shutdown()


if __name__ == '__main__':
    main()
