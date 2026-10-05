// Read-only remote-preview check: no D1 writes, model calls or user data.
import {fetchKariyerList,fetchKariyerDetail,fetchSbbList,fetchIlanGovPage,fetchIlanGovDetail,fetchIskurList,fetchIskurDetail} from '../src/sources.js';
export default {async fetch(request){
  const source=new URL(request.url).pathname.slice(1),start=Date.now();
  try{
    const info={'sbb-info':'https://kamuilan.sbb.gov.tr/','iskur-info':'https://esube.iskur.gov.tr/Istihdam/AcikIsIlanAra.aspx','kariyer-info':'https://kariyerkapisi.gov.tr/'}[source];
    if(info){const r=await fetch(info,{redirect:'manual',signal:AbortSignal.timeout(25000)}),body=await r.text();return Response.json({source,status:r.status,type:r.headers.get('content-type'),length:body.length,title:body.match(/<title[^>]*>([^<]*)/i)?.[1]?.slice(0,160),signals:body.match(/captcha|request.?rejected|access.?denied|cloudflare|incapsula|forbidden|ASP.NET/gi)?.slice(0,6),elapsedMs:Date.now()-start});}
    const items=source==='kariyerkapisi'?await fetchKariyerList():source==='sbb'?await fetchSbbList():source==='ilangov'?(await fetchIlanGovPage()).items:source==='iskur'?await fetchIskurList():null;
    if(!items)return Response.json({error:'unknown_source'}, {status:404});
    const first=items[0];
    const detail=first&&source!=='sbb'?await(source==='kariyerkapisi'?fetchKariyerDetail(first.externalId):source==='ilangov'?fetchIlanGovDetail(first.externalId):fetchIskurDetail(first.externalId)):null;
    return Response.json({source,count:items.length,firstId:first?.id,textChars:detail?.text?.length??0,positions:detail?.positions?.length??0,elapsedMs:Date.now()-start});
  }catch(error){return Response.json({source,error:error.message,elapsedMs:Date.now()-start},{status:502});}
}};
