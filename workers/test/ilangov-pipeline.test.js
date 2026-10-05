import {test} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync,readdirSync} from 'node:fs';
import {readSource,canonicalConditions,canonicalBackfill,processNotice} from '../src/pipeline.js';

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
  await readSource({...f.env,SOURCE_DETAILS_PER_TICK:'1'});
  assert.equal(f.sql.prepare("SELECT COUNT(*) n FROM listings WHERE source_id='ilangov'").get().n,2,'liste ayrıntı/AI kuyruğunu beklemeden eksiksiz görünür');
  assert.equal(f.sql.prepare("SELECT state FROM sources WHERE id='ilangov'").get().state,'processing');
  await readSource({...f.env,SOURCE_DETAILS_PER_TICK:'1'});
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

test('durable source pages resume across ticks and never skip the server native 20-record page',async t=>{
  const f=setup(t);const skips=[];
  globalThis.fetch=async(url,options)=>{
    if(String(url).includes('AdsByFilter')){
      const body=JSON.parse(options.body);skips.push(body.skipCount);assert.equal(body.maxResultCount,20);
      return Response.json({result:{numFound:41,ads:Array.from({length:Math.min(20,41-body.skipCount)},(_,i)=>({id:body.skipCount+i+1,title:'Kamu personeli '+i,urlStr:'/ilan/'+(body.skipCount+i+1)+'/kamu',publishStartDate:'2026-10-01'}))}});
    }
    return Response.json({result:{content:'<p>Resmî kamu personeli ilan metni</p>'}});
  };
  await readSource(f.env);assert.equal(f.sql.prepare('SELECT COUNT(*) n FROM listings').get().n,0);
  await readSource(f.env);assert.equal(f.sql.prepare("SELECT list_page FROM sources WHERE id='ilangov'").get().list_page,2);
  await readSource(f.env);
  assert.deepEqual(skips,[0,20,40]);assert.equal(f.sql.prepare('SELECT COUNT(*) n FROM listings').get().n,41);
  assert.equal(f.sql.prepare("SELECT COUNT(*) n FROM listings WHERE json_extract(payload,'$.text') IS NOT NULL").get().n,1);
});

test('new native identities are published while the older detail backlog is still running',async t=>{
  const f=setup(t);
  await readSource(f.env);
  f.sql.exec("UPDATE sources SET last_attempt='1970-01-01' WHERE id='ilangov'");
  const fetchBefore=globalThis.fetch;
  globalThis.fetch=async(url,options)=>String(url).includes('AdsByFilter')
    ?Response.json({result:{numFound:3,ads:[11,12,13].map(id=>({id,title:'Kamu personeli '+id,urlStr:'/ilan/'+id+'/kamu',publishStartDate:'2026-10-01'}))}})
    :fetchBefore(url,options);
  await readSource(f.env);
  assert.equal(f.sql.prepare('SELECT COUNT(*) n FROM listings').get().n,3);
  const source=f.sql.prepare("SELECT * FROM sources WHERE id='ilangov'").get();
  assert.equal(source.batch_offset,2,'refresh preserves the completed detail cursor');
  assert.deepEqual(JSON.parse(source.pending_batch).map(item=>item.id),['ilangov:11','ilangov:12','ilangov:13']);
  assert.equal(JSON.parse(f.sql.prepare("SELECT payload FROM listings WHERE id='ilangov:13'").get().payload).detailState,'pending');
  await readSource(f.env);
  assert.equal(f.sql.prepare("SELECT pending_batch FROM sources WHERE id='ilangov'").get().pending_batch,null);
  assert.equal(f.sql.prepare('SELECT COUNT(*) n FROM processing_jobs').get().n,3);
});

test('one valid Qwen extraction finishes the canonical job without separate summary inference',async t=>{
  const f=setup(t),text='Lisans mezunu olmak. '+'Genel açıklamalar ve başvuru belgeleri. '.repeat(800);
  f.sql.prepare("INSERT INTO listings(id,source_id,external_id,content_hash,first_seen,updated_at,recheck_at,payload) VALUES('ilangov:e','ilangov','e','h','2026-10-01','2026-10-01','2026-10-01',?)").run(JSON.stringify({text,places:['Ankara']}));
  f.sql.prepare("INSERT INTO processing_jobs(id,listing_id,input_hash,input,due_at) VALUES('j','ilangov:e','h',?,'1970-01-01')").run(JSON.stringify({text,places:['Ankara']}));
  let calls=0;const env={...f.env,AI_SUMMARY_ENABLED:'0',AI_PROVIDER:'external',EXTRACT_AI_PROVIDER:'external',EXTRACT_QWEN_DAILY:'10',EXTERNAL_AI_URL:'https://model.test',EXTERNAL_AI_KEY:'test',EXTERNAL_AI_MODEL:'flash',EXTERNAL_AI_FORMAT:'openai'};
  globalThis.fetch=async(url,options)=>{calls++;assert.match(url,/model.test/);assert.equal(JSON.parse(options.body).response_format.type,'json_object');return Response.json({choices:[{message:{content:JSON.stringify({groups:[{education:['Lisans'],educationQuote:'Lisans mezunu olmak'}]})}}],usage:{prompt_tokens:100,completion_tokens:40}});};
  await processNotice(env);await processNotice(env);
  assert.equal(calls,1);assert.equal(f.sql.prepare("SELECT state FROM processing_jobs WHERE id='j'").get().state,'completed');
  const row=f.sql.prepare("SELECT payload,conditions_checked FROM listings WHERE id='ilangov:e'").get();
  assert.equal(JSON.parse(row.payload).text,text);assert.equal(row.conditions_checked,'h');
  assert.equal(f.sql.prepare("SELECT count FROM assistant_usage WHERE bucket='tokens:extract:input'").get().count,100);
});

test('quota wait on one notice preserves its text and gives the next notice a turn',async t=>{
  const f=setup(t);
  for(const id of ['a','b'])f.sql.prepare("INSERT INTO listings(id,source_id,external_id,content_hash,first_seen,updated_at,recheck_at,payload) VALUES(?,'ilangov',?,?,'2026-10-01','2026-10-01','1970-01-01',?)").run('ilangov:'+id,id,id,JSON.stringify({text:'Lisans mezunu olmak. '+id.repeat(300)}));
  const env={...f.env,EXTRACT_AI_PROVIDER:'external',AI_PROVIDER:'external',EXTERNAL_AI_URL:'https://model.test',EXTERNAL_AI_KEY:'test',EXTERNAL_AI_MODEL:'flash',EXTERNAL_AI_FORMAT:'openai',EXTRACT_QWEN_DAILY:'1',EXTRACT_QWEN_HOURLY:'1'};
  f.sql.prepare('INSERT INTO assistant_usage(day,bucket,count) VALUES(?,?,1)').run(new Date().toISOString().slice(0,10),'x:qwen:h'+new Date().toISOString().slice(11,13));
  await canonicalBackfill(env);
  assert.ok(f.sql.prepare("SELECT conditions_due_at FROM listings WHERE id='ilangov:a'").get().conditions_due_at>new Date().toISOString());
  await canonicalBackfill(env);
  assert.ok(f.sql.prepare("SELECT conditions_due_at FROM listings WHERE id='ilangov:b'").get().conditions_due_at>new Date().toISOString());
  assert.equal(f.sql.prepare("SELECT COUNT(*) n FROM listings WHERE json_extract(payload,'$.text') IS NOT NULL AND conditions_checked IS NULL").get().n,2);
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
  f.sql.exec("UPDATE listings SET conditions_due_at='1970-01-01'");
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
