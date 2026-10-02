import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {DatabaseSync} from 'node:sqlite';
import {searchAnchorKeys,installationAnchorKeys,listingAnchorKeys,matchListing,validateCriteria,migrateFilters} from '../src/criteria.js';
import {fcmMessage} from '../src/fcm.js';
import {fetchRequest,sha256} from '../src/worker.js';
import {aiExtractionRevision,splitAiText,processNotice,readSource,flushOutbox,digestDue,expireListings,matchEvents,runScheduled,maintainRegistry,maintainCatalogue} from '../src/pipeline.js';

function database(){
  const sql=new DatabaseSync(':memory:');sql.exec('PRAGMA foreign_keys=ON');sql.exec(readFileSync(new URL('../migrations/0001_catalogue.sql',import.meta.url),'utf8'));
  sql.exec(readFileSync(new URL('../migrations/0002_digest_delivery.sql',import.meta.url),'utf8'));
  sql.exec(readFileSync(new URL('../migrations/0003_daily_digest.sql',import.meta.url),'utf8'));
  sql.exec(readFileSync(new URL('../migrations/0004_match_facets.sql',import.meta.url),'utf8'));
  sql.exec(readFileSync(new URL('../migrations/0005_notification_sequence.sql',import.meta.url),'utf8'));
  sql.exec(readFileSync(new URL('../migrations/0006_listing_first_seq.sql',import.meta.url),'utf8'));
  sql.exec(readFileSync(new URL('../migrations/0007_maintenance.sql',import.meta.url),'utf8'));
  sql.exec(readFileSync(new URL('../migrations/0008_notification_archive.sql',import.meta.url),'utf8'));
  sql.exec(readFileSync(new URL('../migrations/0009_terminal_payload_retention.sql',import.meta.url),'utf8'));
  sql.exec(readFileSync(new URL('../migrations/0010_education_alias_facets.sql',import.meta.url),'utf8'));sql.exec(readFileSync(new URL('../migrations/0011_catalogue_retention_floor.sql',import.meta.url),'utf8'));sql.exec(readFileSync(new URL('../migrations/0012_catalogue_sweep.sql',import.meta.url),'utf8'));
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
  assert.match(request.messages[0].content,/30-240 characters/);assert.equal(request.temperature,0);
  const {text}=JSON.parse(request.messages[1].content);calls.push(text);
  const quote=text.startsWith('[{')?JSON.parse(text)[0].quote:text.slice(0,80);
  return {response:JSON.stringify({summary:[0,1,2].map(i=>({text:quote.slice(i,60+i),quote})),conditions:[]})};
}};}

test('scheduled timestamp separates source, matching and delivery into three slots',async()=>{
  for(let minute=0;minute<6;minute++){
    const {sql,DB}=database(),queries=[];
    // No source is due: this check exercises real stages without network or model calls.
    sql.exec("UPDATE sources SET next_due='2999-01-01'");
    const original=DB.prepare;DB.prepare=query=>{queries.push(query);return original(query);};
    await runScheduled({DB,AI:{},FCM_PRIVATE_KEY:'fixture',FCM_CLIENT_EMAIL:'fixture'},minute*60000);
    const first=queries[0];
    if(minute%3===0){assert.match(first,/UPDATE listings SET active=0/);assert.ok(queries.some(q=>q.includes('UPDATE processing_jobs')));}
    if(minute%3===1)assert.match(first,/UPDATE match_events/);
    if(minute%3===2)assert.match(first,/UPDATE notification_outbox/);
    assert.ok(!queries.some(q=>q.includes('UPDATE match_events'))||minute%3===1);
    assert.ok(!queries.some(q=>q.includes('UPDATE notification_outbox'))||minute%3===2);
    sql.close();
  }
});

test('catalogue maintenance bounds work and preserves snapshot bases, first publication and latest sequence',async t=>{
  const {sql,DB}=database();t.after(()=>sql.close());
  const old='2026-01-01T00:00:00.000Z',now=new Date('2026-10-01T00:00:00.000Z');
  sql.prepare("INSERT INTO listings(id,source_id,external_id,content_hash,first_seen,updated_at,recheck_at,payload) VALUES('history','sbb','history','h',?,?,'later','{\"title\":\"Revision 1\"}')").run(old,old);
  for(let revision=2;revision<=70;revision++)sql.prepare("UPDATE listings SET revision=?,payload=json_object('title',?),updated_at=? WHERE id='history'").run(revision,'Revision '+revision,old);
  const original=DB.prepare,queries=[];DB.prepare=query=>{queries.push(query);return original(query);};
  await maintainCatalogue({DB},now);
  assert.ok(queries.length<=6);
  assert.equal(sql.prepare('SELECT COUNT(*) n FROM catalogue_changes').get().n,50);
  assert.deepEqual({...sql.prepare('SELECT floor,gc_after FROM catalogue_retention').get()},{floor:50,gc_after:20});
  assert.equal(sql.prepare('SELECT first_seq FROM listings').get().first_seq,1);
  const snapshot=await fetchRequest(new Request('https://api/api/v2/listings?watermark=50'),{DB},{});
  assert.equal(snapshot.status,200);assert.equal((await snapshot.json()).items[0].title,'Revision 50');
  assert.ok(queries.filter(q=>q.includes('LIMIT 50')).length===2);
  const plan=sql.prepare('EXPLAIN QUERY PLAN SELECT 1 FROM catalogue_changes WHERE listing_id=? AND seq>? AND seq<=?').all('history',1,50);
  assert.ok(plan.some(r=>r.detail.includes('catalogue_listing_seq')));
  for(let pass=0;pass<6;pass++){
    const before=sql.prepare('SELECT COUNT(*) n FROM catalogue_changes').get().n;
    await maintainCatalogue({DB},now);
    assert.ok(before-sql.prepare('SELECT COUNT(*) n FROM catalogue_changes').get().n<=20);
  }
  assert.deepEqual(sql.prepare('SELECT seq FROM catalogue_changes ORDER BY seq').all().map(r=>r.seq),[69,70]);
  assert.equal(sql.prepare('SELECT floor FROM catalogue_retention').get().floor,69);
  assert.equal(sql.prepare('SELECT MAX(seq) n FROM catalogue_changes').get().n,70);
  assert.equal(sql.prepare('SELECT first_seq FROM listings').get().first_seq,1);
  const delta=await fetchRequest(new Request('https://api/api/v2/changes?after=69'),{DB},{});
  assert.deepEqual((await delta.json()).changes.map(r=>r.seq),[70]);
  sql.prepare("UPDATE listings SET revision=71,payload='{\"title\":\"New after pruning\"}',updated_at=? WHERE id='history'").run(now.toISOString());
  await maintainCatalogue({DB},now);
  assert.equal(sql.prepare('SELECT first_seq FROM listings').get().first_seq,1);
  assert.equal(sql.prepare('SELECT floor FROM catalogue_retention').get().floor,70);
  assert.deepEqual(sql.prepare('SELECT seq FROM catalogue_changes ORDER BY seq').all().map(r=>r.seq),[70,71]);
});

test('catalogue floor stops at recent/invalid commits and keeps one base for every listing including tombstones',async t=>{
  const {sql,DB}=database();t.after(()=>sql.close());
  const now=new Date('2026-10-01T00:00:00.000Z'),old='2026-01-01T00:00:00.000Z';
  for(const id of ['old','closed','changed'])sql.prepare("INSERT INTO listings(id,source_id,external_id,content_hash,first_seen,updated_at,recheck_at,payload) VALUES(?,'sbb',?,'h',?,?,'later',json_object('title',?))").run(id,id,old,old,id);
  sql.prepare("UPDATE listings SET active=0,revision=2 WHERE id='closed'").run();
  sql.prepare("UPDATE listings SET revision=2,payload='{\"title\":\"Changed\"}' WHERE id='changed'").run();
  sql.prepare("UPDATE listings SET revision=3,payload='{\"title\":\"Recent\"}',updated_at=? WHERE id='changed'").run(now.toISOString());
  sql.prepare("UPDATE listings SET revision=4,payload='{\"title\":\"Later old timestamp\"}',updated_at=? WHERE id='changed'").run(old);
  await maintainCatalogue({DB},now);
  assert.equal(sql.prepare('SELECT floor FROM catalogue_retention').get().floor,5);
  assert.deepEqual(sql.prepare('SELECT seq FROM catalogue_changes ORDER BY seq').all().map(r=>r.seq),[1,4,5,6,7]);
  const snapshot=await fetchRequest(new Request('https://api/api/v2/listings?watermark=5'),{DB},{});
  assert.deepEqual((await snapshot.json()).items.map(r=>r.title),['Changed','old']);
  sql.exec("UPDATE catalogue_changes SET committed_at='not a timestamp' WHERE seq=6");
  await maintainCatalogue({DB},new Date('2027-10-01T00:00:00.000Z'));
  assert.equal(sql.prepare('SELECT floor FROM catalogue_retention').get().floor,5);
});

test('concurrent retention pass and failed sweep cannot lose the durable cleanup cursor',async t=>{
  const {sql,DB}=database();t.after(()=>sql.close());
  const old='2026-01-01T00:00:00.000Z',now=new Date('2026-10-01T00:00:00.000Z');
  sql.prepare("INSERT INTO listings(id,source_id,external_id,content_hash,first_seen,updated_at,recheck_at,payload) VALUES('one','sbb','one','h',?,?,'later','{}')").run(old,old);
  for(let i=2;i<=5;i++)sql.prepare("UPDATE listings SET revision=?,payload=json_object('revision',?) WHERE id='one'").run(i,i);
  const batch=DB.batch;
  DB.batch=async statements=>{sql.exec('UPDATE catalogue_retention SET gc_after=2');return batch(statements);};
  await maintainCatalogue({DB},now);
  assert.equal(sql.prepare('SELECT COUNT(*) n FROM catalogue_changes').get().n,5);
  assert.equal(sql.prepare('SELECT gc_after FROM catalogue_retention').get().gc_after,2);
  DB.batch=async statements=>{sql.exec('BEGIN');try{await statements[0].run();throw new Error('interrupted');}finally{sql.exec('ROLLBACK');}};
  await assert.rejects(maintainCatalogue({DB},now),/interrupted/);
  assert.equal(sql.prepare('SELECT COUNT(*) n FROM catalogue_changes').get().n,5);
  assert.equal(sql.prepare('SELECT gc_after FROM catalogue_retention').get().gc_after,2);
  DB.batch=batch;
  for(let i=0;i<3;i++)await maintainCatalogue({DB},now);
  assert.deepEqual(sql.prepare('SELECT seq FROM catalogue_changes ORDER BY seq').all().map(r=>r.seq),[4,5]);
});

test('maintenance bounds stale-owner deletion, protects send leases and reactivated owners',async t=>{
  const {sql,DB}=database();t.after(()=>sql.close());
  const now=new Date('2026-10-01T12:00:00Z'),cutoff=new Date(+now-120*86400000).toISOString();
  for(const [id,date,lease] of [['stale',cutoff,null],['active',now.toISOString(),null],['sending',cutoff,'2026-10-01T12:01:00Z']]) {
    sql.prepare("INSERT INTO installations(id,secret_hash,token,platform,preferences,updated_at,send_lease_until) VALUES(?,'hash','token','android','{}',?,?)").run(id,date,lease);
    sql.prepare("INSERT INTO saved_searches VALUES(?,'s','Mine','{}','instant',0)").run(id);
  }
  for(let i=0;i<25;i++)sql.prepare("INSERT INTO notification_outbox(id,installation_id,listing_id,payload,due_at,created_at) VALUES(?,'stale',?,'{}','now','now')").run('event'+i,'listing'+i);
  for(let i=0;i<55;i++)sql.prepare("INSERT INTO installation_facets VALUES(?,'stale')").run('facet'+i);
  await maintainRegistry({DB},now);
  assert.equal(sql.prepare("SELECT enabled FROM installations WHERE id='stale'").get().enabled,0);
  assert.equal(sql.prepare('SELECT COUNT(*) n FROM notification_outbox').get().n,5);
  assert.equal(sql.prepare('SELECT COUNT(*) n FROM installation_facets').get().n,5);
  assert.equal(sql.prepare('SELECT COUNT(*) n FROM saved_searches').get().n,3);
  sql.prepare("UPDATE installations SET enabled=1,updated_at=? WHERE id='stale'").run(now.toISOString());
  await maintainRegistry({DB},now);
  assert.equal(sql.prepare('SELECT COUNT(*) n FROM installations').get().n,3);
  assert.equal(sql.prepare('SELECT COUNT(*) n FROM notification_outbox').get().n,5);
  sql.prepare("UPDATE installations SET updated_at=? WHERE id='stale'").run(cutoff);
  await maintainRegistry({DB},now);
  assert.deepEqual(sql.prepare('SELECT id FROM installations ORDER BY id').all().map(x=>x.id),['active','sending']);
  assert.equal(sql.prepare('SELECT COUNT(*) n FROM saved_searches').get().n,2);
  assert.equal(sql.prepare('SELECT COUNT(*) n FROM notification_outbox').get().n,0);
  assert.equal(sql.prepare('SELECT COUNT(*) n FROM installation_facets').get().n,0);
});

test('hourly maintenance expires bounded counters while preserving current budget and pipeline slots',async t=>{
  const {sql,DB}=database();t.after(()=>sql.close());
  for(let i=0;i<101;i++)sql.prepare("INSERT INTO rate_limits VALUES(?,1,'2000-01-01')").run('expired'+i);
  sql.exec("INSERT INTO rate_limits VALUES('active',2,'2999-01-01'); INSERT INTO daily_usage VALUES('2000-01-01',20),('2999-01-01',20)");
  const prepare=DB.prepare,queries=[];DB.prepare=query=>{queries.push(query);return prepare(query);};
  await runScheduled({DB},59*60000);
  assert.equal(queries.length,6);
  assert.equal(sql.prepare('SELECT COUNT(*) n FROM rate_limits').get().n,2);
  assert.deepEqual(sql.prepare('SELECT day,ai_jobs FROM daily_usage').all().map(x=>({...x})),[{day:'2999-01-01',ai_jobs:20}]);
  const plan=sql.prepare('EXPLAIN QUERY PLAN SELECT key FROM rate_limits WHERE expires_at<=? ORDER BY expires_at,key LIMIT 100').all('now');
  assert.ok(plan.some(x=>x.detail.includes('rate_limit_expiry')));
});

test('heartbeat between stale selection and deletion protects every child record',async t=>{
  const {sql,DB}=database();t.after(()=>sql.close());
  const now=new Date('2026-10-01T12:00:00Z');
  sql.exec("INSERT INTO installations(id,secret_hash,token,platform,preferences,updated_at) VALUES('owner','hash','token','android','{}','2000-01-01'); INSERT INTO saved_searches VALUES('owner','s','Mine','{}','instant',0); INSERT INTO installation_facets VALUES('*','owner'); INSERT INTO notification_outbox(id,installation_id,listing_id,payload,due_at,created_at) VALUES('event','owner','listing','{}','now','now')");
  const batch=DB.batch;let refreshed=false;DB.batch=async statements=>{
    if(!refreshed){refreshed=true;sql.prepare("UPDATE installations SET updated_at=? WHERE id='owner'").run(now.toISOString());}
    return batch(statements);
  };
  await maintainRegistry({DB},now);
  for(const table of ['installations','saved_searches','installation_facets','notification_outbox'])assert.equal(sql.prepare('SELECT COUNT(*) n FROM '+table).get().n,1);
  assert.equal(sql.prepare('SELECT enabled FROM installations').get().enabled,1);
});

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

test('account AI quota preserves progress and retry allowance, and stops other jobs today',async()=>{
  const {sql,DB}=database(),calls=[];insertNotice(sql,'Kaynakta belirtilen başvuru şartı. '.repeat(1000));
  const env={DB,AI:model(calls),AI_MODEL:'model',AI_DAILY_JOBS:'20'};
  await processNotice(env);
  const input=sql.prepare("SELECT input FROM processing_jobs WHERE id='processing'").get().input;
  sql.exec("UPDATE processing_jobs SET attempts=4");
  let rejected=0;
  await processNotice({...env,AI:{async run(){rejected++;throw new Error('3036: Account limited');}}});
  const row=sql.prepare("SELECT * FROM processing_jobs WHERE id='processing'").get();
  assert.equal(row.state,'quota_wait');assert.equal(row.attempts,4);assert.equal(row.lease_until,null);
  assert.equal(row.error_code,'ai_account_quota');assert.equal(row.input,input);
  assert.ok(Date.parse(row.due_at)>Date.now());assert.match(row.due_at,/T00:00:00\.000Z$/);
  assert.equal(sql.prepare('SELECT ai_jobs FROM daily_usage').get().ai_jobs,20);
  sql.prepare("INSERT INTO processing_jobs(id,listing_id,input_hash,input,due_at) VALUES('other','job','other',?,'1970-01-01')").run(input);
  // Make this a current separate revision, so the hash guard cannot hide an extra provider call.
  sql.exec("UPDATE listings SET content_hash='other'");
  await processNotice({...env,AI:{async run(){rejected++;throw new Error('must_not_call');}}});
  assert.equal(rejected,1);
  const other=sql.prepare("SELECT * FROM processing_jobs WHERE id='other'").get();
  assert.equal(other.state,'quota_wait');assert.equal(other.attempts,0);assert.equal(other.error_code,'ai_daily_budget');
  // Simulate tomorrow's budget reset and resume the original chunk, never chunk zero.
  sql.exec("DELETE FROM daily_usage; UPDATE listings SET content_hash='hash'; UPDATE processing_jobs SET due_at='1970-01-01' WHERE id='processing'");
  await processNotice(env);
  assert.equal(JSON.parse(sql.prepare("SELECT input FROM processing_jobs WHERE id='processing'").get().input).aiProgress.index,2);
  assert.equal(calls.length,2);sql.close();
});

test('partial AI jobs pin the model across configuration changes and publish provenance',async t=>{
  const {sql,DB}=database();t.after(()=>sql.close());const calls=[],models=[];
  insertNotice(sql,'Başvuru koşulları kaynak metninde açıklanmaktadır. '.repeat(600));
  const AI={async run(name,request,options){models.push(name);return model(calls).run(name,request,options);}};
  await processNotice({DB,AI,AI_MODEL:'original-model'});
  const contract=JSON.parse(sql.prepare("SELECT input FROM processing_jobs WHERE id='processing'").get().input).aiContract;
  assert.deepEqual(contract,{provider:'cloudflare',model:'original-model',extractionRevision:aiExtractionRevision});
  for(let i=0;i<10&&sql.prepare("SELECT state FROM processing_jobs WHERE id='processing'").get().state!=='completed';i++)await processNotice({DB,AI,AI_MODEL:'replacement-model'});
  assert.ok(models.length>1);assert.ok(models.every(name=>name==='original-model'));
  assert.equal(sql.prepare("SELECT state FROM processing_jobs WHERE id='processing'").get().state,'completed');
  const payload=JSON.parse(sql.prepare("SELECT payload FROM listings WHERE id='job'").get().payload);
  assert.deepEqual(payload.aiProvenance,contract);assert.equal(payload.aiContract,undefined);assert.equal(payload.aiProgress,undefined);
});

test('unknown or incompatible partial AI revisions preserve work without spending quota',async t=>{
  for(const incompatible of [false,true]){
    const {sql,DB}=database();t.after(()=>sql.close());insertNotice(sql,'Başvuru koşulları kaynak metninde açıklanmaktadır. '.repeat(600));
    const progress={index:1,summaries:[[{text:'Kalıcı kaynak alıntısı korunur.',quote:'Kalıcı kaynak alıntısı korunur.'}]],conditions:[[]]};
    sql.prepare("UPDATE processing_jobs SET input=json_set(input,'$.aiProgress',json(?)) WHERE id='processing'").run(JSON.stringify(progress));
    if(incompatible)sql.prepare("UPDATE processing_jobs SET input=json_set(input,'$.aiContract',json(?)) WHERE id='processing'").run(JSON.stringify({provider:'cloudflare',model:'original',extractionRevision:aiExtractionRevision+1}));
    const before=sql.prepare("SELECT input FROM processing_jobs WHERE id='processing'").get().input;
    let calls=0;await processNotice({DB,AI_MODEL:'replacement',AI:{async run(){calls++;throw new Error('must_not_call');}}});
    const job=sql.prepare("SELECT * FROM processing_jobs WHERE id='processing'").get();
    assert.equal(job.state,'failed');assert.equal(job.lease_until,null);assert.equal(job.error_code,incompatible?'ai_revision_mismatch':'ai_revision_unknown');
    assert.equal(job.input,before);assert.equal(calls,0);assert.equal(sql.prepare('SELECT COUNT(*) n FROM daily_usage').get().n,0);
    assert.equal(sql.prepare("SELECT processed_hash FROM listings WHERE id='job'").get().processed_hash,null);
  }
});

test('AI capacity errors use bounded retry without losing completed chunks',async()=>{
  const {sql,DB}=database(),calls=[];insertNotice(sql,'Kaynakta belirtilen başvuru şartı. '.repeat(1000));
  const env={DB,AI:model(calls),AI_MODEL:'model',AI_DAILY_JOBS:'20'};
  await processNotice(env);
  const input=sql.prepare("SELECT input FROM processing_jobs WHERE id='processing'").get().input;
  for(let attempt=1;attempt<=5;attempt++){
    sql.exec("UPDATE processing_jobs SET due_at='1970-01-01'");
    await processNotice({...env,AI:{async run(){throw new Error('3040: Out of capacity');}}});
    const row=sql.prepare("SELECT * FROM processing_jobs WHERE id='processing'").get();
    assert.equal(row.state,attempt===5?'failed':'pending');assert.equal(row.attempts,attempt);
    assert.equal(row.error_code,'ai_busy');assert.equal(row.input,input);assert.equal(row.lease_until,null);
    assert.ok(Date.parse(row.due_at)>Date.now());
  }
  assert.equal(sql.prepare('SELECT ai_jobs FROM daily_usage').get().ai_jobs,6);
  await processNotice(env);assert.equal(calls.length,1);sql.close();
});

test('source slots fetch at most one detail and resume every persisted batch entry',async()=>{
  const {sql,DB}=database(),batch=Array.from({length:4},(_,i)=>({id:'kariyerkapisi:'+i,externalId:'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa'+i,title:'İlan '+i,deadline:null}));
  sql.prepare("UPDATE sources SET pending_batch=?,batch_offset=0,next_due='1970-01-01',last_success='2026-01-01' WHERE id='kariyerkapisi'").run(JSON.stringify(batch));
  sql.exec("UPDATE sources SET next_due='2999-01-01' WHERE id!='kariyerkapisi'");
  const before=globalThis.fetch;let fetched=0;globalThis.fetch=async()=>{fetched++;return new Response('',{status:522});};
  try{
    for(let i=0;i<batch.length;i++){
      await readSource({DB});const source=sql.prepare("SELECT * FROM sources WHERE id='kariyerkapisi'").get();
      assert.equal(fetched,i+1);assert.equal(sql.prepare('SELECT COUNT(*) n FROM listings').get().n,i+1);assert.equal(source.lease_until,null);
      if(i<batch.length-1){assert.equal(source.batch_offset,i+1);assert.equal(source.pending_batch,JSON.stringify(batch));assert.equal(source.last_success,'2026-01-01');assert.equal(source.state,'processing');}
      else{assert.equal(source.batch_offset,0);assert.equal(source.pending_batch,null);assert.equal(source.state,'ok');assert.notEqual(source.last_success,'2026-01-01');}
    }
    await readSource({DB});assert.equal(fetched,4); // Completed source waits its polling interval.
  }finally{globalThis.fetch=before;sql.close();}
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

function notifications(t,count=1,{mode='digest',created='2026-10-01T09:00:00.000Z',preferences={quietStart:22,quietEnd:8,cap:6}}={}) {
  const {sql,DB}=database();t.after(()=>sql.close());
  sql.prepare("INSERT INTO installations(id,secret_hash,token,platform,preferences,updated_at) VALUES('device','hash','oldtoken','android',?,'now')").run(JSON.stringify(preferences));
  sql.prepare("INSERT INTO saved_searches VALUES('device','search','Memur',?, ?,0)").run(JSON.stringify({version:2,keyword:'Memur'}),mode);
  for(let i=0;i<count;i++) {
    const id='notice'+String(i).padStart(2,'0'),payload={id,title:'Memur '+i,url:'https://example.gov.tr/'+id,deadline:null};
    sql.prepare("INSERT INTO listings(id,source_id,external_id,content_hash,first_seen,updated_at,recheck_at,payload) VALUES(?,'sbb',?,'hash','first','now','later',?)").run(id,id,JSON.stringify(payload));
    sql.prepare("INSERT INTO notification_outbox(id,installation_id,listing_id,payload,due_at,created_at) VALUES(?,'device',?,?,?,?)").run('event'+i,id,JSON.stringify({...payload,revision:1,mode,preferencesVersion:1,searchIds:['search']}),created,created);
  }
  const env={DB,FCM_PRIVATE_KEY:'fixture-not-a-key',FCM_CLIENT_EMAIL:'fixture@example.com'},calls=[];
  const send=async(e,token,event)=>{calls.push({token,event});return {state:'accepted',id:'fcm/accepted'};};
  return {sql,env,calls,send};
}

test('digest waits for fixed Istanbul 18:00 rather than perpetually moving due date',async t=>{
  const {sql,env,calls,send}=notifications(t,3);
  assert.equal(digestDue(new Date('2026-10-01T14:00:00Z')),'2026-10-01T15:00:00.000Z');
  assert.equal(digestDue(new Date('2026-10-01T16:00:00Z')),'2026-10-02T15:00:00.000Z');
  await flushOutbox(env,{send,now:new Date('2026-10-01T14:00:00Z')});
  assert.equal(calls.length,0);
  assert.equal(sql.prepare("SELECT due_at FROM notification_outbox WHERE id='event0'").get().due_at,'2026-10-01T15:00:00.000Z');
  await flushOutbox(env,{send,now:new Date('2026-10-01T15:00:00Z')});
  assert.equal(calls.length,1);assert.equal(calls[0].event.digestCount,3);assert.equal(calls[0].event.mode,'digest');
  assert.equal(sql.prepare("SELECT COUNT(*) n FROM notification_outbox WHERE state='accepted'").get().n,3);
  assert.equal(sql.prepare('SELECT sent_count FROM installations').get().sent_count,0);
  assert.equal(sql.prepare('SELECT digest_day FROM installations').get().digest_day,'2026-10-01');
});

test('digest retries frozen membership and event ID; late arrivals form later groups',async t=>{
  const {sql,env,calls,send}=notifications(t,3);
  const now=new Date('2026-10-01T15:00:00Z');let failed;
  await flushOutbox(env,{now,send:async(e,token,event)=>{failed=event;throw new Error('fcm_timeout');}});
  assert.equal(sql.prepare("SELECT COUNT(*) n FROM notification_outbox WHERE delivery_id='event0' AND state='pending'").get().n,3);
  const original=sql.prepare("SELECT * FROM notification_outbox WHERE id='event2'").get();
  sql.prepare("INSERT INTO notification_outbox(id,installation_id,listing_id,payload,due_at,created_at) VALUES('late','device','late',?,'2026-10-01T15:00:00.000Z',?)").run(original.payload,original.created_at);
  await flushOutbox(env,{send,now:new Date('2026-10-01T15:06:00Z')});
  // The late independent leader can run first; frozen group still has three members.
  await flushOutbox(env,{send,now:new Date('2026-10-01T15:06:00Z')});
  const delivered=calls.find(x=>x.event.eventId===failed.eventId);
  assert.ok(delivered);assert.equal(delivered.event.digestCount,3);
  assert.equal(sql.prepare("SELECT state FROM notification_outbox WHERE id='late'").get().state,'expired');
  assert.equal(sql.prepare("SELECT COUNT(*) n FROM notification_outbox WHERE state='accepted'").get().n,3);
});

test('current eligibility, deadline and deletion are rechecked before FCM',async t=>{
  const {sql,env,calls,send}=notifications(t,4);
  sql.exec("UPDATE listings SET deadline='2026-10-01T14:00:00Z',payload=json_set(payload,'$.deadline','2026-10-01T14:00:00Z') WHERE id='notice00'; UPDATE listings SET active=0 WHERE id='notice01'; UPDATE listings SET payload=json_set(payload,'$.title','Başka pozisyon') WHERE id='notice02'; UPDATE listings SET revision=8 WHERE id='notice03'");
  await flushOutbox(env,{send,now:new Date('2026-10-01T15:00:00Z')});
  assert.equal(calls.length,1);assert.equal(calls[0].event.digestCount,1);assert.equal(calls[0].event.revision,8);
  const states=sql.prepare('SELECT id,state FROM notification_outbox ORDER BY id').all();
  assert.deepEqual(states.map(x=>x.state),['expired','expired','cancelled','accepted']);
});

test('quiet hours and caps defer to real next calendar day; bounded digest leaves remainder',async t=>{
  const {sql,env,calls,send}=notifications(t,12,{preferences:{quietStart:17,quietEnd:20,cap:1}});
  await flushOutbox(env,{send,now:new Date('2026-10-01T15:00:00Z')});
  assert.equal(calls.length,0);assert.equal(sql.prepare("SELECT due_at FROM notification_outbox WHERE id='event0'").get().due_at,'2026-10-01T17:00:00.000Z');
  await flushOutbox(env,{send,now:new Date('2026-10-01T17:00:00Z')});
  assert.equal(calls[0].event.digestCount,10);
  await flushOutbox(env,{send,now:new Date('2026-10-01T17:01:00Z')});
  assert.equal(calls.length,1);assert.equal(sql.prepare("SELECT COUNT(*) n FROM notification_outbox WHERE state='pending'").get().n,2);
  const deferred=sql.prepare("SELECT due_at FROM notification_outbox WHERE state='pending' ORDER BY due_at DESC LIMIT 1").get();
  assert.equal(deferred.due_at,'2026-10-02T17:00:00.000Z');
});

test('preference change and invalid tokens cancel jobs, rotated token is retained',async t=>{
  const {sql,env,calls,send}=notifications(t,2,{mode:'instant'});
  sql.exec('UPDATE installations SET version=2');
  await flushOutbox(env,{send,now:new Date('2026-10-01T15:00:00Z')});assert.equal(calls.length,0);
  assert.equal(sql.prepare("SELECT state FROM notification_outbox WHERE id='event0'").get().state,'cancelled');
  sql.exec('UPDATE installations SET version=1');
  await flushOutbox(env,{now:new Date('2026-10-01T15:00:00Z'),send:async()=>{sql.exec("UPDATE installations SET token='newtoken'");return {state:'invalid_token'};}});
  assert.equal(sql.prepare('SELECT enabled FROM installations').get().enabled,1);
  await flushOutbox(env,{send,now:new Date('2026-10-01T15:04:00Z')});
  assert.equal(calls[0].token,'newtoken');
});

test('digest FCM payload uses stable event tag and deadline-bounded TTL',()=>{
  const event={id:'notice',eventId:'stable',revision:8,url:'https://example.gov.tr/notice',title:'Memur',mode:'digest',digestCount:3,deadline:'2026-10-01T15:05:00Z'};
  const {message}=fcmMessage('token',event,new Date('2026-10-01T15:00:00Z'));
  assert.equal(message.data.kind,'digest');assert.equal(message.data.revision,'8');assert.equal(message.data.count,'3');
  assert.equal(message.android.ttl,'300s');assert.equal(message.android.notification.tag,'stable');
  assert.match(message.notification.body,/3 yeni ilan/);
  assert.equal(message.apns.headers['apns-expiration'],String(Date.parse(event.deadline)/1000));
  assert.equal(JSON.stringify(message).includes('searchIds'),false);
});

test('parallel sends for one installation cannot exceed its daily cap',async t=>{
  const {sql,env,calls,send}=notifications(t,2,{mode:'instant',preferences:{quietStart:22,quietEnd:8,cap:1}});
  let finish,started;
  const waiting=new Promise(resolve=>{finish=resolve;}),ready=new Promise(resolve=>{started=resolve;});
  const first=flushOutbox(env,{now:new Date('2026-10-01T15:00:00Z'),send:async(...args)=>{started();await waiting;return send(...args);}});
  await ready;
  await flushOutbox(env,{send,now:new Date('2026-10-01T15:00:01Z')});
  assert.equal(calls.length,0);
  finish();await first;
  await flushOutbox(env,{send,now:new Date('2026-10-01T15:04:00Z')});
  assert.equal(calls.length,1);assert.equal(sql.prepare('SELECT sent_count FROM installations').get().sent_count,1);
  const pending=sql.prepare("SELECT due_at FROM notification_outbox WHERE state='pending'").get();
  assert.equal(pending.due_at,'2026-10-02T05:00:00.000Z');
});

test('crashed digest lease recovers once, and terminal failure keeps its audit rows',async t=>{
  const {sql,env,calls,send}=notifications(t,2);
  sql.exec("UPDATE notification_outbox SET delivery_id='event0',state='leased',lease_until='2026-10-01T14:59:00.000Z'");
  await flushOutbox(env,{send,now:new Date('2026-10-01T15:00:00Z')});
  assert.equal(calls.length,1);assert.equal(calls[0].event.digestCount,2);
  sql.exec("UPDATE notification_outbox SET state='pending',attempts=7,due_at='2026-10-01T15:00:00.000Z'");
  await flushOutbox(env,{now:new Date('2026-10-02T15:00:00Z'),send:async()=>{throw new Error('fcm_http_503');}});
  assert.equal(sql.prepare("SELECT COUNT(*) n FROM notification_outbox WHERE state='failed' AND attempts=8").get().n,2);
});

test('expired catalogue produces immutable tombstones and no matching fanout',async t=>{
  const {sql,env,calls,send}=notifications(t,2);
  sql.exec("UPDATE listings SET deadline='1970-01-01T00:00:00.000Z',processed_hash='hash' WHERE id='notice00'");
  await expireListings(env);
  assert.equal(sql.prepare("SELECT active FROM listings WHERE id='notice00'").get().active,0);
  assert.equal(sql.prepare("SELECT operation FROM catalogue_changes WHERE listing_id='notice00' ORDER BY seq DESC LIMIT 1").get().operation,'tombstone');
  await matchEvents(env);
  assert.equal(sql.prepare('SELECT state FROM match_events').get().state,'expired');
  await flushOutbox(env,{send,now:new Date('2026-10-01T15:00:00Z')});
  assert.equal(calls[0].event.digestCount,1);
  assert.equal(sql.prepare("SELECT state FROM notification_outbox WHERE listing_id='notice00'").get().state,'expired');
});

test('expired processing jobs do not consume an AI call',async t=>{
  const {sql,DB}=database();t.after(()=>sql.close());insertNotice(sql,'Başvuru koşulları kaynak metnidir.');
  sql.exec("UPDATE listings SET deadline='1970-01-01T00:00:00Z'");
  let calls=0;await processNotice({DB,AI:{async run(){calls++;throw new Error('must_not_call');}}});
  assert.equal(calls,0);assert.equal(sql.prepare('SELECT state FROM processing_jobs').get().state,'superseded');
  assert.equal(sql.prepare('SELECT COUNT(*) n FROM daily_usage').get().n,0);
});

test('in-progress source refresh never emits unsupported v2 metadata state',async t=>{
  const {sql,DB}=database();t.after(()=>sql.close());
  sql.exec("UPDATE sources SET state='processing',last_success='2026-10-01T00:00:00Z' WHERE id='kariyerkapisi'");
  const response=await fetchRequest(new Request('https://api/api/v2/meta'),{DB},{});
  assert.equal(response.status,200);
  const {sources}=await response.json();
  assert.equal(sources.find(x=>x.id==='kariyerkapisi').state,'ok');
  assert.ok(sources.every(x=>['ok','failed','blocked','disabled'].includes(x.state)));
});

test('opt-out between matching and sending cancels a grouped digest before FCM',async t=>{
  const {sql,env,calls,send}=notifications(t,2);
  let reads=0;const prepare=env.DB.prepare;
  env.DB.prepare=query=>{
    if(query==='SELECT * FROM installations WHERE id=? AND enabled=1'&&++reads===2)sql.exec('UPDATE installations SET enabled=0');
    return prepare(query);
  };
  await flushOutbox(env,{send,now:new Date('2026-10-01T15:00:00Z')});
  assert.equal(calls.length,0);
  assert.equal(sql.prepare("SELECT COUNT(*) n FROM notification_outbox WHERE state='cancelled'").get().n,2);
  assert.equal(sql.prepare('SELECT send_lease_until FROM installations').get().send_lease_until,null);
});

test('notification history keeps per-row ID and digest delivery ID separate',async t=>{
  const {sql,DB}=database();t.after(()=>sql.close());const id='a'.repeat(32),secret='b'.repeat(64);
  sql.prepare("INSERT INTO installations(id,secret_hash,token,platform,preferences,updated_at) VALUES(?,?,'token','android','{}','now')").run(id,await sha256(secret));
  sql.prepare("INSERT INTO notification_outbox(id,installation_id,listing_id,payload,due_at,created_at,delivery_id) VALUES('event',?,'listing',?,'now','now','group')").run(id,JSON.stringify({eventId:'must-not-override',title:'Memur',mode:'digest'}));
  sql.exec("UPDATE notification_outbox SET state='accepted' WHERE id='event'");
  const response=await fetchRequest(new Request('https://api/api/v2/installations/'+id+'/notifications',{headers:{Authorization:'Bearer '+secret}}),{DB},{});
  assert.equal(response.status,200);const body=await response.json();
  assert.equal(body.items[0].eventId,'event');assert.equal(body.items[0].deliveryId,'group');
});

test('accepted history follows acceptance order, pins pages and bounds source payloads',async t=>{
  const {sql,DB}=database();t.after(()=>sql.close());const id='a'.repeat(32),secret='b'.repeat(64),other='c'.repeat(32);
  for(const owner of [id,other])sql.prepare("INSERT INTO installations(id,secret_hash,token,platform,preferences,updated_at) VALUES(?,?,'token','android','{}','now')").run(owner,await sha256(owner===id?secret:'d'.repeat(64)));
  const add=(key,owner=id)=>sql.prepare("INSERT INTO notification_outbox(id,installation_id,listing_id,payload,due_at,created_at) VALUES(?,?,?,?,'now','2000-01-01')").run(key,owner,key,JSON.stringify({title:'Memur',url:'https://example.gov.tr',text:'x'.repeat(2000000),preferencesVersion:10,searchIds:['search'],mode:'instant'}));
  const get=async(query='',bearer=secret)=>fetchRequest(new Request('https://api/api/v2/installations/'+id+'/notifications'+query,{headers:{Authorization:'Bearer '+bearer}}),{DB},{});
  for(const key of ['z','y','a','pending'])add(key);add('private',other);
  sql.exec("UPDATE notification_outbox SET state='accepted' WHERE id='z'; UPDATE notification_outbox SET state='accepted' WHERE id='y'; UPDATE notification_outbox SET state='accepted' WHERE id='private'");
  const firstResponse=await get('?limit=1'),firstText=await firstResponse.text(),first=JSON.parse(firstText);
  assert.equal(firstResponse.headers.get('cache-control'),'no-store');assert.ok(firstText.length<5000);
  assert.equal(first.items[0].eventId,'z');assert.equal(first.items[0].text,undefined);assert.equal(first.items[0].preferencesVersion,undefined);
  assert.deepEqual(first.items[0].searchIds,['search']);assert.equal(first.next,'1');assert.equal(first.watermark,2);
  sql.exec("UPDATE notification_outbox SET state='accepted' WHERE id='a'");
  const second=await(await get('?after='+first.next+'&watermark='+first.watermark+'&limit=1')).json();
  assert.deepEqual(second.items.map(x=>x.eventId),['y']);assert.equal(second.appliedThrough,2);assert.equal(second.hasMore,false);
  const newer=await(await get('?after='+second.appliedThrough)).json();
  assert.deepEqual(newer.items.map(x=>x.eventId),['a']);assert.equal(newer.items[0].seq,4);
  const sequence=sql.prepare('SELECT seq FROM notification_sequence').get().seq;
  sql.exec("UPDATE notification_outbox SET state='accepted' WHERE id='a'");
  assert.equal(sql.prepare('SELECT seq FROM notification_sequence').get().seq,sequence);
  assert.equal((await get('', 'e'.repeat(64))).status,401);
  for(const query of ['?after=z','?after=-1','?after=9007199254740992','?watermark=999','?watermark=-1'])assert.equal((await get(query)).status,400);
  assert.equal((await get('?after=999')).status,409);
  const plan=sql.prepare('EXPLAIN QUERY PLAN SELECT id FROM notification_outbox WHERE installation_id=? AND history_seq>? AND history_seq<=? ORDER BY history_seq LIMIT 10').all(id,0,4);
  assert.ok(plan.some(x=>x.detail.includes('installation_history_seq')));
  sql.prepare('DELETE FROM installations WHERE id=?').run(id);
  assert.equal(sql.prepare('SELECT COUNT(*) n FROM notification_outbox WHERE installation_id=?').get(id).n,0);
});

test('archived history preserves pinned cursors and later acceptances',async t=>{
  const {sql,DB}=database();t.after(()=>sql.close());const id='a'.repeat(32),secret='b'.repeat(64);
  sql.prepare("INSERT INTO installations(id,secret_hash,token,platform,preferences,updated_at) VALUES(?,?,'token','android','{}','2999-01-01')").run(id,await sha256(secret));
  const add=key=>sql.prepare("INSERT INTO notification_outbox(id,installation_id,listing_id,payload,state,due_at,created_at) VALUES(?,?,?,?,'accepted','now','now')").run(key,id,key,JSON.stringify({title:'Memur',url:'https://example.gov.tr/'+key,mode:'instant',searchIds:['s'],revision:1}));
  const get=query=>fetchRequest(new Request('https://api/api/v2/installations/'+id+'/notifications'+query,{headers:{Authorization:'Bearer '+secret}}),{DB},{});
  add('first');add('second');
  const first=await(await get('?limit=1')).json();assert.equal(first.watermark,2);assert.equal(first.next,'1');
  sql.exec("UPDATE notification_outbox SET accepted_at='2000-01-01' WHERE history_seq<=2");
  add('new');
  await maintainRegistry({DB},new Date());
  const pinnedResponse=await get('?after=1&watermark=2&limit=1');assert.equal(pinnedResponse.status,200);
  const pinned=await pinnedResponse.json();assert.deepEqual(pinned.items,[]);assert.equal(pinned.appliedThrough,2);assert.equal(pinned.hasMore,false);
  const newer=await(await get('?after=2')).json();assert.deepEqual(newer.items.map(x=>x.eventId),['new']);assert.equal(newer.appliedThrough,3);
  assert.equal((await get('?after=3')).status,200);
  assert.equal(sql.prepare('SELECT seq FROM notification_sequence').get().seq,3);
});

test('history archival bounds payload writes, preserves dedupe and incomplete digest members',async t=>{
  const {sql,env}=notifications(t,22),{DB}=env;
  sql.exec("UPDATE notification_outbox SET state='accepted'; UPDATE notification_outbox SET accepted_at='2000-01-01',fcm_id='provider'; UPDATE notification_outbox SET delivery_id='group' WHERE id='event0'; INSERT INTO notification_outbox(id,installation_id,listing_id,payload,due_at,created_at,delivery_id) VALUES('pending','device','pending','{}','now','now','group')");
  await maintainRegistry({DB},new Date());
  assert.equal(sql.prepare("SELECT COUNT(*) n FROM notification_outbox WHERE state='archived'").get().n,20);
  assert.equal(sql.prepare("SELECT state FROM notification_outbox WHERE id='event0'").get().state,'accepted');
  await maintainRegistry({DB},new Date());
  assert.equal(sql.prepare("SELECT COUNT(*) n FROM notification_outbox WHERE state='archived' AND payload='{}' AND fcm_id IS NULL").get().n,21);
  sql.exec("INSERT OR IGNORE INTO notification_outbox(id,installation_id,listing_id,payload,due_at,created_at) VALUES('duplicate','device','notice01','{}','now','now')");
  assert.equal(sql.prepare("SELECT COUNT(*) n FROM notification_outbox WHERE id='duplicate'").get().n,0);
  assert.equal(sql.prepare("SELECT state FROM notification_outbox WHERE id='pending'").get().state,'pending');
  assert.equal(sql.prepare('SELECT seq FROM notification_sequence').get().seq,22);
  const plan=sql.prepare("EXPLAIN QUERY PLAN SELECT id FROM notification_outbox INDEXED BY outbox_accepted_retention WHERE state='accepted' AND accepted_at<=? ORDER BY accepted_at,id LIMIT 20").all('now');
  assert.ok(plan.some(x=>x.detail.includes('outbox_accepted_retention')));
});

test('terminal payload retention is bounded, preserves status/dedupe and skips live digest groups',async t=>{
  const {sql,env}=notifications(t,25),{DB}=env;
  const now=new Date('2026-10-02T00:00:00Z'),cutoff=new Date(+now-90*86400000).toISOString();
  sql.exec("UPDATE notification_outbox SET state='failed',created_at='2000-01-01',fcm_id='provider',error_code='fixture_error'; UPDATE notification_outbox SET state='cancelled' WHERE id='event1'; UPDATE notification_outbox SET state='expired' WHERE id='event2'; UPDATE notification_outbox SET delivery_id='group' WHERE id IN ('event0','event24'); UPDATE notification_outbox SET state='pending' WHERE id IN ('event22','event24'); UPDATE notification_outbox SET state='leased',lease_until='2999-01-01' WHERE id='event23'");
  sql.prepare("UPDATE notification_outbox SET created_at=? WHERE id='event20'").run(cutoff);
  sql.prepare("UPDATE notification_outbox SET created_at=? WHERE id='event21'").run(new Date(Date.parse(cutoff)+1).toISOString());
  await maintainRegistry({DB},now);
  assert.equal(sql.prepare("SELECT COUNT(*) n FROM notification_outbox WHERE payload='{}'").get().n,20);
  for(const id of ['event0','event21','event22','event23','event24'])assert.notEqual(sql.prepare('SELECT payload FROM notification_outbox WHERE id=?').get(id).payload,'{}',id);
  assert.equal(sql.prepare("SELECT state FROM notification_outbox WHERE id='event1'").get().state,'cancelled');
  assert.equal(sql.prepare("SELECT state FROM notification_outbox WHERE id='event2'").get().state,'expired');
  assert.equal(sql.prepare("SELECT COUNT(*) n FROM notification_outbox WHERE payload='{}' AND fcm_id IS NULL AND error_code='fixture_error'").get().n,20);
  sql.exec("INSERT OR IGNORE INTO notification_outbox(id,installation_id,listing_id,payload,due_at,created_at) VALUES('duplicate','device','notice01','{}','now','now')");
  assert.equal(sql.prepare("SELECT COUNT(*) n FROM notification_outbox WHERE id='duplicate'").get().n,0);
  await maintainRegistry({DB},now);
  assert.equal(sql.prepare("SELECT COUNT(*) n FROM notification_outbox WHERE payload='{}'").get().n,20);
  sql.exec("UPDATE notification_outbox SET state='cancelled' WHERE id='event24'");
  await maintainRegistry({DB},now);
  assert.equal(sql.prepare("SELECT COUNT(*) n FROM notification_outbox WHERE payload='{}'").get().n,22);
  assert.equal(sql.prepare('SELECT seq FROM notification_sequence').get().seq,0);
  const plan=sql.prepare("EXPLAIN QUERY PLAN SELECT id FROM notification_outbox INDEXED BY outbox_terminal_retention WHERE state IN ('failed','cancelled','expired') AND payload!='{}' AND created_at<=? ORDER BY created_at,id LIMIT 20").all(cutoff);
  assert.ok(plan.some(x=>x.detail.includes('outbox_terminal_retention')));
});

test('history migration preserves accepted rows and skips pending rows',t=>{
  const sql=new DatabaseSync(':memory:');t.after(()=>sql.close());sql.exec(readFileSync(new URL('../migrations/0001_catalogue.sql',import.meta.url),'utf8'));
  sql.exec("INSERT INTO installations(id,secret_hash,token,platform,preferences,updated_at) VALUES('owner','hash','token','android','{}','now'); INSERT INTO notification_outbox(id,installation_id,listing_id,payload,state,due_at,created_at) VALUES('z','owner','z','{}','accepted','now','2000-01-01'),('a','owner','a','{}','accepted','now','2001-01-01'),('pending','owner','pending','{}','pending','now','1999-01-01')");
  sql.exec(readFileSync(new URL('../migrations/0005_notification_sequence.sql',import.meta.url),'utf8'));
  assert.deepEqual(sql.prepare('SELECT id,history_seq FROM notification_outbox ORDER BY id').all().map(x=>({...x})),[{id:'a',history_seq:2},{id:'pending',history_seq:null},{id:'z',history_seq:1}]);
  sql.exec("UPDATE notification_outbox SET state='accepted' WHERE id='pending'");
  assert.equal(sql.prepare("SELECT history_seq FROM notification_outbox WHERE id='pending'").get().history_seq,3);
});

test('fresh send lease rechecks cap after an earlier stale installation read',async t=>{
  const {sql,env,calls,send}=notifications(t,1,{mode:'instant',preferences:{quietStart:22,quietEnd:8,cap:1}});
  const prepare=env.DB.prepare;
  env.DB.prepare=query=>{
    if(query.startsWith('UPDATE installations SET send_lease_until=?'))sql.exec("UPDATE installations SET sent_day='2026-10-01',sent_count=1");
    return prepare(query);
  };
  await flushOutbox(env,{send,now:new Date('2026-10-01T15:00:00Z')});
  assert.equal(calls.length,0);assert.equal(sql.prepare('SELECT due_at FROM notification_outbox').get().due_at,'2026-10-02T05:00:00.000Z');
});

test('one daily digest does not consume instant cap, remaining jobs stay queued',async t=>{
  const {sql,env,calls,send}=notifications(t,12);
  sql.exec("UPDATE installations SET sent_day='2026-10-01',sent_count=6");
  await flushOutbox(env,{send,now:new Date('2026-10-01T15:00:00Z')});
  assert.equal(calls.length,1);assert.equal(calls[0].event.digestCount,10);
  assert.equal(sql.prepare('SELECT sent_count FROM installations').get().sent_count,6);
  await flushOutbox(env,{send,now:new Date('2026-10-01T15:01:00Z')});
  assert.equal(calls.length,1);
  assert.equal(sql.prepare("SELECT COUNT(*) n FROM notification_outbox WHERE state='pending'").get().n,2);
  await flushOutbox(env,{send,now:new Date('2026-10-02T15:00:00Z')});
  assert.equal(calls.length,2);assert.equal(calls[1].event.digestCount,2);
});

test('candidate anchors retain every exact match in shared Dart corpus and group variants',()=>{
  const now=new Date('2026-09-30T12:00:00Z');
  const corpus=JSON.parse(readFileSync(new URL('../../contracts/criteria-v2.json',import.meta.url),'utf8'));
  for(const row of corpus) {
    const criteria=row.legacy?migrateFilters(row.legacy):validateCriteria(row.criteria);
    if(matchListing(row.listing,criteria,row.now?new Date(row.now):now)==='match')assert.ok(searchAnchorKeys(criteria).some(key=>listingAnchorKeys(row.listing).includes(key)),row.name);
  }
  for(const groups of [undefined,[{cities:[],education:['Lisans'],occupations:['Mühendis']}],[{cities:['Ankara'],education:['Lisans']},{cities:['İstanbul'],education:['Lise']}]] ) {
    const listing={title:'Memur',institution:'Kurum',places:['Ankara'],occupations:['Mühendis'],requirementGroups:groups};
    for(const cities of [[],['Ankara'],['İstanbul','Ankara']])for(const education of [[],['Lisans'],['Lise']])for(const occupations of [[],['Mühendis']])for(const institutions of [[],['Kurum']]) {
      const criteria={cities,education,occupations,institutions};
      if(matchListing(listing,criteria,now)==='match')assert.ok(searchAnchorKeys(criteria).some(key=>listingAnchorKeys(listing).includes(key)));
    }
  }
  assert.deepEqual(installationAnchorKeys([{mode:'instant',criteria:{cities:['Ankara']}},{mode:'digest',criteria:{keyword:'Memur'}}]),['*']);
  assert.deepEqual(installationAnchorKeys([{mode:'off',criteria:{cities:['Ankara']}}]),[]);
});

test('pruning catalogue history never turns an old listing into a new subscription push',async t=>{
  const {sql,DB}=database();t.after(()=>sql.close());
  insertNotice(sql,'Original notice');
  for(const [id,baseline] of [['old',0],['new',1]]) {
    sql.prepare("INSERT INTO installations(id,secret_hash,token,platform,preferences,updated_at) VALUES(?,'hash','token','android','{}','now')").run(id);
    sql.prepare("INSERT INTO saved_searches VALUES(?,'s','All','{\"version\":2}','instant',?)").run(id,baseline);
    sql.prepare("INSERT INTO installation_facets VALUES('*',?)").run(id);
  }
  sql.exec("UPDATE listings SET payload=json_set(payload,'$.title','Updated notice'),revision=2; DELETE FROM catalogue_changes WHERE seq=1; UPDATE listings SET processed_hash='hash'");
  assert.equal(sql.prepare('SELECT MIN(seq) seq FROM catalogue_changes').get().seq,2);
  assert.equal(sql.prepare('SELECT first_seq FROM listings').get().first_seq,1);
  await matchEvents({DB});
  assert.deepEqual(sql.prepare('SELECT installation_id FROM notification_outbox').all().map(x=>x.installation_id),['old']);
});

test('first sequence migration backfills earliest publication and future changes preserve it',t=>{
  const sql=new DatabaseSync(':memory:');t.after(()=>sql.close());
  sql.exec(readFileSync(new URL('../migrations/0001_catalogue.sql',import.meta.url),'utf8'));
  insertNotice(sql,'Existing notice');
  sql.exec("UPDATE listings SET payload=json_set(payload,'$.title','Updated'),revision=2");
  sql.exec(readFileSync(new URL('../migrations/0006_listing_first_seq.sql',import.meta.url),'utf8'));
  assert.equal(sql.prepare('SELECT first_seq FROM listings').get().first_seq,1);
  sql.exec("DELETE FROM catalogue_changes; UPDATE listings SET payload=json_set(payload,'$.title','Third'),revision=3");
  assert.equal(sql.prepare('SELECT first_seq FROM listings').get().first_seq,1);
  sql.exec("INSERT INTO listings(id,source_id,external_id,content_hash,first_seen,updated_at,recheck_at,payload) VALUES('new','sbb','new','h','first','now','later','{}')");
  assert.equal(sql.prepare("SELECT first_seq FROM listings WHERE id='new'").get().first_seq,4);
});

test('indexed matching skips unrelated installations, resumes pages and dedupes multiple facets',async t=>{
  const {sql,DB}=database();t.after(()=>sql.close());
  const payload={id:'job',title:'Memur',places:['Ankara'],requirementGroups:[{cities:['Ankara'],education:['Lisans'],kpssStatus:'unknown'}]};
  const add=(id,searches,baseline=0)=>{
    sql.prepare("INSERT INTO installations(id,secret_hash,token,platform,preferences,updated_at) VALUES(?,'hash','token','android','{}','now')").run(id);
    for(const s of searches)sql.prepare('INSERT INTO saved_searches VALUES(?,?,?,?,?,?)').run(id,s.id,s.id,JSON.stringify(s.criteria),s.mode,baseline);
    for(const key of installationAnchorKeys(searches))sql.prepare('INSERT INTO installation_facets VALUES(?,?)').run(key,id);
  };
  const city={id:'city',mode:'instant',criteria:{version:2,cities:['Ankara']}};
  for(let n=0;n<15;n++)add('matching'+String(n).padStart(2,'0'),[city]);
  for(let n=0;n<30;n++)add('unrelated'+String(n).padStart(2,'0'),[{...city,criteria:{version:2,cities:['İstanbul']}}]);
  add('double',[city,{id:'education',mode:'digest',criteria:{version:2,education:['Lisans']}}]);
  add('broad',[{id:'broad',mode:'digest',criteria:{version:2,keyword:'Memur'}}]);
  add('unknown',[{...city,criteria:{version:2,cities:['Ankara'],kpssType:'P3'}}]);
  add('new',[city],1);
  sql.prepare("INSERT INTO listings(id,source_id,external_id,content_hash,first_seen,updated_at,recheck_at,payload) VALUES('job','sbb','job','hash','first','now','later',?)").run(JSON.stringify(payload));
  sql.exec("UPDATE listings SET processed_hash='hash' WHERE id='job'");
  const prepare=DB.prepare,seen=[];let queries=0;
  DB.prepare=query=>{
    queries++;
    if(query==='SELECT * FROM installations WHERE id=? AND enabled=1') {
      const statement=prepare(query),bind=statement.bind;
      statement.bind=function(id){seen.push(id);return bind.call(this,id);};return statement;
    }
    assert.ok(!query.includes('FROM installations WHERE enabled=1 AND id>'));
    return prepare(query);
  };
  for(let n=0;n<10;n++) {
    queries=0;
    await matchEvents({DB});
    assert.ok(queries<=38,`matching query budget: ${queries}`);
    if(sql.prepare('SELECT state FROM match_events').get().state==='completed')break;
  }
  assert.equal(sql.prepare('SELECT state FROM match_events').get().state,'completed');
  assert.equal(sql.prepare('SELECT COUNT(*) n FROM notification_outbox').get().n,17);
  assert.ok(!seen.some(id=>id.startsWith('unrelated')));
  assert.equal(sql.prepare("SELECT COUNT(*) n FROM notification_outbox WHERE installation_id IN ('unknown','new')").get().n,0);
  const double=JSON.parse(sql.prepare("SELECT payload FROM notification_outbox WHERE installation_id='double'").get().payload);
  assert.deepEqual(double.searchIds.sort(),['city','education']);assert.equal(double.mode,'instant');
  assert.equal(sql.prepare("SELECT COUNT(*) n FROM notification_outbox WHERE installation_id='double'").get().n,1);
  const plan=sql.prepare('EXPLAIN QUERY PLAN SELECT installation_id FROM installation_facets WHERE key=? AND installation_id>? ORDER BY installation_id LIMIT 10').all('cities:ankara','');
  assert.ok(plan.some(row=>row.detail.includes('key=? AND installation_id>?')));
});

test('registry replaces facets atomically and preserves them on token-only heartbeat',async t=>{
  const {sql,DB}=database();t.after(()=>sql.close());const id='a'.repeat(32),secret='b'.repeat(64);
  const put=async(searches,token='token'.repeat(8))=>fetchRequest(new Request('https://api/api/v2/installations/'+id,{method:'PUT',headers:{'Content-Type':'application/json',Authorization:'Bearer '+secret},body:JSON.stringify({fcmToken:token,platform:'android',searches})}),{DB},{});
  const search={id:'city',name:'Şehrim',mode:'instant',criteria:{version:2,cities:['Ankara']}};
  assert.equal((await put([search])).status,201);
  const keys=()=>sql.prepare('SELECT key FROM installation_facets WHERE installation_id=? ORDER BY key').all(id).map(x=>x.key);
  assert.deepEqual(keys(),['cities:ankara']);
  const version=sql.prepare('SELECT version FROM installations').get().version;
  await put([search],'rotated'.repeat(8));assert.deepEqual(keys(),['cities:ankara']);assert.equal(sql.prepare('SELECT version FROM installations').get().version,version);
  await put([{...search,criteria:{version:2,education:['Lisans']}}]);assert.deepEqual(keys(),['education:bachelor']);
  await put([{...search,mode:'off'}]);assert.deepEqual(keys(),[]);
  await put([search]);
  const response=await fetchRequest(new Request('https://api/api/v2/installations/'+id,{method:'DELETE',headers:{Authorization:'Bearer '+secret}}),{DB},{});
  assert.equal(response.status,200);assert.deepEqual(keys(),[]);
});

test('facet migration preserves existing subscriptions and restarts old partial match cursor',async t=>{
  const sql=new DatabaseSync(':memory:');t.after(()=>sql.close());sql.exec('PRAGMA foreign_keys=ON');
  sql.exec(readFileSync(new URL('../migrations/0001_catalogue.sql',import.meta.url),'utf8'));
  sql.exec("INSERT INTO installations(id,secret_hash,token,platform,preferences,updated_at) VALUES('existing','hash','token','android','{}','now'),('off','hash','token','android','{}','now'); INSERT INTO saved_searches VALUES('existing','s','My city','{}','instant',0),('off','s','Off','{}','off',0); INSERT INTO match_events(id,listing_id,revision,payload,created_at,cursor,state,lease_until) VALUES('old','listing',1,'{}','now','last-old-device','leased','future')");
  sql.exec(readFileSync(new URL('../migrations/0004_match_facets.sql',import.meta.url),'utf8'));
  assert.deepEqual(sql.prepare('SELECT key,installation_id FROM installation_facets').all().map(row=>({...row})),[{key:'*',installation_id:'existing'}]);
  const event=sql.prepare('SELECT cursor,state,lease_until,facet_index FROM match_events').get();
  assert.deepEqual({...event},{cursor:'',state:'pending',lease_until:null,facet_index:0});
  assert.equal(sql.prepare('SELECT COUNT(*) n FROM saved_searches').get().n,2);
});

test('education anchor migration retains old subscriptions, resets fanout and rebuilds on heartbeat',async t=>{
  const {sql,DB}=database();t.after(()=>sql.close());const id='a'.repeat(32),secret='b'.repeat(64);
  const search={id:'s',name:'Eğitim',mode:'instant',criteria:{version:2,education:['Ön lisans']}};
  const put=()=>fetchRequest(new Request('https://api/api/v2/installations/'+id,{method:'PUT',headers:{'Content-Type':'application/json',Authorization:'Bearer '+secret},body:JSON.stringify({fcmToken:'token'.repeat(8),platform:'android',searches:[search]})}),{DB},{});
  await put();const version=sql.prepare('SELECT version FROM installations').get().version;
  sql.prepare("UPDATE installation_facets SET key='education:on lisans' WHERE installation_id=?").run(id);
  sql.exec("INSERT INTO match_events(id,listing_id,revision,payload,created_at,cursor,state,lease_until,facet_index) VALUES('old','listing',1,'{}','now','last','leased','future',4),('done','listing',2,'{}','now','last','completed',NULL,9)");
  sql.exec(readFileSync(new URL('../migrations/0010_education_alias_facets.sql',import.meta.url),'utf8'));
  assert.deepEqual(sql.prepare('SELECT key FROM installation_facets ORDER BY key').all().map(x=>x.key),['*','education:on lisans']);
  assert.deepEqual({...sql.prepare("SELECT cursor,state,lease_until,facet_index FROM match_events WHERE id='old'").get()},{cursor:'',state:'pending',lease_until:null,facet_index:0});
  assert.equal(sql.prepare("SELECT state FROM match_events WHERE id='done'").get().state,'completed');
  await put();
  assert.deepEqual(sql.prepare('SELECT key FROM installation_facets').all().map(x=>x.key),['education:associate']);
  assert.equal(sql.prepare('SELECT version FROM installations').get().version,version);
  assert.equal(sql.prepare('SELECT COUNT(*) n FROM saved_searches').get().n,1);
});

test('invalid token removes candidate facets but preserves saved preferences',async t=>{
  const {sql,env}=notifications(t,1,{mode:'instant'});
  sql.exec("INSERT INTO installation_facets VALUES('*','device')");
  await flushOutbox(env,{now:new Date('2026-10-01T15:00:00Z'),send:async()=>({state:'invalid_token'})});
  assert.equal(sql.prepare('SELECT COUNT(*) n FROM installation_facets').get().n,0);
  assert.equal(sql.prepare('SELECT COUNT(*) n FROM saved_searches').get().n,1);
  assert.equal(sql.prepare('SELECT enabled FROM installations').get().enabled,0);
});

test('consolidation keeps later source excerpts and incomplete final summaries stay unpublished',async t=>{
  const quotes=['Başvurular yalnız Kariyer Kapısı üzerinden alınacaktır.','Son başvuru tarihi itibarıyla 35 yaşını doldurmamış olmak.','2024 KPSS (P94) puanı en az 60 puan ve üzeri olmak.'];
  for(const count of [2,3]){
    const {sql,DB}=database();t.after(()=>sql.close());
    const text=quotes.join('\n').repeat(100);insertNotice(sql,text);
    const progress={index:splitAiText(text).length,summaries:[quotes.map(quote=>({text:quote,quote}))],conditions:[[]]};
    sql.prepare("UPDATE processing_jobs SET input=json_set(input,'$.aiProgress',json(?),'$.aiContract',json(?)) WHERE id='processing'").run(JSON.stringify(progress),JSON.stringify({provider:'cloudflare',model:'@cf/meta/llama-3.3-70b-instruct-fp8-fast',extractionRevision:aiExtractionRevision}));
    await processNotice({DB,AI_MODEL:'@cf/meta/llama-3.3-70b-instruct-fp8-fast',AI:{async run(_,request){
      assert.equal(request.response_format.type,'json_schema');assert.equal(request.response_format.json_schema.properties.summary.minItems,3);
      assert.equal(request.response_format.json_schema.properties.summary.items.additionalProperties,false);
      const excerpts=JSON.parse(JSON.parse(request.messages[1].content).text).map(s=>s.quote);
      assert.ok(excerpts.includes(quotes[1]));assert.ok(excerpts.includes(quotes[2]));
      return {response:{summary:quotes.slice(0,count).map(quote=>({quote})),conditions:[]}};
    }}});
    const job=sql.prepare("SELECT state,error_code FROM processing_jobs WHERE id='processing'").get();
    assert.equal(job.state,count===3?'completed':'pending');assert.equal(job.error_code,count===3?null:'ai_incomplete_summary');
    const listing=sql.prepare("SELECT payload,processed_hash FROM listings WHERE id='job'").get();
    assert.equal(listing.processed_hash,count===3?'hash':null);
    assert.equal(JSON.parse(listing.payload).summary.length,count===3?3:0);
  }
});

test('city identity migration protects old anchors until authenticated heartbeat rebuilds them',async t=>{
  const {sql,DB}=database();t.after(()=>sql.close());const id='a'.repeat(32),secret='b'.repeat(64);
  const search={id:'s',name:'Şehir',mode:'instant',criteria:{version:2,cities:['city:istanbul']}};
  const put=()=>fetchRequest(new Request('https://api/api/v2/installations/'+id,{method:'PUT',headers:{'Content-Type':'application/json',Authorization:'Bearer '+secret},body:JSON.stringify({fcmToken:'token'.repeat(8),platform:'android',searches:[search]})}),{DB},{});
  await put();const version=sql.prepare('SELECT version FROM installations').get().version;
  sql.prepare("UPDATE installation_facets SET key='cities:city:istanbul' WHERE installation_id=?").run(id);
  sql.exec("INSERT INTO match_events(id,listing_id,revision,payload,created_at,cursor,state,lease_until,facet_index) VALUES('old','listing',1,'{}','now','last','leased','future',4),('done','listing',2,'{}','now','last','completed',NULL,9)");
  sql.exec(readFileSync(new URL('../migrations/0013_city_alias_facets.sql',import.meta.url),'utf8'));
  assert.deepEqual(sql.prepare('SELECT key FROM installation_facets ORDER BY key').all().map(x=>x.key),['*','cities:city:istanbul']);
  assert.deepEqual({...sql.prepare("SELECT cursor,state,lease_until,facet_index FROM match_events WHERE id='old'").get()},{cursor:'',state:'pending',lease_until:null,facet_index:0});
  assert.equal(sql.prepare("SELECT state FROM match_events WHERE id='done'").get().state,'completed');
  await put();assert.deepEqual(sql.prepare('SELECT key FROM installation_facets').all().map(x=>x.key),['cities:istanbul']);
  assert.equal(sql.prepare('SELECT version FROM installations').get().version,version);
  assert.equal(sql.prepare('SELECT COUNT(*) n FROM saved_searches').get().n,1);
});
