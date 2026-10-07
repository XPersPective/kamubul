import test from 'node:test';
import assert from 'node:assert/strict';
import { externalAiEnabled, externalAiRun, externalRequest } from '../src/external_ai.js';

const env = { AI_PROVIDER: 'external', EXTERNAL_AI_URL: 'https://api.example.test', EXTERNAL_AI_KEY: 'k', EXTERNAL_AI_MODEL: 'm' };
const request = { messages: [{ role: 'system', content: 'sys' }, { role: 'user', content: 'u' }], max_tokens: 50, temperature: 0 };

test('disabled unless provider and all secrets are set', () => {
  assert.equal(externalAiEnabled({}), false);
  assert.equal(externalAiEnabled({ ...env, EXTERNAL_AI_KEY: '' }), false);
  assert.equal(externalAiEnabled(env), true);
});

test('anthropic messages request and response', async () => {
  const { url, init } = externalRequest(env, request);
  assert.equal(url, 'https://api.example.test/v1/messages');
  assert.equal(init.headers['x-api-key'], 'k');
  const body = JSON.parse(init.body);
  assert.equal(body.system, 'sys');
  assert.deepEqual(body.messages, [{ role: 'user', content: 'u' }]);
  const out = await externalAiRun(env, request, async () => new Response(JSON.stringify({ content: [{ type: 'text', text: '{"a":1}' }] })));
  assert.equal(out.response, '{"a":1}');
});

test('openai compatible request and response', async () => {
  const e = { ...env, EXTERNAL_AI_FORMAT: 'openai' };
  assert.equal(externalRequest(e, request).url, 'https://api.example.test/chat/completions');
  const out = await externalAiRun(e, request, async () => new Response(JSON.stringify({ choices: [{ message: { content: 'ok' } }] })));
  assert.equal(out.response, 'ok');
});

test('429 maps to quota wait code; http and insecure urls fail closed', async () => {
  await assert.rejects(externalAiRun(env, request, async () => new Response('', { status: 429 })), /^Error: 3036:/);
  await assert.rejects(externalAiRun(env, request, async () => new Response('', { status: 500 })), /external_ai_http_500/);
  await assert.rejects(externalAiRun({ ...env, EXTERNAL_AI_URL: 'http://x.test' }, request, async () => new Response('{}')), /insecure/);
});

test('qwen compatible mode can disable thinking', () => {
  const e = { ...env, EXTERNAL_AI_FORMAT: 'openai', EXTERNAL_AI_NOTHINK: '1' };
  assert.equal(JSON.parse(externalRequest(e, request).init.body).enable_thinking, false);
  assert.equal('enable_thinking' in JSON.parse(externalRequest({ ...e, EXTERNAL_AI_NOTHINK: '' }, request).init.body), false);
});

test('Qwen receives JSON response format and exposes provider token usage',async()=>{
  const e={...env,EXTERNAL_AI_FORMAT:'openai'};
  const req={...request,response_format:{type:'json_object'}};
  assert.deepEqual(JSON.parse(externalRequest(e,req).init.body).response_format,{type:'json_object'});
  const usage={prompt_tokens:100,completion_tokens:20,total_tokens:120};
  const out=await externalAiRun(e,req,async()=>Response.json({choices:[{message:{content:'{}'}}],usage}));
  assert.deepEqual(out.usage,usage);
});

test('usage counts actual responses by model and tier, including malformed output and missing usage',async()=>{
  const rows=[];
  const DB={prepare:()=>({bind:(...values)=>values}),batch:async values=>rows.push(...values)};
  const e={...env,DB,EXTERNAL_AI_FORMAT:'openai'};
  const req={...request,usageBucket:'assistant',usageTier:'pro'};
  await externalAiRun(e,req,async()=>Response.json({choices:[{message:{content:'ok'}}],usage:{prompt_tokens:100,completion_tokens:20,prompt_tokens_details:{cached_tokens:50}}}));
  const value=bucket=>rows.filter(r=>r[1]===bucket).reduce((sum,r)=>sum+r[2],0);
  assert.equal(value('metrics:assistant:m:pro:calls'),1);
  assert.equal(value('metrics:assistant:m:pro:measured'),1);
  assert.equal(value('metrics:assistant:m:pro:input'),100);
  assert.equal(value('tokens:assistant:cached'),50);
  await assert.rejects(externalAiRun(e,req,async()=>Response.json({usage:{prompt_tokens:2,completion_tokens:1}})),/ai_schema/);
  await externalAiRun(e,req,async()=>Response.json({choices:[{message:{content:'ok'}}]}));
  assert.equal(value('metrics:assistant:m:pro:calls'),3);
  assert.equal(value('metrics:assistant:m:pro:measured'),2);
  assert.equal(value('metrics:assistant:m:pro:input'),102);
  await externalAiRun(e,req,async()=>Response.json({choices:[{message:{content:'ok'}}],usage:{prompt_tokens:99}}));
  assert.equal(value('metrics:assistant:m:pro:measured'),2);
  assert.equal(value('metrics:assistant:m:pro:input'),102,'partial usage must not inflate the measured mean');
});
