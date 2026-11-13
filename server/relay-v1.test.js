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

test('completing a weekly occurrence after editing its deadline creates only one successor on the original schedule', async () => {
  const deadline = Date.now() + 86_400_000;
  const task = await request('/tasks', { familyId: 'weekly', fromUserId: 'wife', toUserId: 'husband',
    title: 'Take out recycling', deadline, repeat: { kind: 'weekly' } });
  await request(`/tasks/${task.objectId}`, { deadline: deadline + 3600_000 });
  await Promise.all([1, 2].map(() => request(`/tasks/${task.objectId}`, { status: 'done', archived: true })));
  const rows = await request('/tasks?familyId=weekly&caps=v2');
  assert.equal(rows.length, 2);
  const next = rows.find(row => row.objectId !== task.objectId);
  assert.equal(next.deadline, deadline + 7 * 86_400_000);
  assert.equal(next.repeat.seriesId, task.repeat.seriesId);
  assert.equal(next.status, 'pending');
  assert.equal(next.recipientSyncedAt, 0);
});

test('paused occurrences do not advance until resumed; skipping is archived but not counted as completion', async () => {
  const task = await request('/tasks', { familyId: 'pause-skip', fromUserId: 'wife', toUserId: 'husband',
    title: 'Replace filter', repeat: { kind: 'afterDone', days: 90 } });
  const route = `/tasks/${task.objectId}/repeat`;
  const command = (action, userId = 'wife', status = 200) => request(route, { action, userId, familyId: task.familyId }, status);
  await command('pause', 'husband', 403);
  assert.equal((await command('pause')).repeat.paused, true);
  const skipped = await command('skip', 'husband');
  assert.ok(skipped.repeat.skippedAt > 0);
  assert.equal(skipped.archived, true);
  assert.equal(skipped.doneAt, 0);
  assert.equal((await request('/tasks?familyId=pause-skip&caps=v2')).length, 1);
  await command('resume');
  await command('resume', 'wife', 409);
  const rows = await request('/tasks?familyId=pause-skip&caps=v2');
  assert.equal(rows.length, 2);
  const next = rows.find(row => row.repeat.current);
  assert.equal(next.deadline, skipped.repeat.skippedAt + 90 * 86_400_000);
  assert.equal(next.repeat.generated, true);
});

test('calendar months clamp short months and restore the original day; intervals start on completion', () => {
  const { nextDeadline, parseRule } = require('./recurrence');
  const jan = Date.parse('2028-01-31T20:00:00+08:00');
  const feb = Date.parse('2028-02-29T20:00:00+08:00');
  assert.equal(nextDeadline({ kind: 'monthly', anchorAt: jan, scheduledAt: jan }, jan), feb);
  assert.equal(nextDeadline({ kind: 'monthly', anchorAt: jan, scheduledAt: feb }, feb), Date.parse('2028-03-31T20:00:00+08:00'));
  assert.equal(nextDeadline({ kind: 'afterDone', days: 3, scheduledAt: feb, completedAt: jan }, jan), jan + 3 * 86_400_000);
  assert.equal(parseRule({ kind: 'weekly' }, 0), null);
  assert.equal(parseRule({ kind: 'afterDone', days: 0 }, 0), null);
});

test('skipping a live occurrence is safe to retry and removing the successor stops the series', async () => {
  const task = await request('/tasks', { familyId: 'skip-retry', fromUserId: 'wife', toUserId: 'husband',
    title: 'Clean', deadline: Date.now() + 86_400_000, repeat: { kind: 'weekly' } });
  const body = { action: 'skip', familyId: task.familyId, userId: 'husband' };
  const endpoint = `/tasks/${task.objectId}/repeat`;
  await request(endpoint, body);
  await request(endpoint, body, 409);
  await request(`/tasks/${task.objectId}`, { status: 'done', doneAt: Date.now() });
  let rows = await request('/tasks?familyId=skip-retry&caps=v2');
  assert.equal(rows.length, 2);
  assert.equal(rows.find(row => row.objectId === task.objectId).doneAt, 0);
  const next = rows.find(row => row.repeat.current);
  await request(`/tasks/${next.objectId}`, { deleted: true });
  await request(`/tasks/${next.objectId}`, { status: 'done' });
  rows = await request('/tasks?familyId=skip-retry&caps=v2');
  assert.equal(rows.length, 2);
  assert.equal(rows.some(row => row.repeat.current), false);
});
