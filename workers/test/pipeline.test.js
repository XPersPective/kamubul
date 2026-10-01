import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {DatabaseSync} from 'node:sqlite';
import {splitAiText,processNotice,readSource} from '../src/pipeline.js';

function database(){
  const sql=new DatabaseSync(':memory:');sql.exec('PRAGMA foreign_keys=ON');sql.exec(readFileSync(new URL('../migrations/0001_catalogue.sql',import.meta.url),'utf8'));
  const DB={prepare(query){let values=[];return {bind(...args){values=args;return this;},async first(){return sql.prepare(query).get(...values)??null;},async all(){return {results:sql.prepare(query).all(...values)};},async run(){return sql.prepare(query).run(...values);}};},async batch(statements){sql.exec('BEGIN');try{const results=[];for(const s of statements)results.push(await s.run());sql.exec('COMMIT');return results;}catch(e){sql.exec('ROLLBACK');throw e;}}};
  return {sql,DB};
}
function insertNotice(sql,text){
  const payload={id:'job',title:'Kamu ilanı',sourceId:'sbb',text,positions:[],summary:[],deadline:null};
  sql.prepare("INSERT INTO listings(id,source_id,external_id,content_hash,first_seen,updated_at,recheck_at,payload) VALUES('job','sbb','job','hash','first','first','later',?)").run(JSON.stringify(payload));
  sql.prepare("INSERT INTO processing_jobs(id,listing_id,input_hash,input,due_at) VALUES('processing','job','hash',?,'1970-01-01')").run(JSON.stringify(payload));
}
function model(calls){return {async run(model,request,options){
  assert.equal(options.rejectIfBusy,true);assert.ok(new TextEncoder().encode(JSON.stringify(request)).length<=24000);
  const {text}=JSON.parse(request.messages[1].content);calls.push(text);
  const quote=text.startsWith('[{')?JSON.parse(text)[0].quote:text.slice(0,80);
  return {response:JSON.stringify({summary:[{text:'Resmî başvuru koşulları.',quote}],conditions:[]})};
}};}

test('long Turkish/emoji document is split losslessly on UTF8 boundaries',()=>{
  for(const text of ['','ğ'.repeat(16000),'😀'.repeat(17000),('Başvuru bilgileri\n').repeat(4000)]){
    const chunks=splitAiText(text);assert.equal(chunks.join(''),text);
    for(const chunk of chunks)assert.ok(new TextEncoder().encode(chunk).length<=12000);
  }
  assert.throws(()=>splitAiText('a'.repeat(120001)),/text_oversize/);
});

test('long AI job resumes stored chunks and publishes only after consolidation',async()=>{
  const {sql,DB}=database(),calls=[],text=('Adaylar başvuru koşullarını incelemelidir.\n').repeat(1000);insertNotice(sql,text);
  const env={DB,AI:model(calls),AI_MODEL:'model',AI_DAILY_JOBS:'20'};
  await processNotice(env);
  let job=sql.prepare("SELECT * FROM processing_jobs WHERE id='processing'").get();
  assert.equal(job.state,'pending');assert.equal(JSON.parse(job.input).aiProgress.index,1);
  assert.equal(sql.prepare("SELECT processed_hash FROM listings WHERE id='job'").get().processed_hash,null);
  sql.exec("UPDATE listings SET payload=json_set(payload,'$.publishedAt','2026-10-01T00:00:00Z') WHERE id='job'");
  // A new invocation/model instance sees persisted progress rather than rereading chunk 0.
  for(let n=0;n<20&&job.state!=='completed';n++){
    await processNotice({...env,AI:model(calls)});job=sql.prepare("SELECT * FROM processing_jobs WHERE id='processing'").get();
  }
  assert.equal(job.state,'completed');
  assert.equal(calls.slice(0,-1).join(''),text);
  const listing=sql.prepare("SELECT * FROM listings WHERE id='job'").get(),payload=JSON.parse(listing.payload);
  assert.equal(listing.processed_hash,'hash');assert.equal(payload.aiProgress,undefined);assert.equal(payload.firstSeenAt,'first');
  assert.equal(payload.aiStatus,'summary_validated');assert.ok(text.includes(payload.summary[0].quote));
  assert.equal(payload.publishedAt,'2026-10-01T00:00:00Z');
  assert.equal(sql.prepare('SELECT COUNT(*) n FROM match_events').get().n,1);
  const count=calls.length;await processNotice(env);assert.equal(calls.length,count);
  assert.equal(sql.prepare('SELECT ai_jobs FROM daily_usage').get().ai_jobs,count);sql.close();
});

test('AI daily quota waits without discarding or repeating successful chunks',async()=>{
  const {sql,DB}=database(),calls=[];insertNotice(sql,'Başvuru koşulları. '.repeat(2000));
  const env={DB,AI:model(calls),AI_MODEL:'model',AI_DAILY_JOBS:'1'};
  await processNotice(env);await processNotice(env);
  const row=sql.prepare("SELECT * FROM processing_jobs WHERE id='processing'").get();
  assert.equal(row.state,'quota_wait');assert.equal(JSON.parse(row.input).aiProgress.index,1);assert.equal(calls.length,1);
  sql.exec("DELETE FROM daily_usage; UPDATE processing_jobs SET due_at='1970-01-01'");
  await processNotice(env);
  assert.equal(JSON.parse(sql.prepare("SELECT input FROM processing_jobs WHERE id='processing'").get().input).aiProgress.index,2);
  assert.equal(calls.length,2);sql.close();
});

test('temporary source detail failure preserves previously processed listing',async()=>{
  const {sql,DB}=database(),id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',listingId='kariyerkapisi:'+id;
  const payload={id:listingId,title:'Eski doğrulanmış ilan',text:'Doğrulanmış kaynak ayrıntısı.',summary:[{text:'Özet',quote:'Doğrulanmış kaynak ayrıntısı.'}]};
  sql.prepare("INSERT INTO listings(id,source_id,external_id,content_hash,processed_hash,first_seen,updated_at,recheck_at,payload) VALUES(?,'kariyerkapisi',?,'good','good','first','first','1970-01-01',?)").run(listingId,id,JSON.stringify(payload));
  sql.prepare("UPDATE sources SET pending_batch=?,next_due='1970-01-01' WHERE id='kariyerkapisi'").run(JSON.stringify([{id:listingId,externalId:id,title:'Yeni liste başlığı',deadline:null}]));
  const fetchBefore=globalThis.fetch;globalThis.fetch=async()=>new Response('',{status:522});
  try{await readSource({DB});}finally{globalThis.fetch=fetchBefore;}
  const after=sql.prepare('SELECT * FROM listings WHERE id=?').get(listingId);
  assert.equal(after.payload,JSON.stringify(payload));assert.equal(after.revision,1);assert.equal(after.processed_hash,'good');
  assert.match(sql.prepare("SELECT note FROM sources WHERE id='kariyerkapisi'").get().note,/önceki ilan bilgileri korunuyor/);
  assert.equal(sql.prepare('SELECT COUNT(*) n FROM processing_jobs').get().n,0);sql.close();
});

test('failed middle chunk retries that chunk and keeps completed progress',async()=>{
  const {sql,DB}=database(),calls=[];insertNotice(sql,'Kaynakta belirtilen başvuru şartı. '.repeat(1000));
  const env={DB,AI:model(calls),AI_MODEL:'model',AI_DAILY_JOBS:'20'};
  await processNotice(env);
  await processNotice({...env,AI:{async run(){throw new Error('model_unavailable');}}});
  let row=sql.prepare("SELECT * FROM processing_jobs WHERE id='processing'").get();
  assert.equal(row.error_code,'model_unavailable');assert.equal(JSON.parse(row.input).aiProgress.index,1);
  sql.exec("UPDATE processing_jobs SET due_at='1970-01-01'");await processNotice(env);
  row=sql.prepare("SELECT * FROM processing_jobs WHERE id='processing'").get();
  assert.equal(JSON.parse(row.input).aiProgress.index,2);assert.equal(row.attempts,0);assert.equal(calls.length,2);
  assert.equal(sql.prepare('SELECT ai_jobs FROM daily_usage').get().ai_jobs,3);sql.close();
});
