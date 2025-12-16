/**
 * RPI Server Mock for WAPRO Network
 * Main server file
 */

const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
const morgan = require('morgan');
const path = require('path');
const fs = require('fs');
const dotenv = require('dotenv');
const promClient = require('prom-client');
const winston = require('winston');
const net = require('net');
const sql = require('mssql');
const { Server: IOServer } = require('socket.io');

// Load environment variables
dotenv.config();

// Create Express app
const app = express();
const PORT_GUI = process.env.RPI_GUI_PORT || 8080;
const PORT_API = process.env.RPI_API_PORT || 8081;

// Logger setup
const logsDir = path.join(__dirname, 'logs');
if (!fs.existsSync(logsDir)) {
  try { fs.mkdirSync(logsDir, { recursive: true }); } catch (_) {}
}
const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        winston.format.printf(({ level, message, timestamp, ...meta }) => `${timestamp} [${level}] ${message} ${Object.keys(meta).length ? JSON.stringify(meta) : ''}`)
      )
    }),
    new winston.transports.File({ filename: path.join(logsDir, 'server.log'), maxsize: 5 * 1024 * 1024, maxFiles: 3, tailable: true })
  ]
});

// Middleware
app.use(cors());
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));
app.use(morgan('combined', { stream: { write: (msg) => logger.http(msg.trim()) } }));
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    logger.info(`${req.method} ${req.originalUrl} ${res.statusCode} - ${Date.now() - start}ms`);
  });
  next();
});
app.use(express.static(path.join(__dirname, 'public')));

// Basic favicon to avoid 404 in GUI
app.get('/favicon.ico', (_req, res) => res.status(204).end());

// Setup Prometheus metrics
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok', timestamp: new Date().toISOString() });
});

// API metrics endpoint
app.get('/api/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Basic API endpoint
app.get('/api/status', (req, res) => {
  res.json({
    name: 'RPI Server Mock',
    version: '1.0.0',
    status: 'running',
    timestamp: new Date().toISOString()
  });
});

// GUI expects this endpoint
app.get('/api/health', async (req, res) => {
  try {
    const [dbOk, z1, z2] = await Promise.all([
      (async () => {
        try { await sql.connect(dbConfig('WAPROMAG_TEST')); await sql.close(); return true; } catch (_) { try { await sql.close(); } catch (_) {} return false; }
      })(),
      checkTcp(PRINTERS['zebra-1'].host, PRINTERS['zebra-1'].port, 800),
      checkTcp(PRINTERS['zebra-2'].host, PRINTERS['zebra-2'].port, 800),
    ]);
    const ok = dbOk && z1 && z2;
    
    // Symulacja latencji sieciowej (w rzeczywistej aplikacji byłoby to prawdziwe pingowanie)
    const networkLatency = Math.random() * 20 + 5; // 5-25ms
    
    res.json({
      status: ok ? 'HEALTHY' : 'DEGRADED',
      uptime: process.uptime(),
      memory: process.memoryUsage(),
      timestamp: new Date().toISOString(),
      network: {
        latency_ms: Math.round(networkLatency),
        status: networkLatency < 50 ? 'good' : networkLatency < 100 ? 'warning' : 'poor'
      }
    });
  } catch (e) {
    res.json({ status: 'DEGRADED', error: e.message });
  }
});

// Detailed health for integration tests
app.get('/api/health/detailed', async (_req, res) => {
  try {
    const [dbOk, z1, z2] = await Promise.all([
      (async () => {
        try { await sql.connect(dbConfig('WAPROMAG_TEST')); await sql.close(); return true; } catch (_) { try { await sql.close(); } catch (_) {} return false; }
      })(),
      checkTcp(PRINTERS['zebra-1'].host, PRINTERS['zebra-1'].port, 800),
      checkTcp(PRINTERS['zebra-2'].host, PRINTERS['zebra-2'].port, 800),
    ]);
    const total = 3; const passed = (dbOk?1:0)+(z1?1:0)+(z2?1:0);
    res.json({
      summary: { overall_status: passed===total ? 'HEALTHY' : 'DEGRADED' },
      database: { wapromag: { success: dbOk } },
      printers: { 'zebra-1': { success: z1 }, 'zebra-2': { success: z2 } }
    });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// Database configuration from environment
const DB_HOST = process.env.MSSQL_HOST || process.env.MSSQL_WAPROMAG_HOST || 'mssql-wapromag';
const DB_PORT = parseInt(process.env.MSSQL_PORT || process.env.MSSQL_WAPROMAG_PORT || '1433', 10);
const DB_USER = process.env.MSSQL_USER || process.env.MSSQL_WAPROMAG_USER || 'sa';
const DB_PASS = process.env.MSSQL_PASSWORD || process.env.MSSQL_WAPROMAG_PASSWORD || 'WapromagPass123!';
const DB_NAME = process.env.MSSQL_DATABASE || 'WAPROMAG_TEST';

function dbConfig(databaseName) {
  return {
    server: DB_HOST,
    port: DB_PORT,
    user: DB_USER,
    password: DB_PASS,
    database: databaseName,
    options: {
      trustServerCertificate: true,
      encrypt: false,
      enableArithAbort: true,
    },
    pool: {
      max: 5,
      min: 0,
      idleTimeoutMillis: 30000,
    },
  };
}

function mapDbAlias(alias) {
  // Map GUI alias to actual DB name
  if ((alias || '').toLowerCase() === 'wapromag') return DB_NAME;
  return alias || DB_NAME;
}

// Database test endpoint used by GUI
app.get('/api/sql/test/:db', async (req, res) => {
  const dbName = mapDbAlias(req.params.db);
  let pool;
  try {
    pool = await sql.connect(dbConfig(dbName));
    const result = await pool.request().query('SELECT TOP 1 1 AS ok');
    res.json({ success: true, message: `Connected to ${dbName}`, recordset: result.recordset });
  } catch (err) {
    res.status(200).json({ success: false, error: err.message });
  } finally {
    try { await sql.close(); } catch (_) {}
  }
});

// SQL query endpoint used by GUI
app.post('/api/sql/query', async (req, res) => {
  const { database, query } = req.body || {};
  if (!query || !database) {
    return res.status(400).json({ success: false, error: 'Missing database or query' });
  }
  const dbName = mapDbAlias(database);
  let pool;
  try {
    pool = await sql.connect(dbConfig(dbName));
    const result = await pool.request().query(query);
    const rows = result.recordset || [];
    let arrayRows = [];
    if (rows.length > 0 && typeof rows[0] === 'object') {
      const keys = Object.keys(rows[0]);
      arrayRows = rows.map(r => keys.map(k => r[k]));
    }
    res.json({ success: true, recordset: arrayRows });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  } finally {
    try { await sql.close(); } catch (_) {}
  }
});

// Tables listing used by tests
app.get('/api/sql/tables/:db', async (req, res) => {
  const dbName = mapDbAlias(req.params.db);
  let pool;
  try {
    pool = await sql.connect(dbConfig(dbName));
    const q = "SELECT TABLE_SCHEMA, TABLE_NAME, TABLE_TYPE FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE' ORDER BY TABLE_SCHEMA, TABLE_NAME";
    const result = await pool.request().query(q);
    const rows = result.recordset || [];
    const arrayRows = rows.map(r => [r.TABLE_SCHEMA, r.TABLE_NAME, r.TABLE_TYPE]);
    res.json({ success: true, recordset: arrayRows });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  } finally { try { await sql.close(); } catch(_){} }
});

// TCP helper for printers
function checkTcp(host, port, timeoutMs = 2000) {
  return new Promise((resolve) => {
    const socket = new net.Socket();
    let done = false;
    const onDone = (ok) => {
      if (done) return;
      done = true;
      try { socket.destroy(); } catch (_) {}
      resolve(ok);
    };
    const timer = setTimeout(() => onDone(false), timeoutMs);
    socket.once('error', () => { clearTimeout(timer); onDone(false); });
    socket.connect(port, host, () => { clearTimeout(timer); onDone(true); });
  });
}

function sendToPrinter(host, port, data, timeoutMs = 3000) {
  return new Promise((resolve) => {
    const socket = new net.Socket();
    let resolved = false;
    const finish = (ok) => { if (!resolved) { resolved = true; try { socket.end(); socket.destroy(); } catch (_) {} resolve(ok); } };
    const timer = setTimeout(() => finish(false), timeoutMs);
    socket.once('error', () => { clearTimeout(timer); finish(false); });
    socket.connect(port, host, () => {
      socket.write(data + '\n', () => { clearTimeout(timer); finish(true); });
    });
  });
}

// Printer configuration from environment
const PRINTERS = {
  'zebra-1': { 
    host: process.env.ZEBRA_1_HOST || 'zebra-printer-1', 
    port: parseInt(process.env.ZEBRA_1_PORT || '9100', 10), 
    printer: process.env.ZEBRA_1_NAME || 'ZEBRA-001',
    model: process.env.ZEBRA_1_MODEL || 'ZT230'
  },
  'zebra-2': { 
    host: process.env.ZEBRA_2_HOST || 'zebra-printer-2', 
    port: parseInt(process.env.ZEBRA_2_PORT || '9100', 10), 
    printer: process.env.ZEBRA_2_NAME || 'ZEBRA-002',
    model: process.env.ZEBRA_2_MODEL || 'ZT410'
  },
};

// Printers status for GUI
app.get('/api/zebra/status', async (_req, res) => {
  const entries = await Promise.all(
    Object.entries(PRINTERS).map(async ([id, cfg]) => {
      const ok = await checkTcp(cfg.host, cfg.port, 1500);
      return [id, { ...cfg, connection: { success: ok } }];
    })
  );
  res.json(Object.fromEntries(entries));
});

app.get('/api/zebra/test/:id', async (req, res) => {
  const cfg = PRINTERS[req.params.id];
  if (!cfg) return res.status(404).json({ success: false, error: 'Unknown printer' });
  const ok = await checkTcp(cfg.host, cfg.port, 1500);
  res.json({ success: ok });
});

// Per-printer status required by tests
app.get('/api/zebra/status/:id', async (req, res) => {
  const cfg = PRINTERS[req.params.id];
  if (!cfg) return res.status(404).json({ success: false, error: 'Unknown printer' });
  const ok = await checkTcp(cfg.host, cfg.port, 1500);
  res.json({ success: true, status: ok ? 'online' : 'offline' });
});

app.post('/api/zebra/test-print/:id', async (req, res) => {
  const cfg = PRINTERS[req.params.id];
  if (!cfg) return res.status(404).json({ success: false, error: 'Unknown printer' });
  const zpl = '^XA^FO50,50^ADN,36,20^FDTest Label^FS^XZ';
  const ok = await sendToPrinter(cfg.host, cfg.port, zpl, 3000);
  res.json({ success: ok });
});

app.post('/api/zebra/command', async (req, res) => {
  const { printerId, command } = req.body || {};
  const cfg = PRINTERS[printerId];
  if (!cfg) return res.status(400).json({ success: false, error: 'Unknown printerId' });
  if (!command || !String(command).trim()) return res.status(400).json({ success: false, error: 'Empty command' });
  const ok = await sendToPrinter(cfg.host, cfg.port, String(command), 4000);
  res.json({ success: ok });
});

// Commands catalogue for tests/GUI
app.get('/api/zebra/commands', (_req, res) => {
  res.json({
    host_identification: '~HI',
    host_status: '~HS',
    ping: 'PING',
    config_dump: '^WD'
  });
});

// Simple diagnostics report for GUI
app.get('/api/diagnostic/report', async (_req, res) => {
  try {
    const [dbOk, z1, z2] = await Promise.all([
      (async () => {
        try { await sql.connect(dbConfig('WAPROMAG_TEST')); await sql.close(); return true; } catch (_) { try { await sql.close(); } catch (_) {} return false; }
      })(),
      checkTcp(PRINTERS['zebra-1'].host, PRINTERS['zebra-1'].port, 1500),
      checkTcp(PRINTERS['zebra-2'].host, PRINTERS['zebra-2'].port, 1500),
    ]);
    const total = 3; const passed = (dbOk ? 1 : 0) + (z1 ? 1 : 0) + (z2 ? 1 : 0);
    res.json({
      summary: { overall_status: passed === total ? 'HEALTHY' : 'DEGRADED', total_checks: total, passed_checks: passed },
      details: {
        database: { wapromag: { success: dbOk } },
        printers: {
          'zebra-1': { connection: { success: z1 } },
          'zebra-2': { connection: { success: z2 } },
        }
      },
      recommendations: [],
      generated: new Date().toISOString()
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// Full diagnostics for tests
app.get('/api/diagnostic/full', async (_req, res) => {
  try {
    const [dbOk, z1, z2] = await Promise.all([
      (async () => {
        try { await sql.connect(dbConfig('WAPROMAG_TEST')); await sql.close(); return true; } catch (_) { try { await sql.close(); } catch (_) {} return false; }
      })(),
      checkTcp(PRINTERS['zebra-1'].host, PRINTERS['zebra-1'].port, 1000),
      checkTcp(PRINTERS['zebra-2'].host, PRINTERS['zebra-2'].port, 1000),
    ]);
    res.json({ database: { wapromag: dbOk }, printers: { 'zebra-1': z1, 'zebra-2': z2 }, network: { latency_ms: 5 } });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// GUI homepage
app.get('/', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
      <title>RPI Server Mock</title>
      <style>
        body { font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }
        h1 { color: #333; }
        .status { padding: 10px; background-color: #e7f7e7; border-radius: 5px; }
      </style>
    </head>
    <body>
      <h1>RPI Server Mock Interface</h1>
      <div class="status">
        <p><strong>Status:</strong> Running</p>
        <p><strong>Time:</strong> ${new Date().toLocaleString()}</p>
      </div>
      <h2>Available Endpoints:</h2>
      <ul>
        <li><a href="/health">Health Check</a></li>
        <li><a href="/api/status">API Status</a></li>
        <li><a href="/api/metrics">Metrics</a></li>
      </ul>
    </body>
    </html>
  `);
});

// Start servers
const guiServer = app.listen(PORT_GUI, () => {
  console.log(`GUI server running on port ${PORT_GUI}`);
});

const apiServer = app.listen(PORT_API, () => {
  console.log(`API server running on port ${PORT_API}`);
});

// Attach Socket.IO to GUI server
const io = new IOServer(guiServer, { cors: { origin: '*' } });
io.on('connection', (socket) => {
  console.log('Socket.IO client connected');
  socket.emit('log-entry', { level: 'info', message: 'Connected to RPI server', timestamp: new Date().toISOString() });
  socket.on('disconnect', () => console.log('Socket.IO client disconnected'));
});

// Startup preflight diagnostics (non-blocking)
(async () => {
  try {
    const [dbOk, z1, z2] = await Promise.all([
      (async () => { try { await sql.connect(dbConfig('WAPROMAG_TEST')); await sql.close(); return true; } catch (_) { try { await sql.close(); } catch (_) {} return false; } })(),
      checkTcp(PRINTERS['zebra-1'].host, PRINTERS['zebra-1'].port, 800),
      checkTcp(PRINTERS['zebra-2'].host, PRINTERS['zebra-2'].port, 800),
    ]);
    logger.info('Preflight diagnostics', { database: dbOk, zebra1: z1, zebra2: z2 });
  } catch (e) {
    logger.error('Preflight diagnostics error', { error: e.message });
  }
})();

// Process-level error handlers
process.on('unhandledRejection', (err) => {
  logger.error('UnhandledRejection', { error: (err && err.stack) || String(err) });
});
process.on('uncaughtException', (err) => {
  logger.error('UncaughtException', { error: (err && err.stack) || String(err) });
});

// Handle graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM signal received: closing HTTP servers');
  guiServer.close(() => console.log('GUI server closed'));
  apiServer.close(() => console.log('API server closed'));
  process.exit(0);
});

module.exports = { app, guiServer, apiServer };