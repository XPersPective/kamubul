// Opsiyonel harici model: Anthropic Messages API veya OpenAI uyumlu /chat/completions.
// Yalnız AI_PROVIDER=external ve EXTERNAL_AI_URL/KEY/MODEL (Cloudflare secret) varsa açılır;
// aksi halde Workers AI kullanılır. Günlük sınır mevcut AI_DAILY_JOBS sayacını paylaşır.
export const externalAiEnabled = env => env.AI_PROVIDER === 'external' && !!(env.EXTERNAL_AI_URL && env.EXTERNAL_AI_KEY && env.EXTERNAL_AI_MODEL);

export function externalRequest(env, request) {
  const base = String(env.EXTERNAL_AI_URL).replace(/\/+$/, '');
  const system = request.messages.filter(m => m.role === 'system').map(m => m.content).join('\n');
  const messages = request.messages.filter(m => m.role !== 'system');
  if (env.EXTERNAL_AI_FORMAT === 'openai') {
    return { url: base + '/chat/completions', init: { method: 'POST', headers: { 'content-type': 'application/json', authorization: 'Bearer ' + env.EXTERNAL_AI_KEY },
      body: JSON.stringify({ model: env.EXTERNAL_AI_MODEL, messages: request.messages, max_tokens: request.max_tokens, temperature: request.temperature ?? 0, ...(request.response_format ? {response_format:request.response_format} : {}), ...(env.EXTERNAL_AI_NOTHINK === '1' ? { enable_thinking: false } : {}) }) } };
  }
  return { url: base + '/v1/messages', init: { method: 'POST', headers: { 'content-type': 'application/json', 'x-api-key': env.EXTERNAL_AI_KEY, 'anthropic-version': '2023-06-01' },
    body: JSON.stringify({ model: env.EXTERNAL_AI_MODEL, system, messages, max_tokens: request.max_tokens ?? 1024, temperature: request.temperature ?? 0 }) } };
}

// Workers AI ile aynı şekli döndürür: { response: string }.
export async function externalAiRun(env, request, fetchImpl = fetch) {
  const { url, init } = externalRequest(env, request);
  if (new URL(url).protocol !== 'https:') throw new Error('external_ai_insecure_url');
  const res = await fetchImpl(url, { ...init, signal: AbortSignal.timeout(request.timeoutMs ?? 40000) });
  if (res.status === 429) throw new Error('3036: external provider rate limited');
  if (!res.ok) throw new Error('external_ai_http_' + res.status);
  const body = await res.json();
  const text = body.content?.find?.(c => c.type === 'text')?.text ?? body.choices?.[0]?.message?.content;
  if (typeof text !== 'string') throw new Error('ai_schema');
  try{if(env.DB&&['assistant','extract'].includes(request.usageBucket)&&body.usage){
    // Observed tokens, not estimated Credits: compare these with the plan console.
    const day=new Date().toISOString().slice(0,10);
    for(const [field,value] of Object.entries({input:body.usage.prompt_tokens??body.usage.input_tokens,output:body.usage.completion_tokens??body.usage.output_tokens,cached:body.usage.prompt_tokens_details?.cached_tokens})){
      if(Number.isSafeInteger(value)&&value>=0)await env.DB.prepare('INSERT INTO assistant_usage(day,bucket,count) VALUES(?,?,?) ON CONFLICT(day,bucket) DO UPDATE SET count=count+excluded.count').bind(day,'tokens:'+request.usageBucket+':'+field,value).run();
    }
  }}catch{console.error('ai_usage_record_failed');}
  return { response: text, usage: body.usage ?? null };
}
