import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {DatabaseSync} from 'node:sqlite';
import {fcmMessage} from '../src/fcm.js';
import {fetchRequest,sha256} from '../src/worker.js';
import {splitAiText,processNotice,readSource,flushOutbox,digestDue,expireListings,matchEvents} from '../src/pipeline.js';

function database(){
  const sql=new DatabaseSync(':memory:');sql.exec('PRAGMA foreign_keys=ON');sql.exec(readFileSync(new URL('../migrations/0001_catalogue.sql',import.meta.url),'utf8'));
  sql.exec(readFileSync(new URL('../migrations/0002_digest_delivery.sql',import.meta.url),'utf8'));
  sql.exec(readFileSync(new URL('../migrations/0003_daily_digest.sql',import.meta.url),'utf8'));
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
  const response=await fetchRequest(new Request('https://api/api/v2/installations/'+id+'/notifications',{headers:{Authorization:'Bearer '+secret}}),{DB},{});
  assert.equal(response.status,200);const body=await response.json();
  assert.equal(body.items[0].eventId,'event');assert.equal(body.items[0].deliveryId,'group');
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
