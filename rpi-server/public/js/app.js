// rpi-server/public/js/app.js
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
        this.loadInitialData();
        this.setupAutoRefresh();
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

    switchTab(tabName) {
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
        try {
            const response = await fetch(`/api/zebra/test/${printerId}`);
            const result = await response.json();

            this.updatePrinterStatus(printerId, result.success);
            this.showToast(`${printerId} test: ${result.success ? 'Success' : 'Failed'}`,
                          result.success ? 'success' : 'error');
        } catch (error) {
            this.showToast(`${printerId} test failed`, 'error');
        }
    }

    async printTestLabel(printerId) {
        try {
            const response = await fetch(`/api/zebra/test-print/${printerId}`, {
                method: 'POST'
            });
            const result = await response.json();

            this.showToast(`Test label ${result.success ? 'sent' : 'failed'}`,
                          result.success ? 'success' : 'error');
        } catch (error) {
            this.showToast('Test print failed', 'error');
        }
    }

    sendPrinterCommand(printerId) {
        // Convert printerId format: zebra-1 -> zebra1, zebra-2 -> zebra2
        const elemId = printerId.replace('-', '');
        const commandSection = document.getElementById(`${elemId}Commands`);
        if (commandSection) {
            if (commandSection.style.display === 'none') {
                commandSection.style.display = 'block';
            } else {
                commandSection.style.display = 'none';
            }
        } else {
            console.warn(`Command section not found: ${elemId}Commands`);
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
        }
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
window.runFullDiagnostics = () => app.runFullDiagnostics();
window.refreshLogs = () => app.refreshLogs();
window.clearLogs = () => app.clearLogs();

// Initialize the application
let app;
document.addEventListener('DOMContentLoaded', () => {
    app = new WaproConsole();
});