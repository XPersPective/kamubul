import {test} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync,readdirSync} from 'node:fs';
import {readSbbDetail,readSource,readNoticeDetail} from '../src/pipeline.js';
import {sha256} from '../src/worker.js';

function setup(t){
  const sql=new DatabaseSync(':memory:');t.after(()=>sql.close());sql.exec('PRAGMA foreign_keys=ON');
  for(const file of readdirSync(new URL('../migrations/',import.meta.url)).filter(f=>f.endsWith('.sql')).sort())sql.exec(readFileSync(new URL('../migrations/'+file,import.meta.url),'utf8'));
  const DB={prepare(query){let args=[];return {bind(...values){args=values;return this;},async first(){return sql.prepare(query).get(...args)??null;},async run(){return sql.prepare(query).run(...args);}};},async batch(statements){sql.exec('BEGIN');try{for(const statement of statements)await statement.run();sql.exec('COMMIT');}catch(error){sql.exec('ROLLBACK');throw error;}}};
  const original=globalThis.fetch;t.after(()=>{globalThis.fetch=original;});
  let pdf='%PDF-1.7\nfixture',calls=0;
  globalThis.fetch=async(url,options)=>{
    assert.ok(String(url).startsWith('https://kamuilan.sbb.gov.tr/ilanDetay.aspx?kod='));assert.equal(options.redirect,'manual');
    return new Response(pdf);
  };
  const env={DB,AI:{async toMarkdown(doc,options){calls++;assert.equal(doc.blob.type,'application/pdf');assert.equal(await doc.blob.text(),pdf);assert.deepEqual(options,{conversionOptions:{output:{format:'text'},pdf:{metadata:false}}});return {format:'text',mimetype:'application/pdf',data:'Resmî ilan metni. Başvuru koşulları burada bulunur.'};}}};
  return {sql,env,calls:()=>calls,setPdf:value=>{pdf=value;}};
}

test('PDF raw hash cache avoids repeated conversion; changed bytes reserve a new bounded request',async t=>{
  const f=setup(t),first=await readSbbDetail(f.env,'a+b/c');
  assert.equal(first.documentHash,await sha256(new TextEncoder().encode('%PDF-1.7\nfixture')));
  assert.equal(await sha256('fixture'),await sha256(new TextEncoder().encode('fixture')));
  assert.deepEqual(await readSbbDetail(f.env,'a+b/c',first),first);assert.equal(f.calls(),1);
  f.setPdf('%PDF-1.7\nchanged');await readSbbDetail(f.env,'a+b/c',first);assert.equal(f.calls(),2);
  assert.equal(f.sql.prepare("SELECT count FROM rate_limits WHERE key LIKE 'pdf:%'").get().count,2);
});

test('detail repair has two durable reads; same revision cannot reset on a new Cron',async t=>{
  const f=setup(t),base={id:'sbb:bounded',sourceId:'sbb',externalId:'bounded',title:'Resmî ilan',publishedAt:'2026-10-01'};
  let reads=0;globalThis.fetch=async()=>{reads++;return new Response('blocked',{status:403});};
  for(let i=0;i<2;i++)await assert.rejects(readNoticeDetail(f.env,base),/blocked/);
  await assert.rejects(readNoticeDetail({...f.env},base),/detail_retry_exhausted_or_busy/);
  assert.equal(reads,2);assert.equal(f.sql.prepare('SELECT attempts FROM source_detail_runs').get().attempts,2);
  await assert.rejects(readNoticeDetail(f.env,{...base,publishedAt:'2026-10-02'}),/blocked/);
  assert.equal(reads,3);assert.equal(f.sql.prepare('SELECT attempts FROM source_detail_runs').get().attempts,1);
});

test('concurrent detail repair reserves one read, and complete text ends the repair episode',async t=>{
  const f=setup(t),base={id:'sbb:one',sourceId:'sbb',externalId:'one',title:'Resmî ilan'};
  let resume;const blocked=new Promise(resolve=>{resume=resolve;});
  globalThis.fetch=async()=>{await blocked;return new Response('%PDF-1.7\nfixture');};
  const first=readNoticeDetail(f.env,base);
  // Wait until the durable reservation exists, without relying on timer scheduling.
  for(let i=0;i<100&&!f.sql.prepare('SELECT 1 FROM source_detail_runs').get();i++)await new Promise(resolve=>setImmediate(resolve));
  assert.ok(f.sql.prepare('SELECT 1 FROM source_detail_runs').get());
  await assert.rejects(readNoticeDetail(f.env,base),/detail_retry_exhausted_or_busy/);
  resume();assert.equal((await first).detailState,'available');assert.equal(f.calls(),1);
  assert.equal(f.sql.prepare('SELECT COUNT(*) n FROM source_detail_runs').get().n,0);
});

test('empty converted text stays a failed repair; quota or missing fields never fabricate completion',async t=>{
  const f=setup(t),base={id:'sbb:empty',sourceId:'sbb',externalId:'empty',title:'Resmî ilan'};
  f.env.AI.toMarkdown=async()=>({format:'text',mimetype:'application/pdf',data:'   '});
  await assert.rejects(readNoticeDetail(f.env,base),/pdf_text_empty/);
  assert.equal(f.sql.prepare('SELECT attempts FROM source_detail_runs').get().attempts,1);
  f.env.AI.toMarkdown=async()=>({format:'text',mimetype:'application/pdf',data:'Şartlar kaynakta belirtilmemiştir.'});
  assert.equal((await readNoticeDetail(f.env,base)).text,'Şartlar kaynakta belirtilmemiştir.');
  assert.equal(f.sql.prepare('SELECT COUNT(*) n FROM source_detail_runs').get().n,0);
});

test('PDF budget is atomic and failures remain bounded; non-PDF never reaches converter',async t=>{
  const f=setup(t),day=new Date().toISOString().slice(0,10);
  f.sql.prepare('INSERT INTO rate_limits VALUES(?,19,?)').run('pdf:'+day,day);
  const results=await Promise.allSettled([readSbbDetail(f.env,'one'),readSbbDetail(f.env,'two')]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);assert.equal(results.find(r=>r.status==='rejected').reason.message,'pdf_daily_budget');assert.equal(f.calls(),1);
  f.setPdf('<html>Access denied</html>');await assert.rejects(readSbbDetail(f.env,'one'),/pdf_format/);assert.equal(f.calls(),1);
  await assert.rejects(readSbbDetail(f.env,''),/pdf_identity/);
});

test('PDF output schema, empty scan and UTF-8 byte limit fail without fabricated text',async t=>{
  const f=setup(t);
  for(const [result,error] of [[{format:'error',error:'private provider error'},'pdf_conversion'],[{format:'text',mimetype:'image/png',data:'description'},'pdf_conversion'],[{format:'text',mimetype:'application/pdf',data:'   '},'pdf_text_empty'],[{format:'text',mimetype:'application/pdf',data:'ş'.repeat(60001)},'pdf_text_oversize']]){
    f.env.AI.toMarkdown=async()=>result;await assert.rejects(readSbbDetail(f.env,'one'),new RegExp(error));
  }
});

test('SBB pipeline persists converted text/hash/job and preserves successful detail on fetch failure',async t=>{
  const f=setup(t),batch=[{id:'sbb:one',externalId:'one',sourceId:'sbb',title:'Resmî ilan',category:'Kamu Personeli',deadline:null,url:'https://kamuilan.sbb.gov.tr/ilanDetay.aspx?kod=one',publishedAt:null}];
  f.sql.exec("UPDATE sources SET next_due='2999-01-01' WHERE id!='sbb'");
  const reset=()=>f.sql.prepare("UPDATE sources SET next_due='1970-01-01',pending_batch=?,batch_offset=0 WHERE id='sbb'").run(JSON.stringify(batch));
  reset();await readSource(f.env);
  let row=f.sql.prepare("SELECT * FROM listings WHERE id='sbb:one'").get();const firstPayload=row.payload;
  assert.equal(JSON.parse(row.payload).detailState,'available');assert.ok(JSON.parse(row.payload).documentHash);
  assert.equal(f.sql.prepare("SELECT state,contract_key FROM processing_jobs").get().state,'pending');
  f.sql.exec("UPDATE listings SET recheck_at='1970-01-01'");reset();await readSource(f.env);assert.equal(f.calls(),1);
  f.setPdf('%PDF-1.7\nnew metadata only');f.sql.exec("UPDATE listings SET recheck_at='1970-01-01'");reset();await readSource(f.env);
  row=f.sql.prepare("SELECT * FROM listings WHERE id='sbb:one'").get();assert.notEqual(JSON.parse(row.payload).documentHash,JSON.parse(firstPayload).documentHash);
  assert.equal(f.sql.prepare('SELECT COUNT(*) n FROM processing_jobs').get().n,1,'Same converted content must not queue another AI summary');
  globalThis.fetch=async()=>new Response('blocked',{status:403});const saved=row.payload;
  f.sql.exec("UPDATE listings SET recheck_at='1970-01-01'");reset();await readSource(f.env);
  assert.equal(f.sql.prepare("SELECT payload FROM listings WHERE id='sbb:one'").get().payload,saved);
});
