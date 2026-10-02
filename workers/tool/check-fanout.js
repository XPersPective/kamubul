// Offline capacity check: ephemeral SQLite only; no Cloudflare, AI or FCM calls.
import assert from 'node:assert/strict';
import {readFileSync,readdirSync} from 'node:fs';
import {DatabaseSync} from 'node:sqlite';
import {performance} from 'node:perf_hooks';
import {matchEvents,runScheduled} from '../src/pipeline.js';

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
    const owner=sql.prepare("INSERT INTO installations(id,secret_hash,token,platform,preferences,updated_at) VALUES(?,'fixture','not-an-fcm-token','android','{}','now')");
    const search=sql.prepare("INSERT INTO saved_searches VALUES(?,'search','Capacity','{\"version\":2}','instant',0)");
    const facet=sql.prepare("INSERT INTO installation_facets VALUES('*',?)");
    sql.exec('BEGIN');
    for(let n=0;n<recipients;n++){const id=String(n).padStart(6,'0');owner.run(id);search.run(id);facet.run(id);}
    sql.exec("COMMIT; UPDATE listings SET processed_hash='hash' WHERE id='capacity'");
    let queries=0,totalQueries=0,maximumQueries=0,rounds=0;
    const timings=[];
    const DB={prepare(query){let args=[];return {bind(...values){args=values;return this;},async first(){queries++;return sql.prepare(query).get(...args)??null;},async all(){queries++;return {results:sql.prepare(query).all(...args)};},async run(){queries++;return sql.prepare(query).run(...args);}};}};
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
  }finally{sql.close();}
}
