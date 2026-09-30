import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {DatabaseSync} from 'node:sqlite';
import {validateCriteria,matchListing,fold} from '../src/criteria.js';
import {nextAllowed,validateAiSummary} from '../src/pipeline.js';
import {fetchRequest} from '../src/worker.js';

const now=new Date('2026-09-30T12:00:00Z');
test('typed criteria rejects ambiguous and invalid dates',()=>{
  assert.throws(()=>validateCriteria({version:1}));
  assert.throws(()=>validateCriteria({age:30,ageAsOf:'2026-02-30'}));
  assert.throws(()=>validateCriteria({kpssScore:70}));
  assert.equal(fold('İŞÇİ IĞDIR'),'isci igdir');
});
test('criteria are AND within one position and OR across positions',()=>{
  const listing={title:'Mühendis alımı',requirementGroups:[
    {cities:['Ankara'],education:['Lisans'],kpssStatus:'required',kpssType:'P3',kpssScore:70,ageStatus:'known',maxAge:35},
    {cities:['İstanbul'],education:['Lise'],kpssStatus:'not_required',ageStatus:'no_restriction'},
  ]};
  const criteria={cities:['Ankara'],education:['Lisans'],kpssType:'P3',kpssScore:70,age:35,ageAsOf:'2026-09-30'};
  assert.equal(matchListing(listing,criteria,now),'match');
  assert.equal(matchListing(listing,{...criteria,kpssScore:69.99},now),'no_match');
  assert.equal(matchListing(listing,{...criteria,kpssType:'P93'},now),'no_match');
  assert.equal(matchListing(listing,{...criteria,education:['Lise']},now),'no_match');
  assert.equal(matchListing(listing,{cities:['İstanbul'],age:70,ageAsOf:'2026-09-30'},now),'match');
  assert.equal(matchListing(listing,{cities:['Ankara'],onlyKpss:true},now),'match');
  assert.equal(matchListing({title:'İlan',requirementGroups:[{}]},{kpssType:'P3'},now),'unknown');
});
test('quiet hours wrap midnight in Istanbul',()=>{
  assert.equal(nextAllowed({quietStart:22,quietEnd:8},new Date('2026-09-30T20:15:00Z')),'2026-10-01T05:00:00.000Z');
  assert.equal(nextAllowed({quietStart:22,quietEnd:8},now),now.toISOString());
});
test('unsupported AI statements never enter summary',()=>{
  assert.deepEqual(validateAiSummary({summary:[{text:'Tahmin',quote:'Kaynakta bulunmayan alıntı'}]},'Lisans mezunları başvurabilir.'),[]);
});
test('real migration enforces identity, committed changes and deletion cascade',()=>{
  const db=new DatabaseSync(':memory:');db.exec('PRAGMA foreign_keys=ON');
  db.exec(readFileSync(new URL('../migrations/0001_catalogue.sql',import.meta.url),'utf8'));
  db.prepare(`INSERT INTO listings(id,source_id,external_id,content_hash,first_seen,updated_at,recheck_at,payload) VALUES(?,?,?,?,?,?,?,?)`).run('a','sbb','one','h','now','now','later','{"title":"A"}');
  assert.throws(()=>db.prepare(`INSERT INTO listings(id,source_id,external_id,content_hash,first_seen,updated_at,recheck_at,payload) VALUES(?,?,?,?,?,?,?,?)`).run('b','sbb','one','h','now','now','later','{}'));
  db.exec("UPDATE listings SET processed_hash='h',revision=2,payload='{}' WHERE id='a'");
  assert.equal(db.prepare('SELECT COUNT(*) n FROM match_events').get().n,1);
  assert.equal(db.prepare('SELECT MAX(seq) n FROM catalogue_changes').get().n,2);
  db.exec("UPDATE listings SET active=0 WHERE id='a'");
  assert.equal(db.prepare('SELECT operation FROM catalogue_changes ORDER BY seq DESC LIMIT 1').get().operation,'tombstone');
  db.exec(`INSERT INTO installations(id,secret_hash,token,platform,preferences,updated_at) VALUES('i','h','t','android','{}','now'); INSERT INTO saved_searches VALUES('i','s','S','{}','off',0); DELETE FROM installations WHERE id='i';`);
  assert.equal(db.prepare('SELECT COUNT(*) n FROM saved_searches').get().n,0);db.close();
});
test('registry heartbeat and token rotation preserve pending notifications',async()=>{
  const sql=new DatabaseSync(':memory:');sql.exec('PRAGMA foreign_keys=ON');sql.exec(readFileSync(new URL('../migrations/0001_catalogue.sql',import.meta.url),'utf8'));
  const DB={prepare(query){let values=[];return {bind(...args){values=args;return this;},async first(){return sql.prepare(query).get(...values)??null;},async all(){return {results:sql.prepare(query).all(...values)};},async run(){return sql.prepare(query).run(...values);}};},async batch(statements){sql.exec('BEGIN');try{const results=[];for(const s of statements)results.push(await s.run());sql.exec('COMMIT');return results;}catch(e){sql.exec('ROLLBACK');throw e;}}};
  const id='a'.repeat(32),secret='b'.repeat(64),body={fcmToken:'token'.repeat(10),platform:'android',searches:[{id:'s1',name:'Ankara',criteria:{version:2,cities:['Ankara']},mode:'instant'}]};
  const put=async value=>fetchRequest(new Request('https://api/api/v2/installations/'+id,{method:'PUT',headers:{'Content-Type':'application/json',Authorization:'Bearer '+secret},body:JSON.stringify(value)}),{DB},{});
  assert.equal((await put(body)).status,201);
  sql.prepare("INSERT INTO notification_outbox(id,installation_id,listing_id,payload,due_at,created_at) VALUES('event',?,'listing','{}','now','now')").run(id);
  assert.equal((await (await put({...body,fcmToken:'newtoken'.repeat(10)})).json()).version,1);
  assert.equal(sql.prepare("SELECT state FROM notification_outbox WHERE id='event'").get().state,'pending');
  assert.equal((await (await put({...body,searches:[]})).json()).version,2);
  assert.equal(sql.prepare("SELECT state FROM notification_outbox WHERE id='event'").get().state,'cancelled');
  assert.equal((await put({...body,searches:[{...body.searches[0],criteria:{cities:'Ankara'}}]})).status,400);
  sql.close();
});
