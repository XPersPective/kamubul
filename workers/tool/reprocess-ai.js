// Explicit, bounded operator work through the already-authorized Wrangler; no public admin route.
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {aiExtractionRevision} from '../src/pipeline.js';

const models=['@cf/meta/llama-3.1-8b-instruct','@cf/meta/llama-3.1-8b-instruct-fp8','@cf/meta/llama-3.3-70b-instruct-fp8-fast'];
const literal=value=>"'"+value.replaceAll("'","''")+"'";
export function reprocessSql({ids,model,apply=false,now=new Date().toISOString()}){
  if(!Array.isArray(ids)||ids.length<1||ids.length>5||new Set(ids).size!==ids.length||ids.some(id=>typeof id!=='string'||!id||id.length>200)||!models.includes(model)||!Number.isFinite(Date.parse(now)))throw new Error('invalid_reprocess_plan');
  const contract={provider:'cloudflare',model,extractionRevision:aiExtractionRevision};
  const key=literal(JSON.stringify([contract.provider,contract.model,contract.extractionRevision])),time=literal(new Date(now).toISOString());
  const selected=`WITH selected AS (SELECT l.*,CASE
    WHEN active!=1 OR (deadline IS NOT NULL AND deadline<=${time}) THEN 'inactive_or_expired'
    WHEN NOT (COALESCE(length(trim(json_extract(payload,'$.text'))),0)>0 OR EXISTS(SELECT 1 FROM json_each(payload,'$.positions') p WHERE length(trim(json_extract(p.value,'$.text')))>0)) THEN 'source_text_missing'
    WHEN processed_hash=content_hash AND processed_contract=${key} THEN 'already_processed'
    WHEN EXISTS(SELECT 1 FROM processing_jobs p WHERE p.listing_id=l.id AND p.input_hash=l.content_hash AND p.contract_key=${key}) THEN 'job_exists'
    ELSE 'eligible' END reason FROM listings l WHERE id IN (SELECT value FROM json_each(${literal(JSON.stringify(ids))})))`;
  if(!apply)return selected+` SELECT id,content_hash,revision,reason FROM selected ORDER BY id;`;
  // ponytail: at most five explicit IDs per plan; bulk re-extraction requires a separate measured cursor/budget.
  return selected+` INSERT OR IGNORE INTO processing_jobs(id,listing_id,input_hash,input,due_at,contract_key,purpose)
    SELECT json_array(id,content_hash,${key}),id,content_hash,
      json_set(json_remove(payload,'$.aiProgress','$.aiCandidates','$.aiContract','$.summary','$.aiProvenance'),'$.aiContract',json(${literal(JSON.stringify(contract))})),
      ${time},${key},'reprocess' FROM selected WHERE reason='eligible' RETURNING id,listing_id,input_hash,contract_key,purpose;`;
}

if(process.argv[1]===fileURLToPath(import.meta.url)){
  try{
    const args=process.argv.slice(2),apply=args.includes('--apply'),index=args.indexOf('--model');
    let model;
    if(index>=0){model=args[index+1];if(!model||model.startsWith('--'))throw new Error('invalid_reprocess_plan');args.splice(index,2);}
    const ids=args.filter(arg=>arg!=='--apply');
    model??=JSON.parse(readFileSync(new URL('../wrangler.jsonc',import.meta.url),'utf8')).vars.AI_MODEL;
    const execute=sql=>{
      let result;
      try{result=JSON.parse(execFileSync(process.execPath,[fileURLToPath(new URL('../node_modules/wrangler/bin/wrangler.js',import.meta.url)),'d1','execute','DB','--remote','--json','--command',sql],{cwd:fileURLToPath(new URL('../',import.meta.url)),encoding:'utf8',stdio:['ignore','pipe','pipe'],timeout:60000}));}
      catch{throw new Error('reprocess_query_failed');}
      if(!result.every(row=>row.success))throw new Error('reprocess_query_failed');
      return result.flatMap(row=>row.results);
    };
    const plan=execute(reprocessSql({ids,model}));
    console.log(JSON.stringify({mode:apply?'apply':'plan',model,extractionRevision:aiExtractionRevision,plan,missingIds:ids.filter(id=>!plan.some(row=>row.id===id))}));
    if(apply){
      if(ids.some(id=>!plan.some(row=>row.id===id)))throw new Error('listing_not_found');
      console.log(JSON.stringify({queued:execute(reprocessSql({ids,model,apply:true}))}));
    }
  }catch(e){console.error(e.message);process.exitCode=1;}
}
