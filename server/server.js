// Paihuor relay (pure Node, no deps). Polling-based cross-device sync.
// API: POST /tasks (create), POST /tasks/:objectId (update/merge), GET /tasks?familyId=&since=
// Auth: header x-paihuor-key must equal env PAIHUOR_KEY.
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const PORT = process.env.PORT || 8787;
const SECRET = process.env.PAIHUOR_KEY || 'CHANGE_ME';
const DATA_FILE = path.join(__dirname, 'tasks.json');

let tasks = [];
try { tasks = JSON.parse(fs.readFileSync(DATA_FILE, 'utf8')); } catch (e) { tasks = []; }
function save() { try { fs.writeFileSync(DATA_FILE, JSON.stringify(tasks)); } catch (e) {} }

function send(res, code, obj) {
  res.writeHead(code, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': '*',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
  });
  res.end(obj === undefined ? '' : JSON.stringify(obj));
}
function readBody(req) {
  return new Promise((resolve) => {
    let b = '';
    req.on('data', (c) => (b += c));
    req.on('end', () => { try { resolve(b ? JSON.parse(b) : {}); } catch (e) { resolve({}); } });
  });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  if (req.method === 'OPTIONS') return send(res, 204);
  if (url.pathname === '/health') return send(res, 200, { ok: true });
  if (req.headers['x-paihuor-key'] !== SECRET) return send(res, 401, { error: 'bad key' });

  if (req.method === 'POST' && url.pathname === '/tasks') {
    const t = await readBody(req);
    const now = Date.now();
    t.objectId = crypto.randomUUID();
    t.createdAt = now;
    t.updatedAt = now;
    tasks.push(t);
    save();
    return send(res, 200, t);
  }
  if (req.method === 'POST' && url.pathname.startsWith('/tasks/')) {
    const id = url.pathname.slice('/tasks/'.length);
    const patch = await readBody(req);
    const i = tasks.findIndex((t) => t.objectId === id);
    if (i < 0) return send(res, 404, { error: 'not found' });
    Object.assign(tasks[i], patch);
    tasks[i].updatedAt = Date.now();
    save();
    return send(res, 200, tasks[i]);
  }
  if (req.method === 'GET' && url.pathname === '/tasks') {
    const fam = url.searchParams.get('familyId') || '';
    const since = Number(url.searchParams.get('since') || 0);
    return send(res, 200, tasks.filter((t) => t.familyId === fam && (t.updatedAt || 0) > since));
  }
  send(res, 404, { error: 'no route' });
});
server.listen(PORT, () => console.log('Paihuor relay on :' + PORT));
