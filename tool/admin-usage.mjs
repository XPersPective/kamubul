// Read-only admin report. Uses the owner's Wrangler login; never exposes device IDs or credentials.
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

const days=Number(process.argv[2]??7);
if(!Number.isInteger(days)||days<1||days>30)throw new Error('Days must be 1..30');
const config=JSON.parse(readFileSync(new URL('../workers/wrangler.jsonc',import.meta.url),'utf8'));
const cli=fileURLToPath(new URL('../workers/node_modules/wrangler/bin/wrangler.js',import.meta.url));
const auth=JSON.parse(execFileSync(process.execPath,[cli,'auth','token','--json'],{encoding:'utf8',stdio:['ignore','pipe','pipe'],timeout:30000}));
const base=`https://api.cloudflare.com/client/v4/accounts/${config.account_id}`;
async function cf(path,body){
  const r=await fetch(base+path,{method:body?'POST':'GET',headers:{Authorization:`Bearer ${auth.token}`,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(30000)});
  const data=await r.json();if(!r.ok||!data.success)throw new Error(`Cloudflare request failed: ${r.status}`);
  return data.result;
}
const since=new Date(Date.now()-(days-1)*86400000).toISOString().slice(0,10);
const deployments=await cf(`/workers/scripts/${config.name}/deployments`);
const latest=deployments.deployments.reduce((a,b)=>Date.parse(a.created_on)>Date.parse(b.created_on)?a:b);
const version=await cf(`/workers/scripts/${config.name}/versions/${latest.versions[0].version_id}`);
const vars=Object.fromEntries(version.resources.bindings.filter(b=>b.type==='plain_text').map(b=>[b.name,b.text]));
const sql=`SELECT day,bucket,count FROM assistant_usage WHERE day>=? AND (bucket IN ('global','x:global','x:qwen') OR bucket LIKE 'x:qwen:h%' OR bucket LIKE 'tokens:%' OR bucket LIKE 'metrics:%') ORDER BY day,bucket`;
const query=async(sql,params=[])=> (await cf(`/d1/database/${config.d1_databases[0].database_id}/query`,{sql,params}))[0].results;
const rows=await query(sql,[since]);
const users=await query("SELECT day,COUNT(*) active_installations,SUM(count) attempts FROM assistant_usage WHERE day>=? AND bucket LIKE 'inst:%' GROUP BY day ORDER BY day",[since]);
for(const user of users){const tokens=rows.filter(r=>r.day===user.day&&['tokens:assistant:input','tokens:assistant:output'].includes(r.bucket));user.reportedTokensPerActiveInstallation=tokens.length?tokens.reduce((sum,r)=>sum+r.count,0)/user.active_installations:null;}
const metrics={};
for(const {bucket,count} of rows){const match=bucket.match(/^metrics:(assistant|extract):(.+):(free|pro|server):(calls|measured|input|output|cached)$/);if(!match)continue;const key=match.slice(1,4).join(':');(metrics[key]??={})[match[4]]=((metrics[key]??{})[match[4]]??0)+count;}
for(const value of Object.values(metrics))value.meanTokensPerMeasuredResponse=value.measured?((value.input??0)+(value.output??0))/value.measured:null;
const daily=await query('SELECT * FROM daily_usage WHERE day>=? ORDER BY day',[since]);
const backlog=await query("SELECT conditions_error reason,COUNT(*) notices FROM listings WHERE active=1 AND (conditions_checked IS NULL OR conditions_checked!=content_hash) GROUP BY conditions_error");
const outbox=await query('SELECT state,COUNT(*) notifications FROM notification_outbox GROUP BY state');
let providerLimits={status:'credentials_unavailable'},credits={status:'console_auth_required',balance:null};
try{
  const credentialFile=process.env.KAMUBUL_QWEN_ENV??'D:/AppPublishing/apps/kamubul/credentials/ai/qwen.env';
  const e=Object.fromEntries(readFileSync(credentialFile,'utf8').split(/\r?\n/).filter(l=>l&&!l.startsWith('#')&&l.includes('=')).map(l=>{const i=l.indexOf('=');return[l.slice(0,i).trim(),l.slice(i+1).trim().replace(/^['"]|['"]$/g,'')];}));
  const origin=new URL(e.EXTERNAL_AI_URL).origin;
  if(new URL(origin).protocol!=='https:')throw new Error('HTTPS required');
  const responses=await Promise.all(['qwen3.8-flash','qwen3.6-flash'].map(async model=>{
    const r=await fetch(`${origin}/api/v1/models/limits?model=${model}&page_size=100`,{headers:{Authorization:`Bearer ${e.EXTERNAL_AI_KEY}`},signal:AbortSignal.timeout(20000)});
    if(!r.ok)return {model,status:r.status,limits:null};
    const data=await r.json();return {model,status:r.status,limits:data.output?.quotas??null};
  }));
  providerLimits={status:responses.every(r=>r.limits)?'available':'not_exposed_by_token_plan_endpoint',models:responses};
}catch{providerLimits={status:'query_failed',limits:null};}
console.log(JSON.stringify({generatedAt:new Date().toISOString(),since,days,liveVersion:latest.versions[0].version_id,
  limits:{extractionQwenDaily:Number(vars.EXTRACT_QWEN_DAILY),extractionQwenHourly:Number(vars.EXTRACT_QWEN_HOURLY),extractionGlobal:Number(vars.EXTRACT_DAILY_GLOBAL),assistantFree:Number(vars.ASSISTANT_DAILY_INSTALL??30),assistantPro:Number(vars.ASSISTANT_DAILY_PRO??100),assistantGlobal:Number(vars.ASSISTANT_DAILY_GLOBAL??300),assistantIp:Number(vars.ASSISTANT_DAILY_IP??500),queueJobsDaily:3000},
  metrics,activeInstallationsWithAttempts:users,usage:rows.filter(r=>!r.bucket.startsWith('metrics:')),daily,backlog,outbox,providerLimits,credits,
  notes:['Tokens are provider-reported, not Credits.','Per-response means require the new measured counters; historical token totals remain separate.','Reported tokens per active installation use attempted installations that day; historical recording may cover only part of a day.','Installations are anonymous app instances, not registered people.','HTTP failures/timeouts may consume provider Credits without returning usage; reconcile with provider console.','Credits depend on model, input/output/cache and discounts; do not convert using a guessed fixed rate.']},null,2));
