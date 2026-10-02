import {test} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync,readdirSync} from 'node:fs';
import {dispatchWork,handleWorkQueue,matchEvents} from '../src/pipeline.js';

function setup(t,count=25){
  const sql=new DatabaseSync(':memory:');t.after(()=>sql.close());sql.exec('PRAGMA foreign_keys=ON');
  for(const file of readdirSync(new URL('../migrations/',import.meta.url)).filter(f=>f.endsWith('.sql')).sort())sql.exec(readFileSync(new URL('../migrations/'+file,import.meta.url),'utf8'));
  let queries=0;
  const DB={prepare(query){let args=[];return {bind(...values){args=values;return this;},async first(){queries++;return sql.prepare(query).get(...args)??null;},async all(){queries++;return {results:sql.prepare(query).all(...args)};},async run(){queries++;return sql.prepare(query).run(...args);}};},async batch(statements){sql.exec('BEGIN');try{const results=[];for(const statement of statements)results.push(await statement.run());sql.exec('COMMIT');return results;}catch(error){sql.exec('ROLLBACK');throw error;}}};
  const tasks=[],env={DB,WORK_QUEUE:{async send(body){tasks.push(body);}},FCM_CLIENT_EMAIL:'fixture',FCM_PRIVATE_KEY:'not-a-key'};
  for(let n=0;n<count;n++){
    const id=String(n).padStart(6,'0');
    sql.prepare("INSERT INTO installations(id,secret_hash,token,platform,preferences,updated_at) VALUES(?,'fixture','not-a-token','android','{\"quietStart\":0,\"quietEnd\":0,\"cap\":3}','now')").run(id);
    sql.prepare("INSERT INTO saved_searches VALUES(?,'search','Fixture','{\"version\":2}','instant',0)").run(id);
    sql.prepare("INSERT INTO installation_facets VALUES('*',?)").run(id);
  }
  sql.prepare("INSERT INTO listings(id,source_id,external_id,content_hash,first_seen,updated_at,recheck_at,payload) VALUES('fixture','sbb','fixture','hash','now','now','later',?)").run(JSON.stringify({id:'fixture',title:'Fixture',deadline:'2030-01-01T00:00:00Z',active:true}));
  sql.exec("UPDATE listings SET processed_hash='hash'");
  return {sql,env,tasks,resetQueries:()=>queries=0,queries:()=>queries};
}
const message=body=>({body,acked:false,ack(){this.acked=true;}});

test('one wake-up owns each generation; chained matching finishes and duplicate tickets cannot replay',async t=>{
  const {sql,env,tasks}=setup(t);
  await Promise.all([dispatchWork(env,'match'),dispatchWork(env,'match')]);
  assert.equal(tasks.length,1);const first=tasks[0];let consumed=0;
  while(tasks.length){const item=message(tasks.shift());await handleWorkQueue({messages:[item]},env);assert.equal(item.acked,true);assert.ok(++consumed<=4);}
  assert.equal(sql.prepare('SELECT COUNT(*) n FROM notification_outbox').get().n,25);
  const duplicate=message(first);await handleWorkQueue({messages:[duplicate]},env);assert.equal(duplicate.acked,true);
  assert.equal(sql.prepare('SELECT COUNT(*) n FROM notification_outbox').get().n,25);assert.equal(tasks.length,0);
});
test('queue budget and transport failures leave authoritative work recoverable',async t=>{
  const {sql,env,tasks}=setup(t,1),day=new Date().toISOString().slice(0,10);
  sql.prepare('INSERT INTO daily_usage(day,ai_jobs,queue_jobs) VALUES(?,7,3000)').run(day);
  await dispatchWork(env,'match');assert.equal(tasks.length,0);
  assert.equal(sql.prepare("SELECT state FROM match_events").get().state,'pending');
  assert.equal(sql.prepare("SELECT state FROM dispatch_state WHERE kind='match'").get().state,'idle');
  sql.prepare('UPDATE daily_usage SET queue_jobs=0 WHERE day=?').run(day);
  env.WORK_QUEUE.send=async()=>{throw new Error('queue_unavailable');};await dispatchWork(env,'match');
  assert.equal(sql.prepare("SELECT state FROM dispatch_state WHERE kind='match'").get().state,'idle');
  assert.deepEqual({...sql.prepare('SELECT ai_jobs,queue_jobs FROM daily_usage WHERE day=?').get(day)},{ai_jobs:7,queue_jobs:1});
});
test('four instant recipients fit a bounded consumer; final digest is left for its own task',async t=>{
  const {sql,env,tasks,resetQueries,queries}=setup(t,4);await matchEvents(env);
  const sorted=sql.prepare('SELECT id FROM notification_outbox ORDER BY id').all();
  sql.prepare("UPDATE notification_outbox SET payload=json_set(payload,'$.mode','digest'),created_at='2026-10-01T12:00:00Z' WHERE id=?").run(sorted.at(-1).id);
  let sends=0;const send=async()=>{sends++;return {state:'accepted',id:'offline-stub'};};
  await dispatchWork(env,'send');resetQueries();
  await handleWorkQueue({messages:[message(tasks.shift())]},env,{send});
  assert.equal(sends,3);assert.ok(queries()+sends+1<=50,'D1 + FCM + one OAuth query budget');
  assert.equal(sql.prepare("SELECT COUNT(*) n FROM notification_outbox WHERE state='pending'").get().n,1);
  await handleWorkQueue({messages:[message(tasks.shift())]},env,{send});assert.equal(sends,4);
  assert.equal(sql.prepare('SELECT COUNT(*) n FROM installations WHERE send_lease_until IS NOT NULL').get().n,0);
});
test('instant batch drains four owners; malformed and expired tickets cannot start work',async t=>{
  const {sql,env,tasks,resetQueries,queries}=setup(t,4);await matchEvents(env);let sends=0;
  const bad=message({kind:'send',generation:'1'});await handleWorkQueue({messages:[bad]},env);assert.equal(bad.acked,true);
  const stale=message({kind:'send',generation:1});await handleWorkQueue({messages:[stale]},env);assert.equal(stale.acked,true);
  await dispatchWork(env,'send');resetQueries();
  await handleWorkQueue({messages:[message(tasks.shift())]},env,{send:async()=>{sends++;return {state:'accepted',id:'offline-stub'};}});assert.equal(sends,4);
  assert.ok(queries()+sends+1<=50,'Four-recipient consumer including dispatch must fit');
  assert.equal(sql.prepare("SELECT COUNT(*) n FROM notification_outbox WHERE state='accepted'").get().n,4);
});
test('last daily reservation is shared atomically by both kinds and expired wake-up recovers',async t=>{
  const {sql,env,tasks}=setup(t,1),day=new Date().toISOString().slice(0,10);
  await matchEvents(env);sql.exec("UPDATE match_events SET state='pending'");
  sql.prepare('INSERT INTO daily_usage(day,queue_jobs) VALUES(?,2999)').run(day);
  await Promise.all([dispatchWork(env,'match'),dispatchWork(env,'send')]);
  assert.equal(tasks.length,1);assert.equal(sql.prepare('SELECT queue_jobs FROM daily_usage WHERE day=?').get(day).queue_jobs,3000);
  const old=tasks.shift();sql.prepare("UPDATE dispatch_state SET lease_until='1970-01-01' WHERE kind=?").run(old.kind);
  const expired=message(old);await handleWorkQueue({messages:[expired]},env);assert.equal(expired.acked,true);
  assert.equal(sql.prepare("SELECT COUNT(*) n FROM notification_outbox WHERE state='accepted'").get().n,0);
  sql.prepare('UPDATE daily_usage SET queue_jobs=0 WHERE day=?').run(day);
  await dispatchWork(env,old.kind);assert.equal(tasks.length,1);assert.equal(tasks[0].generation,old.generation+1);
});

test('consumer stage and cleanup failures retain D1 work until lease recovery',async t=>{
  const {sql,env,tasks}=setup(t,1),prepare=env.DB.prepare;
  await dispatchWork(env,'match');
  env.DB.prepare=query=>{
    if(query.startsWith('SELECT active,deadline,first_seq'))throw new Error('d1_unavailable');
    return prepare(query);
  };
  const failed=message(tasks.shift());await handleWorkQueue({messages:[failed]},env);
  assert.equal(failed.acked,true);assert.equal(tasks.length,0);
  assert.equal(sql.prepare('SELECT state FROM match_events').get().state,'leased');
  assert.equal(sql.prepare("SELECT state FROM dispatch_state WHERE kind='match'").get().state,'idle');
  env.DB.prepare=prepare;sql.exec("UPDATE match_events SET lease_until='1970-01-01'");
  await dispatchWork(env,'match');
  env.DB.prepare=query=>{
    if(query.startsWith("UPDATE dispatch_state SET state='idle'"))throw new Error('d1_unavailable');
    return prepare(query);
  };
  const cleanupFailed=message(tasks.shift());
  await assert.rejects(handleWorkQueue({messages:[cleanupFailed]},env),/d1_unavailable/);
  assert.equal(cleanupFailed.acked,false);
  assert.equal(sql.prepare('SELECT state FROM match_events').get().state,'completed');
  assert.equal(sql.prepare('SELECT COUNT(*) n FROM notification_outbox').get().n,1);
  assert.equal(sql.prepare("SELECT state FROM dispatch_state WHERE kind='match'").get().state,'running');
  env.DB.prepare=prepare;
  sql.exec("UPDATE match_events SET state='pending',cursor='',facet_index=0; UPDATE dispatch_state SET lease_until='1970-01-01' WHERE kind='match'");
  await dispatchWork(env,'match');
  const old=message(cleanupFailed.body);await handleWorkQueue({messages:[old]},env);
  assert.equal(old.acked,true);
  while(tasks.length)await handleWorkQueue({messages:[message(tasks.shift())]},env);
  assert.equal(sql.prepare('SELECT state FROM match_events').get().state,'completed');
  assert.equal(sql.prepare('SELECT COUNT(*) n FROM notification_outbox').get().n,1);
});
