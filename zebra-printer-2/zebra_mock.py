# zebra-printer-2/zebra_mock.py
# Identyczny plik jak zebra-printer-1/zebra_mock.py
import socket
import threading
import time
import json
import os
from datetime import datetime
from flask import Flask, jsonify, request, render_template_string
import logging

# Konfiguracja loggingu
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class ZebraPrinterMock:
    def __init__(self, name, model, host='0.0.0.0', port=9100):
        self.name = name
        self.model = model
        self.host = host
        self.port = port
        self.status = 'READY'
        self.jobs_printed = 0
        self.last_command = None
        self.error_messages = []
        self.web_app = Flask(__name__)
        self.setup_web_routes()

    def setup_web_routes(self):
        @self.web_app.route('/')
        def index():
            return render_template_string(WEB_INTERFACE_TEMPLATE, printer=self)

        @self.web_app.route('/api/status')
        def api_status():
            return jsonify({
                'name': self.name,
                'model': self.model,
                'status': self.status,
                'jobs_printed': self.jobs_printed,
                'last_command': self.last_command,
                'timestamp': datetime.now().isoformat()
            })

        @self.web_app.route('/api/reset', methods=['POST'])
        def api_reset():
            self.jobs_printed = 0
            self.error_messages.clear()
            self.status = 'READY'
            return jsonify({'message': 'Printer reset successfully'})

    def handle_client(self, client_socket, address):
        logger.info(f"Connection from {address}")
        try:
            while True:
                data = client_socket.recv(1024)
                if not data:
                    break

                command = data.decode('utf-8', errors='ignore')
                logger.info(f"Received command: {command[:100]}...")

                response = self.process_zebra_command(command)
                if response:
                    client_socket.send(response.encode('utf-8'))

        except Exception as e:
            logger.error(f"Error handling client {address}: {e}")
        finally:
            client_socket.close()
            logger.info(f"Connection closed: {address}")

    def process_zebra_command(self, command):
        self.last_command = command

        # Symulacja różnych komend ZPL
        if command.startswith('^XA'):  # Start Format
            self.status = 'PRINTING'
            return None

        elif command.startswith('^XZ'):  # End Format
            self.jobs_printed += 1
            self.status = 'READY'
            return f"JOB COMPLETED: {self.jobs_printed}\n"

        elif command.startswith('~HI'):  # Host Identification
            return f"{self.name},{self.model},V1.0,12345,READY\n"

        elif command.startswith('~HS'):  # Host Status
            return f"STATUS:{self.status},JOBS:{self.jobs_printed}\n"

        elif command.startswith('^WD'):  # Get Configuration
            return self.get_printer_config()

        elif 'PING' in command.upper():
            return "PONG\n"

        else:
            # Inne komendy - symulacja pozytywnej odpowiedzi
            return "OK\n"

    def get_printer_config(self):
        config = {
            'name': self.name,
            'model': self.model,
            'dpi': '203',
            'width': '4.00',
            'length': '6.00',
            'darkness': '10',
            'speed': '2'
        }
        return json.dumps(config) + "\n"

    def start_socket_server(self):
        server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

        try:
            server_socket.bind((self.host, self.port))
            server_socket.listen(5)
            logger.info(f"ZEBRA Mock {self.name} listening on {self.host}:{self.port}")

            while True:
                client_socket, address = server_socket.accept()
                client_thread = threading.Thread(
                    target=self.handle_client,
                    args=(client_socket, address)
                )
                client_thread.daemon = True
                client_thread.start()

        except Exception as e:
            logger.error(f"Socket server error: {e}")
        finally:
            server_socket.close()

    def start_web_server(self):
        port = int(self.web_app.config.get('PORT', 8080))
        self.web_app.run(host='0.0.0.0', port=port, debug=False)

    def start(self):
        # Start socket server in separate thread
        socket_thread = threading.Thread(target=self.start_socket_server)
        socket_thread.daemon = True
        socket_thread.start()

        # Start web server (blocking)
        self.start_web_server()


# HTML template for web interface
WEB_INTERFACE_TEMPLATE = '''
<!DOCTYPE html>
<html>
<head>
    <title>ZEBRA Printer Mock - {{ printer.name }}</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .status { padding: 10px; border-radius: 5px; margin: 10px 0; }
        .ready { background-color: #d4edda; color: #155724; }
        .printing { background-color: #fff3cd; color: #856404; }
        .error { background-color: #f8d7da; color: #721c24; }
        .info-box { border: 1px solid #ddd; padding: 15px; margin: 10px 0; border-radius: 5px; }
        button { padding: 10px 20px; margin: 5px; cursor: pointer; }
    </style>
    <script>
        function refreshStatus() {
            fetch('/api/status')
                .then(response => response.json())
                .then(data => {
                    document.getElementById('status').innerText = data.status;
                    document.getElementById('jobs').innerText = data.jobs_printed;
                    document.getElementById('lastCommand').innerText = data.last_command || 'None';
                    document.getElementById('timestamp').innerText = data.timestamp;
                });
        }

        function resetPrinter() {
            fetch('/api/reset', {method: 'POST'})
                .then(() => refreshStatus());
        }

        setInterval(refreshStatus, 5000);
        window.onload = refreshStatus;
    </script>
</head>
<body>
    <h1>ZEBRA Printer Mock: {{ printer.name }}</h1>

    <div class="info-box">
        <h3>Printer Information</h3>
        <p><strong>Name:</strong> {{ printer.name }}</p>
        <p><strong>Model:</strong> {{ printer.model }}</p>
        <p><strong>Socket Port:</strong> 9100</p>
        <p><strong>Web Port:</strong> 8080</p>
    </div>

    <div class="info-box">
        <h3>Current Status</h3>
        <p><strong>Status:</strong> <span id="status">{{ printer.status }}</span></p>
        <p><strong>Jobs Printed:</strong> <span id="jobs">{{ printer.jobs_printed }}</span></p>
        <p><strong>Last Command:</strong> <span id="lastCommand">{{ printer.last_command or 'None' }}</span></p>
        <p><strong>Last Update:</strong> <span id="timestamp"></span></p>
    </div>

    <div class="info-box">
        <h3>Actions</h3>
        <button onclick="refreshStatus()">Refresh Status</button>
        <button onclick="resetPrinter()">Reset Printer</button>
    </div>

    <div class="info-box">
        <h3>Test Commands</h3>
        <p>You can test the printer using telnet or netcat:</p>
        <code>telnet {{ printer.name }} 9100</code><br>
        <code>echo "~HI" | nc {{ printer.name }} 9100</code>
    </div>
</body>
</html>
'''

# Main execution
if __name__ == '__main__':
    printer_name = os.getenv('PRINTER_NAME', 'ZEBRA-MOCK-2')
    printer_model = os.getenv('PRINTER_MODEL', 'ZT230')
    socket_port = int(os.getenv('PRINTER_SOCKET_PORT', '9100'))
    web_port = int(os.getenv('FLASK_RUN_PORT', '8080'))
    
    printer = ZebraPrinterMock(
        name=printer_name,
        model=printer_model,
        port=socket_port
    )
    
    # Override web port
    printer.web_app.config['PORT'] = web_port
    
    print(f"Starting {printer_name} on socket port {socket_port} and web port {web_port}")
    printer.start()