import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {DatabaseSync} from 'node:sqlite';
import {fetchRequest} from '../src/worker.js';

function setup(t){
  const sql=new DatabaseSync(':memory:');sql.exec(readFileSync(new URL('../migrations/0001_catalogue.sql',import.meta.url),'utf8'));sql.exec(readFileSync(new URL('../migrations/0011_catalogue_retention_floor.sql',import.meta.url),'utf8'));t.after(()=>sql.close());
  const DB={prepare(query){let values=[];return {bind(...args){values=args;return this;},async first(){return sql.prepare(query).get(...values)??null;},async all(){return {results:sql.prepare(query).all(...values)};}};}};
  const insert=(id,text)=>sql.prepare("INSERT INTO listings(id,source_id,external_id,content_hash,first_seen,updated_at,recheck_at,payload) VALUES(?,'sbb',?,'hash','first','first','later',?)").run(id,id,JSON.stringify({id,title:'Resmî ilan '+id,sourceId:'sbb',text,url:'https://kamuilan.sbb.gov.tr/ilanDetay.aspx?kod='+id,updatedAt:'2026-10-01T00:00:00Z'}));
  const fetch=async path=>{
    const response=await fetchRequest(new Request('https://api/api/v2/'+path),{DB},{}),bytes=new Uint8Array(await response.arrayBuffer());
    assert.ok(bytes.length<=1800000);return {status:response.status,body:JSON.parse(new TextDecoder().decode(bytes))};
  };
  return {sql,insert,fetch,DB};
}

test('large UTF8 delta pages advance only sent immutable changes, including tombstones',async t=>{
  const {sql,insert,fetch}=setup(t);
  for(let i=0;i<8;i++)insert('notice'+i,'Ğ'.repeat(150000));
  sql.exec("UPDATE listings SET active=0,revision=2 WHERE id='notice0'");
  let {body}=await fetch('changes?after=0&limit=50');
  assert.ok(body.changes.length<9);assert.equal(body.hasMore,true);
  const watermark=body.watermark,received=[...body.changes];
  sql.exec("UPDATE listings SET payload=json_set(payload,'$.title','Daha sonraki sürüm'),revision=2 WHERE id='notice7'");
  while(body.hasMore){
    const after=body.appliedThrough;({body}=await fetch('changes?after='+after+'&watermark='+watermark+'&limit=50'));
    assert.equal(body.watermark,watermark);assert.ok(body.appliedThrough>after);received.push(...body.changes);
  }
  // notice0's upsert (seq 1) is superseded by its tombstone (seq 9) within the watermark and is not replayed.
  assert.equal(received.length,8);assert.deepEqual(received.map(r=>r.seq),[2,3,4,5,6,7,8,9]);
  assert.equal(received.at(-1).operation,'tombstone');assert.equal(received.find(r=>r.id==='notice7').item.title,'Resmî ilan notice7');
  assert.equal(body.appliedThrough,watermark);
});

test('a delta sends each listing once at its newest revision up to the watermark',async t=>{
  const {sql,insert,fetch}=setup(t);
  insert('busy','metin');insert('quiet','metin');
  for(let revision=2;revision<=4;revision++)sql.prepare("UPDATE listings SET payload=json_set(payload,'$.title',?),revision=? WHERE id='busy'").run('Sürüm '+revision,revision);
  const {body}=await fetch('changes?after=0&limit=50');
  assert.deepEqual(body.changes.map(r=>[r.id,r.revision]),[['quiet',1],['busy',4]]);
  assert.equal(body.appliedThrough,body.watermark);assert.equal(body.hasMore,false);
  // A device already past the first revisions still receives the newest one.
  assert.deepEqual((await fetch('changes?after=3&watermark=5')).body.changes.map(r=>r.revision),[4]);
});

test('large bootstrap pages retain stable watermark and listing order without losing rows',async t=>{
  const {sql,insert,fetch}=setup(t);
  for(let i=0;i<8;i++)insert('notice'+i,'İ'.repeat(150000));
  let {body}=await fetch('listings?limit=50');assert.ok(body.next);
  const watermark=body.watermark,items=[...body.items];
  sql.exec("UPDATE listings SET payload=json_set(payload,'$.title','Yeni sürüm'),revision=2 WHERE id='notice7'");
  while(body.next){({body}=await fetch('listings?limit=50&watermark='+watermark+'&after='+body.next));items.push(...body.items);}
  assert.equal(items.length,8);assert.deepEqual(items.map(r=>r.id),Array.from({length:8},(_,i)=>'notice'+i));
  assert.equal(items.at(-1).title,'Resmî ilan notice7');assert.equal(body.watermark,watermark);
});

test('single oversized record fails explicitly without returning an advanced cursor',async t=>{
  const {insert,fetch}=setup(t);insert('large','a'.repeat(1800000));
  for(const path of ['changes?after=0','listings']){
    const response=await fetch(path);assert.equal(response.status,413);assert.deepEqual(response.body,{error:'record_oversize'});
  }
});

test('catalogue numeric cursors never silently change a frozen watermark',async t=>{
  const {insert,fetch}=setup(t);insert('first','one');insert('second','two');
  for(const invalid of ['', '-1','abc','1.5','1e0','+1','%20','9007199254740992']) {
    for(const path of ['changes?after='+invalid,'changes?watermark='+invalid,'listings?watermark='+invalid])assert.equal((await fetch(path)).status,400,path);
  }
  for(const path of ['changes?after=3','changes?watermark=3','listings?watermark=3'])assert.equal((await fetch(path)).status,409,path);
  assert.equal((await fetch('changes?after=2&watermark=1')).status,400);
  const delta=await fetch('changes?after=0&watermark=1');assert.equal(delta.body.watermark,1);assert.deepEqual(delta.body.changes.map(x=>x.id),['first']);
  const snapshot=await fetch('listings?watermark=1');assert.equal(snapshot.body.watermark,1);assert.deepEqual(snapshot.body.items.map(x=>x.id),['first']);
  assert.equal((await fetch('listings?watermark=0')).body.items.length,0);
});

test('metadata ETag changes when retained boundary changes without a new publication',async t=>{
  const {sql,insert,DB}=setup(t);insert('first','one');insert('second','two');
  const request=etag=>new Request('https://api/api/v2/meta',{headers:etag?{'If-None-Match':etag}:{}});
  const initial=await fetchRequest(request(),{DB},{}),etag=initial.headers.get('etag');
  assert.equal((await initial.json()).oldestRetainedSeq,1);
  assert.equal((await fetchRequest(request(etag),{DB},{})).status,304);
  sql.exec('DELETE FROM catalogue_changes WHERE seq=1');
  const changed=await fetchRequest(request(etag),{DB},{});assert.equal(changed.status,200);
  const body=await changed.json();assert.equal(body.latestSeq,2);assert.equal(body.oldestRetainedSeq,2);assert.notEqual(changed.headers.get('etag'),etag);
});

test('durable retention floor rejects expired pins while preserving older snapshot bases',async t=>{
  const {sql,insert,fetch,DB}=setup(t);insert('first','one');insert('second','two');
  sql.exec("UPDATE listings SET revision=2,payload=json_set(payload,'$.title','Revised') WHERE id='second'");
  const meta=etag=>fetchRequest(new Request('https://api/api/v2/meta',{headers:etag?{'If-None-Match':etag}:{}}),{DB},{});
  const initial=await meta(),etag=initial.headers.get('etag');
  sql.exec('UPDATE catalogue_retention SET floor=2 WHERE id=1');
  const changed=await meta(etag);assert.equal(changed.status,200);
  const metadata=await changed.json();assert.equal(metadata.latestSeq,3);assert.equal(metadata.oldestRetainedSeq,3);
  assert.equal(sql.prepare('SELECT MIN(seq) n FROM catalogue_changes').get().n,1);
  for(const path of ['changes?after=0','changes?after=1&watermark=2'])assert.deepEqual(await fetch(path),{status:409,body:{error:'cursor_expired'}});
  assert.deepEqual(await fetch('listings?watermark=1'),{status:409,body:{error:'snapshot_expired'}});
  const snapshot=await fetch('listings?watermark=2');assert.equal(snapshot.status,200);
  assert.deepEqual(snapshot.body.items.map(x=>x.title),['Resmî ilan first','Resmî ilan second']);
  const delta=await fetch('changes?after=2');assert.equal(delta.status,200);assert.equal(delta.body.changes[0].item.title,'Revised');
  assert.equal((await fetch('changes?after=2&watermark=2')).body.changes.length,0);
  assert.throws(()=>sql.exec('UPDATE catalogue_retention SET floor=-1'));
  assert.throws(()=>sql.exec('INSERT INTO catalogue_retention(id,floor) VALUES(2,0)'));
});

test('retention racing a page read returns expiry instead of silently skipping deleted revisions',async t=>{
  for(const phase of ['bounds','payload'])for(const snapshot of [false,true]){
    const {sql,insert,DB}=setup(t);insert('first','one');
    sql.exec("UPDATE listings SET revision=2,payload=json_set(payload,'$.title','Revised') WHERE id='first'");
    insert('second','two');insert('third','three');
    const prepare=DB.prepare;let pruned=false;
    const prune=()=>{pruned=true;sql.exec('UPDATE catalogue_retention SET floor=3; DELETE FROM catalogue_changes WHERE seq=1');};
    DB.prepare=query=>{
      const statement=prepare(query);
      if(phase==='bounds'&&query.includes('COALESCE(MIN(seq)')){
        const first=statement.first;statement.first=async()=>{const result=await first();if(!pruned)prune();return result;};
      }
      if(phase==='payload'&&query.includes('payload_bytes')){
        const all=statement.all;statement.all=async()=>{const result=await all();if(!pruned)prune();return result;};
      }
      return statement;
    };
    const path=snapshot?'listings?watermark=1':'changes?after=0&watermark=4';
    const response=await fetchRequest(new Request('https://api/api/v2/'+path),{DB},{});
    assert.equal(response.status,409,phase+' '+path);
    assert.deepEqual(await response.json(),{error:snapshot?'snapshot_expired':'cursor_expired'});
  }
});
