import test from 'node:test';
import assert from 'node:assert/strict';
import { handleExtract, validateGroups, mentions } from '../src/extract.js';

import { createHash } from 'node:crypto';
const sha256 = async v => createHash('sha256').update(v).digest('hex');
const TEXT = 'Zabıta Memuru kadrosu için: Lisans mezunu olmak. KPSS P3 puan türünden en az 65 puan almış olmak. '
  + 'Başvuru tarihi itibarıyla 30 yaşını doldurmamış olmak. '.repeat(3)
  + 'Tekniker kadrosu için ilgili ön lisans bölümünden mezun olmak.';

function fakeDb() {
  const usage = new Map(), cache = new Map();
  return {
    cache, usage,
    prepare(sql) {
      return { bind: (...a) => ({
        first: async () => {
          if (sql.startsWith('SELECT groups')) return cache.has(a[0]) ? { groups: cache.get(a[0]) } : null;
          const k = a[0] + a[1]; usage.set(k, (usage.get(k) ?? 0) + 1); return { count: usage.get(k) };
        },
        run: async () => { if (!cache.has(a[0])) cache.set(a[0], a[1]); },
      }) };
    },
  };
}
const env = db => ({ DB: db, AI_PROVIDER: 'external', EXTERNAL_AI_URL: 'https://m.test', EXTERNAL_AI_KEY: 'k', EXTERNAL_AI_MODEL: 'm', EXTERNAL_AI_FORMAT: 'openai', EXTRACT_DAILY_INSTALL: '2' });
const id = 'a'.repeat(32);
const modelReply = groups => async () => ({ ok: true, status: 200, json: async () => ({ choices: [{ message: { content: JSON.stringify({ groups }) } }] }) });

test('alıntısı metinde olmayan değer atılır; sınır "doldurmamış" N-1 olur', () => {
  const groups = validateGroups({ groups: [
    { label: 'Zabıta Memuru', education: ['Lisans'], educationQuote: 'Lisans mezunu olmak', kpssStatus: 'required', kpssType: 'P3', kpssScore: 65, kpssQuote: 'KPSS P3 puan türünden en az 65 puan', maxAge: 30, ageQuote: '30 yaşını doldurmamış olmak' },
    { label: 'Uydurma', education: ['Doktora'], educationQuote: 'doktora mezunu olmak' },
  ] }, TEXT);
  assert.equal(groups.length, 1);
  assert.deepEqual(groups[0].education, ['Lisans']);
  assert.equal(groups[0].kpssType, 'P3');
  assert.equal(groups[0].kpssScore, 65);
  assert.equal(groups[0].maxAge, 29);
  assert.equal(groups[0].ageStatus, 'known');
});

test('aynı metin ikinci kez modeli çağırmaz; kurulum tavanı uygulanır', async () => {
  const db = fakeDb(); let calls = 0;
  const fetch = async (...a) => { calls++; return modelReply([{ education: ['Lisans'], educationQuote: 'Lisans mezunu olmak' }])(...a); };
  const first = await handleExtract({ installationId: id, text: TEXT }, env(db), { sha256, fetch });
  assert.equal(first.status, 200); assert.equal(first.body.cached, false);
  const again = await handleExtract({ installationId: id, text: TEXT + '   ' }, env(db), { sha256, fetch });
  assert.equal(again.body.cached, true); assert.equal(calls, 1);
  await handleExtract({ installationId: id, text: TEXT + ' x' }, env(db), { sha256, fetch });
  const capped = await handleExtract({ installationId: id, text: TEXT + ' y' }, env(db), { sha256, fetch });
  assert.equal(capped.status, 429);
});

test('kısa metin ve geçersiz kimlik reddedilir; bozuk model yanıtı önbelleğe girmez', async () => {
  const db = fakeDb();
  assert.equal((await handleExtract({ installationId: id, text: 'kısa' }, env(db), { sha256 })).status, 400);
  assert.equal((await handleExtract({ installationId: 'x', text: TEXT }, env(db), { sha256 })).status, 400);
  const bad = await handleExtract({ installationId: id, text: TEXT }, env(db), { sha256, fetch: async () => ({ ok: true, status: 200, json: async () => ({ choices: [{ message: { content: 'yok' } }] }) }) });
  assert.equal(bad.status, 502); assert.equal(db.cache.size, 0);
});

test('yaş sayısı yazıyla da doğrulanır', () => {
  assert.ok(mentions('otuz beş yaşını doldurmamış olmak', 35));
  assert.ok(mentions('35 yaşını doldurmamış', 35));
  assert.ok(!mentions('325 sayılı kanun', 32));
  const text = 'Yazılı sınavın yapıldığı yılın ocak ayının birinci günü itibariyle otuz beş yaşını doldurmamış olmak. ' + 'x'.repeat(300);
  const [g] = validateGroups({ groups: [{ maxAge: 35, ageQuote: 'otuz beş yaşını doldurmamış olmak' }] }, text);
  assert.equal(g.maxAge, 34);
});
