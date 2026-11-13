const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { once } = require('node:events');

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'paihuor-relay-'));
const key = 'relay-test-key';
let child;
let base;

before(async () => {
  child = spawn(process.execPath, [path.join(__dirname, 'server.js')], {
    env: { ...process.env, PORT: '0', PAIHUOR_DATA_DIR: dir, PAIHUOR_KEY: key, HW_PROJECT_ID: '' },
    stdio: ['ignore', 'pipe', 'inherit']
  });
  const port = await new Promise((resolve, reject) => {
    child.stdout.on('data', chunk => {
      const match = /relay \(sqlite\) on :(\d+)/.exec(String(chunk));
      if (match) resolve(match[1]);
    });
    child.once('exit', () => reject(new Error('Relay exited before listening')));
    child.once('error', reject);
  });
  base = `http://127.0.0.1:${port}`;
});

after(async () => {
  if (child && child.exitCode === null) {
    const exited = once(child, 'exit');
    child.kill();
    await exited;
  }
  fs.rmSync(dir, { recursive: true, force: true });
});

async function request(route, data, status = 200) {
  const response = await fetch(base + route, {
    method: data === undefined ? 'GET' : 'POST',
    headers: { 'x-paihuor-key': key, 'Content-Type': 'application/json' },
    body: JSON.stringify(data)
  });
  assert.equal(response.status, status);
  return response.json();
}

test('retrying a task keeps one server row and never resets its state', async () => {
  const payload = { familyId: '1217', fromUserId: 'wife', toUserId: 'husband', title: 'Test',
    clientRequestId: '55dfa010-d8b3-4679-8369-c9378c520001' };
  const first = await request('/tasks', payload);
  await request('/tasks/' + first.objectId, { status: 'received' });
  const retried = await request('/tasks', payload);
  assert.equal(retried.objectId, first.objectId);
  assert.equal(retried.status, 'received');
  assert.equal((await request('/tasks?familyId=1217&caps=v2')).length, 1);
});

test('only the matching recipient profile acknowledges a task after syncing', async () => {
  const task = await request('/tasks', { familyId: 'receipt', fromUserId: 'wife', toUserId: 'husband', title: 'Receipt' });
  const ack = { familyId: 'receipt', userId: 'husband', platform: 'harmony',
    deviceId: '55dfa010-d8b3-4679-8369-c9378c520002', objectIds: [task.objectId] };
  assert.equal((await request('/sync/ack', { ...ack, userId: 'wife' })).changed, 0);
  assert.equal((await request('/sync/ack', { ...ack, familyId: 'other' })).changed, 0);
  assert.equal((await request('/sync/ack', ack)).changed, 1);
  assert.equal((await request('/sync/ack', ack)).changed, 0);
  const updates = await request(`/tasks?familyId=receipt&since=${task.updatedAt}&caps=v2`);
  assert.equal(updates.length, 1);
  assert.ok(updates[0].recipientSyncedAt > 0);
  assert.equal(updates[0].status, 'pending');
  assert.ok((await request('/sync/status?familyId=receipt&userId=wife')).peerSyncedAt > 0);
});
