// Field precision/recall of the blind ilan.gov labels against the live catalogue payload and against this code's
// mechanical extraction. Texts are read from the public API (GET only) and never stored in the repository; pass a
// cache path to keep a local copy once the labelled notices start expiring.
// Usage: node tool/eval-labels.js [catalogue-cache.json] [--detail]
import {existsSync,readFileSync,writeFileSync} from 'node:fs';
import {extractNotice} from '../src/notice_extraction.js';
import {fold} from '../src/criteria.js';

const args=process.argv.slice(2),detail=args.includes('--detail'),cache=args.find(a=>!a.startsWith('--'));
const labels=JSON.parse(readFileSync(new URL('../test/fixtures/ilangov-labels.json',import.meta.url),'utf8')).labels;
let catalogue;
if(cache&&existsSync(cache))catalogue=JSON.parse(readFileSync(cache,'utf8'));
else{
  catalogue=[];let watermark=null,after=null;
  for(let page=0;page<100;page++){
    const url=new URL('https://kamubul-api.devx8585.workers.dev/api/v2/listings');url.searchParams.set('limit','50');
    if(watermark)url.searchParams.set('watermark',watermark);if(after)url.searchParams.set('after',after);
    const body=await (await fetch(url)).json();watermark=body.watermark;catalogue.push(...body.items);after=body.next;if(!after)break;
  }
  if(cache)writeFileSync(cache,JSON.stringify(catalogue));
}
const items=new Map(catalogue.map(i=>[i.id,i]));
const day=v=>v?new Date(Date.parse(v)+3*3600000).toISOString().slice(0,10):null;
const education=v=>({onlisans:'Ön lisans','on lisans':'Ön lisans',yukseklisans:'Yüksek lisans'})[fold(v)]??v;
const views={
  payload:async i=>({quota:i.quota??null,deadline:day(i.deadline),groups:i.requirementGroups??[]}),
  mechanical:async i=>{
    const text=[i.text,...(i.positions??[]).map(p=>p.text)].filter(Boolean).join('\n\n');
    const r=(await extractNotice(i,text,{},{mechanicalOnly:true,sha256:async()=>''})).result;
    return {quota:r.fields.quota?.value??null,deadline:day(r.fields.deadline?.value),groups:r.groups};
  },
};
const missing=Object.keys(labels).filter(id=>!labels[id].skip&&!items.has(id));
if(missing.length)console.log(`${missing.length} labelled notices are no longer in the catalogue: ${missing.join(', ')}`);
for(const [name,view] of Object.entries(views)){
  const score=Object.fromEntries(['quota','deadline','maxAge','edu','kpss'].map(f=>[f,[0,0,0]])),misses=[]; // [tp, fp, fn]
  const scalar=(field,label,got,id)=>{
    if(label!=null&&got===label){score[field][0]++;return;}
    if(got!=null)score[field][1]++;if(label!=null)score[field][2]++;
    if(got!=null||label!=null)misses.push(`${field} ${id}: label=${label} got=${got}`);
  };
  const set=(field,label,got,id)=>{
    if(label==null)return;
    const want=new Set(label.map(String)),have=new Set(got.map(String));
    for(const v of have)if(want.has(v))score[field][0]++;else{score[field][1]++;misses.push(`${field} ${id}: extra ${v}`);}
    for(const v of want)if(!have.has(v)){score[field][2]++;misses.push(`${field} ${id}: missing ${v}`);}
  };
  for(const [id,l] of Object.entries(labels)){
    if(l.skip||!items.has(id))continue;
    const v=await view(items.get(id));
    scalar('quota',l.quota,v.quota,id);scalar('deadline',l.deadline,v.deadline,id);
    set('maxAge',l.maxAge,[...new Set(v.groups.map(g=>g.maxAge).filter(x=>x!=null))],id);
    set('edu',l.edu,[...new Set(v.groups.flatMap(g=>g.education??[]).map(education))],id);
    set('kpss',l.kpss,[...new Set(v.groups.map(g=>g.kpssType).filter(Boolean))],id);
  }
  console.log(`\n== ${name}`);
  for(const [field,[tp,fp,fn]] of Object.entries(score))
    console.log(`${field.padEnd(9)} precision ${tp+fp?(tp/(tp+fp)).toFixed(3):'—'} (${tp}/${tp+fp})  recall ${tp+fn?(tp/(tp+fn)).toFixed(3):'—'} (${tp}/${tp+fn})`);
  if(detail)for(const m of misses)console.log('  '+m);
}
