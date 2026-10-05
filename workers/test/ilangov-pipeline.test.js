import {test} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync,readdirSync} from 'node:fs';
import {readSource} from '../src/pipeline.js';

function setup(t){
  const sql=new DatabaseSync(':memory:');t.after(()=>sql.close());sql.exec('PRAGMA foreign_keys=ON');
  for(const file of readdirSync(new URL('../migrations/',import.meta.url)).filter(f=>f.endsWith('.sql')).sort())sql.exec(readFileSync(new URL('../migrations/'+file,import.meta.url),'utf8'));
  sql.exec("UPDATE sources SET next_due='2999-01-01' WHERE id!='ilangov'");
  const DB={prepare(query){let args=[];return {bind(...values){args=values;return this;},async first(){return sql.prepare(query).get(...args)??null;},async run(){return sql.prepare(query).run(...args);},async all(){return {results:sql.prepare(query).all(...args)};}};},async batch(statements){sql.exec('BEGIN');try{for(const statement of statements)await statement.run();sql.exec('COMMIT');}catch(error){sql.exec('ROLLBACK');throw error;}}};
  const original=globalThis.fetch;t.after(()=>{globalThis.fetch=original;});
  const ad=id=>({id,title:`Belediye ${id} Zabıta Memuru Alım İlanı`,urlStr:`/ilan/${id}/zabita`,advertiserName:'TEST BELEDİYE BAŞKANLIĞI',addressCityName:'ANKARA',publishStartDate:'2026-10-01T21:00:01Z'});
  let lists=0;
  globalThis.fetch=async(url,options)=>{
    const u=String(url);
    if(u.endsWith('/Ad/AdsByFilter')){lists++;assert.equal(options.headers['X-Request-Origin'],'IGT-UI');return Response.json({result:{ads:[ad(11),ad(12)],numFound:2}});}
    if(u.includes('/AdDetail/GetAdDetail?id=')){const id=new URL(u).searchParams.get('id');return Response.json({result:{content:`<p>Belediye ${id}</p><p>Lise mezunu olmak. 30 yaşını doldurmamış olmak.</p>`}});}
    throw new Error('unexpected '+u);
  };
  return {sql,env:{DB,AI_MODEL:'m'},lists:()=>lists};
}

test('ilan.gov.tr merkezi kaynak: sayfalı liste, ayrıntı metni, ayıklama işi, ilk görüntü sessiz',async t=>{
  const f=setup(t);
  await readSource(f.env);
  assert.equal(f.sql.prepare("SELECT state FROM sources WHERE id='ilangov'").get().state,'processing');
  await readSource(f.env);
  assert.equal(f.lists(),1,'bekleyen parti yeniden listelenmez');
  const rows=f.sql.prepare("SELECT id,payload FROM listings WHERE source_id='ilangov' ORDER BY id").all();
  assert.deepEqual(rows.map(r=>r.id),['ilangov:11','ilangov:12']);
  const notice=JSON.parse(rows[0].payload);
  assert.match(notice.text,/30 yaşını doldurmamış/);
  assert.equal(notice.notificationEligible,false,'ilk anlık görüntü bildirim üretmez');
  assert.equal(f.sql.prepare("SELECT COUNT(*) n FROM processing_jobs WHERE listing_id LIKE 'ilangov:%'").get().n,2);
  const source=f.sql.prepare("SELECT state,baseline_at,last_success FROM sources WHERE id='ilangov'").get();
  assert.equal(source.state,'ok');assert.ok(source.baseline_at);assert.ok(source.last_success);
});
