// One server result feeds cards, details and matching. Original text is never rewritten.
import {handleExtract,validateGroups,missingTopics,mentions,MIN_TEXT,MAX_TEXT} from './extract.js';
import {fold} from './criteria.js';
export const NOTICE_VERSION='notice-3';
const countHeader=value=>/^(?:adet|kontenjan(?: sayisi)?|kadro sayisi|personel sayisi|alinacak (?:kisi|personel) sayisi|kisi sayisi|sayi|istihdam edilecek (?:personel|uzman) sayisi|acik isci sayisi|alinmasi planlanan kadro sayisi|atama yapilabilecek bos kadro sayisi)$/.test(fold(value).replace(/[:.*]/g,'').trim());
const datePattern=/\b(\d{1,2})[./-](\d{1,2})[./-](20\d{2})\b/g;
function civilDate(day,month,year){const d=`${year}-${String(month).padStart(2,'0')}-${String(day).padStart(2,'0')}`;return Number.isFinite(Date.parse(d))&&new Date(d).toISOString().slice(0,10)===d?d+'T20:59:59.999Z':null;}
function conditions(text){
  const raw={};
  // ponytail: explicit requirement clauses only; ambiguous/scoped prose goes to Qwen, never inferred from document checklists.
  const clause=text.split(/\n|\||(?<=[.;])\s+/).find(s=>/mezun|derecesine sahip|doktorasini|doktora yapm|lisans.*yapmis|docentlik.*(?:unvan|almi)/.test(fold(s)));
  if(clause){const at=clause.search(/lisans|doktora|lise|ortaöğretim|fakülte/i);raw.education=['Lise','Ön lisans','Lisans','Yüksek lisans','Doktora'];raw.educationQuote=clause.slice(Math.max(0,at-30),Math.max(0,at-30)+400);}
  const k=text.split(/\n|(?<=[.;])\s+/).find(s=>/kpss/i.test(s)&&/puan|aranm|istenm|sınav/.test(s));
  if(k&&k.length<=400){raw.kpssQuote=k;raw.kpssStatus=/aranm|istenm|muaf|şartı yok/.test(k)?'not_required':'required';raw.kpssType=k.match(/\bP\s?(\d{1,3})\b/i)?.[0].replace(/\s/g,'').toUpperCase();const score=k.match(/(?:en az|asgari)\s+(\d{1,3}(?:[.,]\d+)?)\s*puan/i);if(score)raw.kpssScore=Number(score[1].replace(',','.'));}
  const a=text.split(/\n|(?<=[.;])\s+/).find(s=>/yas/.test(fold(s))&&/doldur|tamamla|gun alm|buyuk|kucuk|asmam/.test(fold(s)));
  if(a&&a.length<=400){const nums=Array.from({length:55},(_,i)=>i+16).filter(n=>mentions(a,n));if(nums.length===1){if(/doldurmam|gun almam|asmam|buyuk olmam/.test(fold(a)))raw.maxAge=nums[0];else if(/doldurmus|tamamlamis|kucuk olmam/.test(fold(a)))raw.minAge=nums[0];}raw.ageQuote=a;}
  return validateGroups({groups:[raw]},text)[0]??{};
}
export function mechanicalNotice(notice,text){
  const fields={}, groups=[], lines=text.split('\n'),seenRows=new Map();let headers=null,count=-1,rows=0,tableAmbiguous=false,tableNumber=0;
  const tableStart=lines.findIndex(l=>l.split('|').some(countHeader));
  const shared=[];if(tableStart>0)shared.push(lines.slice(0,tableStart).join('\n').split(/\n[^\n]{0,30}ÖZEL ŞARTLAR/i)[0]);
  for(let i=0;i<lines.length;i++)if(lines[i].length<120&&/genel sartlar/.test(fold(lines[i]))){const section=[];for(let j=i+1;j<lines.length;j++){if(lines[j].length<120&&/ozel sart|basvuru|istenilen belg|degerlendirme/.test(fold(lines[j])))break;section.push(lines[j]);}shared.push(section.join('\n'));}
  const register=/tercuman|bilirkisi/.test(fold(notice.title))&&(/liste|basvuru/.test(fold(notice.title))||/(?:tercuman|bilirkisi)[^\n]{0,100}liste/.test(fold(text)));
  for(const line of lines){
    const cells=line.split('|').map(s=>s.trim());
    if(cells.length<2)continue;
    const index=cells.findIndex(countHeader);
    if(index>=0){headers=cells;count=index;tableNumber++;continue;}
    if(!headers)continue;
    if(/^toplam\b/.test(fold(cells[0])))continue;
    // Official ministry table uses rowspan only for the final salary cell.
    const missingSalary=cells.length===headers.length-1&&(/ucret|maas/.test(fold(headers.at(-1)))||(fold(headers.at(-1))==='toplam'&&count<headers.length-1));
    if(cells.length!==headers.length&&!missingSalary){if(cells.some(s=>/^\d+$/.test(s)))tableAmbiguous=true;continue;}
    const number=cells[count].match(/^(\d+)(?:\s*\((?:Erkek|Kadın|Erkek-Kadın|Kadın-Erkek)\))?$/i);
    if(!number){if(cells.some((s,i)=>s&&/unvan|pozisyon|meslek/.test(fold(headers[i]))))tableAmbiguous=true;continue;}
    const quota=Number(number[1]);if(quota<1||quota>100000){tableAmbiguous=true;continue;}
    const label=cells.filter((s,i)=>i!==count&&/unvan|pozisyon|bolum|program|anabilim|anasanat|meslek adi|ogrenim dali|atama yapilacak yer/.test(fold(headers[i]))).join(' · ');
    if(!label){tableAmbiguous=true;continue;}
    const rowKey=headers.join('|')+'\n'+line;
    if(seenRows.has(rowKey)&&seenRows.get(rowKey)<tableNumber)continue;seenRows.set(rowKey,tableNumber);
    rows++;
    const parsed=conditions(line);
    groups.push({label,quota,...parsed,quotes:{...parsed.quotes,quota:line},sourceText:line});
  }
  if(groups.length&&!tableAmbiguous){const total=groups.reduce((n,g)=>n+g.quota,0);if(total<=100000)fields.quota={value:total,quote:groups.map(g=>g.sourceText).join('\n')};}
  const totals=[...text.matchAll(/(?:toplam\s+)?(\d{1,5})\s*(?:\([^)]*\)\s*)?(?:adet\s+)?(?:sözleşmeli\s+)?(?:personel|kişi|işçi)\s+(?:alınacak|alınacaktır|istihdam edilecek)/gi)];
  if(!fields.quota&&totals.length===1)fields.quota={value:Number(totals[0][1]),quote:totals[0][0]};
  if(Number.isSafeInteger(notice.quota)&&notice.quota>0&&notice.quota<=100000&&(!notice.fieldEvidence?.quota||notice.fieldEvidence.quota.origin==='source'))fields.quota={value:notice.quota,quote:notice.quotaQuote??notice.fieldEvidence?.quota?.quote??null,origin:'source'};
  if(notice.deadline&&(!notice.fieldEvidence?.deadline||notice.fieldEvidence.deadline.origin==='source'))fields.deadline={value:notice.deadline,quote:notice.deadlineQuote??notice.fieldEvidence?.deadline?.quote??null,origin:'source'};
  const deadlines=[];
  for(const line of lines){
    if(!/son\s*basvuru\s*tarihi|basvurular[^\n]*\d{1,2}[./-]\d{1,2}[./-]20\d{2}[^\n]*tarihleri arasinda/.test(fold(line)))continue;
    const dates=[...line.matchAll(datePattern)].map(m=>civilDate(m[1],m[2],m[3])).filter(Boolean);
    const months=['ocak','subat','mart','nisan','mayis','haziran','temmuz','agustos','eylul','ekim','kasim','aralik'];
    for(const m of fold(line).matchAll(/\b(\d{1,2})\s+(ocak|subat|mart|nisan|mayis|haziran|temmuz|agustos|eylul|ekim|kasim|aralik)\s+(20\d{2})\b/g)){const date=civilDate(m[1],months.indexOf(m[2])+1,m[3]);if(date)dates.push(date);}
    if(dates.length)deadlines.push({value:dates.at(-1),quote:line});
  }
  if(!fields.deadline&&new Set(deadlines.map(d=>d.value)).size===1){fields.deadline=deadlines.find(d=>/son\s*başvuru/i.test(d.quote))??deadlines[0];const time=fields.deadline.quote.match(/(?:saat|mesai bitimi[^\d]*)\s*(\d{1,2})[:.](\d{2})/i);if(time&&Number(time[1])<24&&Number(time[2])<60){const d=new Date(fields.deadline.value);d.setUTCHours(Number(time[1])-3,Number(time[2]),0,0);fields.deadline.value=d.toISOString();}}
  const relative=lines.filter(l=>/(?:yayin|yayim).*itibaren\s+\d+\.?\s*gun/.test(fold(l))&&/basvur|aday|dilekce|teslim/.test(fold(l)));
  const multipleDeadlines=relative.length>0;
  // A relative civil-day rule does not establish an inclusive/exclusive counting convention.
  if(multipleDeadlines){fields.applicationPeriods={value:[...deadlines.map(d=>({deadline:d.value,text:d.quote})),...relative.map(text=>({deadline:null,text,reference:notice.gazettePublishedQuote??null}))],quote:null};fields.deadline={value:null,quote:null};}
  if(!groups.length&&!headers){const general=conditions(text);if(Object.keys(general).length)groups.push({...general,label:'Başvuru koşulları'});}
  // Native position documents already have their own scope and quota.
  if(notice.positions?.length){groups.length=0;for(const p of notice.positions){const parsed=conditions(p.text??'');groups.push({label:p.title??p.profession??'Başvuru koşulları',...parsed,...(p.quota>0?{quota:p.quota}:{}),cities:p.places??notice.places??[],occupations:p.profession?[p.profession]:[],sourceText:p.text??''});}if(notice.positions.every(p=>Number.isSafeInteger(p.quota)&&p.quota>0)){const quota=notice.positions.reduce((n,p)=>n+p.quota,0);if(quota<=100000)fields.quota={value:quota,quote:null,origin:'source'};}}
  for(const field of Object.values(fields))field.origin??='mechanical';
  for(const group of groups)group.fieldOrigins=Object.fromEntries(Object.keys(group.quotes??{}).map(key=>[key,'mechanical']));
  return {fields,groups,register,tableAmbiguous,rows,multipleDeadlines,sharedText:shared.join('\n')};
}
export function assessNotice(result,text){
  const missing=[];
  if(!result.register&&!result.fields.quota)missing.push('quota');
  if(result.multipleDeadlines)missing.push('deadline_scope');
  else if(!result.fields.deadline?.value)missing.push('deadline');
  if(result.tableAmbiguous)missing.push('table_rows');
  if(!result.groups.length&&/mezun|yaş|kpss|kadro|pozisyon/i.test(text))missing.push('conditions');
  missing.push(...missingTopics(result.groups,text));
  for(const group of result.groups){const scope=group.sourceText||text;for(const topic of missingTopics([group],scope))missing.push(topic);}
  return [...new Set(missing)];
}
export async function extractNotice(notice,text,env,deps){
  const result=mechanicalNotice(notice,text);let missing=assessNotice(result,text),method='mechanical',response={status:200};
  if(missing.length&&!deps.mechanicalOnly&&text.trim().length>=MIN_TEXT&&text.length<=MAX_TEXT){
    response=await handleExtract({installationId:'0'.repeat(32),text,noticeMode:true},env,{...deps,internal:true});
    if(response.status===200){
      const ai=response.body;let contributed=false;
      for(const [key,field] of Object.entries(ai.fields??{}))if(!result.fields[key]){result.fields[key]={...field,origin:'ai'};contributed=true;}
      if(result.groups.length&&result.groups.some(g=>g.sourceText)){
        for(const group of result.groups){
          const candidates=ai.groups.filter(a=>fold(a.label)===fold(group.label)||Object.entries(a.quotes??{}).some(([key,q])=>key!=='quota'&&group.sourceText.includes(q)));
          if(candidates.length!==1)continue;
          const a=candidates[0],accepted={};
          for(const [key,quote] of Object.entries(a.quotes??{})){const general=a.quoteScopes?.[key]==='general'&&result.sharedText.includes(quote)&&!result.groups.some(g=>g.label&&fold(quote).includes(fold(g.label)));if(key!=='quota'&&(group.sourceText.includes(quote)||general))accepted[key]=quote;}
          for(const [key,value] of Object.entries(a)){const topic=key.startsWith('kpss')?'kpss':/Age|^age/.test(key)?'age':key==='education'?'education':null;if(topic&&accepted[topic]&&group[key]==null){group[key]=value;group.fieldOrigins[topic]='ai';contributed=true;}}
          group.quotes={...accepted,...group.quotes};
        }
      }else if(ai.groups.length){result.groups=ai.groups.map(g=>({...g,fieldOrigins:Object.fromEntries(Object.keys(g.quotes??{}).map(key=>[key,'ai']))}));contributed=true;}
      if(contributed)method=result.rows||Object.keys(mechanicalNotice(notice,text).fields).length?'hybrid':'ai';
      missing=assessNotice(result,text);
    }
  }else if(missing.length&&!deps.mechanicalOnly)response={status:422,body:{error:text.length>MAX_TEXT?'text_oversize':'text_short'}};
  return {...response,result:{fields:result.fields,groups:result.groups.map(({sourceText,...g})=>({...g,...(sourceText?{text:sourceText}:{}),cities:g.cities??notice.places??[]})),extraction:{version:NOTICE_VERSION,method,status:missing.length?'partial':'complete',missing,kind:result.register?'register':'vacancy'}}};
}
