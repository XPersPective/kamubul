import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {plain,parseIlanGovList,parseIlanGovDetail,fetchIlanGovPage,fetchIlanGovList,fetchIlanGovDetail} from '../src/sources.js';

test('ilan.gov identity, official origin and dates are checked; missing deadline stays unknown', () => {
  const raw={result:{numFound:1,ads:[{id:123,title:'Belediye personel alımı',urlStr:'/ilan/123/belediye',advertiserName:'Belediye',addressCityName:'İzmir',publishStartDate:'2026-10-01'}]}};
  const {items,total}=parseIlanGovList(raw);
  assert.equal(total,1);assert.equal(items.length,1);
  assert.equal(items[0].id,'ilangov:123');assert.equal(items[0].deadline,null);
  assert.deepEqual(items[0].places,['İzmir']);
  assert.throws(()=>parseIlanGovList({result:{ads:[],numFound:'2'}}),/layout_changed/);
  assert.throws(()=>parseIlanGovList({result:{numFound:2,ads:[...raw.result.ads,{id:124,title:'Bad',urlStr:'/ilan/999/wrong'}]}}),/layout_changed/);
});

test('ilan.gov page request uses only personel category and bounded pagination; detail never fetches arbitrary IDs', async t => {
  const original=globalThis.fetch;t.after(()=>globalThis.fetch=original);
  const calls=[];
  globalThis.fetch=async(url,init)=>{calls.push([url,init]);return Response.json(url.includes('AdsByFilter')?{result:{ads:[],numFound:0}}:{result:{content:'<style>secret</style><p>Başvuru şartları</p><script>command()</script><p>Lisans mezunu olmak.</p>'}});};
  await fetchIlanGovPage(2);
  assert.deepEqual(JSON.parse(calls[0][1].body),{keys:{ats:[5]},skipCount:40,maxResultCount:20});
  assert.equal(calls[0][1].redirect,'manual');
  assert.equal((await fetchIlanGovDetail('123')).text,'Başvuru şartları\nLisans mezunu olmak.');
  await assert.rejects(fetchIlanGovPage(1000),/source_page/);
  await assert.rejects(fetchIlanGovPage(0,101),/source_page/);
  await assert.rejects(fetchIlanGovDetail('../private'),/source_identity/);
  assert.equal(calls.length,2);
});

const ad=id=>({id,title:'İlan '+id,urlStr:'/ilan/'+id+'/test'});
test('all ilan.gov pages above the former 200 row limit are collected without silent partial success',async t=>{
  const original=globalThis.fetch;t.after(()=>globalThis.fetch=original);let calls=0;
  globalThis.fetch=async(_,options)=>{calls++;const body=JSON.parse(options.body);return Response.json({result:{numFound:221,ads:Array.from({length:Math.min(20,221-body.skipCount)},(_,i)=>ad(i+body.skipCount))}});};
  const all=await fetchIlanGovList();assert.equal(all.length,221);assert.equal(all.at(-1).externalId,'220');assert.equal(calls,12);
  await assert.rejects(fetchIlanGovPage(2,100),/source_page/);assert.equal(calls,12,'clamped page size cannot skip official rows');
});
test('empty, duplicate, malformed and changing pages never produce a successful incomplete snapshot',async t=>{
  const original=globalThis.fetch;t.after(()=>globalThis.fetch=original);
  for(const mode of ['empty','repeat','invalid','total']){
    globalThis.fetch=async(_,options)=>{const offset=JSON.parse(options.body).skipCount;return Response.json({result:{numFound:mode==='total'&&offset?41:40,ads:offset&&mode==='empty'?[]:Array.from({length:20},(_,i)=>mode==='invalid'&&offset&&i===0?{id:'bad'}:ad(i+(offset&&mode==='repeat'?0:offset)))}});};
    await assert.rejects(fetchIlanGovList(),{code:{empty:'source_incomplete',repeat:'source_page_repeated',invalid:'layout_changed',total:'source_total_changed'}[mode]});
  }
});

const corpus=JSON.parse(readFileSync(new URL('./fixtures/ilangov-details.json',import.meta.url),'utf8')).notices;
test('captured official detail corpus retains full text, every table cell, headers and row-specific quota evidence',()=>{
  assert.deepEqual(corpus.map(n=>n.id),['2242968','2244776','2244748','2244739','2236938','2234989','2243231']);
  for(const notice of corpus){
    const detail=parseIlanGovDetail({result:notice.result},notice.id);assert.equal(detail.text,notice.text,notice.id+': stored full text changes');
    const flattened=detail.text.replace(/\s+/g,' ');
    for(const cell of notice.result.content.matchAll(/<t([dh])\b[^>]*>([\s\S]*?)<\/t\1>/gi)){
      const expected=plain(cell[2]).replace(/\s+/g,' ');if(expected)assert.ok(flattened.includes(expected),notice.id+': lost cell '+expected.slice(0,100));
    }
  }
  const text=id=>corpus.find(n=>n.id===id).text;
  assert.match(text('2242968'),/Kadro Sayısı \| ALES Puan Şartı/);assert.match(text('2242968'),/Öğr\. Gör\. \| 1 \| 70 \| 85/);
  assert.match(text('2244748'),/UNVAN \| ADET \| DERECE \| ALES \| YABANCI DİL \| AÇIKLAMA/);
  assert.match(text('2244739'),/Kıdemli Java Yazılım Uzmanı \| 3 \| 30/);assert.match(text('2244739'),/Kıdemli \.Net Yazılım Uzmanı \| 2 \| 20/);
  assert.equal(text('2244739').match(/SIRA \| POZİSYON \| ALINACAK KİŞİ SAYISI/g).length,2,'official repeated table is retained for readers; extraction must deduplicate it');
  assert.match(text('2236938'),/İLAN NO \| ÜNVANI \| KPSS PUAN TÜRÜ \| ADET \| ARANAN NİTELİKLER/);
  assert.match(text('2236938'),/TİBU-01 \| Destek Personeli- Şoför \(Erkek\) \| Ön Lisans KPSSP93 \| 1 \|/);
});
test('explicit official deadline metadata transfers without treating publication/ad display dates as application deadlines',()=>{
  for(const notice of corpus){const detail=parseIlanGovDetail({result:notice.result});if(notice.id==='2243231')assert.equal(detail.deadline,'2026-10-31T20:59:59.000Z');else assert.equal(detail.deadline,undefined,notice.id+': no native deadline');}
  const raw={result:{id:'9',content:'<p>Metin</p>',publishes:[{endDate:'2026-12-31'}],adTypeFilters:[{key:'Resmî Gazete Yayım Tarihi',value:'05.10.2026'}]}};
  assert.equal(parseIlanGovDetail(raw).deadline,undefined);
  for(const value of ['31.02.2026','garbage','31.10.2026 13:00']){
    raw.result.adTypeFilters=[{key:'SON BAŞVURU TARİHİ',value}];assert.equal(parseIlanGovDetail(raw).deadline,undefined);
  }
  raw.result.adTypeFilters=[{key:'Son başvuru Tarihi',value:'29.02.2028'}];assert.equal(parseIlanGovDetail(raw).deadline,'2028-02-29T20:59:59.000Z');
  raw.result.adTypeFilters.push({key:'Son Başvuru Tarihi',value:'01.03.2028'});assert.equal(parseIlanGovDetail(raw).deadline,undefined,'ambiguous metadata is unknown');
  assert.throws(()=>parseIlanGovDetail(raw,'8'),/source_identity/);
});

test('official Gazette civil date stays separate from index publication and application deadline, with native evidence',()=>{
  for(const notice of corpus){
    const detail=parseIlanGovDetail({result:notice.result});
    const expected={'2242968':'2026-10-02','2244776':'2026-10-05','2244748':'2026-10-05','2244739':'2026-10-04','2236938':'2026-09-28','2234989':'2026-09-25'}[notice.id];
    assert.equal(detail.gazettePublishedAt,expected,notice.id);assert.equal(detail.publishedAt,undefined,'index publication is not overwritten');
    if(expected)assert.equal(detail.gazettePublishedQuote,'Resmî Gazete Yayım Tarihi: '+notice.result.adTypeFilters.find(f=>f.key==='Resmî Gazete Yayım Tarihi').value);
    else assert.equal(detail.gazettePublishedQuote,undefined);
  }
  const raw={result:{content:'Metin',adTypeFilters:[{key:'Resmî Gazete Yayım Tarihi',value:'29.02.2028'}]}};
  assert.equal(parseIlanGovDetail(raw).gazettePublishedAt,'2028-02-29');assert.equal(parseIlanGovDetail(raw).deadline,undefined);
  for(const value of ['31.02.2026','29.02.2026','2026-10-05','05.10.2026 17:00','garbage']){
    raw.result.adTypeFilters[0].value=value;const detail=parseIlanGovDetail(raw);assert.equal(detail.gazettePublishedAt,undefined);assert.equal(detail.gazettePublishedQuote,undefined);
  }
  raw.result.adTypeFilters=[{key:'Yayım Tarihi',value:'05.10.2026'}];assert.equal(parseIlanGovDetail(raw).gazettePublishedAt,undefined,'unlabeled publication is not a Gazette date');
  raw.result.adTypeFilters=[{key:'Resmî Gazete Yayım Tarihi',value:'05.10.2026'},{key:'Resmî Gazete Yayım Tarihi',value:'06.10.2026'}];assert.equal(parseIlanGovDetail(raw).gazettePublishedAt,undefined);
});
