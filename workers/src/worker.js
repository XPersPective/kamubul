import {handleAssistant} from './assistant.js';
import {handleTrial} from './trial.js';
import {validateCriteria,migrateFilters,fold,installationAnchorKeys,educationValues,cityValues} from './criteria.js';
import {runScheduled,handleWorkQueue} from './pipeline.js';

export const nowISO=()=>new Date().toISOString();
export async function sha256(value){return [...new Uint8Array(await crypto.subtle.digest('SHA-256',value instanceof Uint8Array?value:new TextEncoder().encode(value)))].map(x=>x.toString(16).padStart(2,'0')).join('');}
const json=(body,status=200,headers={})=>Response.json(body,{status,headers:{'X-Content-Type-Options':'nosniff','Cache-Control':'no-store',...headers}});
const int=(raw,min,max,fallback,strict=false)=>{if(raw===null||raw===undefined||(!strict&&raw===''))return fallback;if(strict&&!/^\d{1,16}$/.test(raw))return NaN;const n=Number(raw);return Number.isSafeInteger(n)&&n>=min&&n<=max?n:strict?NaN:fallback;};
const stable=(a,b)=>{if(a.length!==b.length)return false;let diff=0;for(let i=0;i<a.length;i++)diff|=a.charCodeAt(i)^b.charCodeAt(i);return diff===0;};
async function bodyJSON(request){
  if(request.headers.get('content-type')?.split(';',1)[0].trim().toLowerCase()!=='application/json')throw new Error('content_type');
  const reader=request.body?.getReader();if(!reader)throw new Error('registration');
  const chunks=[];let total=0;
  while(true){const {done,value}=await reader.read();if(done)break;total+=value.byteLength;if(total>32768){await reader.cancel();throw new Error('body_oversize');}chunks.push(value);}
  const bytes=new Uint8Array(total);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.byteLength;}
  return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
}
export async function latestSeq(db){return (await db.prepare('SELECT COALESCE(MAX(seq),0) n FROM catalogue_changes').first()).n;}
async function catalogueBounds(db){return db.prepare('SELECT (SELECT COALESCE(MAX(seq),0) FROM catalogue_changes) n,(SELECT COALESCE(MIN(seq),0) FROM catalogue_changes) oldest,(SELECT floor FROM catalogue_retention WHERE id=1) floor').first();}
async function boundedCataloguePage(db,statement){
  const metadata=(await statement.all()).results,selected=[];
  let bytes=1024;
  for(const row of metadata){
    // Reserve JSON envelope/escaped identity overhead before loading full payloads.
    const cost=row.payload_bytes+512+new TextEncoder().encode(row.listing_id).length*6;
    if(bytes+cost>1800000){if(!selected.length)throw new Error('record_oversize');break;}
    bytes+=cost;selected.push(row);
  }
  if(!selected.length)return {rows:[],hasMore:false};
  const rows=(await db.prepare(`SELECT * FROM catalogue_changes WHERE seq IN (${selected.map(()=>'?').join(',')})`).bind(...selected.map(r=>r.seq)).all()).results;
  const bySeq=new Map(rows.map(r=>[r.seq,r]));
  if(selected.some(r=>!bySeq.has(r.seq)))throw new Error('catalogue_expired');
  return {rows:selected.map(r=>bySeq.get(r.seq)),hasMore:selected.length<metadata.length};
}
async function authenticate(request,db,id){
  if(!/^[a-f\d]{32}$/.test(id))throw new Error('installation_id');
  const secret=request.headers.get('authorization')?.replace(/^Bearer /,'')??'';
  if(!/^[a-f\d]{64}$/.test(secret))return null;
  const hash=await sha256(secret);const record=await db.prepare('SELECT * FROM installations WHERE id=?').bind(id).first();
  return record&&stable(hash,record.secret_hash)?record:null;
}
async function registry(request,env,id){
  if(!/^[a-f\d]{32}$/.test(id))return json({error:'invalid_id'},400);
  const secret=request.headers.get('authorization')?.replace(/^Bearer /,'')??'';
  if(!/^[a-f\d]{64}$/.test(secret))return json({error:'unauthorized'},401);
  const hash=await sha256(secret);const existing=await env.DB.prepare('SELECT * FROM installations WHERE id=?').bind(id).first();
  if(existing&&!stable(hash,existing.secret_hash))return json({error:'unauthorized'},401);
  if(request.method==='DELETE') {
    if(existing)await env.DB.prepare('DELETE FROM installations WHERE id=? AND secret_hash=?').bind(id,hash).run();
    return json({deleted:true});
  }
  const raw=await bodyJSON(request);
  if(!raw||typeof raw.fcmToken!=='string'||raw.fcmToken.length<20||raw.fcmToken.length>4096||!['android','ios'].includes(raw.platform)||!Array.isArray(raw.searches)||raw.searches.length>20)throw new Error('registration');
  const quietStart=int(raw.quietStartHour,0,23,22),quietEnd=int(raw.quietEndHour,0,23,8),cap=int(raw.maxInstantPerDay,1,20,6);
  for(const [key,min,max] of [['quietStartHour',0,23],['quietEndHour',0,23],['maxInstantPerDay',1,20]])if(raw[key]!==undefined&&(!Number.isInteger(raw[key])||raw[key]<min||raw[key]>max))throw new Error('registration');
  const ids=new Set();const searches=raw.searches.map(s=>{
    if(!s||!/^[-\w]{1,40}$/.test(s.id)||ids.has(s.id)||typeof s.name!=='string'||!s.name.trim()||s.name.length>80)throw new Error('search');ids.add(s.id);
    const criteria=s.criteria?validateCriteria(s.criteria):migrateFilters(s.filters??{});
    const mode=s.mode??s.filters?.bildirim??'instant';if(!['instant','digest','off'].includes(mode))throw new Error('mode');
    return {id:s.id,name:s.name.trim(),criteria,mode};
  });
  const now=nowISO(),seq=await latestSeq(env.DB);
  const preferences=JSON.stringify({quietStart,quietEnd,cap});
  const previous=existing?(await env.DB.prepare('SELECT id,name,criteria,mode FROM saved_searches WHERE installation_id=? ORDER BY id').bind(id).all()).results:[];
  const desired=searches.map(s=>({id:s.id,name:s.name,criteria:JSON.stringify(s.criteria),mode:s.mode})).sort((a,b)=>a.id.localeCompare(b.id));
  const changed=!existing||existing.preferences!==preferences||JSON.stringify(previous)!==JSON.stringify(desired);
  const version=existing?(existing.version+(changed?1:0)):1;
  // Registry writes are bounded to 20 searches; existing effective baseline survives updates.
  // A stale read must abort the entire batch rather than reuse a preferences version.
  // The NOT NULL version constraint enforces this optimistic write precondition.
  const statements=[env.DB.prepare(`INSERT INTO installations(id,secret_hash,token,platform,preferences,updated_at) VALUES(?,?,?,?,?,?)
    ON CONFLICT(id) DO UPDATE SET token=excluded.token,platform=excluded.platform,preferences=excluded.preferences,
    updated_at=excluded.updated_at,enabled=1,version=CASE WHEN installations.version=? THEN ? ELSE NULL END`).bind(id,hash,raw.fcmToken,raw.platform,preferences,now,existing?.version??0,version)];
  if(searches.length)statements.push(env.DB.prepare(`DELETE FROM saved_searches WHERE installation_id=? AND id NOT IN (${searches.map(()=>'?').join(',')})`).bind(id,...searches.map(s=>s.id)));
  else statements.push(env.DB.prepare('DELETE FROM saved_searches WHERE installation_id=?').bind(id));
  for(const s of searches)statements.push(env.DB.prepare(`INSERT INTO saved_searches(installation_id,id,name,criteria,mode,effective_after) VALUES(?,?,?,?,?,?)
    ON CONFLICT(installation_id,id) DO UPDATE SET name=excluded.name,criteria=excluded.criteria,mode=excluded.mode`).bind(id,s.id,s.name,JSON.stringify(s.criteria),s.mode,seq));
  const facets=JSON.stringify(installationAnchorKeys(searches));
  // Diff in the same transaction as searches: concurrent PUTs cannot leave stale anchors.
  statements.push(env.DB.prepare('DELETE FROM installation_facets WHERE installation_id=? AND key NOT IN (SELECT value FROM json_each(?))').bind(id,facets));
  statements.push(env.DB.prepare('INSERT OR IGNORE INTO installation_facets(installation_id,key) SELECT ?,value FROM json_each(?)').bind(id,facets));
  if(changed)statements.push(env.DB.prepare("UPDATE notification_outbox SET state='cancelled' WHERE installation_id=? AND state IN ('pending','leased')").bind(id));
  await env.DB.batch(statements);
  return json({registered:true,version},existing?200:201);
}
export async function fetchRequest(request,env,ctx){
  if(!env.DB)return json({error:'database_not_configured'},503);
  const url=new URL(request.url),path=url.pathname;
  try {
    if(['PUT','DELETE'].includes(request.method)&&/^\/(?:api\/v2\/installations|v1\/devices)\/[a-f\d]{32}$/.test(path)) {
      const ip=request.headers.get('CF-Connecting-IP');
      if(ip){const key=await sha256('registration:'+ip+':'+new Date().toISOString().slice(0,13));
        const result=await env.DB.prepare(`INSERT INTO rate_limits(key,count,expires_at) VALUES(?,1,?) ON CONFLICT(key) DO UPDATE SET count=count+1 RETURNING count`).bind(key,new Date(Date.now()+3600000).toISOString()).first();
        if(result.count>60)return json({error:'rate_limited'},429,{'Retry-After':'3600'});
      }
      return await registry(request,env,path.split('/').pop());
    }
    if(request.method==='POST'&&path==='/api/v2/trial') {
      if(!/^application\/json(?:\s*;|$)/i.test(request.headers.get('content-type')??''))return json({error:'content_type'},415);
      const text=await request.text();if(text.length>512)return json({error:'body_oversize'},413);
      let body;try{body=JSON.parse(text);}catch{return json({error:'json'},400);}
      const result=await handleTrial(body,env,{sha256,ip:request.headers.get('CF-Connecting-IP')??'unknown'});
      return json(result.body,result.status);
    }
    if(request.method==='POST'&&path==='/api/v2/assistant') {
      if(!/^application\/json(?:\s*;|$)/i.test(request.headers.get('content-type')??''))return json({error:'content_type'},415);
      const text=await request.text();if(text.length>262144)return json({error:'body_oversize'},413);
      let body;try{body=JSON.parse(text);}catch{return json({error:'json'},400);}
      const result=await handleAssistant(body,env,{sha256,ip:request.headers.get('CF-Connecting-IP')??'unknown'});
      return json(result.body,result.status);
    }
    if(request.method!=='GET')return json({error:'method_not_allowed'},405,{'Allow':'GET'});
    if(path==='/api/v2/health'||path==='/v1/health') {
      const seq=await latestSeq(env.DB);return json({status:seq?'ok':'awaiting_ingestion',latestSeq:seq,fcmConfigured:!!(env.FCM_PRIVATE_KEY&&env.FCM_CLIENT_EMAIL),aiConfigured:!!env.AI});
    }
    if(path==='/api/v2/meta') {
      const {n:seq,oldest:minimum,floor}=await catalogueBounds(env.DB);const sources=(await env.DB.prepare("SELECT id,name,CASE WHEN state IN ('ok','failed','blocked','disabled') THEN state WHEN state='processing' AND last_success IS NOT NULL THEN 'ok' ELSE 'failed' END state,last_attempt,last_success,note FROM sources").all()).results;
      const oldest=floor>0?floor+1:minimum;
      return conditional(request,{schemaVersion:2,taxonomyVersion:1,latestSeq:seq,oldestRetainedSeq:oldest,sources},'"meta-'+seq+'-'+oldest+'-'+await sha256(JSON.stringify(sources))+'"');
    }
    if(path==='/api/v2/taxonomy') {
      const occupations=(await env.DB.prepare("SELECT DISTINCT value FROM listings,json_each(payload,'$.occupations') WHERE active=1 LIMIT 200").all()).results.map(x=>x.value);
      return json({version:1,education:educationValues.map(x=>x.label),educationValues,cities:cityValues.map(x=>x.label),cityValues,kpssTypes:['P3','P93','P94'],categories:['işçi','personel','belediye'],occupations},200,{'Cache-Control':'public, max-age=300'});
    }
    if(path==='/api/v2/changes') {
      const {n:latest,floor}=await catalogueBounds(env.DB),after=int(url.searchParams.get('after'),0,Number.MAX_SAFE_INTEGER,0,true),watermark=int(url.searchParams.get('watermark'),0,Number.MAX_SAFE_INTEGER,latest,true),limit=int(url.searchParams.get('limit'),1,50,30);
      if(!Number.isSafeInteger(after)||!Number.isSafeInteger(watermark))return json({error:'cursor'},400);
      if(after>latest||watermark>latest)return json({error:'cursor_ahead'},409);
      if(watermark<after)return json({error:'watermark'},400);
      if(after<floor)return json({error:'cursor_expired'},409);
      const {rows}=await boundedCataloguePage(env.DB,env.DB.prepare('SELECT seq,listing_id,length(CAST(payload AS BLOB)) payload_bytes FROM catalogue_changes WHERE seq>? AND seq<=? ORDER BY seq LIMIT ?').bind(after,watermark,limit));
      if(after<(await env.DB.prepare('SELECT floor FROM catalogue_retention WHERE id=1').first()).floor)return json({error:'cursor_expired'},409);
      const appliedThrough=rows.length?rows.at(-1).seq:watermark;
      return conditional(request,{watermark,appliedThrough,hasMore:appliedThrough<watermark,changes:rows.map(r=>({seq:r.seq,operation:r.operation,id:r.listing_id,revision:r.revision,item:JSON.parse(r.payload)}))},'"changes-'+after+'-'+watermark+'-'+limit+'"');
    }
    if(path==='/api/v2/listings') {
      const {n:latest,floor}=await catalogueBounds(env.DB),watermark=int(url.searchParams.get('watermark'),0,Number.MAX_SAFE_INTEGER,latest,true),after=url.searchParams.get('after')??'',limit=int(url.searchParams.get('limit'),1,50,30);
      if(!Number.isSafeInteger(watermark))return json({error:'cursor'},400);
      if(watermark>latest)return json({error:'cursor_ahead'},409);
      if(after.length>200)return json({error:'cursor'},400);
      if(watermark<floor)return json({error:'snapshot_expired'},409);
      const {rows,hasMore}=await boundedCataloguePage(env.DB,env.DB.prepare(`SELECT c.seq,c.listing_id,length(CAST(c.payload AS BLOB)) payload_bytes FROM catalogue_changes c JOIN (SELECT listing_id,MAX(seq) seq FROM catalogue_changes WHERE seq<=? GROUP BY listing_id) last ON c.seq=last.seq
        WHERE c.operation='upsert' AND c.listing_id>? ORDER BY c.listing_id LIMIT ?`).bind(watermark,after,limit+1));
      if(watermark<(await env.DB.prepare('SELECT floor FROM catalogue_retention WHERE id=1').first()).floor)return json({error:'snapshot_expired'},409);
      const visible=rows.slice(0,limit);return conditional(request,{watermark,items:visible.map(r=>JSON.parse(r.payload)),next:hasMore||rows.length>limit?visible.at(-1).listing_id:null},'"list-'+watermark+'-'+await sha256(after)+'-'+limit+'"');
    }
    if(path.startsWith('/api/v2/listings/')) {
      const id=decodeURIComponent(path.slice('/api/v2/listings/'.length));if(id.length>200)return json({error:'id'},400);
      const row=await env.DB.prepare('SELECT * FROM listings WHERE id=?').bind(id).first();
      if(!row)return json({error:'not_found'},404);
      return conditional(request,{...JSON.parse(row.payload),id:row.id,revision:row.revision,active:row.active===1},'"detail-'+await sha256(id)+'-'+row.revision+'"');
    }
    const history=path.match(/^\/api\/v2\/installations\/([a-f\d]{32})\/notifications$/);
    if(history){
      const record=await authenticate(request,env.DB,history[1]);if(!record)return json({error:'unauthorized'},401);
      const rawAfter=url.searchParams.get('after')??'0',after=Number(rawAfter),limit=int(url.searchParams.get('limit'),1,50,30);
      if(!/^\d{1,16}$/.test(rawAfter)||!Number.isSafeInteger(after))return json({error:'cursor'},400);
      const latest=(await env.DB.prepare('SELECT COALESCE(MAX(history_seq),0) seq FROM notification_outbox WHERE installation_id=?').bind(record.id).first()).seq;
      const rawWatermark=url.searchParams.get('watermark'),watermark=rawWatermark===null?latest:Number(rawWatermark);
      if(rawWatermark!==null&&(!/^\d{1,16}$/.test(rawWatermark)||!Number.isSafeInteger(watermark)||watermark<after||watermark>latest))return json({error:'watermark'},400);
      if(after>latest)return json({error:'cursor_ahead'},409);
      // History carries bounded presentation fields, not source documents/private preferences.
      const rows=(await env.DB.prepare(`SELECT id,listing_id,history_seq,accepted_at,created_at,delivery_id,
        json_object('title',substr(json_extract(payload,'$.title'),1,300),'url',substr(json_extract(payload,'$.url'),1,2048),
          'revision',json_extract(payload,'$.revision'),'searchIds',json_extract(payload,'$.searchIds'),
          'mode',json_extract(payload,'$.mode'),'digestCount',json_extract(payload,'$.digestCount')) payload
        FROM notification_outbox WHERE installation_id=? AND state='accepted' AND history_seq>? AND history_seq<=? ORDER BY history_seq LIMIT ?`).bind(record.id,after,watermark,limit+1).all()).results;
      const visible=rows.slice(0,limit),hasMore=rows.length>limit,appliedThrough=hasMore?visible.at(-1).history_seq:watermark;
      return json({schemaVersion:2,watermark,appliedThrough,hasMore,items:visible.map(r=>({...JSON.parse(r.payload),id:r.listing_id,eventId:r.id,deliveryId:r.delivery_id??r.id,state:'accepted',seq:r.history_seq,createdAt:r.created_at,acceptedAt:r.accepted_at})),next:hasMore?String(appliedThrough):null});
    }
    return json({error:'not_found'},404);
  } catch(error){
    if(error.message?.includes('installation_owner_conflict'))return json({error:'unauthorized'},401);
    if(error.message?.includes('NOT NULL constraint failed: installations.version'))return json({error:'registry_conflict'},409);
    if(error.message==='catalogue_expired')return json({error:path==='/api/v2/changes'?'cursor_expired':'snapshot_expired'},409);
    if(error.message==='record_oversize')return json({error:'record_oversize'},413);
    if(error instanceof SyntaxError||['criteria','unknown_criterion','registration','search','mode','content_type','body_oversize','age','ageAsOf','kpssScore','kpssType','kpssYear','version','cities','categories','occupations','institutions','education','keyword','keywordScope','onlyKpss','last30'].includes(error.message))return json({error:'invalid_request'},400);
    console.error('api_failure',error.name);return json({error:'service_unavailable'},503);
  }
}
function conditional(request,body,etag){const headers={'ETag':etag,'Cache-Control':'public, max-age=60, s-maxage=60'};return request.headers.get('if-none-match')===etag?new Response(null,{status:304,headers}):json(body,200,headers);}
export async function cachedFetch(request,env,ctx){
  const url=new URL(request.url),path=url.pathname;
  const parameters=path==='/api/v2/listings'?['watermark','after','limit']:path==='/api/v2/changes'?['watermark','after','limit']:['/api/v2/meta','/api/v2/taxonomy'].includes(path)||/^\/api\/v2\/listings\/[^/]+$/.test(path)?[]:null;
  const cache=globalThis.caches?.default;
  // Only explicitly public reads share cache entries; credentials and private routes bypass it.
  if(!cache||!ctx?.waitUntil||request.method!=='GET'||parameters===null||request.headers.has('authorization')||request.headers.has('cookie')||url.href.length>1024||/no-store/i.test(request.headers.get('cache-control')??'')||[...url.searchParams.keys()].some(k=>!parameters.includes(k)||url.searchParams.getAll(k).length!==1))return fetchRequest(request,env,ctx);
  url.searchParams.sort();url.pathname='/_cache/public-v2'+path;
  const key=new Request(url.href),fresh=/no-cache|max-age=0/i.test(request.headers.get('cache-control')??'');
  let response;
  try{if(!fresh)response=await cache.match(key);}catch{console.error('public_cache_read_failed');}
  const hit=!!response;
  if(!response){
    const headers=new Headers(request.headers);headers.delete('if-none-match');
    response=await fetchRequest(new Request(request,{headers}),env,ctx);
    if(response.status===200&&response.headers.get('cache-control')?.startsWith('public')){
      const stored=new Response(response.clone().body,response);stored.headers.set('Cache-Control',path==='/api/v2/taxonomy'?'public, max-age=300':'public, max-age=60');
      ctx.waitUntil(cache.put(key,stored).catch(()=>console.error('public_cache_write_failed')));
    }
  }
  const headers=new Headers(response.headers);headers.set('X-KamuBul-Cache',hit?'HIT':'MISS');
  const etag=response.headers.get('etag');
  const unchanged=response.status===200&&etag&&request.headers.get('if-none-match')?.split(',').some(value=>value.trim()==='*'||value.trim().replace(/^W\//,'')===etag);
  return new Response(unchanged?null:response.body,{status:unchanged?304:response.status,headers});
}
export default {fetch:cachedFetch,async scheduled(controller,env,ctx){ctx.waitUntil(runScheduled(env,controller.scheduledTime));},async queue(batch,env){await handleWorkQueue(batch,env);}};
