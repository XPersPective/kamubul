import {test} from 'node:test';
import assert from 'node:assert/strict';
import {parseIlanGovList,fetchIlanGovPage,fetchIlanGovDetail} from '../src/sources.js';

test('ilan.gov identity, official origin and dates are checked; missing deadline stays unknown', () => {
  const raw={result:{numFound:2,ads:[{id:123,title:'Belediye personel alımı',urlStr:'/ilan/123/belediye',advertiserName:'Belediye',addressCityName:'İzmir',publishStartDate:'2026-10-01'}, {id:124,title:'Bad',urlStr:'/ilan/999/wrong'}]}};
  const {items,total}=parseIlanGovList(raw);
  assert.equal(total,2);assert.equal(items.length,1);
  assert.equal(items[0].id,'ilangov:123');assert.equal(items[0].deadline,null);
  assert.deepEqual(items[0].places,['İzmir']);
  assert.throws(()=>parseIlanGovList({result:{ads:[],numFound:'2'}}),/layout_changed/);
});

test('ilan.gov page request uses only personel category and bounded pagination; detail never fetches arbitrary IDs', async t => {
  const original=globalThis.fetch;t.after(()=>globalThis.fetch=original);
  const calls=[];
  globalThis.fetch=async(url,init)=>{calls.push([url,init]);return Response.json(url.includes('AdsByFilter')?{result:{ads:[],numFound:0}}:{result:{content:'<style>secret</style><p>Başvuru şartları</p><script>command()</script><p>Lisans mezunu olmak.</p>'}});};
  await fetchIlanGovPage(2);
  assert.deepEqual(JSON.parse(calls[0][1].body),{keys:{ats:[5]},skipCount:40,maxResultCount:20});
  assert.equal(calls[0][1].redirect,'manual');
  assert.equal((await fetchIlanGovDetail('123')).text,'Başvuru şartları\nLisans mezunu olmak.');
  await assert.rejects(fetchIlanGovPage(10),/source_page/);
  await assert.rejects(fetchIlanGovDetail('../private'),/source_identity/);
  assert.equal(calls.length,2);
});
