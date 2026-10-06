import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {DatabaseSync} from 'node:sqlite';
import {validateCriteria,matchListing,fold,migrateFilters} from '../src/criteria.js';
import {nextAllowed,validateAiSummary} from '../src/pipeline.js';
import {fetchRequest,sha256} from '../src/worker.js';
import {plain,parseKariyerIndex,parseKariyerRss,sourceFetch} from '../src/sources.js';

test('source normalization survives malformed entities and rejects unsafe identities',async()=>{
  assert.equal(plain('&#304; &#128512; &#99999999999999999999; &#55296; &#0;'),'İ 😀 � � �');
  const item={guid:'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',ilanBaslik:'İlan',bitTarih:'2026-12-01'};
  assert.throws(()=>parseKariyerIndex({searchIlan:[null,{...item,guid:'-'.repeat(36)},item]}),/layout_changed/);
  assert.equal(parseKariyerIndex({searchIlan:[item]}).length,1);
  for(const url of ['http://kariyerkapisi.gov.tr/RSS','https://user:pass@kariyerkapisi.gov.tr/RSS','https://kariyerkapisi.gov.tr:8443/RSS','https://example.com/'])await assert.rejects(sourceFetch(url),/host_rejected/);
  assert.throws(()=>parseKariyerRss('<rss><item><link>https://user:pass@kariyerkapisi.gov.tr/IlanDetay?i='+item.guid+'</link><title>İlan</title></item></rss>'),/rss_layout_changed/);
});

const now=new Date('2026-09-30T12:00:00Z');
test('registry accepts JSON media types and rejects lookalike prefixes before writing',async()=>{
  let writes=0;
  const DB={prepare(query){return {bind(){return this;},async first(){return query.startsWith('SELECT * FROM installations')?null:{n:0};},async all(){return {results:[]};}};},async batch(){writes++;}};
  const body=JSON.stringify({fcmToken:'t'.repeat(20),platform:'android',searches:[]});
  const put=contentType=>fetchRequest(new Request('https://api/api/v2/installations/'+'a'.repeat(32),{method:'PUT',headers:{Authorization:'Bearer '+'b'.repeat(64),'Content-Type':contentType},body}),{DB},{});
  for(const type of ['application/jsonp','application/json-extra','text/plain'])assert.equal((await put(type)).status,400);
  assert.equal(writes,0);
  for(const type of ['application/json','Application/JSON; charset=utf-8'])assert.equal((await put(type)).status,201);
  assert.equal(writes,2);
});
test('non-finite source KPSS score remains unknown',()=>{
  for(const kpssScore of [NaN,Infinity,-Infinity])assert.equal(matchListing({title:'Memur',requirementGroups:[{kpssStatus:'required',kpssType:'P3',kpssScore}]},{kpssType:'P3',kpssScore:75},now),'unknown');
});
for(const row of JSON.parse(readFileSync(new URL('../../contracts/criteria-v2.json',import.meta.url),'utf8'))){
  test('Dart parity: '+row.name,()=>assert.equal(matchListing(row.listing,row.legacy?migrateFilters(row.legacy):validateCriteria(row.criteria),row.now?new Date(row.now):now),row.expected));
}
test('age ranges agree with enumerated birthdays, including leap-year anniversaries',()=>{
  const ageAt=(birth,day)=>day.getUTCFullYear()-birth.getUTCFullYear()-(day.getUTCMonth()*100+day.getUTCDate()<birth.getUTCMonth()*100+birth.getUTCDate()?1:0);
  for(const asOfText of ['2024-02-29','2025-02-28','2025-03-01','2026-09-30'])for(const age of [20,35]){
    const asOf=new Date(asOfText),births=[];
    for(let birth=new Date(Date.UTC(asOf.getUTCFullYear()-age-2,0,1));birth.getUTCFullYear()<=asOf.getUTCFullYear()-age;birth=new Date(+birth+86400000))if(ageAt(birth,asOf)===age)births.push(birth);
    assert.ok(births.length>=365&&births.length<=366);
    for(const offset of [-366,-1,0,1,365,366])for(const [minAge,maxAge] of [[age,age],[age-1,age],[age,age+1]]){
      const reference=new Date(+asOf+offset*86400000),group={ageStatus:'known',minAge,maxAge,ageReferenceDate:reference.toISOString().slice(0,10)};
      const outcomes=births.map(b=>ageAt(b,reference)>=minAge&&ageAt(b,reference)<=maxAge);
      const expected=outcomes.every(Boolean)?'match':outcomes.some(Boolean)?'unknown':'no_match';
      assert.equal(matchListing({title:'İlan',requirementGroups:[group]},{age,ageAsOf:asOfText},new Date(+asOf+12*3600000)),expected,JSON.stringify({asOfText,age,offset,minAge,maxAge}));
    }
  }
});

test('public taxonomy advertises stable education IDs, labels and accepted aliases',async()=>{
  const response=await fetchRequest(new Request('https://api/api/v2/taxonomy'),{DB:{prepare(){return {async all(){return {results:[]};}};}}},{});
  assert.equal(response.status,200);const body=await response.json();
  assert.deepEqual(body.education,['Lise','Ön lisans','Lisans','Yüksek lisans','Doktora']);
  assert.deepEqual(body.educationValues.map(x=>x.id),['education:secondary','education:associate','education:bachelor','education:master','education:doctorate']);
  for(const value of body.educationValues)for(const alias of [value.label,...value.aliases])assert.equal(matchListing({title:'İlan',requirementGroups:[{education:[alias]}]},validateCriteria({version:2,education:[value.id]}),now),'match');
  const dartCities=readFileSync(new URL('../../packages/kamubul_core/lib/data/turkish_cities.dart',import.meta.url),'utf8').split('];')[0];
  assert.deepEqual(body.cities,[...dartCities.matchAll(/  '([^']+)',/g)].map(m=>m[1]));
  assert.equal(body.cityValues.length,81);assert.equal(new Set(body.cityValues.map(x=>x.id)).size,81);
  for(const value of body.cityValues)assert.equal(matchListing({title:'İlan',places:[value.label]},validateCriteria({version:2,cities:[value.id]}),now),'match');
});

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
test('public extraction and unbounded v1 snapshot routes are not exposed',async()=>{
  const DB={prepare(){throw new Error('no database access');}};
  for(const [method,path] of [['POST','/api/v2/extract'],['GET','/v1/listings.json'],['GET','/v1/sources.json']]){
    const response=await fetchRequest(new Request('https://api'+path,{method,headers:{'content-type':'application/json'},...(method==='POST'?{body:JSON.stringify({installationId:'a'.repeat(32),text:'x'.repeat(300)})}:{})}),{DB},{});
    assert.ok([404,405].includes(response.status),path);
  }
});

test('quiet hours wrap midnight in Istanbul',()=>{
  assert.equal(nextAllowed({quietStart:22,quietEnd:8},new Date('2026-09-30T20:15:00Z')),'2026-10-01T05:00:00.000Z');
  assert.equal(nextAllowed({quietStart:22,quietEnd:8},now),now.toISOString());
});
test('unsupported AI statements never enter summary',()=>{
  assert.deepEqual(validateAiSummary({summary:[{text:'Tahmin',quote:'Kaynakta bulunmayan alıntı'}]},'Lisans mezunları başvurabilir.'),[]);
  const quote='Başvurular yalnız Kariyer Kapısı üzerinden alınacaktır.';
  assert.deepEqual(validateAiSummary({summary:[{text:'KPSS en az 70 puan olmalıdır.',quote}]},quote),[]);
  assert.deepEqual(validateAiSummary({summary:[{text:quote,quote}]},quote),[{text:quote,quote}]);
  assert.deepEqual(validateAiSummary({summary:[{quote}]},quote),[{text:quote,quote}]);
  assert.deepEqual(validateAiSummary({summary:[{text:'Kariyer Kapısı',quote}]},quote),[]);
  assert.deepEqual(validateAiSummary({summary:[{text:quote,quote},{text:quote,quote}]},quote),[{text:quote,quote}]);
});

test('summary scope comes from source positions, never from model labels or concatenated fragments',()=>{
  const quote='2024 KPSS (P94) puanı en az 60 puan ve üzeri olmak.';
  const shared='Son başvuru tarihi itibarıyla 35 yaşını doldurmamış olmak.';
  const general='Başvurular yalnız Kariyer Kapısı üzerinden alınacaktır.';
  const notice={text:general,positions:[{title:'Kütüphaneci',text:shared},{title:'Destek personeli',text:quote+'\n'+shared}]};
  const text=[notice.text,...notice.positions.map(p=>p.text)].join('\n\n');
  const summary=validateAiSummary({summary:[{quote,scopeLabel:'Tüm kadrolar'},{quote:shared},{quote:general}]},text,notice);
  assert.equal(summary[0].scopeLabel,'Destek personeli');assert.equal(summary[1].scopeLabel,'Bazı kadrolar');assert.equal(summary[2].scopeLabel,undefined);
  assert.equal(validateAiSummary({summary:[{quote}]},text,{...notice,text:notice.text+'\n'+quote})[0].scopeLabel,'Destek personeli');
  assert.deepEqual(validateAiSummary({summary:[{quote:general+'\n\n'+shared}]},text,notice),[]);
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
  const sql=new DatabaseSync(':memory:');sql.exec('PRAGMA foreign_keys=ON');sql.exec(readFileSync(new URL('../migrations/0001_catalogue.sql',import.meta.url),'utf8'));sql.exec(readFileSync(new URL('../migrations/0011_catalogue_retention_floor.sql',import.meta.url),'utf8'));sql.exec(readFileSync(new URL('../migrations/0004_match_facets.sql',import.meta.url),'utf8'));sql.exec(readFileSync(new URL('../migrations/0015_installation_ownership.sql',import.meta.url),'utf8'));
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
  sql.prepare(`INSERT INTO listings(id,source_id,external_id,content_hash,first_seen,updated_at,recheck_at,payload) VALUES('visible','sbb','real','h','now','now','later','{"title":"Visible"}')`).run();
  const changes=await (await fetchRequest(new Request('https://api/api/v2/changes?after=0'),{DB},{})).json();
  assert.equal(changes.watermark,1);assert.equal(changes.changes.length,1);
  const listingPage=await (await fetchRequest(new Request('https://api/api/v2/listings'),{DB},{})).json();
  assert.equal(listingPage.items.length,1);
  sql.close();
});

test('concurrent first registration cannot overwrite another owner or its dependent rows',async()=>{
  const sql=new DatabaseSync(':memory:');sql.exec('PRAGMA foreign_keys=ON');
  for(const name of ['0001_catalogue','0004_match_facets','0015_installation_ownership'])sql.exec(readFileSync(new URL('../migrations/'+name+'.sql',import.meta.url),'utf8'));
  const id='a'.repeat(32),secret='b'.repeat(64),ownerHash=await sha256('c'.repeat(64));
  const DB={prepare(query){let values=[];return {bind(...args){values=args;return this;},async first(){return sql.prepare(query).get(...values)??null;},async all(){return {results:sql.prepare(query).all(...values)};},async run(){return sql.prepare(query).run(...values);}};},async batch(statements){
    // The other owner's registration commits after this request's empty read.
    sql.prepare("INSERT INTO installations(id,secret_hash,token,platform,preferences,updated_at) VALUES(?,?,'owner-token','android','{}','now')").run(id,ownerHash);
    sql.prepare("INSERT INTO saved_searches VALUES(?,'mine','Owner','{}','instant',7)").run(id);
    sql.prepare("INSERT INTO installation_facets VALUES('owner-facet',?)").run(id);
    sql.prepare("INSERT INTO notification_outbox(id,installation_id,listing_id,payload,due_at,created_at) VALUES('event',?,'listing','{}','now','now')").run(id);
    sql.exec('BEGIN');try{for(const s of statements)await s.run();sql.exec('COMMIT');}catch(e){sql.exec('ROLLBACK');throw e;}
  }};
  try {
    const response=await fetchRequest(new Request('https://api/api/v2/installations/'+id,{method:'PUT',headers:{'Content-Type':'application/json',Authorization:'Bearer '+secret},body:JSON.stringify({fcmToken:'attacker-token'.repeat(3),platform:'android',searches:[]})}),{DB},{});
    assert.equal(response.status,401);
    assert.deepEqual({...sql.prepare('SELECT secret_hash,token,version FROM installations').get()},{secret_hash:ownerHash,token:'owner-token',version:1});
    assert.equal(sql.prepare('SELECT id,effective_after FROM saved_searches').get().id,'mine');
    assert.equal(sql.prepare('SELECT effective_after FROM saved_searches').get().effective_after,7);
    assert.equal(sql.prepare('SELECT key FROM installation_facets').get().key,'owner-facet');
    assert.equal(sql.prepare('SELECT state FROM notification_outbox').get().state,'pending');
    assert.throws(()=>sql.prepare('UPDATE installations SET secret_hash=? WHERE id=?').run('different-hash',id),/installation_owner_conflict/);
    const prepare=DB.prepare;
    DB.prepare=query=>{
      const statement=prepare(query);
      if(query.startsWith('DELETE FROM installations')){
        const run=statement.run;
        statement.run=async()=>{
          // The authenticated row is deleted/recreated under another key before DELETE.
          sql.prepare('DELETE FROM installations WHERE id=?').run(id);
          sql.prepare("INSERT INTO installations(id,secret_hash,token,platform,preferences,updated_at) VALUES(?,?,'replacement','android','{}','now')").run(id,await sha256(secret));
          return run();
        };
      }
      return statement;
    };
    const deletion=await fetchRequest(new Request('https://api/api/v2/installations/'+id,{method:'DELETE',headers:{Authorization:'Bearer '+'c'.repeat(64)}}),{DB},{});
    assert.equal(deletion.status,200);
    assert.equal(sql.prepare('SELECT token FROM installations WHERE id=?').get(id).token,'replacement');
  } finally {sql.close();}
});

test('stale registry heartbeat rolls back instead of reverting newer criteria at the same version',async()=>{
  const sql=new DatabaseSync(':memory:');sql.exec('PRAGMA foreign_keys=ON');
  for(const name of ['0001_catalogue','0004_match_facets','0015_installation_ownership'])sql.exec(readFileSync(new URL('../migrations/'+name+'.sql',import.meta.url),'utf8'));
  const id='a'.repeat(32),secret='b'.repeat(64),body={fcmToken:'token'.repeat(10),platform:'android',searches:[{id:'s',name:'Original',criteria:{version:2},mode:'instant'}]};
  let race=false;
  const DB={prepare(query){let values=[];return {bind(...args){values=args;return this;},async first(){return sql.prepare(query).get(...values)??null;},async all(){return {results:sql.prepare(query).all(...values)};},async run(){return sql.prepare(query).run(...values);}};},async batch(statements){
    if(race){race=false;sql.prepare('UPDATE installations SET version=version+1 WHERE id=?').run(id);sql.prepare("UPDATE saved_searches SET name='Newer' WHERE installation_id=?").run(id);}
    sql.exec('BEGIN');try{const results=[];for(const s of statements)results.push(await s.run());sql.exec('COMMIT');return results;}catch(e){sql.exec('ROLLBACK');throw e;}
  }};
  const put=()=>fetchRequest(new Request('https://api/api/v2/installations/'+id,{method:'PUT',headers:{'Content-Type':'application/json',Authorization:'Bearer '+secret},body:JSON.stringify(body)}),{DB},{});
  try {
    assert.equal((await put()).status,201);
    race=true;
    const response=await put();assert.equal(response.status,409);assert.equal((await response.json()).error,'registry_conflict');
    assert.equal(sql.prepare('SELECT version FROM installations').get().version,2);
    assert.equal(sql.prepare('SELECT name FROM saved_searches').get().name,'Newer');
    assert.equal((await (await put()).json()).version,3);
    assert.equal(sql.prepare('SELECT name FROM saved_searches').get().name,'Original');
  } finally {sql.close();}
});
