// Paihuor relay (pure Node, no deps). Polling sync + Huawei Push Kit notify.
// Tasks API: POST /tasks (create), POST /tasks/:objectId (update), GET /tasks?familyId=&since=
// Devices API: POST /devices ({familyId,userId,platform,pushToken})
// Debug: POST /push-test ({familyId,userId,title,body})
// Auth: header x-paihuor-key must equal env PAIHUOR_KEY.
// Push env: HW_CLIENT_ID, HW_CLIENT_SECRET, HW_PROJECT_ID (HarmonyOS NEXT v3 push).
const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const PORT = process.env.PORT || 8787;
const SECRET = process.env.PAIHUOR_KEY || 'CHANGE_ME';
const DATA_FILE = path.join(__dirname, 'tasks.json');
const DEVICES_FILE = path.join(__dirname, 'devices.json');

const HW_CLIENT_ID = process.env.HW_CLIENT_ID || '';
const HW_CLIENT_SECRET = process.env.HW_CLIENT_SECRET || '';
const HW_PROJECT_ID = process.env.HW_PROJECT_ID || '';

let tasks = [];
try { tasks = JSON.parse(fs.readFileSync(DATA_FILE, 'utf8')); } catch (e) { tasks = []; }
function save() { try { fs.writeFileSync(DATA_FILE, JSON.stringify(tasks)); } catch (e) {} }

let devices = [];
try { devices = JSON.parse(fs.readFileSync(DEVICES_FILE, 'utf8')); } catch (e) { devices = []; }
function saveDevices() { try { fs.writeFileSync(DEVICES_FILE, JSON.stringify(devices)); } catch (e) {} }

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

// ---------- Huawei Push Kit (HarmonyOS NEXT, v3) ----------
function httpsPost(host, pathName, headers, bodyStr) {
  return new Promise((resolve, reject) => {
    const req = https.request({ host, path: pathName, method: 'POST', headers }, (res) => {
      let d = '';
      res.on('data', (c) => (d += c));
      res.on('end', () => resolve({ status: res.statusCode, body: d }));
    });
    req.on('error', reject);
    req.write(bodyStr);
    req.end();
  });
}

let hwToken = null;
let hwTokenExp = 0;
async function getHwToken() {
  if (hwToken && Date.now() < hwTokenExp - 60000) return hwToken;
  const body = 'grant_type=client_credentials'
    + '&client_id=' + encodeURIComponent(HW_CLIENT_ID)
    + '&client_secret=' + encodeURIComponent(HW_CLIENT_SECRET);
  const r = await httpsPost('oauth-login.cloud.huawei.com', '/oauth2/v3/token', {
    'Content-Type': 'application/x-www-form-urlencoded',
    'Content-Length': Buffer.byteLength(body)
  }, body);
  const data = JSON.parse(r.body);
  if (!data.access_token) throw new Error('oauth fail: ' + r.body);
  hwToken = data.access_token;
  hwTokenExp = Date.now() + (data.expires_in || 3600) * 1000;
  return hwToken;
}

// 发"通知型"消息(push-type:0)，App 关闭也能在通知栏自动弹出
async function pushToTokens(tokens, title, content) {
  if (!HW_CLIENT_ID || !HW_PROJECT_ID) { console.log('push skipped: no HW env'); return null; }
  if (!tokens || tokens.length === 0) { console.log('push skipped: no tokens'); return null; }
  const at = await getHwToken();
  const payload = JSON.stringify({
    payload: {
      notification: {
        category: 'IM',
        title: title,
        body: content,
        clickAction: { actionType: 0 }
      }
    },
    target: { token: tokens },
    pushOptions: { ttl: 86400 }
  });
  const r = await httpsPost('push-api.cloud.huawei.com', '/v3/' + HW_PROJECT_ID + '/messages:send', {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ' + at,
    'push-type': '0',
    'Content-Length': Buffer.byteLength(payload)
  }, payload);
  console.log('push result:', r.status, r.body);
  return r.body;
}

// 新任务 → 给收件人(toUserId)的鸿蒙设备推送通知
function notifyRecipient(task) {
  try {
    const toks = devices
      .filter((d) => d.familyId === task.familyId && d.userId === task.toUserId
        && d.platform === 'harmony' && d.pushToken)
      .map((d) => d.pushToken);
    if (toks.length === 0) return;
    const title = '派活儿';
    const content = '新任务：' + (task.title || task.rawText || '有一条新任务');
    pushToTokens(toks, title, content).catch((e) => console.log('push err:', e.message));
  } catch (e) { console.log('notify err:', e.message); }
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
    notifyRecipient(t); // 不阻塞响应
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

  // 设备注册：保存某用户某端的 push token
  if (req.method === 'POST' && url.pathname === '/devices') {
    const d = await readBody(req);
    if (!d.pushToken || !d.userId || !d.familyId) return send(res, 400, { error: 'missing fields' });
    const platform = d.platform || 'harmony';
    const rec = { familyId: d.familyId, userId: d.userId, platform: platform, pushToken: d.pushToken, updatedAt: Date.now() };
    const i = devices.findIndex((x) => x.familyId === d.familyId && x.userId === d.userId && x.platform === platform);
    if (i >= 0) devices[i] = rec; else devices.push(rec);
    saveDevices();
    return send(res, 200, { ok: true, count: devices.length });
  }

  // 调试：直接给某用户推一条，验证推送链路
  if (req.method === 'POST' && url.pathname === '/push-test') {
    const b = await readBody(req);
    const toks = devices
      .filter((d) => d.familyId === (b.familyId || '') && d.userId === (b.userId || '') && d.pushToken)
      .map((d) => d.pushToken);
    try {
      const result = await pushToTokens(toks, b.title || '派活儿', b.body || '这是一条测试推送');
      return send(res, 200, { sent: toks.length, result: result });
    } catch (e) {
      return send(res, 500, { error: e.message });
    }
  }

  send(res, 404, { error: 'no route' });
});
server.listen(PORT, () => console.log('Paihuor relay on :' + PORT));
