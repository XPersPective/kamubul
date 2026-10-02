import {test} from 'node:test';
import assert from 'node:assert/strict';
import {sourceFetch} from '../src/sources.js';

const url='https://kariyerkapisi.gov.tr/RSS';
const cap=3*1024*1024;

test('source errors cancel unread bodies without waiting for failing or stalled cleanup',async t=>{
  const original=globalThis.fetch;t.after(()=>{globalThis.fetch=original;});
  for(const [status,length,code] of [[403,0,'blocked'],[522,0,'source_http_522'],[302,0,'source_http_302'],[200,cap+1,'source_oversize']]){
    for(const fails of [true,false]){
      let cancelled=false;
      const body=new ReadableStream({cancel(){cancelled=true;return fails?Promise.reject(new Error('cancel failure')):new Promise(()=>{});}});
      globalThis.fetch=async(_,options)=>{
        assert.equal(options.redirect,'manual');assert.ok(options.signal instanceof AbortSignal);
        return new Response(body,{status,headers:{'content-length':String(length)}});
      };
      await assert.rejects(sourceFetch(url),{code});
      assert.equal(cancelled,true,`${status}/${length} must release unread response`);
    }
  }
});

test('source byte cap accepts exact length and rejects streamed overflow with cancellation',async t=>{
  const original=globalThis.fetch;t.after(()=>{globalThis.fetch=original;});
  for(const extra of [0,1]){
    let cancelled=false;
    const body=new ReadableStream({start(controller){
      controller.enqueue(new Uint8Array(cap).fill(65));
      if(extra)controller.enqueue(new Uint8Array(extra));else controller.close();
    },cancel(){cancelled=true;}});
    globalThis.fetch=async()=>new Response(body);
    if(extra){await assert.rejects(sourceFetch(url),{code:'source_oversize'});assert.equal(cancelled,true);}
    else assert.equal((await sourceFetch(url)).length,cap);
  }
});

test('stream error remains the source failure even when cancellation fails',async t=>{
  const original=globalThis.fetch;t.after(()=>{globalThis.fetch=original;});
  const failed=new Error('upstream stream failure');
  globalThis.fetch=async()=>new Response(new ReadableStream({start(controller){controller.error(failed);}}));
  await assert.rejects(sourceFetch(url),e=>e===failed);
});

test('bodyless errors retain HTTP classification and bodyless success is explicit',async t=>{
  const original=globalThis.fetch;t.after(()=>{globalThis.fetch=original;});
  for(const [status,code] of [[403,'blocked'],[522,'source_http_522'],[200,'source_empty']]){
    globalThis.fetch=async()=>new Response(null,{status});
    await assert.rejects(sourceFetch(url),{code});
  }
});

test('source allowlist rejects credentials, ports, HTTP and foreign hosts before fetch',async t=>{
  const original=globalThis.fetch;t.after(()=>{globalThis.fetch=original;});
  let calls=0;globalThis.fetch=async()=>{calls++;throw new Error('must not fetch');};
  for(const rejected of ['http://kariyerkapisi.gov.tr/RSS','https://user:secret@kariyerkapisi.gov.tr/RSS','https://kariyerkapisi.gov.tr:444/RSS','https://other.example/RSS'])
    await assert.rejects(sourceFetch(rejected),{code:'host_rejected'});
  assert.equal(calls,0);
});
