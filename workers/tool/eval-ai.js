// Real public notice, real Workers AI; all catalogue writes stay in memory.
import assert from 'node:assert/strict';
import {readFileSync,readdirSync,writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {DatabaseSync} from 'node:sqlite';
import {fileURLToPath} from 'node:url';
import {aiExtractionRevision,processNotice,semanticInput,splitAiText} from '../src/pipeline.js';
import {sha256} from '../src/worker.js';

const [inputPath,reportPath,modelOverride]=process.argv.slice(2);
assert.ok(inputPath&&reportPath,'Usage: node tool/eval-ai.js real-notice.json report.json [model]');
const notice=JSON.parse(readFileSync(inputPath,'utf8'));
assert.ok(notice.id&&notice.externalId&&notice.sourceId&&notice.title&&notice.text,'Full official notice required');
const sourceUrl=new URL(notice.url);
assert.equal(sourceUrl.protocol,'https:');
assert.ok(['kariyerkapisi.gov.tr','www.sbb.gov.tr'].includes(sourceUrl.hostname),'Official source required');
assert.ok(!notice.deadline||Date.parse(notice.deadline)>Date.now(),'Use an active notice');
const text=[notice.text,...(notice.positions??[]).map(p=>p.text)].filter(Boolean).join('\n\n');
const chunks=splitAiText(text),callLimit=chunks.length+(chunks.length>1?1:0);
// ponytail: three paid-in-compute calls maximum per manual pilot; larger documents need a reviewed evaluation budget.
// This is a spend ceiling, not a completion estimate: revision2 reduction can require additional calls.
assert.ok(callLimit<=3,'Pilot permits at most three model calls');
const config=JSON.parse(readFileSync(new URL('../wrangler.jsonc',import.meta.url),'utf8'));
const aiModel=modelOverride??config.vars.AI_MODEL;
assert.ok(['@cf/meta/llama-3.1-8b-instruct-fp8','@cf/meta/llama-3.1-8b-instruct','@cf/meta/llama-3.3-70b-instruct-fp8-fast'].includes(aiModel),'Only reviewed Free-accessible models; no paid fallback');
// Capture authorized OAuth in memory; never persist or print credentials.
let auth;
try{auth=JSON.parse(execFileSync(process.execPath,[fileURLToPath(new URL('../node_modules/wrangler/bin/wrangler.js',import.meta.url)),'auth','token','--json'],{encoding:'utf8',stdio:['ignore','pipe','pipe'],timeout:30000}));}
catch{throw new Error('wrangler_authorization_failed');}
assert.ok(auth.token,'Wrangler authorization required');
const sql=new DatabaseSync(':memory:');sql.exec('PRAGMA foreign_keys=ON');
for(const name of readdirSync(new URL('../migrations/',import.meta.url)).filter(n=>n.endsWith('.sql')).sort())sql.exec(readFileSync(new URL('../migrations/'+name,import.meta.url),'utf8'));
const DB={prepare(query){let values=[];return {bind(...args){values=args;return this;},async first(){return sql.prepare(query).get(...values)??null;},async run(){return sql.prepare(query).run(...values);}};},async batch(statements){sql.exec('BEGIN');try{for(const statement of statements)await statement.run();sql.exec('COMMIT');}catch(e){sql.exec('ROLLBACK');throw e;}}};
const hash=await sha256(semanticInput(notice)),now=new Date().toISOString();
sql.prepare('INSERT INTO listings(id,source_id,external_id,content_hash,first_seen,updated_at,recheck_at,deadline,payload) VALUES(?,?,?,?,?,?,?,?,?)').run(notice.id,notice.sourceId,notice.externalId,hash,now,now,now,notice.deadline??null,JSON.stringify(notice));
sql.prepare('INSERT INTO processing_jobs(id,listing_id,input_hash,input,due_at) VALUES(?,?,?,?,?)').run('pilot',notice.id,hash,JSON.stringify(notice),now);
const calls=[],AI={async run(model,request,options){
  assert.ok(calls.length<callLimit,'Pilot call limit exceeded');assert.equal(options.rejectIfBusy,true);
  const call={number:calls.length+1,inputBytes:Buffer.byteLength(JSON.stringify(request)),startedAt:new Date().toISOString()};calls.push(call);
  let response;
  try{response=await fetch(`https://api.cloudflare.com/client/v4/accounts/${config.account_id}/ai/run/${model}`,{method:'POST',headers:{Authorization:`Bearer ${auth.token}`,'Content-Type':'application/json'},body:JSON.stringify({...request,options}),signal:AbortSignal.timeout(45000)});}
  catch(e){call.failureCode=e.name==='TimeoutError'?'ai_timeout':'ai_transport_failed';call.finishedAt=new Date().toISOString();throw new Error(call.failureCode);}
  call.httpStatus=response.status;
  const envelope=await response.json();call.finishedAt=new Date().toISOString();
  if(!response.ok||!envelope.success){call.errorCodes=(envelope.errors??[]).map(e=>e.code);const code=call.errorCodes[0];throw new Error([3036,3040].includes(code)?`${code}: ai_http_${response.status}`:'ai_http_'+response.status);}
  call.result=envelope.result;return envelope.result;
}};
try{
  for(let i=0;i<callLimit;i++){
    await processNotice({DB,AI,AI_MODEL:aiModel,AI_DAILY_JOBS:String(callLimit)});
    const job=sql.prepare("SELECT * FROM processing_jobs WHERE id='pilot'").get();
    if(job.state!=='pending'||job.error_code)break;
  }
  const job=sql.prepare("SELECT * FROM processing_jobs WHERE id='pilot'").get();
  const payload=JSON.parse(sql.prepare('SELECT payload FROM listings WHERE id=?').get(notice.id).payload);
  // Replay the completed hash as pending, so the hash guard itself is exercised.
  let replayState=null;
  if(job.state==='completed'){
    sql.prepare("UPDATE processing_jobs SET state='pending',lease_until=NULL,due_at=? WHERE id='pilot'").run(new Date().toISOString());
    const before=calls.length;await processNotice({DB,AI,AI_MODEL:aiModel});
    assert.equal(calls.length,before,'Completed hash must not be inferred again');
    replayState=sql.prepare("SELECT state FROM processing_jobs WHERE id='pilot'").get().state;assert.equal(replayState,'superseded');
  }
  const report={sourceUrl:notice.url,listingId:notice.id,inputHash:hash,model:aiModel,extractionRevision:aiExtractionRevision,aiProvenance:payload.aiProvenance??null,textBytes:Buffer.byteLength(text),chunks:chunks.length,calls,reportedNeurons:calls.reduce((sum,c)=>sum+(c.result?.usage?.neurons??0),0),state:job.state,errorCode:job.error_code,summary:payload.summary??[],aiCandidates:JSON.parse(job.input).aiCandidates??null,completedHashDedupChecked:job.state==='completed',replayState,scope:'Actual REST inference and production pipeline with in-memory SQLite; API-reported neurons, not invoice, Worker CPU, production D1, or field precision'};
  writeFileSync(reportPath,JSON.stringify(report,null,2));
  console.log(JSON.stringify({state:report.state,errorCode:report.errorCode,calls:calls.length,summaryItems:report.summary.length,reportPath}));
  if(job.state!=='completed')process.exitCode=1;
}finally{sql.close();}
