import {test} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync,readdirSync} from 'node:fs';
import {readSource,canonicalConditions,canonicalBackfill} from '../src/pipeline.js';

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

test('kanonik ayıklama: alıntılı gruplar ilana yazılır, aynı içerik ikinci kez modele gitmez',async t=>{
  const f=setup(t);
  const text='Zabıta Memuru kadrosu için ortaöğretim (lise) mezunu olmak. Başvuru tarihi itibarıyla 30 yaşını doldurmamış olmak. '+'Genel şartlar ve belgeler ilanın devamında yer almaktadır. '.repeat(4);
  f.sql.prepare("INSERT INTO listings(id,source_id,external_id,content_hash,first_seen,updated_at,recheck_at,payload) VALUES('ilangov:9','ilangov','9','h9','2026-10-05','2026-10-05','2026-10-05',?)").run(JSON.stringify({title:'Zabıta',places:['Ankara'],requirementGroups:[],text}));
  let calls=0;
  const env={DB:f.env.DB,EXTRACT_AI_MODEL:'m',AI:{async run(){calls++;return {response:JSON.stringify({groups:[{label:'Zabıta Memuru',education:['Lise'],educationQuote:'ortaöğretim (lise) mezunu olmak',maxAge:30,ageQuote:'Başvuru tarihi itibarıyla 30 yaşını doldurmamış olmak'}]})};}}};
  const before=f.sql.prepare("SELECT revision FROM listings WHERE id='ilangov:9'").get().revision;
  await canonicalConditions(env,'ilangov:9','h9',text,['Ankara']);
  const row=f.sql.prepare("SELECT revision,payload FROM listings WHERE id='ilangov:9'").get();
  const [g]=JSON.parse(row.payload).requirementGroups;
  assert.deepEqual(g.education,['Lise']);assert.equal(g.maxAge,29);assert.deepEqual(g.cities,['Ankara']);
  assert.equal(row.revision,before+1);
  assert.equal(f.sql.prepare("SELECT COUNT(*) n FROM catalogue_changes WHERE listing_id='ilangov:9'").get().n,2,'değişiklik istemcilere yayılır');
  await canonicalConditions(env,'ilangov:9','h9',text,['Ankara']);
  assert.equal(calls,1);
});

test('telafi: geçici hata işaretlenmez ve sonraki turda tamamlanır; boş sonuç revizyonu artırmaz',async t=>{
  const f=setup(t);
  const text='Zabıta Memuru kadrosu için ortaöğretim (lise) mezunu olmak. '+'Genel şartlar ve belgeler ilanın devamında yer almaktadır. '.repeat(5);
  f.sql.prepare("INSERT INTO listings(id,source_id,external_id,content_hash,first_seen,updated_at,recheck_at,payload) VALUES('ilangov:8','ilangov','8','h8','2026-10-05','2026-10-05','2026-10-05',?)").run(JSON.stringify({title:'Zabıta',places:['Ankara'],requirementGroups:[],text}));
  let reply='{"groups":[{"label":"yar';
  const env={DB:f.env.DB,EXTRACT_AI_MODEL:'m',AI:{async run(){return {response:reply};}}};
  await canonicalBackfill(env);
  assert.equal(f.sql.prepare("SELECT conditions_checked c FROM listings WHERE id='ilangov:8'").get().c,null,'bozuk yanıt işaretlenmez');
  reply=JSON.stringify({groups:[{education:['Lise'],educationQuote:'ortaöğretim (lise) mezunu olmak'}]});
  f.sql.exec('DELETE FROM extraction_runs');
  await canonicalBackfill(env);
  const row=f.sql.prepare("SELECT conditions_checked c,payload FROM listings WHERE id='ilangov:8'").get();
  assert.equal(row.c,'h8');assert.deepEqual(JSON.parse(row.payload).requirementGroups[0].education,['Lise']);
});

test('ilan.gov.tr tablo satırı tek satır olarak okunur', async t => {
  const original = globalThis.fetch; t.after(() => { globalThis.fetch = original; });
  globalThis.fetch = async () => new Response(JSON.stringify({ result: { content: '<p>Genel</p><table><tr><th>S.No</th><th>Ünvan</th></tr><tr><td>1</td><td><p>Öğretim</p><p>Görevlisi</p></td></tr><tr><td></td><td></td></tr></table><p>Son</p>' } }));
  const { fetchIlanGovDetail } = await import('../src/sources.js');
  assert.equal((await fetchIlanGovDetail('1')).text, 'Genel\nS.No | Ünvan\n1 | Öğretim Görevlisi\nSon');
});
