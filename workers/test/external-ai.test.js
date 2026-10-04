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
