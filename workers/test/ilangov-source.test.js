import {test} from 'node:test';
import assert from 'node:assert/strict';
import {parseIlanGovList,fetchIlanGovPage,fetchIlanGovList,fetchIlanGovDetail} from '../src/sources.js';

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
