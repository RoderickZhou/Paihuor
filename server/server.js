// Paihuor relay (pure Node, node:sqlite, no npm deps). Polling sync + Huawei Push Kit notify.
// Tasks API: POST /tasks (create), POST /tasks/:objectId (update/patch), DELETE /tasks/:objectId (soft delete; ?hard=1 purge)
//            GET /tasks?familyId=&since=   (incremental; includes archived & deleted tombstones so flags propagate)
// Devices  : POST /devices ({familyId,userId,platform,pushToken})
// Admin    : GET /admin (web CRUD page), GET /admin/list (all rows, key-gated)
// Debug    : POST /push-test ({familyId,userId,title,body})
// Auth     : header x-paihuor-key must equal env PAIHUOR_KEY (except /health and GET /admin html shell).
// Push env : HW_CLIENT_ID, HW_CLIENT_SECRET, HW_PROJECT_ID (HarmonyOS NEXT v3 push).
const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { DatabaseSync } = require('node:sqlite');

const PORT = process.env.PORT || 8787;
const SECRET = process.env.PAIHUOR_KEY || 'CHANGE_ME';
const DIR = __dirname;
const DB_FILE = path.join(DIR, 'paihuor.db');
const LEGACY_TASKS = path.join(DIR, 'tasks.json');
const LEGACY_DEVICES = path.join(DIR, 'devices.json');
const TOMBSTONE_TTL = 30 * 24 * 3600 * 1000; // 软删墓碑保留 30 天后清理（低频App，给离线端足够同步窗口）

const HW_CLIENT_ID = process.env.HW_CLIENT_ID || '';
const HW_CLIENT_SECRET = process.env.HW_CLIENT_SECRET || '';
const HW_PROJECT_ID = process.env.HW_PROJECT_ID || '';

// ---------------- DB ----------------
const db = new DatabaseSync(DB_FILE);
db.exec(`
  CREATE TABLE IF NOT EXISTS tasks (
    objectId   TEXT PRIMARY KEY,
    id         TEXT,
    familyId   TEXT NOT NULL,
    fromUserId TEXT,
    toUserId   TEXT,
    rawText    TEXT DEFAULT '',
    title      TEXT DEFAULT '',
    detail     TEXT DEFAULT '',
    deadline   INTEGER DEFAULT 0,
    status     TEXT DEFAULT 'pending',
    reminder   TEXT DEFAULT '{}',
    negotiation TEXT DEFAULT '[]',
    archived   INTEGER DEFAULT 0,
    deleted    INTEGER DEFAULT 0,
    receivedAt INTEGER DEFAULT 0,
    doneAt     INTEGER DEFAULT 0,
    createdAt  INTEGER DEFAULT 0,
    updatedAt  INTEGER DEFAULT 0
  );
  CREATE INDEX IF NOT EXISTS idx_family_updated ON tasks(familyId, updatedAt);
  CREATE TABLE IF NOT EXISTS devices (
    familyId TEXT, userId TEXT, platform TEXT, pushToken TEXT, updatedAt INTEGER,
    PRIMARY KEY (familyId, userId, platform)
  );
`);

// 标量字段列表（真实列），其余 reminder/negotiation 为 JSON 列
const SCALAR = ['id','familyId','fromUserId','toUserId','rawText','title','detail',
  'deadline','status','archived','deleted','receivedAt','doneAt','createdAt','updatedAt'];
const INTCOLS = ['deadline','receivedAt','doneAt','createdAt','updatedAt']; // 整数列(其余标量按字符串)

function rowToTask(r) {
  if (!r) return null;
  let reminder = {}; let negotiation = [];
  try { reminder = JSON.parse(r.reminder || '{}'); } catch (e) {}
  try { negotiation = JSON.parse(r.negotiation || '[]'); } catch (e) {}
  return {
    objectId: r.objectId, id: r.id || '', familyId: r.familyId,
    fromUserId: r.fromUserId, toUserId: r.toUserId, rawText: r.rawText,
    title: r.title, detail: r.detail, deadline: r.deadline, status: r.status,
    reminder, negotiation,
    archived: !!r.archived, deleted: !!r.deleted,
    receivedAt: r.receivedAt, doneAt: r.doneAt,
    createdAt: r.createdAt, updatedAt: r.updatedAt
  };
}

function getTask(objectId) {
  return rowToTask(db.prepare('SELECT * FROM tasks WHERE objectId=?').get(objectId));
}

function insertTask(t) {
  db.prepare(`INSERT INTO tasks
    (objectId,id,familyId,fromUserId,toUserId,rawText,title,detail,deadline,status,
     reminder,negotiation,archived,deleted,receivedAt,doneAt,createdAt,updatedAt)
    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`).run(
    t.objectId, t.id || '', t.familyId, t.fromUserId || '', t.toUserId || '',
    t.rawText || '', t.title || '', t.detail || '', Number(t.deadline) || 0,
    t.status || 'pending',
    JSON.stringify(t.reminder || {}), JSON.stringify(t.negotiation || []),
    t.archived ? 1 : 0, t.deleted ? 1 : 0,
    Number(t.receivedAt) || 0, Number(t.doneAt) || 0,
    Number(t.createdAt) || 0, Number(t.updatedAt) || 0
  );
}

// 用 patch 的字段做"浅合并"更新（等价于旧 Object.assign），刷新 updatedAt
function patchTask(objectId, patch) {
  const cur = getTask(objectId);
  if (!cur) return null;
  const sets = []; const vals = [];
  for (const k of Object.keys(patch)) {
    if (k === 'objectId' || k === 'updatedAt') continue;
    if (k === 'reminder') { sets.push('reminder=?'); vals.push(JSON.stringify(patch[k] || {})); }
    else if (k === 'negotiation') { sets.push('negotiation=?'); vals.push(JSON.stringify(patch[k] || [])); }
    else if (k === 'archived' || k === 'deleted') { sets.push(`${k}=?`); vals.push(patch[k] ? 1 : 0); }
    else if (SCALAR.includes(k)) {
      let v = patch[k];
      if (v === undefined || v === null) continue;
      if (INTCOLS.indexOf(k) >= 0) { v = Number(v) || 0; }
      else if (typeof v === 'object') { continue; } // 拒绝把对象/数组塞进标量列
      else { v = String(v); }
      sets.push(`${k}=?`); vals.push(v);
    }
  }
  const now = Date.now();
  sets.push('updatedAt=?'); vals.push(now);
  vals.push(objectId);
  db.prepare(`UPDATE tasks SET ${sets.join(',')} WHERE objectId=?`).run(...vals);
  return getTask(objectId);
}

// 一次性迁移旧 tasks.json / devices.json
(function migrateLegacy() {
  const count = db.prepare('SELECT COUNT(*) c FROM tasks').get().c;
  if (count === 0 && fs.existsSync(LEGACY_TASKS)) {
    try {
      const arr = JSON.parse(fs.readFileSync(LEGACY_TASKS, 'utf8'));
      const now = Date.now();
      for (const t of arr) {
        if (!t.objectId) t.objectId = crypto.randomUUID();
        if (!t.createdAt) t.createdAt = now;
        if (!t.updatedAt) t.updatedAt = now;
        try { insertTask(t); } catch (e) { console.log('migrate skip', t.objectId, e.message); }
      }
      console.log('migrated', arr.length, 'tasks from tasks.json');
      fs.renameSync(LEGACY_TASKS, LEGACY_TASKS + '.migrated');
    } catch (e) { console.log('migrate tasks err', e.message); }
  }
  const dcount = db.prepare('SELECT COUNT(*) c FROM devices').get().c;
  if (dcount === 0 && fs.existsSync(LEGACY_DEVICES)) {
    try {
      const arr = JSON.parse(fs.readFileSync(LEGACY_DEVICES, 'utf8'));
      for (const d of arr) {
        db.prepare('INSERT OR REPLACE INTO devices (familyId,userId,platform,pushToken,updatedAt) VALUES (?,?,?,?,?)')
          .run(d.familyId, d.userId, d.platform || 'harmony', d.pushToken, d.updatedAt || Date.now());
      }
      console.log('migrated', arr.length, 'devices');
      fs.renameSync(LEGACY_DEVICES, LEGACY_DEVICES + '.migrated');
    } catch (e) { console.log('migrate devices err', e.message); }
  }
})();

// 清理过期墓碑（开机 + 每天）
function purgeTombstones() {
  try {
    const cut = Date.now() - TOMBSTONE_TTL;
    const r = db.prepare('DELETE FROM tasks WHERE deleted=1 AND updatedAt < ?').run(cut);
    if (r.changes) console.log('purged', r.changes, 'tombstones');
  } catch (e) {}
}
purgeTombstones();
setInterval(purgeTombstones, 24 * 3600 * 1000);

// ---------------- HTTP helpers ----------------
function send(res, code, obj, isHtml) {
  res.writeHead(code, {
    'Content-Type': isHtml ? 'text/html; charset=utf-8' : 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': '*',
    'Access-Control-Allow-Methods': 'GET,POST,DELETE,OPTIONS'
  });
  if (isHtml) return res.end(obj);
  res.end(obj === undefined ? '' : JSON.stringify(obj));
}
function readBody(req) {
  return new Promise((resolve) => {
    let b = '';
    req.on('data', (c) => (b += c));
    req.on('end', () => { try { resolve(b ? JSON.parse(b) : {}); } catch (e) { resolve({}); } });
  });
}

// ---------------- Huawei Push Kit (HarmonyOS NEXT, v3) ----------------
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
let hwToken = null; let hwTokenExp = 0;
async function getHwToken() {
  if (hwToken && Date.now() < hwTokenExp - 60000) return hwToken;
  const body = 'grant_type=client_credentials&client_id=' + encodeURIComponent(HW_CLIENT_ID)
    + '&client_secret=' + encodeURIComponent(HW_CLIENT_SECRET);
  const r = await httpsPost('oauth-login.cloud.huawei.com', '/oauth2/v3/token', {
    'Content-Type': 'application/x-www-form-urlencoded', 'Content-Length': Buffer.byteLength(body)
  }, body);
  const data = JSON.parse(r.body);
  if (!data.access_token) throw new Error('oauth fail: ' + r.body);
  hwToken = data.access_token;
  hwTokenExp = Date.now() + (data.expires_in || 3600) * 1000;
  return hwToken;
}
async function pushToTokens(tokens, title, content) {
  if (!HW_CLIENT_ID || !HW_PROJECT_ID) { console.log('push skipped: no HW env'); return null; }
  if (!tokens || tokens.length === 0) { console.log('push skipped: no tokens'); return null; }
  const at = await getHwToken();
  const payload = JSON.stringify({
    payload: { notification: { category: 'IM', title, body: content, clickAction: { actionType: 0 } } },
    target: { token: tokens }, pushOptions: { ttl: 86400 }
  });
  const r = await httpsPost('push-api.cloud.huawei.com', '/v3/' + HW_PROJECT_ID + '/messages:send', {
    'Content-Type': 'application/json', 'Authorization': 'Bearer ' + at,
    'push-type': '0', 'Content-Length': Buffer.byteLength(payload)
  }, payload);
  console.log('push result:', r.status, r.body);
  return r.body;
}
function notifyRecipient(task) {
  try {
    const toks = db.prepare(
      `SELECT pushToken FROM devices WHERE familyId=? AND userId=? AND platform='harmony' AND pushToken<>''`)
      .all(task.familyId, task.toUserId).map((d) => d.pushToken);
    if (toks.length === 0) return;
    const content = '新任务：' + (task.title || task.rawText || '有一条新任务');
    pushToTokens(toks, '派活儿', content).catch((e) => console.log('push err:', e.message));
  } catch (e) { console.log('notify err:', e.message); }
}

// ---------------- Routes ----------------
const server = http.createServer(async (req, res) => {
 try {
  const url = new URL(req.url, 'http://x');
  if (req.method === 'OPTIONS') return send(res, 204);
  if (url.pathname === '/health') return send(res, 200, { ok: true });

  // 管理台 HTML 外壳无需 key（页面内再用 key 调 API）
  if (req.method === 'GET' && url.pathname === '/admin') return send(res, 200, ADMIN_HTML, true);

  if (req.headers['x-paihuor-key'] !== SECRET) return send(res, 401, { error: 'bad key' });

  // 管理台数据：全部任务（含归档/墓碑），按 updatedAt 倒序
  if (req.method === 'GET' && url.pathname === '/admin/list') {
    const rows = db.prepare('SELECT * FROM tasks ORDER BY updatedAt DESC').all().map(rowToTask);
    return send(res, 200, rows);
  }

  if (req.method === 'POST' && url.pathname === '/tasks') {
    const t = await readBody(req);
    const now = Date.now();
    t.objectId = crypto.randomUUID();
    t.createdAt = now; t.updatedAt = now;
    if (t.archived === undefined) t.archived = false;
    insertTask(t);
    const saved = getTask(t.objectId);
    notifyRecipient(saved); // 不阻塞
    return send(res, 200, saved);
  }

  if (req.method === 'POST' && url.pathname.startsWith('/tasks/')) {
    const id = decodeURIComponent(url.pathname.slice('/tasks/'.length));
    const patch = await readBody(req);
    const updated = patchTask(id, patch);
    if (!updated) return send(res, 404, { error: 'not found' });
    return send(res, 200, updated);
  }

  if (req.method === 'DELETE' && url.pathname.startsWith('/tasks/')) {
    const id = decodeURIComponent(url.pathname.slice('/tasks/'.length));
    if (url.searchParams.get('hard') === '1') {
      const r = db.prepare('DELETE FROM tasks WHERE objectId=?').run(id);
      return send(res, 200, { ok: true, hard: true, removed: r.changes });
    }
    // 软删：置 deleted=1 + 刷新 updatedAt，让另一端轮询到墓碑后本地移除
    const updated = patchTask(id, { deleted: true });
    if (!updated) return send(res, 404, { error: 'not found' });
    return send(res, 200, updated);
  }

  if (req.method === 'GET' && url.pathname === '/tasks') {
    const fam = url.searchParams.get('familyId') || '';
    const since = Number(url.searchParams.get('since') || 0);
    // 能力分流：仅 caps=v2 的新客户端下发 已归档/软删墓碑 行；
    // 老客户端(无 caps，不识别 archived/deleted)只拿活跃未删行，避免幽灵任务/已完成堆积。
    const caps = url.searchParams.get('caps') || '';
    let sql = 'SELECT * FROM tasks WHERE familyId=? AND updatedAt>?';
    if (caps.indexOf('v2') < 0) {
      sql += ' AND deleted=0 AND archived=0';
    }
    sql += ' ORDER BY updatedAt ASC';
    const rows = db.prepare(sql).all(fam, since).map(rowToTask);
    return send(res, 200, rows);
  }

  if (req.method === 'POST' && url.pathname === '/devices') {
    const d = await readBody(req);
    if (!d.pushToken || !d.userId || !d.familyId) return send(res, 400, { error: 'missing fields' });
    const platform = d.platform || 'harmony';
    db.prepare('INSERT OR REPLACE INTO devices (familyId,userId,platform,pushToken,updatedAt) VALUES (?,?,?,?,?)')
      .run(d.familyId, d.userId, platform, d.pushToken, Date.now());
    const c = db.prepare('SELECT COUNT(*) c FROM devices').get().c;
    return send(res, 200, { ok: true, count: c });
  }

  if (req.method === 'POST' && url.pathname === '/push-test') {
    const b = await readBody(req);
    const toks = db.prepare(`SELECT pushToken FROM devices WHERE familyId=? AND userId=? AND pushToken<>''`)
      .all(b.familyId || '', b.userId || '').map((d) => d.pushToken);
    try {
      const result = await pushToTokens(toks, b.title || '派活儿', b.body || '这是一条测试推送');
      return send(res, 200, { sent: toks.length, result });
    } catch (e) { return send(res, 500, { error: e.message }); }
  }

  send(res, 404, { error: 'no route' });
 } catch (e) {
   console.log('route err:', e && e.message);
   try { send(res, 500, { error: 'server error' }); } catch (e2) {}
 }
});
process.on('unhandledRejection', (e) => console.log('unhandledRejection:', e && (e.message || e)));
server.listen(PORT, () => console.log('Paihuor relay (sqlite) on :' + PORT));

// ---------------- Admin page (single file, vanilla JS) ----------------
const ADMIN_HTML = `<!doctype html><html lang="zh"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>派活儿 · 任务管理台</title>
<style>
:root{--g:#4CAF50;--bg:#F5F7F6;--mut:#9E9E9E;--dan:#F44336;--warn:#FF9800}
*{box-sizing:border-box}body{font-family:-apple-system,'Microsoft YaHei',sans-serif;margin:0;background:var(--bg);color:#212121}
header{background:var(--g);color:#fff;padding:12px 16px;display:flex;gap:10px;align-items:center;flex-wrap:wrap}
header h1{font-size:18px;margin:0;flex:1}
input,select,button,textarea{font:inherit;padding:7px 9px;border:1px solid #ddd;border-radius:8px}
button{background:var(--g);color:#fff;border:none;cursor:pointer}
button.sec{background:#fff;color:#333;border:1px solid #ccc}
button.dan{background:var(--dan)}
.wrap{padding:14px;max-width:1200px;margin:0 auto}
.bar{display:flex;gap:8px;align-items:center;margin-bottom:12px;flex-wrap:wrap}
table{width:100%;border-collapse:collapse;background:#fff;border-radius:10px;overflow:hidden;font-size:13px}
th,td{padding:8px 10px;border-bottom:1px solid #eee;text-align:left;vertical-align:top}
th{background:#fafafa;color:#666;font-weight:600}
tr.del{opacity:.45;text-decoration:line-through}
.tag{font-size:11px;padding:2px 7px;border-radius:7px;color:#fff;white-space:nowrap}
.s-pending{background:#81C784}.s-received{background:var(--g)}.s-negotiating{background:var(--warn)}.s-done{background:var(--mut)}
.arch{background:#607D8B}
.acts button{padding:4px 8px;font-size:12px;margin-right:4px}
dialog{border:none;border-radius:14px;padding:18px;width:min(520px,92vw)}
dialog label{display:block;font-size:12px;color:#666;margin:10px 0 4px}
dialog input,dialog textarea,dialog select{width:100%}
.row{display:flex;gap:8px}.row>*{flex:1}
small{color:var(--mut)}
</style></head><body>
<header><h1>派活儿 · 任务管理台</h1>
<input id="key" type="password" placeholder="访问密钥 x-paihuor-key" style="color:#333;min-width:220px">
<button class="sec" onclick="saveKey()">保存密钥</button>
<button class="sec" onclick="load()">刷新</button>
<button onclick="openNew()">＋ 新建</button>
</header>
<div class="wrap">
<div class="bar">
  <input id="q" placeholder="搜索 标题/原文/familyId..." oninput="render()" style="flex:1;min-width:180px">
  <label><input type="checkbox" id="showDel" onchange="render()"> 显示已删除</label>
  <label><input type="checkbox" id="showArch" checked onchange="render()"> 显示已归档</label>
  <small id="cnt"></small>
</div>
<table><thead><tr>
<th>标题 / 原文</th><th>from→to</th><th>状态</th><th>截止</th><th>商量</th><th>更新</th><th>操作</th>
</tr></thead><tbody id="tb"></tbody></table>
</div>

<dialog id="dlg"><form method="dialog" id="frm">
  <div class="row"><div><label>标题</label><input id="f_title"></div>
  <div><label>状态</label><select id="f_status">
    <option value="pending">pending</option><option value="received">received</option>
    <option value="negotiating">negotiating</option><option value="done">done</option>
  </select></div></div>
  <label>细节</label><textarea id="f_detail" rows="2"></textarea>
  <label>原文 rawText</label><input id="f_rawText">
  <div class="row">
    <div><label>fromUserId</label><input id="f_from"></div>
    <div><label>toUserId</label><input id="f_to"></div>
    <div><label>familyId</label><input id="f_family"></div>
  </div>
  <div class="row">
    <div><label>截止 deadline (epoch ms, 0=无)</label><input id="f_deadline" type="number"></div>
    <div><label>归档</label><select id="f_archived"><option value="0">否</option><option value="1">是</option></select></div>
  </div>
  <input type="hidden" id="f_objectId">
  <div class="bar" style="margin-top:14px;justify-content:flex-end">
    <button type="button" class="sec" onclick="dlg.close()">取消</button>
    <button type="button" onclick="saveRow()">保存</button>
  </div>
</form></dialog>

<script>
let DATA=[];
const $=id=>document.getElementById(id);
const dlg=$('dlg');
function K(){return $('key').value.trim()}
function saveKey(){localStorage.setItem('phk',K());load()}
function hdr(){return {'x-paihuor-key':K(),'Content-Type':'application/json'}}
function fmt(ms){if(!ms)return '-';const d=new Date(ms);const p=n=>(n<10?'0':'')+n;return d.getFullYear()+'-'+p(d.getMonth()+1)+'-'+p(d.getDate())+' '+p(d.getHours())+':'+p(d.getMinutes())}
async function load(){
  if(!K()){alert('先填访问密钥');return}
  try{const r=await fetch('/admin/list',{headers:hdr()});
    if(r.status===401){alert('密钥错误');return}
    DATA=await r.json();render()}catch(e){alert('加载失败 '+e.message)}
}
function render(){
  const q=$('q').value.trim().toLowerCase();
  const showDel=$('showDel').checked, showArch=$('showArch').checked;
  const rows=DATA.filter(t=>{
    if(t.deleted&&!showDel)return false;
    if(t.archived&&!showArch)return false;
    if(q){const s=(t.title+' '+t.rawText+' '+t.familyId).toLowerCase();if(!s.includes(q))return false}
    return true;
  });
  $('cnt').textContent='共 '+rows.length+' 条 / 总 '+DATA.length;
  $('tb').innerHTML=rows.map(t=>{
    const neg=(t.negotiation||[]).length;
    return '<tr class="'+(t.deleted?'del':'')+'">'
      +'<td><b>'+esc(t.title||t.rawText||'(无标题)')+'</b>'+(t.detail?'<br><small>'+esc(t.detail)+'</small>':'')+'</td>'
      +'<td>'+esc(t.fromUserId)+'→'+esc(t.toUserId)+'</td>'
      +'<td><span class="tag s-'+esc(t.status)+'">'+esc(t.status)+'</span>'+(t.archived?' <span class="tag arch">归档</span>':'')+'</td>'
      +'<td>'+fmt(t.deadline)+'</td>'
      +'<td>'+(neg?neg+' 条':'-')+'</td>'
      +'<td>'+fmt(t.updatedAt)+'</td>'
      +'<td class="acts">'
        +'<button class="sec" onclick=\\'edit("'+t.objectId+'")\\'>编辑</button>'
        +(t.archived?'<button class="sec" onclick=\\'setArch("'+t.objectId+'",0)\\'>取消归档</button>':'<button class="sec" onclick=\\'setArch("'+t.objectId+'",1)\\'>归档</button>')
        +(t.deleted?'<button class="dan" onclick=\\'purge("'+t.objectId+'")\\'>彻底清除</button>':'<button class="dan" onclick=\\'softDel("'+t.objectId+'")\\'>删除</button>')
      +'</td></tr>';
  }).join('');
}
function esc(s){return (s==null?'':''+s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]))}
function openNew(){
  $('f_objectId').value='';$('f_title').value='';$('f_detail').value='';$('f_rawText').value='';
  $('f_from').value='wife';$('f_to').value='husband';$('f_family').value=(DATA[0]&&DATA[0].familyId)||'fam-xxx';
  $('f_deadline').value=0;$('f_status').value='pending';$('f_archived').value='0';dlg.showModal();
}
function edit(oid){
  const t=DATA.find(x=>x.objectId===oid);if(!t)return;
  $('f_objectId').value=t.objectId;$('f_title').value=t.title||'';$('f_detail').value=t.detail||'';
  $('f_rawText').value=t.rawText||'';$('f_from').value=t.fromUserId||'';$('f_to').value=t.toUserId||'';
  $('f_family').value=t.familyId||'';$('f_deadline').value=t.deadline||0;$('f_status').value=t.status||'pending';
  $('f_archived').value=t.archived?'1':'0';dlg.showModal();
}
async function saveRow(){
  const oid=$('f_objectId').value;
  const body={title:$('f_title').value,detail:$('f_detail').value,rawText:$('f_rawText').value,
    fromUserId:$('f_from').value,toUserId:$('f_to').value,familyId:$('f_family').value,
    deadline:Number($('f_deadline').value)||0,status:$('f_status').value,archived:$('f_archived').value==='1'};
  try{
    if(oid){await fetch('/tasks/'+encodeURIComponent(oid),{method:'POST',headers:hdr(),body:JSON.stringify(body)});}
    else{await fetch('/tasks',{method:'POST',headers:hdr(),body:JSON.stringify(body)});}
    dlg.close();load();
  }catch(e){alert('保存失败 '+e.message)}
}
async function setArch(oid,v){await fetch('/tasks/'+encodeURIComponent(oid),{method:'POST',headers:hdr(),body:JSON.stringify({archived:!!v})});load()}
async function softDel(oid){if(!confirm('确定删除？会同步移除两端（保留墓碑，勾"显示已删除"可见）'))return;await fetch('/tasks/'+encodeURIComponent(oid),{method:'DELETE',headers:hdr()});load()}
async function purge(oid){if(!confirm('彻底清除该墓碑？仅在两端都已同步移除后使用，不可恢复'))return;await fetch('/tasks/'+encodeURIComponent(oid)+'?hard=1',{method:'DELETE',headers:hdr()});load()}
window.onload=()=>{const k=localStorage.getItem('phk');if(k){$('key').value=k;load()}};
</script></body></html>`;
