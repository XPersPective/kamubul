import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {DatabaseSync} from 'node:sqlite';
import {validateCriteria,matchListing,fold,migrateFilters} from '../src/criteria.js';
import {nextAllowed,validateAiSummary} from '../src/pipeline.js';
import {fetchRequest} from '../src/worker.js';
import {plain,parseKariyerIndex,parseKariyerRss,sourceFetch} from '../src/sources.js';

test('source normalization survives malformed entities and rejects unsafe identities',async()=>{
  assert.equal(plain('&#304; &#128512; &#99999999999999999999; &#55296; &#0;'),'İ 😀 � � �');
  const item={guid:'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',ilanBaslik:'İlan',bitTarih:'2026-12-01'};
  assert.equal(parseKariyerIndex({searchIlan:[null,{...item,guid:'-'.repeat(36)},item]}).length,1);
  for(const url of ['http://kariyerkapisi.gov.tr/RSS','https://user:pass@kariyerkapisi.gov.tr/RSS','https://kariyerkapisi.gov.tr:8443/RSS','https://example.com/'])await assert.rejects(sourceFetch(url),/host_rejected/);
  assert.equal(parseKariyerRss('<rss><item><link>https://user:pass@kariyerkapisi.gov.tr/IlanDetay?i='+item.guid+'</link><title>İlan</title></item></rss>').length,0);
});

const now=new Date('2026-09-30T12:00:00Z');
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
test('v1 age projection never discards date-dependent restrictions into a simple maximum',async()=>{
  const groups=[{ageStatus:'known',maxAge:35},{ageStatus:'known',maxAge:35,ageReferenceDate:'2026-10-01'},{ageStatus:'known',maxAge:35,bornOnOrAfter:'1991-01-01'},{ageStatus:'known',maxAge:35,bornOnOrBefore:'1991-09-30'},{ageStatus:'known',maxAge:35,ageCalculation:'year_start'}];
  const DB={prepare(query){return {async all(){return {results:query.includes('FROM listings')?groups.map(g=>({payload:JSON.stringify({title:'İlan',requirementGroups:[g]})})):[]};},async first(){return {n:1};}};}};
  const response=await fetchRequest(new Request('https://api/v1/listings.json'),{DB},{});
  assert.equal(response.status,200);const payload=await response.json();
  assert.deepEqual(payload.listings.map(x=>x.maxAge),[35,null,null,null,null]);
  assert.deepEqual(payload.listings.map(x=>x.requirementGroups[0]),groups);
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
  const sql=new DatabaseSync(':memory:');sql.exec('PRAGMA foreign_keys=ON');sql.exec(readFileSync(new URL('../migrations/0001_catalogue.sql',import.meta.url),'utf8'));sql.exec(readFileSync(new URL('../migrations/0011_catalogue_retention_floor.sql',import.meta.url),'utf8'));sql.exec(readFileSync(new URL('../migrations/0004_match_facets.sql',import.meta.url),'utf8'));
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
