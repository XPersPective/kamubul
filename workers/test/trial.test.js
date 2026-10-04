import test from 'node:test';
import assert from 'node:assert/strict';
import { handleTrial } from '../src/trial.js';

const db = () => {
  const usage = new Map(); const devices = new Map();
  return { prepare: sql => ({ bind: (...a) => ({
    first: async () => {
      if (sql.startsWith('INSERT INTO assistant_usage')) { const k = a[0] + a[1]; usage.set(k, (usage.get(k) ?? 0) + 1); return { count: usage.get(k) }; }
      if (sql.startsWith('SELECT first_seen')) return { first_seen: devices.get(a[0]) };
    },
    run: async () => { if (!devices.has(a[0])) devices.set(a[0], a[1]); },
  }) }) };
};
const sha256 = async v => 'h' + v;
const h = 'a'.repeat(64);

test('first seen is kept across reinstalls (later calls never move it forward)', async () => {
  const env = { DB: db() };
  const a = await handleTrial({ deviceHash: h }, env, { sha256, ip: '1', now: new Date('2026-10-01T00:00:00Z') });
  const b = await handleTrial({ deviceHash: h }, env, { sha256, ip: '1', now: new Date('2026-10-20T00:00:00Z') });
  assert.equal(a.body.firstSeen, '2026-10-01T00:00:00.000Z');
  assert.equal(b.body.firstSeen, '2026-10-01T00:00:00.000Z');
});

test('rejects bad hashes and rate limits per ip', async () => {
  const env = { DB: db(), TRIAL_DAILY_IP: '2' };
  assert.equal((await handleTrial({ deviceHash: 'raw-android-id' }, env, { sha256, ip: '1' })).status, 400);
  await handleTrial({ deviceHash: h }, env, { sha256, ip: '2' });
  await handleTrial({ deviceHash: h }, env, { sha256, ip: '2' });
  assert.equal((await handleTrial({ deviceHash: h }, env, { sha256, ip: '2' })).status, 429);
});
