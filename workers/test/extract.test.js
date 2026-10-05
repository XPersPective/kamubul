import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';
import { handleExtract, validateGroups, mentions, focusText } from '../src/extract.js';

import { createHash } from 'node:crypto';
const sha256 = async v => createHash('sha256').update(v).digest('hex');
const TEXT = 'Zabıta Memuru kadrosu için: Lisans mezunu olmak. KPSS P3 puan türünden en az 65 puan almış olmak. '
  + 'Başvuru tarihi itibarıyla 30 yaşını doldurmamış olmak. '.repeat(3)
  + 'Tekniker kadrosu için ilgili ön lisans bölümünden mezun olmak.';

function fakeDb() {
  const sql = new DatabaseSync(':memory:');
  for (const file of ['0017_assistant_usage.sql', '0019_extraction_cache.sql', '0020_extraction_runs.sql']) {
    sql.exec(readFileSync(new URL('../migrations/' + file, import.meta.url), 'utf8'));
  }
  return {
    sql,
    get cache() { return new Map(sql.prepare('SELECT hash,groups FROM extraction_cache').all().map(r => [r.hash,r.groups])); },
    prepare(query) {
      return { bind: (...args) => ({
        first: async () => sql.prepare(query).get(...args) ?? null,
        run: async () => sql.prepare(query).run(...args),
      }) };
    },
  };
}
const env = db => ({ DB: db, EXTRACT_AI_PROVIDER: 'external', AI_PROVIDER: 'external', EXTERNAL_AI_URL: 'https://m.test', EXTERNAL_AI_KEY: 'k', EXTERNAL_AI_MODEL: 'm', EXTERNAL_AI_FORMAT: 'openai', EXTRACT_DAILY_INSTALL: '2' });
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
  assert.equal(again.body.cached, true); assert.equal(calls, 2);
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


test('Workers AI is preferred despite external chat configuration; empty result is cached after two checks', async () => {
  const db = fakeDb(); let calls = 0;
  const config = { ...env(db), EXTRACT_AI_PROVIDER: 'cloudflare', AI_MODEL: '@cf/test', AI: { run: async () => { calls++; return { response: '{"groups":[]}' }; } } };
  const deps = { sha256, fetch: async () => assert.fail('external provider must not run') };
  const first = await handleExtract({ installationId: id, text: TEXT }, config, deps);
  assert.equal(first.status, 200); assert.equal(calls, 2);
  assert.deepEqual(first.body.groups, []);
  assert.equal((await handleExtract({ installationId: id, text: TEXT }, config, deps)).body.cached, true);
  assert.equal(calls, 2);
  config.AI_MODEL = '@cf/new';
  assert.equal((await handleExtract({ installationId: id, text: TEXT }, config, deps)).body.cached, false);
  assert.equal(calls, 4);
});

test('repair reads the same text and stops at two; global budget counts each inference', async () => {
  const db = fakeDb(); let calls = 0;
  const config = { ...env(db), EXTRACT_DAILY_GLOBAL: '1' };
  const result = await handleExtract({ installationId: id, text: TEXT }, config, { sha256, fetch: async () => { calls++; return modelReply([])(); } });
  assert.equal(result.status, 429); assert.equal(calls, 1); assert.equal(db.cache.size, 0);
});

test('quota alone permits separately capped Qwen fallback within two total calls', async () => {
  const db = fakeDb(); let cf = 0, qwen = 0;
  const config = { ...env(db), EXTRACT_AI_PROVIDER: 'cloudflare', EXTRACT_QWEN_DAILY: '1', AI_MODEL: '@cf/test', AI: { run: async () => { cf++; throw new Error('3036: daily neuron quota'); } } };
  const deps = { sha256, fetch: async () => { qwen++; return modelReply([])(); } };
  const result = await handleExtract({ installationId: id, text: TEXT }, config, deps);
  assert.equal(result.status, 200); assert.equal(cf, 1); assert.equal(qwen, 1);
  const capped = await handleExtract({ installationId: id, text: TEXT + ' changed' }, config, deps);
  assert.equal(capped.status, 429); assert.equal(qwen, 1);
  config.AI.run = async () => { throw new Error('network error'); };
  const failure = await handleExtract({ installationId: 'b'.repeat(32), text: TEXT + ' failed' }, config, deps);
  assert.equal(failure.status, 502); assert.equal(qwen, 1);
});


test('failed inference ceiling survives new installations; concurrent requests share a lease', async () => {
  const db = fakeDb(); let calls = 0, release, started;
  const running = new Promise(resolve => { started = resolve; });
  const held = new Promise(resolve => { release = resolve; });
  const config = { ...env(db), EXTRACT_AI_PROVIDER: 'cloudflare', AI_MODEL: '@cf/test', AI: { run: async () => { calls++; started(); await held; throw new Error('invalid response'); } } };
  const first = handleExtract({ installationId: id, text: TEXT }, config, { sha256 });
  await running;
  const concurrent = await handleExtract({ installationId: 'b'.repeat(32), text: TEXT }, config, { sha256 });
  assert.equal(concurrent.status, 409); assert.equal(calls, 1);
  release(); assert.equal((await first).status, 502);
  assert.equal((await handleExtract({ installationId: 'c'.repeat(32), text: TEXT }, config, { sha256 })).status, 502);
  assert.equal((await handleExtract({ installationId: 'd'.repeat(32), text: TEXT }, config, { sha256 })).status, 422);
  assert.equal(calls, 2);
});

test('numeric evidence keeps fractional KPSS scores exact and word boundaries intact', () => {
  assert.equal(mentions('En az 70 puan', 70.5), false);
  assert.equal(mentions('En az 70,5 puan', 70.5), true);
  assert.equal(mentions('otuz beş yaş', 3), false);
  assert.equal(mentions('birinci yıl', 1), false);
  const text = 'KPSS P3 puan türünden en az 70 puan almış olmak.';
  const [group] = validateGroups({ groups: [{ kpssStatus: 'required', kpssScore: 70.5, kpssQuote: text }] }, text);
  assert.equal(group.kpssScore, undefined);
});

test('Qwen repairs missing coverage under its own cap; oversized text is never silently cut', async () => {
  const db = fakeDb(); let cf = 0, qwen = 0;
  const config = { ...env(db), EXTRACT_AI_PROVIDER: 'cloudflare', EXTRACT_QWEN_DAILY: '1', AI_MODEL: '@cf/test', AI: { run: async () => { cf++; return { response: '{"groups":[]}' }; } } };
  const result = await handleExtract({ installationId: id, text: TEXT }, config, { sha256, fetch: async () => {
    qwen++; return modelReply([{ education: ['Lisans'], educationQuote: 'Lisans mezunu olmak' }])();
  } });
  assert.equal(result.status, 200); assert.equal(cf, 1); assert.equal(qwen, 1);
  assert.equal(result.body.groups.length, 1);
  assert.equal(db.sql.prepare('SELECT model FROM extraction_cache').get().model, 'm');
  const oversized = await handleExtract({ installationId: id, text: TEXT.repeat(400) }, config, { sha256 });
  assert.equal(oversized.status, 413); assert.equal(cf, 1);
});

test('real official exam threshold is not KPSS; law faculty and associate alternatives both survive', () => {
  const educationQuote='Hukuk fakültesi, adalet meslek yüksekokulu, meslek yüksekokullarının adalet bölümü veya adalet meslek eğitimi ön lisans programı mezunu olmak';
  const examQuote='Yazılı sınavda yüz tam puan üzerinden Genel Başarı Puanı en az yetmiş puan almak kaydıyla';
  const ageQuote='Yazılı sınavın yapıldığı yılın ocak ayının birinci günü itibariyle otuz beş yaşını doldurmamış olmak';
  const [group]=validateGroups({groups:[{education:['Ön lisans'],educationQuote,kpssStatus:'required',kpssScore:70,kpssQuote:examQuote,maxAge:35,ageQuote}]},[educationQuote,examQuote,ageQuote].join('. '));
  assert.deepEqual(group.education,['Ön lisans','Lisans']);
  assert.equal(group.kpssStatus,undefined);assert.equal(group.kpssScore,undefined);
  assert.equal(group.maxAge,34);assert.equal(group.ageCalculation,'other_reference');
  assert.deepEqual(validateGroups({groups:[{education:['Doktora'],educationQuote:'Lisans mezunu olmak'}]},'Lisans mezunu olmak'),[]);
});

test('bozuk JSON ilk denemede kalırsa ikinci hak (Qwen) kullanılır', async () => {
  const db = fakeDb(); let cf = 0, qwen = 0;
  const config = { ...env(db), EXTRACT_AI_PROVIDER: 'cloudflare', EXTRACT_QWEN_DAILY: '5', AI_MODEL: '@cf/test', AI: { run: async () => { cf++; return { response: '{"groups":[{"label":"yarım' }; } } };
  const result = await handleExtract({ installationId: id, text: TEXT }, config, { sha256, fetch: async () => {
    qwen++; return modelReply([{ education: ['Lisans'], educationQuote: 'Lisans mezunu olmak' }])();
  } });
  assert.equal(result.status, 200); assert.equal(cf, 1); assert.equal(qwen, 1);
  assert.deepEqual(result.body.groups[0].education, ['Lisans']);
});

test('uzun ilanda modele yalnız şart kesiti gider; alıntılar kesitte doğrulanır', () => {
  const filler = 'Bu bölüm ilan süreci hakkında genel bilgi içermektedir ve şartlarla ilgisi yoktur. '.repeat(200);
  const conditions = 'Zabıta Memuru kadrosu için: Lise mezunu olmak. Başvuru tarihi itibarıyla 30 yaşını doldurmamış olmak.';
  const focused = focusText(filler + conditions + ' ' + filler);
  assert.ok(focused.length <= 7000);
  assert.ok(focused.includes('Lise mezunu olmak.'));
  assert.ok(focused.includes('30 yaşını doldurmamış olmak.'));
  const [g] = validateGroups({ groups: [{ education: ['Lise'], educationQuote: 'Lise mezunu olmak', maxAge: 30, ageQuote: 'Başvuru tarihi itibarıyla 30 yaşını doldurmamış olmak' }] }, focused);
  assert.equal(g.maxAge, 29);
  const short = 'Kısa metin. '.repeat(30);
  assert.equal(focusText(short), short);
});

test('zaman aşımında Qwen; saatlik pay dolunca o saat için durur', async () => {
  const db = fakeDb(); let qwen = 0;
  const config = { ...env(db), EXTRACT_AI_PROVIDER: 'cloudflare', EXTRACT_QWEN_DAILY: '20', EXTRACT_QWEN_HOURLY: '1', EXTRACT_DAILY_INSTALL: '10', AI_MODEL: '@cf/test', AI: { run: async () => { throw new Error('extract_timeout'); } } };
  const fetch = async () => { qwen++; return modelReply([{ education: ['Lisans'], educationQuote: 'Lisans mezunu olmak' }])(); };
  const first = await handleExtract({ installationId: id, text: TEXT }, config, { sha256, fetch });
  assert.equal(first.status, 200); assert.equal(qwen, 1);
  assert.deepEqual(first.body.groups[0].education, ['Lisans']);
  const second = await handleExtract({ installationId: id, text: TEXT + ' farklı' }, config, { sha256, fetch });
  assert.equal(second.status, 429); assert.equal(second.body.error, 'fallback_budget'); assert.equal(qwen, 1);
});
