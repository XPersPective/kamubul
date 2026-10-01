import {test} from 'node:test';
import assert from 'node:assert/strict';
import {cachedFetch} from '../src/worker.js';

function setup(t){
  const before=Object.getOwnPropertyDescriptor(globalThis,'caches'),entries=new Map(),pending=[];
  let reads=0,matches=0,puts=0;
  Object.defineProperty(globalThis,'caches',{configurable:true,value:{default:{
    async match(key){matches++;return entries.get(key.url)?.clone();},
    async put(key,response){puts++;entries.set(key.url,response.clone());},
  }}});
  t.after(()=>{if(before)Object.defineProperty(globalThis,'caches',before);else delete globalThis.caches;});
  const DB={prepare(query){return {bind(){return this;},async first(){reads++;return query.includes('installations')?null:{n:40};},async all(){reads++;return {results:[]};}};}};
  const ctx={waitUntil(promise){pending.push(promise);}};
  return {env:{DB},ctx,entries,counts:()=>({reads,matches,puts}),settle:()=>Promise.all(pending)};
}

test('public cache hit and conditional hit skip database work',async t=>{
  const state=setup(t),request=new Request('https://api/api/v2/meta');
  const first=await cachedFetch(request,state.env,state.ctx);await state.settle();
  assert.equal(first.headers.get('X-KamuBul-Cache'),'MISS');
  const expected=await first.json(),before=state.counts().reads;
  const second=await cachedFetch(request,state.env,state.ctx);
  assert.equal(second.headers.get('X-KamuBul-Cache'),'HIT');assert.deepEqual(await second.json(),expected);
  const conditional=await cachedFetch(new Request(request,{headers:{'If-None-Match':'W/'+first.headers.get('etag')}}),state.env,state.ctx);
  assert.equal(conditional.status,304);assert.equal(await conditional.text(),'');assert.equal(state.counts().reads,before);
  const stored=[...state.entries.values()][0];assert.equal(stored.headers.get('Cache-Control'),'public, max-age=60');
});

test('private, credentialed, unknown query and health requests bypass public cache',async t=>{
  const state=setup(t),id='a'.repeat(32);
  for(const request of [
    new Request('https://api/api/v2/installations/'+id+'/notifications',{headers:{Authorization:'Bearer '+'b'.repeat(64)}}),
    new Request('https://api/api/v2/meta',{headers:{Authorization:'Bearer private'}}),
    new Request('https://api/api/v2/meta',{headers:{Cookie:'session=private'}}),
    new Request('https://api/api/v2/meta?user=private'),
    new Request('https://api/api/v2/health'),
    new Request('https://api/api/v2/meta',{headers:{'Cache-Control':'no-store'}}),
  ])await cachedFetch(request,state.env,state.ctx);
  await state.settle();assert.equal(state.counts().matches,0);assert.equal(state.counts().puts,0);
});

test('query order shares a key, distinct watermarks stay isolated, no-cache refreshes',async t=>{
  const state=setup(t);
  const fetch=url=>cachedFetch(new Request('https://api'+url),state.env,state.ctx);
  await fetch('/api/v2/changes?after=0&watermark=40&limit=30');await state.settle();
  const before=state.counts().reads;
  assert.equal((await fetch('/api/v2/changes?limit=30&watermark=40&after=0')).headers.get('X-KamuBul-Cache'),'HIT');
  assert.equal(state.counts().reads,before);
  assert.equal((await fetch('/api/v2/changes?after=0&watermark=39&limit=30')).headers.get('X-KamuBul-Cache'),'MISS');
  await cachedFetch(new Request('https://api/api/v2/changes?after=0&watermark=40&limit=30',{headers:{'Cache-Control':'no-cache'}}),state.env,state.ctx);
  assert.ok(state.counts().reads>before);await state.settle();
});

test('cache read/write failures preserve public API availability',async t=>{
  const state=setup(t);
  globalThis.caches.default={async match(){throw new Error('offline');},async put(){throw new Error('offline');}};
  const response=await cachedFetch(new Request('https://api/api/v2/meta'),state.env,state.ctx);
  assert.equal(response.status,200);assert.equal((await response.json()).latestSeq,40);await state.settle();
});

test('missing detail and database failure are never cached',async t=>{
  const state=setup(t);
  const missing=await cachedFetch(new Request('https://api/api/v2/listings/missing'),{DB:{prepare(){return {bind(){return this;},async first(){return null;}};}}},state.ctx);
  assert.equal(missing.status,404);
  const failed=await cachedFetch(new Request('https://api/api/v2/meta'),{DB:{prepare(){throw new Error('database_offline');}}},state.ctx);
  assert.equal(failed.status,503);await state.settle();assert.equal(state.counts().puts,0);
});
