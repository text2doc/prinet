// rpi-server/public/js/app.js

// Sample ZPL Labels for quick insertion
const SAMPLE_LABELS = {
    simple: `^XA
^FO50,50^A0N,50,50^FDHello World^FS
^FO50,120^A0N,30,30^FDTest Label^FS
^XZ`,
    barcode: `^XA
^FO50,50^A0N,30,30^FDProduct Code:^FS
^FO50,90^BY3^BCN,100,Y,N,N^FD5901234123457^FS
^XZ`,
    qrcode: `^XA
^FO50,50^A0N,30,30^FDScan QR Code:^FS
^FO50,100^BQN,2,5^FDQA,https://example.com^FS
^XZ`,
    product: `^XA
^FO50,30^A0N,40,40^FDProduct Name^FS
^FO50,80^A0N,25,25^FDSKU: PRD-001234^FS
^FO50,115^A0N,20,20^FDPrice: 29.99 PLN^FS
^FO50,150^BY2^BCN,80,Y,N,N^FD1234567890123^FS
^FO50,260^A0N,18,18^FDMade in Poland^FS
^XZ`,
    box: `^XA
^FO50,50^GB300,200,3^FS
^FO70,70^A0N,35,35^FDWARNING^FS
^FO70,120^A0N,20,20^FDFragile Content^FS
^FO70,150^A0N,20,20^FDHandle with Care^FS
^XZ`,
    line: `^XA
^FO50,50^GB300,0,3^FS
^FO50,100^A0N,30,30^FDSection A^FS
^FO50,140^GB300,0,3^FS
^FO50,160^A0N,30,30^FDSection B^FS
^FO50,200^GB300,0,3^FS
^XZ`,
    multifield: `^XA
^FO50,30^A0N,25,25^FDFrom:^FS
^FO120,30^A0N,25,25^FDWarehouse A^FS
^FO50,60^A0N,25,25^FDTo:^FS
^FO120,60^A0N,25,25^FDCustomer XYZ^FS
^FO50,100^GB300,0,2^FS
^FO50,120^A0N,20,20^FDDate: 2025-01-15^FS
^FO50,150^A0N,20,20^FDWeight: 2.5 kg^FS
^FO50,180^BY2^BCN,60,Y,N,N^FDSHIP001234^FS
^XZ`,
    warehouse: `^XA
^FO30,20^GB340,280,2^FS
^FO50,40^A0N,45,45^FDLOCATION^FS
^FO50,100^A0N,80,80^FDA-12-03^FS
^FO50,190^GB280,0,2^FS
^FO50,210^A0N,25,25^FDZone: PICKING^FS
^FO50,245^A0N,20,20^FDCapacity: 500 units^FS
^XZ`
};

// ZPL Parser for label emulation
class ZPLParser {
    constructor() {
        this.scale = 0.5; // Scale factor for display
        this.elements = [];
        this.labelWidth = 400;
        this.labelHeight = 300;
    }

    parse(zpl) {
        this.elements = [];
        const commands = this.extractCommands(zpl);
        let currentX = 0;
        let currentY = 0;
        let fontSize = 30;
        
        for (const cmd of commands) {
            if (cmd.startsWith('^FO')) {
                // Field Origin
                const match = cmd.match(/\^FO(\d+),(\d+)/);
                if (match) {
                    currentX = parseInt(match[1]) * this.scale;
                    currentY = parseInt(match[2]) * this.scale;
                }
            } else if (cmd.startsWith('^A0')) {
                // Font selection
                const match = cmd.match(/\^A0[A-Z],(\d+),(\d+)/);
                if (match) {
                    fontSize = parseInt(match[1]) * this.scale;
                }
            } else if (cmd.startsWith('^FD')) {
                // Field Data
                const match = cmd.match(/\^FD(.+?)(?:\^FS|$)/);
                if (match) {
                    this.elements.push({
                        type: 'text',
                        x: currentX,
                        y: currentY,
                        text: match[1],
                        fontSize: fontSize
                    });
                }
            } else if (cmd.startsWith('^BC')) {
                // Barcode Code 128
                const heightMatch = cmd.match(/\^BC[A-Z],(\d+)/);
                const height = heightMatch ? parseInt(heightMatch[1]) * this.scale : 50;
                this.elements.push({
                    type: 'barcode',
                    x: currentX,
                    y: currentY,
                    height: height,
                    subtype: 'code128'
                });
            } else if (cmd.startsWith('^BQ')) {
                // QR Code
                const sizeMatch = cmd.match(/\^BQ[A-Z],(\d+),(\d+)/);
                const size = sizeMatch ? parseInt(sizeMatch[2]) * 10 * this.scale : 50;
                this.elements.push({
                    type: 'qrcode',
                    x: currentX,
                    y: currentY,
                    size: size
                });
            } else if (cmd.startsWith('^GB')) {
                // Graphic Box
                const match = cmd.match(/\^GB(\d+),(\d+),(\d+)/);
                if (match) {
                    const width = parseInt(match[1]) * this.scale;
                    const height = parseInt(match[2]) * this.scale;
                    const thickness = parseInt(match[3]) * this.scale;
                    
                    if (height === 0 || height < 3) {
                        // Horizontal line
                        this.elements.push({
                            type: 'line',
                            x: currentX,
                            y: currentY,
                            width: width,
                            height: Math.max(thickness, 1),
                            orientation: 'horizontal'
                        });
                    } else if (width === 0 || width < 3) {
                        // Vertical line
                        this.elements.push({
                            type: 'line',
                            x: currentX,
                            y: currentY,
                            width: Math.max(thickness, 1),
                            height: height,
                            orientation: 'vertical'
                        });
                    } else {
                        // Box
                        this.elements.push({
                            type: 'box',
                            x: currentX,
                            y: currentY,
                            width: width,
                            height: height,
                            thickness: thickness
                        });
                    }
                }
            }
        }
        
        return this.elements;
    }

    extractCommands(zpl) {
        const commands = [];
        const regex = /(\^[A-Z0-9]+[^^\~]*|~[A-Z]+[^^\~]*)/gi;
        let match;
        while ((match = regex.exec(zpl)) !== null) {
            commands.push(match[1].trim());
        }
        return commands;
    }

    renderToHTML() {
        if (this.elements.length === 0) {
            return '<div class="empty-label">No printable content detected</div>';
        }

        let maxX = 200, maxY = 150;
        this.elements.forEach(el => {
            const elRight = el.x + (el.width || el.size || 100);
            const elBottom = el.y + (el.height || el.fontSize || 30);
            if (elRight > maxX) maxX = elRight;
            if (elBottom > maxY) maxY = elBottom;
        });

        let html = `<div class="label-preview" style="width:${maxX + 40}px;height:${maxY + 40}px;position:relative;">`;
        
        for (const el of this.elements) {
            switch (el.type) {
                case 'text':
                    html += `<div class="label-element label-text" style="left:${el.x}px;top:${el.y}px;font-size:${el.fontSize}px;">${this.escapeHtml(el.text)}</div>`;
                    break;
                case 'barcode':
                    html += `<div class="label-element" style="left:${el.x}px;top:${el.y}px;">
                        <div class="label-barcode" style="height:${el.height}px;">|||||||||||||||</div>
                        <div class="label-barcode-text">${this.lastBarcodeData || '1234567890'}</div>
                    </div>`;
                    break;
                case 'qrcode':
                    html += `<div class="label-element label-qr" style="left:${el.x}px;top:${el.y}px;">
                        <div class="label-qr-placeholder" style="width:${el.size}px;height:${el.size}px;"></div>
                    </div>`;
                    break;
                case 'box':
                    html += `<div class="label-element label-box" style="left:${el.x}px;top:${el.y}px;width:${el.width}px;height:${el.height}px;border-width:${el.thickness}px;"></div>`;
                    break;
                case 'line':
                    html += `<div class="label-element label-line" style="left:${el.x}px;top:${el.y}px;width:${el.width}px;height:${el.height}px;"></div>`;
                    break;
            }
        }
        
        html += '</div>';
        return html;
    }

    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    getInfo() {
        const types = {};
        this.elements.forEach(el => {
            types[el.type] = (types[el.type] || 0) + 1;
        });
        return {
            elementCount: this.elements.length,
            types: types
        };
    }
}

class WaproConsole {
    constructor() {
        this.socket = io({
            reconnection: true,
            reconnectionDelay: 1000,
            reconnectionDelayMax: 5000,
            maxReconnectionAttempts: 5,
            timeout: 20000,
            forceNew: true
        });
        this.autoRefreshInterval = null;
        this.init();
    }

    init() {
        this.setupEventListeners();
        this.setupSocketListeners();
        this.setupURLHandling();
        this.loadInitialData();
        this.setupAutoRefresh();
        this.restoreStateFromURL();
    }

    // URL State Management
    setupURLHandling() {
        // Handle browser back/forward
        window.addEventListener('popstate', (event) => {
            if (event.state) {
                this.restoreState(event.state);
            } else {
                this.restoreStateFromURL();
            }
        });
    }

    restoreStateFromURL() {
        const params = new URLSearchParams(window.location.search);
        const tab = params.get('tab');
        const printer = params.get('printer');
        const command = params.get('cmd');
        const action = params.get('action');

        if (tab) {
            this.switchTab(tab, false); // false = don't update URL
        }

        if (printer && command) {
            // Restore printer command
            setTimeout(() => {
                this.openCommandModal(printer);
                const input = document.getElementById('modalCommandInput');
                if (input) {
                    input.value = decodeURIComponent(command);
                    this.previewModalCommand();
                }
            }, 500);
        }

        if (action) {
            this.executeURLAction(action, params);
        }

        this.logURLState('Restored state from URL');
    }

    updateURL(params = {}) {
        const url = new URL(window.location.href);
        
        // Update or remove parameters
        Object.entries(params).forEach(([key, value]) => {
            if (value !== null && value !== undefined && value !== '') {
                url.searchParams.set(key, value);
            } else {
                url.searchParams.delete(key);
            }
        });

        // Push to history
        const state = { ...params, timestamp: Date.now() };
        window.history.pushState(state, '', url.toString());
        
        this.logURLState('URL updated', params);
    }

    restoreState(state) {
        if (state.tab) {
            this.switchTab(state.tab, false);
        }
    }

    executeURLAction(action, params) {
        switch (action) {
            case 'test-printer':
                const printerId = params.get('printer');
                if (printerId) this.testPrinter(printerId);
                break;
            case 'diagnostics':
                this.runFullDiagnostics();
                break;
            case 'test-db':
                this.testDatabaseConnection();
                break;
        }
    }

    logURLState(message, data = {}) {
        console.log(`[URL State] ${message}`, {
            url: window.location.href,
            params: Object.fromEntries(new URLSearchParams(window.location.search)),
            ...data
        });
    }

    setupEventListeners() {
        // Tab switching
        document.querySelectorAll('.tab-button').forEach(button => {
            button.addEventListener('click', (e) => {
                this.switchTab(e.target.dataset.tab);
            });
        });

        // Auto-refresh logs checkbox
        const autoRefreshCheckbox = document.getElementById('autoRefreshLogs');
        if (autoRefreshCheckbox) {
            autoRefreshCheckbox.addEventListener('change', (e) => {
                if (e.target.checked) {
                    this.startAutoRefreshLogs();
                } else {
                    this.stopAutoRefreshLogs();
                }
            });
        }
    }

    setupSocketListeners() {
        this.socket.on('connect', () => {
            console.log('Socket.IO connected');
            this.updateConnectionStatus('connected');
        });

        this.socket.on('disconnect', (reason) => {
            console.log('Socket.IO disconnected:', reason);
            this.updateConnectionStatus('disconnected');
        });

        this.socket.on('connect_error', (error) => {
            console.error('Socket.IO connection error:', error);
        });

        this.socket.on('reconnect', (attemptNumber) => {
            console.log('Socket.IO reconnected after', attemptNumber, 'attempts');
            this.updateConnectionStatus('connected');
        });

        this.socket.on('reconnect_error', (error) => {
            console.error('Socket.IO reconnection error:', error);
        });

        this.socket.on('zebra-response', (data) => {
            this.handleZebraResponse(data);
        });

        this.socket.on('sql-response', (data) => {
            this.handleSqlResponse(data);
        });

        this.socket.on('log-entry', (data) => {
            this.addLogEntry(data);
        });
    }

    switchTab(tabName, updateURL = true) {
        // Update tab buttons
        document.querySelectorAll('.tab-button').forEach(btn => {
            btn.classList.remove('active');
        });
        const tabButton = document.querySelector(`[data-tab="${tabName}"]`);
        if (tabButton) {
            tabButton.classList.add('active');
        }

        // Update tab content
        document.querySelectorAll('.tab-content').forEach(content => {
            content.classList.remove('active');
        });
        const tabContent = document.getElementById(tabName);
        if (tabContent) {
            tabContent.classList.add('active');
        }

        // Update URL with current tab
        if (updateURL) {
            this.updateURL({ tab: tabName, printer: null, cmd: null, action: null });
        }

        // Log tab switch
        this.addLogEntry({
            level: 'info',
            message: `Switched to tab: ${tabName}`,
            timestamp: new Date().toISOString()
        });

        // Load tab-specific data
        this.loadTabData(tabName);
    }

    loadTabData(tabName) {
        switch (tabName) {
            case 'overview':
                this.loadOverviewData();
                break;
            case 'database':
                this.loadDatabaseData();
                break;
            case 'printers':
                this.loadPrintersData();
                break;
            case 'diagnostics':
                this.loadDiagnosticsData();
                break;
            case 'logs':
                this.loadLogsData();
                break;
        }
    }

    async loadInitialData() {
        await this.refreshSystemStatus();
        await this.loadOverviewData();
    }

    async loadOverviewData() {
        console.log('Loading overview data...');
        try {
            const [systemStatus, dbStatus, printersStatus] = await Promise.all([
                this.fetchSystemStatus(),
                this.fetchDatabaseStatus(),
                this.fetchPrintersStatus()
            ]);

            console.log('Fetched system status:', systemStatus);
            this.updateSystemStatusDisplay(systemStatus);
            this.updateDatabaseStatusDisplay(dbStatus);
            this.updatePrintersStatusDisplay(printersStatus);
            this.updateNetworkStatusDisplay(systemStatus);
            console.log('Overview data loaded successfully');
        } catch (error) {
            console.error('Error loading overview data:', error);
            this.showToast('Error loading overview data', 'error');
        }
    }

    async fetchSystemStatus() {
        const response = await fetch('/api/health');
        return await response.json();
    }

    async fetchDatabaseStatus() {
        const response = await fetch('/api/sql/test/wapromag');
        return await response.json();
    }

    async fetchPrintersStatus() {
        const response = await fetch('/api/zebra/status');
        return await response.json();
    }

    updateSystemStatusDisplay(status) {
        const indicator = document.getElementById('systemStatus');
        const details = document.getElementById('systemStatusDetails');

        if (indicator) {
            indicator.className = `status-indicator ${status.status.toLowerCase()}`;
            indicator.innerHTML = `<i class="fas fa-circle"></i><span>${status.status}</span>`;
        }

        if (details) {
            details.innerHTML = `
                <div class="status-details">
                    <p><strong>Status:</strong> ${status.status}</p>
                    <p><strong>Uptime:</strong> ${Math.floor(status.uptime / 60)} minutes</p>
                    <p><strong>Memory:</strong> ${Math.round(status.memory.heapUsed / 1024 / 1024)}MB</p>
                    <p><strong>Last Check:</strong> ${new Date(status.timestamp).toLocaleTimeString()}</p>
                </div>
            `;
        }
    }

    updateDatabaseStatusDisplay(status) {
        const element = document.getElementById('databaseStatus');
        if (!element) return;

        const statusClass = status.success ? 'success' : 'error';
        const statusText = status.success ? 'Connected' : 'Disconnected';
        const message = status.success ? status.message : status.error;

        element.innerHTML = `
            <div class="status-item ${statusClass}">
                <i class="fas fa-${status.success ? 'check-circle' : 'times-circle'}"></i>
                <div>
                    <strong>WAPROMAG:</strong> ${statusText}<br>
                    <small>${message}</small>
                </div>
            </div>
        `;
    }

    updatePrintersStatusDisplay(printersStatus) {
        const element = document.getElementById('printersStatus');
        if (!element) return;

        let html = '';
        Object.entries(printersStatus).forEach(([id, printer]) => {
            const isOnline = printer.connection?.success || false;
            const statusClass = isOnline ? 'success' : 'error';
            const statusText = isOnline ? 'Online' : 'Offline';

            html += `
                <div class="status-item ${statusClass}">
                    <i class="fas fa-${isOnline ? 'check-circle' : 'times-circle'}"></i>
                    <div>
                        <strong>${printer.printer}:</strong> ${statusText}<br>
                        <small>${printer.host}</small>
                    </div>
                </div>
            `;
        });

        element.innerHTML = html;
    }

    updateNetworkStatusDisplay(systemStatus) {
        console.log('Updating network status with data:', systemStatus);
        const element = document.getElementById('networkStatus');
        if (!element) {
            console.error('networkStatus element not found!');
            return;
        }

        const networkData = systemStatus.network || {};
        const latency = networkData.latency_ms || 0;
        const isHealthy = latency > 0 && latency < 100;
        const statusClass = isHealthy ? 'success' : (latency === 0 ? 'error' : 'warning');
        const statusText = isHealthy ? 'Healthy' : (latency === 0 ? 'Offline' : 'Slow');
        
        console.log('Network data:', { networkData, latency, isHealthy, statusClass, statusText });

        element.innerHTML = `
            <div class="status-item ${statusClass}">
                <i class="fas fa-${isHealthy ? 'check-circle' : (latency === 0 ? 'times-circle' : 'exclamation-triangle')}"></i>
                <div>
                    <strong>Network Status:</strong> ${statusText}<br>
                    <small>Latency: ${latency}ms</small>
                </div>
            </div>
            <div class="network-details">
                <div class="metric">
                    <span class="metric-label">Response Time:</span>
                    <span class="metric-value">${latency}ms</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Status:</span>
                    <span class="metric-value ${statusClass}">${statusText}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Last Check:</span>
                    <span class="metric-value">${new Date().toLocaleTimeString()}</span>
                </div>
            </div>
        `;
    }

    async refreshSystemStatus() {
        try {
            const status = await this.fetchSystemStatus();
            this.updateSystemStatusDisplay(status);
            this.updateNetworkStatusDisplay(status);
        } catch (error) {
            console.error('Error refreshing system status:', error);
        }
    }

    async testDatabaseConnection() {
        this.showLoading('databaseStatus');
        try {
            const status = await this.fetchDatabaseStatus();
            this.updateDatabaseStatusDisplay(status);
            this.showToast(`Database test: ${status.success ? 'Success' : 'Failed'}`,
                          status.success ? 'success' : 'error');
        } catch (error) {
            this.showToast('Database test failed', 'error');
        }
    }

    async testAllPrinters() {
        this.showLoading('printersStatus');
        try {
            const status = await this.fetchPrintersStatus();
            this.updatePrintersStatusDisplay(status);

            const onlineCount = Object.values(status).filter(p => p.connection?.success).length;
            const totalCount = Object.keys(status).length;
            this.showToast(`Printer test: ${onlineCount}/${totalCount} online`, 'info');
        } catch (error) {
            this.showToast('Printer test failed', 'error');
        }
    }

    // Database functions
    async executeQuery() {
        const database = document.getElementById('databaseSelect').value;
        const query = document.getElementById('sqlQuery').value.trim();

        if (!query) {
            this.showToast('Please enter a SQL query', 'warning');
            return;
        }

        const resultsContainer = document.getElementById('queryResults');
        this.showLoading('queryResults');

        try {
            const response = await fetch('/api/sql/query', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({ database, query })
            });

            const result = await response.json();

            if (result.success) {
                this.displayQueryResults(result, resultsContainer);
                this.showToast('Query executed successfully', 'success');
            } else {
                resultsContainer.innerHTML = `<div class="error-message">${result.error}</div>`;
                this.showToast('Query failed', 'error');
            }
        } catch (error) {
            resultsContainer.innerHTML = `<div class="error-message">${error.message}</div>`;
            this.showToast('Query execution failed', 'error');
        }
    }

    displayQueryResults(result, container) {
        if (!result.recordset || result.recordset.length === 0) {
            container.innerHTML = '<div class="info-message">No results returned</div>';
            return;
        }

        const columns = Object.keys(result.recordset[0]);
        let html = '<table class="results-table"><thead><tr>';

        columns.forEach(column => {
            html += `<th>${column}</th>`;
        });
        html += '</tr></thead><tbody>';

        result.recordset.forEach(row => {
            html += '<tr>';
            columns.forEach(column => {
                const value = row[column];
                html += `<td>${value !== null ? value : '<em>NULL</em>'}</td>`;
            });
            html += '</tr>';
        });

        html += '</tbody></table>';
        html += `<div class="results-info">Returned ${result.recordset.length} rows</div>`;

        container.innerHTML = html;
    }

    clearQuery() {
        document.getElementById('sqlQuery').value = '';
        document.getElementById('queryResults').innerHTML = '';
    }

    loadQuickQuery(type) {
        const queries = {
            'tables': "SELECT TABLE_SCHEMA, TABLE_NAME, TABLE_TYPE FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_SCHEMA, TABLE_NAME",
            'kontrahenci': "SELECT TOP 10 * FROM Kontrahenci ORDER BY ID DESC",
            'produkty': "SELECT TOP 10 * FROM Produkty ORDER BY ID DESC",
            'dokumenty': "SELECT TOP 10 * FROM Dokumenty ORDER BY ID DESC"
        };

        const query = queries[type];
        if (query) {
            document.getElementById('sqlQuery').value = query;
        }
    }

    // Printer functions
    async testPrinter(printerId) {
        const startTime = Date.now();
        this.addLogEntry({
            level: 'info',
            message: `[PRINTER] Testing connection to ${printerId}...`,
            timestamp: new Date().toISOString()
        });

        try {
            const response = await fetch(`/api/zebra/test/${printerId}`);
            const result = await response.json();
            const elapsed = Date.now() - startTime;

            this.updatePrinterStatus(printerId, result.success);
            
            // Detailed logging
            this.addLogEntry({
                level: result.success ? 'info' : 'error',
                message: `[PRINTER] ${printerId} test ${result.success ? 'PASSED' : 'FAILED'} (${elapsed}ms)`,
                timestamp: new Date().toISOString()
            });

            if (result.success) {
                this.addLogEntry({
                    level: 'info',
                    message: `[PRINTER] ${printerId} - Connection: OK, Port: 9100`,
                    timestamp: new Date().toISOString()
                });
            } else {
                this.addLogEntry({
                    level: 'error',
                    message: `[PRINTER] ${printerId} - Error: ${result.error || 'Connection failed'}`,
                    timestamp: new Date().toISOString()
                });
            }

            this.showToast(`${printerId} test: ${result.success ? 'Success' : 'Failed'} (${elapsed}ms)`,
                          result.success ? 'success' : 'error');
            
            // Update URL with action
            this.updateURL({ tab: 'printers', action: 'test-printer', printer: printerId });
        } catch (error) {
            this.addLogEntry({
                level: 'error',
                message: `[PRINTER] ${printerId} - Exception: ${error.message}`,
                timestamp: new Date().toISOString()
            });
            this.showToast(`${printerId} test failed: ${error.message}`, 'error');
        }
    }

    async printTestLabel(printerId) {
        const startTime = Date.now();
        this.addLogEntry({
            level: 'info',
            message: `[PRINTER] Sending test label to ${printerId}...`,
            timestamp: new Date().toISOString()
        });

        try {
            const response = await fetch(`/api/zebra/test-print/${printerId}`, {
                method: 'POST'
            });
            const result = await response.json();
            const elapsed = Date.now() - startTime;

            this.addLogEntry({
                level: result.success ? 'info' : 'error',
                message: `[PRINTER] Test label to ${printerId}: ${result.success ? 'SENT' : 'FAILED'} (${elapsed}ms)`,
                timestamp: new Date().toISOString()
            });

            if (result.response) {
                this.addLogEntry({
                    level: 'info',
                    message: `[PRINTER] ${printerId} response: ${result.response}`,
                    timestamp: new Date().toISOString()
                });
            }

            this.showToast(`Test label ${result.success ? 'sent' : 'failed'} (${elapsed}ms)`,
                          result.success ? 'success' : 'error');
        } catch (error) {
            this.addLogEntry({
                level: 'error',
                message: `[PRINTER] Test label to ${printerId} failed: ${error.message}`,
                timestamp: new Date().toISOString()
            });
            this.showToast('Test print failed', 'error');
        }
    }

    sendPrinterCommand(printerId) {
        // Open modal instead of inline command section
        this.openCommandModal(printerId);
    }

    // Modal functions
    openCommandModal(printerId) {
        this.currentModalPrinter = printerId;
        const modal = document.getElementById('zplCommandModal');
        const printerName = document.getElementById('modalPrinterName');
        const input = document.getElementById('modalCommandInput');
        
        // Get printer name from config
        const printerNames = {
            'zebra-1': 'ZEBRA-001',
            'zebra-2': 'ZEBRA-002'
        };
        
        printerName.textContent = printerNames[printerId] || printerId.toUpperCase();
        input.value = '';
        this.clearModalPreview();
        
        modal.classList.add('active');
        document.body.style.overflow = 'hidden';

        // Update URL with printer modal state
        this.updateURL({ tab: 'printers', printer: printerId });

        this.addLogEntry({
            level: 'info',
            message: `[PRINTER] Opened command modal for ${printerId}`,
            timestamp: new Date().toISOString()
        });
    }

    closeCommandModal() {
        const modal = document.getElementById('zplCommandModal');
        modal.classList.remove('active');
        document.body.style.overflow = '';
        
        // Clear printer from URL
        this.updateURL({ tab: 'printers', printer: null, cmd: null });
        
        this.currentModalPrinter = null;
    }

    selectCommand(command) {
        const input = document.getElementById('modalCommandInput');
        input.value = command;
        this.previewModalCommand();

        // Update URL with selected command (abbreviated)
        const cmdAbbrev = command.length > 50 ? command.substring(0, 50) : command;
        this.updateURL({ 
            tab: 'printers', 
            printer: this.currentModalPrinter, 
            cmd: encodeURIComponent(cmdAbbrev) 
        });

        this.addLogEntry({
            level: 'info',
            message: `[PRINTER] Selected command: ${command.substring(0, 30)}...`,
            timestamp: new Date().toISOString()
        });
    }

    previewModalCommand() {
        const input = document.getElementById('modalCommandInput');
        const canvas = document.getElementById('modalLabelCanvas');
        const info = document.getElementById('modalEmulatorInfo');
        const zpl = input.value.trim();

        if (!zpl) {
            canvas.innerHTML = '<div class="empty-label">Enter or select a ZPL command to preview</div>';
            info.innerHTML = '';
            return;
        }

        // Check if it's a label command (starts with ^XA)
        if (!zpl.includes('^XA')) {
            canvas.innerHTML = `<div class="empty-label">
                <div style="text-align:center;">
                    <i class="fas fa-terminal" style="font-size:2rem;margin-bottom:10px;display:block;color:var(--primary-color);"></i>
                    <strong>Command: ${this.escapeHtml(zpl)}</strong><br>
                    <small style="color:var(--text-secondary);">This is a status/config command, not a label.</small>
                </div>
            </div>`;
            info.innerHTML = `<div class="info-row"><span>Type:</span><span>Status/Config Command</span></div>`;
            return;
        }

        // Parse ZPL and render preview
        const parser = new ZPLParser();
        parser.parse(zpl);
        const html = parser.renderToHTML();
        const parseInfo = parser.getInfo();

        canvas.innerHTML = html;
        
        let infoHtml = `<div class="info-row"><span>Elements:</span><span>${parseInfo.elementCount}</span></div>`;
        if (Object.keys(parseInfo.types).length > 0) {
            infoHtml += '<div class="parsed-commands">';
            for (const [type, count] of Object.entries(parseInfo.types)) {
                infoHtml += `<code>${type}: ${count}</code> `;
            }
            infoHtml += '</div>';
        }
        info.innerHTML = infoHtml;
    }

    clearModalPreview() {
        const canvas = document.getElementById('modalLabelCanvas');
        const info = document.getElementById('modalEmulatorInfo');
        if (canvas) {
            canvas.innerHTML = '<div class="empty-label">Select a command to preview</div>';
        }
        if (info) {
            info.innerHTML = '';
        }
    }

    async sendModalCommand() {
        const input = document.getElementById('modalCommandInput');
        const command = input.value.trim();
        const printerId = this.currentModalPrinter;
        const startTime = Date.now();

        if (!command) {
            this.showToast('Please enter or select a command', 'warning');
            return;
        }

        if (!printerId) {
            this.showToast('No printer selected', 'error');
            return;
        }

        this.addLogEntry({
            level: 'info',
            message: `[PRINTER] Sending command to ${printerId}...`,
            timestamp: new Date().toISOString()
        });

        // Log command details
        const isLabel = command.includes('^XA');
        this.addLogEntry({
            level: 'info',
            message: `[PRINTER] Command type: ${isLabel ? 'ZPL Label' : 'Status/Config'}, Size: ${command.length} bytes`,
            timestamp: new Date().toISOString()
        });

        try {
            const response = await fetch('/api/zebra/command', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ printerId, command })
            });

            const result = await response.json();
            const elapsed = Date.now() - startTime;

            if (result.success) {
                this.showToast(`Command sent to ${printerId.toUpperCase()} (${elapsed}ms)`, 'success');
                this.addLogEntry({
                    level: 'info',
                    message: `[PRINTER] ✓ Command sent to ${printerId} successfully (${elapsed}ms)`,
                    timestamp: new Date().toISOString()
                });
                this.addLogEntry({
                    level: 'info',
                    message: `[PRINTER] Command: ${command.substring(0, 80)}${command.length > 80 ? '...' : ''}`,
                    timestamp: new Date().toISOString()
                });
                if (result.response) {
                    this.addLogEntry({
                        level: 'info',
                        message: `[PRINTER] Response: ${result.response}`,
                        timestamp: new Date().toISOString()
                    });
                }
                this.closeCommandModal();
            } else {
                this.addLogEntry({
                    level: 'error',
                    message: `[PRINTER] ✗ Command failed: ${result.error || 'Unknown error'}`,
                    timestamp: new Date().toISOString()
                });
                this.showToast('Command failed: ' + (result.error || 'Unknown error'), 'error');
            }
        } catch (error) {
            this.addLogEntry({
                level: 'error',
                message: `[PRINTER] ✗ Exception: ${error.message}`,
                timestamp: new Date().toISOString()
            });
            this.showToast('Command execution failed', 'error');
        }
    }

    async executePrinterCommand(printerId) {
        // Convert printerId format: zebra-1 -> zebra1, zebra-2 -> zebra2
        const elemId = printerId.replace('-', '');
        const commandSection = document.getElementById(`${elemId}Commands`);
        if (!commandSection) {
            console.warn(`Command section not found: ${elemId}Commands`);
            this.showToast('Command section not found', 'error');
            return;
        }
        const textarea = commandSection.querySelector('textarea');
        const command = textarea.value.trim();

        if (!command) {
            this.showToast('Please enter a command', 'warning');
            return;
        }

        try {
            const response = await fetch('/api/zebra/command', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({ printerId, command })
            });

            const result = await response.json();

            if (result.success) {
                this.showToast('Command sent successfully', 'success');
                if (result.response) {
                    this.addLogEntry({
                        level: 'info',
                        message: `${printerId} response: ${result.response}`,
                        timestamp: new Date().toISOString()
                    });
                }
            } else {
                this.showToast('Command failed', 'error');
            }
        } catch (error) {
            this.showToast('Command execution failed', 'error');
        }
    }

    insertCommand(command) {
        // Find the active printer command textarea
        const activeTextarea = document.querySelector('.command-section[style*="block"] textarea') ||
                              document.querySelector('.command-section textarea');

        if (activeTextarea) {
            activeTextarea.value = command;
            // Auto-preview if emulator is visible
            const commandSection = activeTextarea.closest('.command-section');
            if (commandSection) {
                const printerId = commandSection.id.replace('Commands', '').replace('zebra', 'zebra-');
                this.previewLabel(printerId);
            }
        }
    }

    previewLabel(printerId) {
        const elemId = printerId.replace('-', '');
        const commandSection = document.getElementById(`${elemId}Commands`);
        const canvas = document.getElementById(`${elemId}Canvas`);
        const info = document.getElementById(`${elemId}EmulatorInfo`);
        
        if (!commandSection || !canvas) {
            this.showToast('Emulator not found', 'error');
            return;
        }

        const textarea = commandSection.querySelector('textarea');
        const zpl = textarea.value.trim();

        if (!zpl) {
            canvas.innerHTML = '<div class="empty-label">Enter ZPL command to preview</div>';
            info.innerHTML = '';
            return;
        }

        // Check if it's a label command (starts with ^XA)
        if (!zpl.includes('^XA')) {
            // It's a status/config command, show info instead
            canvas.innerHTML = `<div class="empty-label">
                <div style="text-align:center;">
                    <i class="fas fa-terminal" style="font-size:2rem;margin-bottom:10px;display:block;"></i>
                    <strong>Command: ${this.escapeHtml(zpl)}</strong><br>
                    <small>This is a status/config command, not a label.</small>
                </div>
            </div>`;
            info.innerHTML = `<div class="info-row"><span>Type:</span><span>Status/Config Command</span></div>`;
            return;
        }

        // Parse ZPL and render preview
        const parser = new ZPLParser();
        parser.parse(zpl);
        const html = parser.renderToHTML();
        const parseInfo = parser.getInfo();

        canvas.innerHTML = html;
        
        // Show info about parsed elements
        let infoHtml = `<div class="info-row"><span>Elements:</span><span>${parseInfo.elementCount}</span></div>`;
        if (Object.keys(parseInfo.types).length > 0) {
            infoHtml += '<div class="parsed-commands">';
            for (const [type, count] of Object.entries(parseInfo.types)) {
                infoHtml += `<code>${type}: ${count}</code> `;
            }
            infoHtml += '</div>';
        }
        info.innerHTML = infoHtml;

        this.showToast('Label preview generated', 'info');
    }

    clearEmulator(printerId) {
        const elemId = printerId.replace('-', '');
        const canvas = document.getElementById(`${elemId}Canvas`);
        const info = document.getElementById(`${elemId}EmulatorInfo`);
        
        if (canvas) {
            canvas.innerHTML = '<div class="empty-label">Send a ZPL command to see preview</div>';
        }
        if (info) {
            info.innerHTML = '';
        }
    }

    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    updatePrinterStatus(printerId, isOnline) {
        const statusElement = document.getElementById(`${printerId}Status`);
        if (statusElement) {
            const statusClass = isOnline ? 'status-online' : 'status-offline';
            const statusText = isOnline ? 'Online' : 'Offline';
            statusElement.innerHTML = `<i class="fas fa-circle"></i><span>${statusText}</span>`;
            statusElement.className = `printer-status ${statusClass}`;
        }
    }

    // Diagnostics functions
    async runFullDiagnostics() {
        const resultsContainer = document.getElementById('diagnosticsResults');
        this.showLoading('diagnosticsResults');

        try {
            const response = await fetch('/api/diagnostic/report');
            const report = await response.json();

            this.displayDiagnosticsReport(report, resultsContainer);
            this.showToast('Diagnostics completed', 'success');
        } catch (error) {
            resultsContainer.innerHTML = `<div class="error-message">Diagnostics failed: ${error.message}</div>`;
            this.showToast('Diagnostics failed', 'error');
        }
    }

    displayDiagnosticsReport(report, container) {
        let html = `
            <div class="diagnostic-summary">
                <h4>Diagnostic Summary</h4>
                <p><strong>Overall Status:</strong> <span class="status-${report.summary.overall_status.toLowerCase()}">${report.summary.overall_status}</span></p>
                <p><strong>Checks:</strong> ${report.summary.passed_checks}/${report.summary.total_checks} passed</p>
                <p><strong>Generated:</strong> ${new Date(report.generated).toLocaleString()}</p>
            </div>
        `;

        // Recommendations
        if (report.recommendations && report.recommendations.length > 0) {
            html += '<div class="recommendations"><h4>Recommendations</h4>';
            report.recommendations.forEach(rec => {
                html += `<div class="diagnostic-item ${rec.type.toLowerCase()}">
                    <strong>${rec.component}:</strong> ${rec.message}
                </div>`;
            });
            html += '</div>';
        }

        // Detailed results
        html += '<div class="detailed-results"><h4>Detailed Results</h4>';

        // Database results
        if (report.details.database) {
            html += '<h5>Database</h5>';
            Object.entries(report.details.database).forEach(([db, result]) => {
                const status = result.success ? 'success' : 'error';
                html += `<div class="diagnostic-item ${status}">
                    <strong>${db}:</strong> ${result.success ? 'Connected' : result.error}
                </div>`;
            });
        }

        // Printer results
        if (report.details.printers) {
            html += '<h5>Printers</h5>';
            Object.entries(report.details.printers).forEach(([id, printer]) => {
                const status = printer.connection?.success ? 'success' : 'error';
                html += `<div class="diagnostic-item ${status}">
                    <strong>${id}:</strong> ${printer.connection?.success ? 'Online' : 'Offline'}
                </div>`;
            });
        }

        html += '</div>';
        container.innerHTML = html;
    }

    // Logs functions
    addLogEntry(logData) {
        const logsContainer = document.getElementById('logsContainer');
        if (!logsContainer) return;

        const entry = document.createElement('div');
        entry.className = `log-entry ${logData.level}`;
        entry.innerHTML = `
            <span class="timestamp">[${new Date(logData.timestamp).toLocaleTimeString()}]</span>
            <span class="level">${logData.level.toUpperCase()}</span>
            <span class="message">${logData.message}</span>
        `;

        logsContainer.appendChild(entry);
        logsContainer.scrollTop = logsContainer.scrollHeight;

        // Keep only last 1000 entries
        while (logsContainer.children.length > 1000) {
            logsContainer.removeChild(logsContainer.firstChild);
        }
    }

    refreshLogs() {
        // This would typically fetch logs from the server
        this.addLogEntry({
            level: 'info',
            message: 'Logs refreshed',
            timestamp: new Date().toISOString()
        });
    }

    clearLogs() {
        const logsContainer = document.getElementById('logsContainer');
        if (logsContainer) {
            logsContainer.innerHTML = '';
        }
    }

    startAutoRefreshLogs() {
        this.stopAutoRefreshLogs();
        this.autoRefreshInterval = setInterval(() => {
            this.refreshLogs();
        }, 5000);
    }

    stopAutoRefreshLogs() {
        if (this.autoRefreshInterval) {
            clearInterval(this.autoRefreshInterval);
            this.autoRefreshInterval = null;
        }
    }

    // Utility functions
    showLoading(elementId) {
        const element = document.getElementById(elementId);
        if (element) {
            element.innerHTML = '<div class="loading">Loading...</div>';
        }
    }

    showToast(message, type = 'info') {
        const container = document.getElementById('toastContainer');
        if (!container) return;

        const toast = document.createElement('div');
        toast.className = `toast ${type}`;
        toast.innerHTML = `
            <div class="toast-content">
                <i class="fas fa-${this.getToastIcon(type)}"></i>
                <span>${message}</span>
            </div>
        `;

        container.appendChild(toast);

        setTimeout(() => {
            toast.remove();
        }, 5000);
    }

    getToastIcon(type) {
        const icons = {
            success: 'check-circle',
            error: 'exclamation-circle',
            warning: 'exclamation-triangle',
            info: 'info-circle'
        };
        return icons[type] || 'info-circle';
    }

    updateConnectionStatus(status) {
        // Update any connection status indicators
        console.log(`Connection status: ${status}`);
    }

    setupAutoRefresh() {
        // Auto-refresh overview data every 30 seconds
        setInterval(() => {
            if (document.querySelector('.tab-content.active').id === 'overview') {
                this.loadOverviewData();
            }
        }, 30000);
    }

    handleZebraResponse(data) {
        if (data.success) {
            this.showToast('Zebra command successful', 'success');
        } else {
            this.showToast('Zebra command failed', 'error');
        }
    }

    handleSqlResponse(data) {
        if (data.success) {
            this.showToast('SQL command successful', 'success');
        } else {
            this.showToast('SQL command failed', 'error');
        }
    }

    loadDatabaseData() {
        // Load database-specific data when tab is activated
        console.log('Loading database data...');
    }

    loadPrintersData() {
        // Load printer-specific data when tab is activated
        this.testAllPrinters();
    }

    loadDiagnosticsData() {
        // Load diagnostics data when tab is activated
        console.log('Loading diagnostics data...');
    }

    loadLogsData() {
        // Load logs data when tab is activated
        this.refreshLogs();
    }
}

// Global functions for HTML onclick handlers
window.refreshSystemStatus = () => app.refreshSystemStatus();
window.testDatabaseConnection = () => app.testDatabaseConnection();
window.testAllPrinters = () => app.testAllPrinters();
window.executeQuery = () => app.executeQuery();
window.clearQuery = () => app.clearQuery();
window.loadQuickQuery = (type) => app.loadQuickQuery(type);
window.testPrinter = (id) => app.testPrinter(id);
window.printTestLabel = (id) => app.printTestLabel(id);
window.sendPrinterCommand = (id) => app.sendPrinterCommand(id);
window.executePrinterCommand = (id) => app.executePrinterCommand(id);
window.insertCommand = (cmd) => app.insertCommand(cmd);
window.previewLabel = (id) => app.previewLabel(id);
window.clearEmulator = (id) => app.clearEmulator(id);
window.openCommandModal = (id) => app.openCommandModal(id);
window.closeCommandModal = () => app.closeCommandModal();
window.selectCommand = (cmd) => app.selectCommand(cmd);
window.previewModalCommand = () => app.previewModalCommand();
window.clearModalPreview = () => app.clearModalPreview();
window.sendModalCommand = () => app.sendModalCommand();
window.runFullDiagnostics = () => app.runFullDiagnostics();
window.refreshLogs = () => app.refreshLogs();
window.clearLogs = () => app.clearLogs();

// Initialize the application
let app;
document.addEventListener('DOMContentLoaded', () => {
    app = new WaproConsole();
});