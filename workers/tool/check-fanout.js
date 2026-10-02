// Offline capacity check: ephemeral SQLite only; no Cloudflare, AI or FCM calls.
import assert from 'node:assert/strict';
import {readFileSync,readdirSync} from 'node:fs';
import {DatabaseSync} from 'node:sqlite';
import {performance} from 'node:perf_hooks';
import {matchEvents,runScheduled,flushOutbox,dispatchWork,handleWorkQueue} from '../src/pipeline.js';

let matchingSlotsPerDay=0,sendSlotsPerDay=0;
const emptyDB={prepare(query){return {bind(){return this;},async first(){
  if(query.startsWith("UPDATE match_events SET state='leased'"))matchingSlotsPerDay++;
  if(query.startsWith("UPDATE notification_outbox SET state='leased'"))sendSlotsPerDay++;
  return null;
},async all(){return {results:[]};},async run(){return {};}};},async batch(statements){return Promise.all(statements.map(s=>s.run()));}};
for(let minute=0;minute<1440;minute++)await runScheduled({DB:emptyDB,FCM_PRIVATE_KEY:'fixture',FCM_CLIENT_EMAIL:'fixture'},minute*60000);
assert.ok(matchingSlotsPerDay>0&&sendSlotsPerDay>0,'Scheduler never services backlog');

for(const recipients of [100,1000,10000]) {
  const sql=new DatabaseSync(':memory:');
  try {
    sql.exec('PRAGMA foreign_keys=ON');
    for(const file of readdirSync(new URL('../migrations/',import.meta.url)).filter(f=>f.endsWith('.sql')).sort())sql.exec(readFileSync(new URL('../migrations/'+file,import.meta.url),'utf8'));
    const notice={id:'capacity',title:'Capacity fixture',active:true,deadline:'2030-01-01T00:00:00Z',requirementGroups:[]};
    sql.prepare("INSERT INTO listings(id,source_id,external_id,content_hash,first_seen,updated_at,recheck_at,payload) VALUES('capacity','sbb','capacity','hash','now','now','later',?)").run(JSON.stringify(notice));
    const owner=sql.prepare("INSERT INTO installations(id,secret_hash,token,platform,preferences,updated_at) VALUES(?,'fixture','not-an-fcm-token','android','{\"quietStart\":0,\"quietEnd\":0,\"cap\":3}','now')");
    const search=sql.prepare("INSERT INTO saved_searches VALUES(?,'search','Capacity','{\"version\":2}','instant',0)");
    const facet=sql.prepare("INSERT INTO installation_facets VALUES('*',?)");
    sql.exec('BEGIN');
    for(let n=0;n<recipients;n++){const id=String(n).padStart(6,'0');owner.run(id);search.run(id);facet.run(id);}
    sql.exec("COMMIT; UPDATE listings SET processed_hash='hash' WHERE id='capacity'");
    let queries=0,totalQueries=0,maximumQueries=0,rounds=0;
    const timings=[];
    const sendPlans=new Map();
    const DB={prepare(query){let args=[];return {bind(...values){args=values;return this;},async first(){queries++;return sql.prepare(query).get(...args)??null;},async all(){queries++;return {results:sql.prepare(query).all(...args)};},async run(){queries++;return sql.prepare(query).run(...args);}};}};
    const prepare=DB.prepare;DB.prepare=query=>{
      const statement=prepare(query),bind=statement.bind;
      statement.bind=function(...args){
        if((query.startsWith("UPDATE notification_outbox SET state='leased'")||query.startsWith('SELECT o.id,o.payload'))&&!sendPlans.has(query))sendPlans.set(query,sql.prepare('EXPLAIN QUERY PLAN '+query).all(...args).map(row=>row.detail));
        return bind.call(this,...args);
      };return statement;
    };
    DB.batch=async statements=>{sql.exec('BEGIN');try{const results=[];for(const statement of statements)results.push(await statement.run());sql.exec('COMMIT');return results;}catch(error){sql.exec('ROLLBACK');throw error;}};
    do {
      queries=0;const started=performance.now();await matchEvents({DB});timings.push(performance.now()-started);
      totalQueries+=queries;maximumQueries=Math.max(maximumQueries,queries);rounds++;
      assert.ok(queries<=50,'Matching exceeded Free subrequest/query ceiling');
      assert.ok(rounds<=Math.ceil(recipients/10)+4,'Durable cursor did not finish');
    }while(sql.prepare('SELECT state FROM match_events').get().state!=='completed');
    assert.equal(sql.prepare('SELECT COUNT(*) n FROM notification_outbox').get().n,recipients);
    assert.equal(sql.prepare("SELECT COUNT(*) n FROM notification_outbox WHERE state='pending'").get().n,recipients);
    await matchEvents({DB});
    assert.equal(sql.prepare('SELECT COUNT(*) n FROM notification_outbox').get().n,recipients,'Completed replay duplicated outbox');
    timings.sort((a,b)=>a-b);
    console.log(JSON.stringify({scope:'local SQLite; no cloud CPU/D1 row-counter/device delivery proof',recipients,matchingRounds:rounds,totalSqlExecutions:totalQueries,maxSqlExecutionsPerRound:maximumQueries,localWallP95Ms:timings[Math.ceil(timings.length*.95)-1],localWallP99Ms:timings[Math.ceil(timings.length*.99)-1],matchingSlotsPerDay,sendSlotsPerDay,idealSteadyStateSendDays:recipients/sendSlotsPerDay}));
    let sendCalls=0,sendQueries=0,maxSendQueries=0;const sendTimings=[],now=new Date();
    const env={DB,FCM_PRIVATE_KEY:'not-a-private-key',FCM_CLIENT_EMAIL:'offline-fixture'};
    const send=async()=>{sendCalls++;return {state:'accepted',id:'offline-stub'};};
    for(let n=0;n<recipients;n++){
      queries=0;const started=performance.now();await flushOutbox(env,{send,now});sendTimings.push(performance.now()-started);
      sendQueries+=queries;maxSendQueries=Math.max(maxSendQueries,queries);assert.ok(queries<=50,'Send SQL ceiling exceeded');
    }
    assert.equal(sendCalls,recipients);
    assert.equal(sql.prepare("SELECT COUNT(*) n FROM notification_outbox WHERE state='accepted'").get().n,recipients);
    assert.equal(sql.prepare('SELECT COUNT(*) n FROM installations WHERE send_lease_until IS NOT NULL').get().n,0);
    await flushOutbox(env,{send,now});assert.equal(sendCalls,recipients,'Drained replay contacted sender');
    sendTimings.sort((a,b)=>a-b);
    console.log(JSON.stringify({scope:'local SQLite and injected offline sender; no FCM/API/OAuth/device proof',recipients,sendCalls,sendSqlExecutions:sendQueries,maxSendSqlExecutions:maxSendQueries,localSendWallP95Ms:sendTimings[Math.ceil(sendTimings.length*.95)-1],localSendWallP99Ms:sendTimings[Math.ceil(sendTimings.length*.99)-1]}));
    if(recipients===100)console.log(JSON.stringify({sendPlans:[...sendPlans]}));
    // Reset this in-memory fixture only to compare the new dispatch strategy.
    sql.exec("DELETE FROM notification_outbox; UPDATE installations SET sent_count=0,sent_day=NULL; UPDATE match_events SET state='pending',cursor='',facet_index=0,lease_until=NULL");
    const tasks=[];env.WORK_QUEUE={async send(body){tasks.push(body);}};
    let queueMessages=0,queueSends=0;
    const consume=async()=>{
      while(tasks.length){
        const body=tasks.shift();let acked=false;
        await handleWorkQueue({messages:[{body,ack(){acked=true;}}]},env,{send:async()=>{queueSends++;return {state:'accepted',id:'offline-queue-stub'};}});
        assert.ok(acked);assert.ok(++queueMessages<=3000,'Queue reservation ceiling exceeded');
      }
    };
    await dispatchWork(env,'match');await consume();
    assert.equal(sql.prepare('SELECT state FROM match_events').get().state,'completed');
    assert.equal(sql.prepare('SELECT COUNT(*) n FROM notification_outbox').get().n,recipients);
    await dispatchWork(env,'send');await consume();
    const queueReservations=sql.prepare('SELECT queue_jobs FROM daily_usage WHERE day=?').get(new Date().toISOString().slice(0,10)).queue_jobs;
    assert.equal(queueReservations,queueMessages);
    assert.equal(queueSends,Math.min(recipients,(3000-rounds)*4));
    const pending=sql.prepare("SELECT COUNT(*) n FROM notification_outbox WHERE state='pending'").get().n;
    assert.equal(pending+queueSends,recipients,'Quota exhaustion lost outbox work');
    console.log(JSON.stringify({scope:'sequential match/send Queue simulation in memory with injected sender; no cloud Queue operations/CPU/FCM proof',recipients,queueMessages,queueReservations,queueSends,pending,normalOperationEstimate:queueMessages*3}));
  }finally{sql.close();}
}
