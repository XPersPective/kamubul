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

test('KPSS ranking weight is not a required minimum, including cached results',async()=>{
  const quote='2025 veya 2026 yılında yapılan KPSS P3 puanının yüzde yetmişi (%70)',text=quote+'. '+TEXT;
  const wrong={kpssStatus:'required',kpssType:'P3',kpssScore:70,kpssQuote:quote};
  assert.equal(validateGroups({groups:[wrong]},text)[0],undefined);
  const db=fakeDb(),hash=await sha256(JSON.stringify(['x12','conditions','external','m',null,text]));
  db.sql.prepare('INSERT INTO extraction_cache(hash,groups,created_at) VALUES(?,?,?)').run(hash,JSON.stringify([{...wrong,quotes:{kpss:quote}}]),'now');
  const result=await handleExtract({installationId:id,text},env(db),{sha256,fetch:()=>assert.fail('cache replay must not infer')});
  assert.equal(result.body.cached,true);assert.equal(result.body.groups[0].kpssStatus,undefined);assert.equal(result.body.groups[0].kpssScore,undefined);db.sql.close();
});
test('written compound numbers do not validate their tens or ones separately',()=>{
  for(const quote of ['otuz beş yaşını bitirmemiş','otuzbeş yaşını bitirmemiş']){
    assert.equal(mentions(quote,35),true);assert.equal(mentions(quote,30),false);assert.equal(mentions(quote,5),false);
  }
});
test('old cached application dates are checked without another inference or token reservation',async()=>{
  const quote='Son Başvuru Tarihi: 14.10.2026 Ön Değerlendirme Sonuç Açıklama Tarihi: 15.10.2026',quotaQuote='En yüksek puanlı 800 kişi sınava çağrılacaktır.',text=quote+'. '+quotaQuote+' '+TEXT;
  const db=fakeDb(),hash=await sha256(JSON.stringify(['x12','notice','external','m',null,text]));
  db.sql.prepare('INSERT INTO extraction_cache(hash,groups,created_at) VALUES(?,?,?)').run(hash,JSON.stringify({groups:[],fields:{deadline:{value:'2026-10-15T20:59:59.999Z',quote},quota:{value:800,quote:quotaQuote}}}),'now');
  const result=await handleExtract({installationId:id,text,noticeMode:true},env(db),{sha256,fetch:()=>assert.fail('cached validation must not infer')});
  assert.equal(result.body.cached,true);assert.equal(result.body.fields.deadline,undefined);assert.equal(result.body.fields.quota,undefined);assert.equal(db.sql.prepare('SELECT count(*) n FROM assistant_usage').get().n,0);db.sql.close();
});

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
  const config = { ...env(db), EXTRACT_AI_PROVIDER:'cloudflare', AI_MODEL:'m', AI:{async run(){calls++;return {response:'{"groups":[]}'}}}, EXTRACT_DAILY_GLOBAL: '1' };
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

test('Qwen birincil: tam metin (tablo satırları dahil) gider; her satır ayrı grup; pay dolunca bekler', async () => {
  const db = fakeDb(); const sent = [];
  const filler = 'Başvurular şahsen veya posta ile yapılabilir ve belgeler onaylı olmalıdır. '.repeat(1000);
  const table = '\nS.No | Ünvan | KPSS Puan Türü | Açıklama\n1 | Mühendis | P3 | İnşaat Mühendisliği lisans mezunu olmak\n2 | Tekniker | P93 | Elektrik ön lisans programından mezun olmak';
  const text = 'Genel şart: KPSS sınavına girmiş olmak. ' + filler + table;
  const config = { ...env(db), EXTRACT_QWEN_DAILY: '20', EXTRACT_QWEN_HOURLY: '1', EXTRACT_DAILY_INSTALL: '10' };
  const fetch = async (url, init) => { sent.push(JSON.parse(init.body).messages[1].content); return modelReply([
    { label: 'Mühendis', education: ['Lisans'], educationQuote: 'İnşaat Mühendisliği lisans mezunu olmak', kpssStatus: 'required', kpssType: 'P3', kpssQuote: '1 | Mühendis | P3' },
    { label: 'Tekniker', education: ['Ön lisans'], educationQuote: 'Elektrik ön lisans programından mezun olmak', kpssStatus: 'required', kpssType: 'P93', kpssQuote: '2 | Tekniker | P93' },
  ])(); };
  const res = await handleExtract({ installationId: id, text }, config, { sha256, fetch });
  assert.equal(res.status, 200);
  assert.ok(sent[0].includes('2 | Tekniker | P93 | Elektrik'), 'table rows reach the model on their own lines');
  assert.ok(sent[0].length > 60000, 'Qwen reads every accepted character, including text after the former 60k ceiling');
  assert.deepEqual(res.body.groups.map(g => [g.label, g.education[0], g.kpssType]), [['Mühendis', 'Lisans', 'P3'], ['Tekniker', 'Ön lisans', 'P93']]);
  const later = await handleExtract({ installationId: id, text: text + ' ek' }, config, { sha256, fetch });
  assert.equal(later.status, 429); assert.equal(later.body.error, 'fallback_budget'); assert.equal(sent.length, 1);
});

test('tablo hücrelerinden birleşen etiket kabul edilir; metinde olmayan sözcük reddedilir', () => {
  const text = 'S.No | Bölüm | Kadro\n1 | Psikoloji | Profesör | Psikoloji alanında lisans mezunu olmak';
  const [ok, bad] = validateGroups({ groups: [
    { label: 'Psikoloji - Profesör', education: ['Lisans'], educationQuote: 'Psikoloji alanında lisans mezunu olmak' },
    { label: 'Hukuk - Doçent', education: ['Lisans'], educationQuote: 'Psikoloji alanında lisans mezunu olmak' },
  ] }, text);
  assert.equal(ok.label, 'Psikoloji - Profesör'); assert.equal(bad.label, undefined);
});

test('primary and middle school graduation are matchable education levels', () => {
  const primary='En az ilkokul mezunu olmak.',middle='İlköğretim mezunu olmak.';
  assert.deepEqual(validateGroups({groups:[{education:['İlkokul'],educationQuote:primary}]},primary)[0].education,['İlkokul']);
  assert.deepEqual(validateGroups({groups:[{education:['Ortaokul'],educationQuote:middle}]},middle)[0].education,['Ortaokul']);
  assert.deepEqual(validateGroups({groups:[{education:['Lise'],educationQuote:primary}]},primary),[]);
});


test('Qwen budget probe names the next open window without reserving a call', async () => {
  const { qwenWaitUntil } = await import('../src/extract.js');
  const rows = new Map();
  const DB = { prepare: () => ({ bind: (day, bucket) => ({ first: async () => rows.has(day + bucket) ? { count: rows.get(day + bucket) } : null }) }) };
  const env = { DB, AI_PROVIDER: 'external', EXTRACT_AI_PROVIDER: 'external', EXTERNAL_AI_URL: 'https://m.test', EXTERNAL_AI_KEY: 'k', EXTERNAL_AI_MODEL: 'm', EXTRACT_QWEN_DAILY: '150', EXTRACT_QWEN_HOURLY: '30' };
  const now = new Date('2026-10-06T15:20:00Z');
  assert.equal(await qwenWaitUntil(env, now), null);
  rows.set('2026-10-06x:qwen:h15', 30);
  assert.equal(await qwenWaitUntil(env, now), '2026-10-06T16:00:00.000Z');
  rows.set('2026-10-06x:qwen', 150);
  assert.equal(await qwenWaitUntil(env, now), '2026-10-07T00:00:00.000Z');
  assert.equal(await qwenWaitUntil({ ...env, EXTRACT_QWEN_DAILY: undefined }, now), null, 'uncapped providers keep their own error path');
});

test('headerless position rows with gender-marked counts give the vacancy total', async () => {
  const { mechanicalNotice } = await import('../src/notice_extraction.js');
  const text = ['Üniversitemiz birimlerinde istihdam edilmek üzere sözleşmeli personel alınacaktır.',
    'Destek Personeli (Temizlik Görevlisi) (Hastane) | 6 (Erkek-Kadın) | KPSS (P94) 2024 | - 2024 Kpss B Grubu P94 Puan Türünden En Az 60 Puan Almış olmak.',
    'Destek Personeli (Şoför) | 1 (Erkek) | KPSS (P94) 2024 | - Ortaöğretim (Lise ve Dengi) Kurumlarının herhangi bir alanından mezun olmak.',
    'Sağlık Teknikeri (Diş Protez Teknikeri) | 2 (Erkek-Kadın) | KPSS (P93) 2024 | - 2024 yılı Kamu Personeli Seçme Sınavından (P93) en az 60 puan almış olmak.'].join('\n');
  const result = mechanicalNotice({ title: 'Sözleşmeli Personel Alım İlanı' }, text);
  assert.equal(result.fields.quota.value, 9);
  assert.deepEqual(result.groups.map(g => g.quota), [6, 1, 2]);
  assert.equal(result.groups[1].label, 'Destek Personeli (Şoför)');
  // A plain number without the marker in a headerless table stays unknown rather than guessed.
  assert.equal(mechanicalNotice({ title: 'İlan' }, 'Hemşire | 4 | Lisans mezunu olmak.').fields.quota, undefined);
});

test('a bracketed application range after "Başvuru süresi" is the deadline', async () => {
  const { mechanicalNotice } = await import('../src/notice_extraction.js');
  const text = 'Başvuru süresi, ilan yayınladığı tarihten itibaren (30/09/2026 – 14/10/2026) 15 gündür. SIRA NUMARASI | FAKÜLTE | KADRO\n1 | Diş Hekimliği | Profesör';
  const result = mechanicalNotice({ title: 'Öğretim Üyesi Alım İlanı', gazettePublishedAt: '2026-09-30' }, text);
  assert.equal(result.fields.deadline.value, '2026-10-14T20:59:59.999Z');
  // A results or objection date range is not an application window.
  assert.equal(mechanicalNotice({ title: 'İlan' }, 'Sınav sonuçları (01/11/2026 – 05/11/2026) arasında ilan edilir.').fields.deadline, undefined);
});

test('a correction notice lists changed rows but states no new vacancy total', async () => {
  const { mechanicalNotice, assessNotice } = await import('../src/notice_extraction.js');
  const text = ['İPTAL EDİLEN KADRO İLAN SATIRLARI:', 'Fakülte | Bölüm | Uzmanlık Alanı/Aranılan Şartlar | Kadro Sayısı | Kadro Unvanı',
    'Hukuk Fakültesi | Kamu Hukuku | Hukuk Fakültesi mezunu olmak. | 1 | Arş. Gör.',
    'Meslek Yüksekokulu | Hukuk | Hukuk Fakültesi lisans mezunu olmak. | 1 | Öğr. Gör.'].join('\n');
  const result = mechanicalNotice({ title: 'İptal ve Düzeltme İlanı (Medipol Üniversitesi Rektörlüğü)' }, text);
  assert.equal(result.kind, 'amendment');
  assert.equal(result.fields.quota, undefined, 'cancelled/corrected rows are not new posts');
  assert.equal(result.groups.length, 2, 'the changed rows stay readable');
  assert.ok(!assessNotice(result, text).includes('quota'), 'no model call is spent on a correction total');
});

test('a Son Başvuru Tarihi column may spell the month out', async () => {
  const { mechanicalNotice } = await import('../src/notice_extraction.js');
  const text = ['Fakülte | Bölüm- Ana Bilim Dalı | Ünvan | Kadro | Özel Koşullar | Son Başvuru Tarihi', '',
    'İnsanî Bilimler ve Edebiyat Fakültesi | Sosyoloji | Doktor Öğretim Üyesi | 1 | Antropoloji alanında doktora sahibi olmak. | 13 Ekim 2026'].join('\n');
  assert.equal(mechanicalNotice({ title: 'Koç Üniversitesi Öğretim Üyesi Alım İlanı' }, text).fields.deadline?.value, '2026-10-13T20:59:59.999Z');
});

test('position labels map to canonical occupations; department names are not jobs', async () => {
  const { occupationsOf, matchListing } = await import('../src/criteria.js');
  const { extractNotice } = await import('../src/notice_extraction.js');
  // Live labels.
  assert.deepEqual(occupationsOf('Destek Personeli (Temizlik Görevlisi) (Hastane)'), ['Temizlik Görevlisi', 'Destek Personeli']);
  assert.deepEqual(occupationsOf('Destek Personeli (Erkek) (Şoför)'), ['Şoför', 'Destek Personeli']);
  assert.deepEqual(occupationsOf('Yönetim Bilişim Sistemleri Bölümü · - · Arş. Gör.'), ['Araştırma Görevlisi']);
  assert.deepEqual(occupationsOf('Kamu Hukuku · Ar. Gör.'), ['Araştırma Görevlisi']);
  assert.deepEqual(occupationsOf('Bilgisayar Mühendisliği · Dr. Öğr. Üyesi'), ['Öğretim Üyesi']);
  assert.deepEqual(occupationsOf('Teknıker'), ['Tekniker']);
  assert.deepEqual(occupationsOf('Memur'), ['Büro Personeli']);
  assert.deepEqual(occupationsOf('Zabıta Memuru'), ['Zabıta Memuru']);
  for (const label of ['MUHASEBE GRUBU Genel Muhasebe Maliyet Muhasebesi', 'Muhasebe ve Finans Yönetimi programı ile', 'Bilgisayar Mühendisliği', 'Hemşirelik']) assert.deepEqual(occupationsOf(label), [], label);
  const text = 'Fakülte | Bölüm | Kadro\nİnsan ve Toplum Bilimleri | FRANSIZCA MÜTERCİM VE TERCÜMANLIK | 1\n' + 'Genel şartlar ve başvuru belgeleri ilanın devamındadır. '.repeat(4);
  const academic = (await extractNotice({ title: 'Hacettepe Üniversitesi Rektörlüğü Öğretim Üyesi Alım İlanı' }, text, {}, { mechanicalOnly: true, sha256: async () => '' })).result;
  assert.ok(academic.groups.every(g => g.occupations.every(o => o === 'Öğretim Üyesi')), 'a faculty row under an academic title is not "Tercüman"');
  const city = (await extractNotice({ title: 'Gelir İdaresi Başkanlığından 860 Gelir Uzman Yardımcısı Alımı' }, 'İl | Kadro\nFEKE | 1\nGÖLBAŞI | 2\n' + 'Genel şartlar ve başvuru belgeleri ilanın devamındadır. '.repeat(4), {}, { mechanicalOnly: true, sha256: async () => '' })).result;
  assert.deepEqual(city.occupations, ['Uzman Yardımcısı'], 'labels that name no job inherit the title');
  // The editor offers these labels; a saved "Zabıta Memuru" search matches a "Zabıta Memuru (Erkek)" row.
  const listing = { title: 'Şile Belediye Başkanlığı Memur Alım İlanı', requirementGroups: [{ label: 'Zabıta Memuru (Erkek)', occupations: occupationsOf('Zabıta Memuru (Erkek)') }] };
  assert.equal(matchListing(listing, { version: 2, occupations: ['Zabıta Memuru'] }), 'match');
  assert.equal(matchListing(listing, { version: 2, occupations: ['Hemşire'] }), 'no_match');
});

test('labelled-review fixes: scoring prose, stated dates beside relative rules, paired and scoped age limits', async () => {
  const { mechanicalNotice } = await import('../src/notice_extraction.js');
  // TKGM: a scoring sentence that mentions "yüksek lisans mezunu" is not the education requirement.
  const scoring = mechanicalNotice({ title: 'Bilişim Personeli Alım İlanı' }, 'Bilgisayar mühendisliği lisans programından mezun olmak.\nSıralama; programlama dili sayısı, yüksek lisans mezunu olunması ve dil puanı dikkate alınmak suretiyle değerlendirmeye tabi tutulacaktır.');
  assert.deepEqual(scoring.groups[0].education, ['Lisans']);
  // Tarsus: "en az 15 gün" counted from 21.09 gives 05.10; the stated 06.10 is the same rule counted inclusively.
  const tarsus = 'Başvuru süresi, ilanın Resmî Gazete’de yayımlandığı tarih itibariyle en az 15 (on beş) gündür.\nSon Başvuru Tarihi : 06.10.2026 (Mesai Bitimi)';
  assert.equal(mechanicalNotice({ title: 'Öğretim Üyesi Alım İlanı', publishedAt: '2026-09-21T00:00:01.000Z' }, tarsus).fields.deadline?.value, '2026-10-06T20:59:59.999Z');
  assert.equal(mechanicalNotice({ title: 'Öğretim Üyesi Alım İlanı' }, tarsus).fields.deadline?.value, '2026-10-06T20:59:59.999Z', 'an uncomputable relative rule cannot contradict the stated date');
  // TTK: one clause with a lower and an upper bound.
  const ttk = mechanicalNotice({ title: 'İşçi Alım İlanı' }, '-Başvuru tarihinin son günü itibariyle 18 yaşını tamamlamış, başvuru tarihinin ilk günü itibariyle 32 yaşından gün almamış olmak,');
  assert.equal(ttk.groups[0].minAge, 18); assert.equal(ttk.groups[0].maxAge, 31);
  // Şile: an age rule naming the zabıta posts binds only them.
  const sile = mechanicalNotice({ title: 'Memur Alım İlanı' }, ['Sıra No | Kadro Ünvanı | Sınıfı | Kadro Derecesi | Adedi | Niteliği',
    '1 | Zabıta Memuru | GİH | 9 | 2 | Herhangi bir lisans programından mezun olmak.',
    '2 | Tekniker | TH | 10 | 4 | Harita önlisans programından mezun olmak.',
    'c) Zabıta memuru kadrolarına başvuracaklar için sınavın yapıldığı tarihte 30 yaşını doldurmamış olmak,'].join('\n'));
  assert.deepEqual(sile.groups.map(g => [g.label, g.maxAge ?? null]), [['Zabıta Memuru', 29], ['Tekniker', null]]);
  // Hacı Bayram Veli: the score type follows each position's education level.
  const hbv = mechanicalNotice({ title: 'Sözleşmeli Personel Alım İlanı' }, ['S.N. | Ünvan | Adet | Aranan Nitelikler',
    '1 | Büro Personeli | 4 | Büro Yönetimi ön lisans programlarının birinden mezun olmak.',
    '2 | Destek Personeli | 6 | Ortaöğretim (Lise ve dengi) mezunu olmak.',
    '3 | Mühendis | 1 | Makine Mühendisliği lisans programından mezun olmak.',
    'a) Lisans mezunları için 2024 KPSS (B) Grubu KPSSP3 puanı esas alınacaktır.',
    'b) Ön lisans mezunları için 2024 KPSS (B) Grubu KPSSP93 puanı, ortaöğretim mezunları için KPSSP94 puanı esas alınacaktır.'].join('\n'));
  assert.deepEqual(hbv.groups.map(g => [g.label, g.kpssType ?? null]), [['Büro Personeli', 'P93'], ['Destek Personeli', 'P94'], ['Mühendis', 'P3']]);
  // Yargıtay: numbered headings carry the counts; İletişim: "azami kadro sayısı 15 (onbeş) adettir".
  const yargitay = mechanicalNotice({ title: 'Bilişim Personeli Alım İlanı' }, ['1. Mobil Yazılım Geliştirme Uzmanı (2 (iki) kişi - tam zamanlı)', 'Lisans mezunu olmak.',
    '2- Siber Güvenlik Uzmanı (1 (bir) kişi - tam zamanlı)', '3- Kıdemli Siber Güvenlik Uzmanı (1(bir)kişi - tam zamanlı)'].join('\n'));
  assert.equal(yargitay.fields.quota?.value, 4);
  assert.equal(mechanicalNotice({ title: 'Uzman Yardımcısı Alım İlanı' }, '(1) İletişim Uzman Yardımcısı unvanıyla atama yapılabilecek azami kadro sayısı 15 (onbeş) adettir.').fields.quota?.value, 15);
  // Akdeniz/HMKÜ: a second header row splits ALES into "PUAN TÜRÜ | PUAN"; the count column stays readable.
  const akdeniz = mechanicalNotice({ title: 'Öğretim Görevlisi Alım İlanı' }, ['S.N. | BİRİM | ÜNVAN | DER. | ADET | ALES | YABANCI DİL PUANI | İLAN ŞARTLARI', '',
    'PUAN TÜRÜ | PUAN', '',
    '1 | TIP FAKÜLTESİ | ÖĞRETİM GÖREVLİSİ (UYGULAMALI BİRİM) | 1 | 1 | SAYISAL | 70 | 50 | Kadın Hastalıkları ve Doğum Uzmanı olmak.',
    '2 | TIP FAKÜLTESİ | ÖĞRETİM GÖREVLİSİ (UYGULAMALI BİRİM) | 1 | 2 | SAYISAL | 70 | 50 | İç Hastalıkları uzmanı olmak.'].join('\n'));
  assert.equal(akdeniz.fields.quota?.value, 3); assert.equal(akdeniz.tableAmbiguous, false);
  // ÇOMÜ: "ÖĞR.GÖR. (UYGULAMALI BİRİM)" is a count column like "(DERS VERECEK)".
  const comu = mechanicalNotice({ title: 'Öğretim Elemanı Alım İlanı' }, ['İLAN NO | BÖLÜM | BİRİM | ÖĞR.GÖR. (UYGULAMALI BİRİM) | DER. | ARŞ.GÖR. | DER. | ALES',
    '3 | - | BİLİMSEL ARAŞTIRMA PROJELERİ | 1 | 1 | - | - | 70'].join('\n'));
  assert.equal(comu.fields.quota?.value, 1);
  // Osmaniye: the source states two different ends; no single deadline is shown.
  const osmaniye = mechanicalNotice({ title: '2027 Yılı Tercüman Bilirkişi İlanı' }, ['31 Ekim 2026 tarihinden sonra yapılan başvurular değerlendirmeye alınmaz.',
    'Başvuru Tarihi : Başvurular 15 Ekim 2026 Perşembe günü başlayıp, 02 Kasım 2026 Pazartesi günü mesai bitiminde sona erecektir.'].join('\n'));
  assert.equal(osmaniye.fields.deadline?.value ?? null, null); assert.equal(osmaniye.fields.applicationPeriods?.value.length, 2);
  assert.equal(mechanicalNotice({ title: 'İlan' }, '15.10.2026 tarihinden sonra yapılan başvurular kabul edilmeyecektir.').fields.deadline?.value, '2026-10-15T20:59:59.999Z');
  // ÖİB: a KPSS column listing alternatives ("KPSSP-3 KPSSP-44"), a single hyphenated type, and "KPSSP3".
  const oib = mechanicalNotice({ title: 'Uzman Yardımcılığı Giriş Sınavı Duyurusu' }, ['Gruplar | Öğrenim Dalları (Lisans) | KPSS Puan Türü | KPSS Taban Puanı | Atama Yapılabilecek Boş Kadro Sayısı',
    '1. Grup | Hukuk fakültelerinden mezun olmak. | KPSSP-4 | 80 | 5',
    '2. Grup | Muhasebe ve Finans Yönetimi programından mezun olmak. | KPSSP-3 KPSSP-44 KPSSP-45 | 75 | 2'].join('\n'));
  assert.deepEqual(oib.groups.map(g => [g.kpssType ?? null, g.kpssTypes ?? null]), [['P4', null], [null, ['P3', 'P44', 'P45']]]);
  // TTK/Atatürk: a native education column ("EĞİTİM DURUMU | Mesleki Lise ve Dengi Okulların; ...", "ÖĞRENİM | Ön Lisans").
  const ttk2 = mechanicalNotice({ title: 'İşçi Alım İlanı' }, ['MESLEK ADI | AÇIK İŞÇİ SAYISI | EĞİTİM DURUMU | İSTENEN BELGELER',
    '7212.07 KAYNAKÇI | 5 | Mesleki Lise ve Dengi Okulların; Metal Teknolojisi Alanı ve dallarının birinden | Belge',
    'İLAN NO | ÜNVAN | ÖĞRENİM | ADET', 'ST 01 | Sağlık Teknikeri | Ön Lisans | 2'].join('\n'));
  assert.deepEqual(ttk2.groups.map(g => g.education), [['Lise'], ['Ön lisans']]);
});
