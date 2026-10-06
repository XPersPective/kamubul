// One server result feeds cards, details and matching. Original text is never rewritten.
import {handleExtract,validateGroups,missingTopics,mentions,MIN_TEXT,MAX_TEXT} from './extract.js';
import {fold} from './criteria.js';
export const NOTICE_VERSION='notice-8';
const countHeader=value=>/^(?:ad|adet|adedi|(?:kadro|pozisyon) (?:sayisi|adedi)|kontenjan(?: sayisi)?|personel sayisi|alinacak (?:kisi|personel) sayisi|kisi sayisi|sayi|sayisi|istihdam edilecek (?:personel|uzman) sayisi|acik isci sayisi|alinmasi planlanan kadro sayisi|atama yapilabilecek bos kadro sayisi)$/.test(fold(value).replace(/[:.*]/g,'').trim());
const academicHeader=value=>/^(?:prof|profesor|doc|docent|doktorogretimuyesi|drogretimuyesi|drogruyesi|ogrgor|ogrgordersverecek|arsgor)$/.test(fold(value).replace(/[^\p{L}]/gu,''));
const datePattern=/\b(\d{1,2})[./-](\d{1,2})[./-](20\d{2})\b/g;
function civilDate(day,month,year){const d=`${year}-${String(month).padStart(2,'0')}-${String(day).padStart(2,'0')}`;return Number.isFinite(Date.parse(d))&&new Date(d).toISOString().slice(0,10)===d?d+'T20:59:59.999Z':null;}
function conditions(text){
  const raw={},clauses=text.split(/\n|\||•|(?<=[.;])\s+/);
  // ponytail: explicit requirement clauses only; ambiguous/scoped prose goes to Qwen, never inferred from document checklists.
  const educationClauses=clauses.filter(s=>/mezunu|mezun (?:olmak|olmus)|derecesine sahip|doktorasini|doktora yapm|lisans.*yapmis|docentlik.*(?:unvan|almi)/.test(fold(s)));
  if(educationClauses.length){const clause=educationClauses[0],quote=text.slice(text.indexOf(clause),text.lastIndexOf(educationClauses.at(-1))+educationClauses.at(-1).length),at=clause.search(/lisans|doktora|lise|ortaöğretim|fakülte/i);raw.education=['Lise','Ön lisans','Lisans','Yüksek lisans','Doktora'];raw.educationQuote=quote.length<=400?quote:clause.slice(Math.max(0,at-30),Math.max(0,at-30)+400);}
  const k=text.match(/KPSS puanı olmayan[^.\n]{0,300}?dikkate alınır/i)?.[0]??clauses.find(s=>/kpss/i.test(s)&&/puan|aranm|istenm|sınav/.test(s));
  if(k&&k.length<=400){raw.kpssQuote=k;raw.kpssStatus=/aranm|istenm|muaf|şartı yok|puanı olmayan/.test(k)?'not_required':'required';raw.kpssType=k.match(/\bP\s?(\d{1,3})\b/i)?.[0].replace(/\s/g,'').toUpperCase();const score=k.match(/(?:en az|asgari)\s+(\d{1,3}(?:[.,]\d+)?)\s*puan/i)??k.match(/\b(\d{1,3}(?:[.,]\d+)?)\s*(?:\([^)]*\)\s*)?ve üzeri puan/i);if(score)raw.kpssScore=Number(score[1].replace(',','.'));}
  const a=clauses.find(s=>/yas/.test(fold(s))&&/doldur|tamamla|bitirmem|gun alm|buyuk|kucuk|asmam/.test(fold(s)));
  if(a&&a.length<=400){const nums=Array.from({length:55},(_,i)=>i+16).filter(n=>mentions(a,n));if(nums.length===1){if(/doldurmam|bitirmem|gun almam|asmam|buyuk olmam/.test(fold(a)))raw.maxAge=nums[0];else if(/doldurmus|tamamlamis|kucuk olmam/.test(fold(a)))raw.minAge=nums[0];}raw.ageQuote=a;}
  return validateGroups({groups:[raw]},text)[0]??{};
}
export function mechanicalNotice(notice,text){
  const title=fold(notice.title),kind=/iptal ilani/.test(title)?'cancellation':/sinav/.test(title)&&/serbest muhasebeci mali musavirlik|yeminli mali musavirlik|aktuerlik/.test(title)?'exam':null;
  if(kind)return {fields:{quota:{value:null,quote:notice.title,origin:'mechanical'},deadline:{value:null,quote:notice.title,origin:'mechanical'},notificationEligible:{value:false,quote:notice.title,origin:'mechanical'}},groups:[],rows:0,kind};
  const fields={}, groups=[], lines=text.split('\n'),seenRows=new Map(),columnDeadlines=[];let headers=null,count=-1,matrix=[],rows=0,tableAmbiguous=false,tableNumber=0;
  const tableStart=lines.findIndex(l=>l.split('|').some(countHeader)||l.split('|').filter(academicHeader).length>=2);
  const shared=[];if(tableStart>0)shared.push(lines.slice(0,tableStart).join('\n').split(/\n[^\n]{0,30}ÖZEL ŞARTLAR/i)[0]);
  for(let i=0;i<lines.length;i++)if(lines[i].length<120&&/genel sartlar/.test(fold(lines[i]))){const section=[];for(let j=i+1;j<lines.length;j++){if(lines[j].length<120&&/ozel sart|basvuru|istenilen belg|degerlendirme/.test(fold(lines[j])))break;section.push(lines[j]);}shared.push(section.join('\n'));}
  const register=/tercuman|bilirkisi/.test(fold(notice.title))&&(/liste|basvuru/.test(fold(notice.title))||/(?:tercuman|bilirkisi)[^\n]{0,100}liste/.test(fold(text)));
  for(const line of lines){
    const cells=line.split('|').map(s=>s.trim());
    if(cells.length<2)continue;
    let index=cells.findIndex(countHeader);
    if(index<0&&cells.some(c=>/unvan/.test(fold(c))))index=cells.findIndex(c=>/^(?:kadro|pozisyon)$/.test(fold(c)));
    if(index>=0){headers=cells;count=index;matrix=[];tableNumber++;continue;}
    const academic=cells.map((c,i)=>academicHeader(c)?i:-1).filter(i=>i>=0);
    if(academic.length>=2){headers=cells;matrix=academic;tableNumber++;continue;}
    if(cells.some(c=>fold(c)==='konu')&&cells.some(c=>fold(c)==='tarih')){headers=null;matrix=[];continue;}
    if(!headers)continue;
    if(/^toplam\b/.test(fold(cells[0])))continue;
    const deadlineColumn=headers.findIndex(h=>/^(?:son basvuru tarihi|basvuru bitis tarihi)/.test(fold(h)));
    if(cells.length===headers.length&&deadlineColumn>=0){const dates=[...cells[deadlineColumn].matchAll(datePattern)];if(dates.length===1){const m=dates[0],value=civilDate(m[1],m[2],m[3]);if(value)columnDeadlines.push({value,quote:cells[deadlineColumn]});}}
    if(matrix.length){
      if(cells.length!==headers.length){if(cells.some(s=>/^\d/.test(s)))tableAmbiguous=true;continue;}
      if(matrix.some(i=>cells[i]&&!/^(?:-|\d+(?:\s*\(\*\))?)$/.test(cells[i]))){tableAmbiguous=true;continue;}
      const rowKey=headers.join('|')+'\n'+line;if(seenRows.has(rowKey)&&seenRows.get(rowKey)<tableNumber)continue;seenRows.set(rowKey,tableNumber);
      const label=cells.filter((s,i)=>!matrix.includes(i)&&/birim|bolum|anabilim|anasanat|program|fakulte/.test(fold(headers[i]))).join(' · ');
      for(const i of matrix){const quota=Number(cells[i].match(/^\d+/)?.[0]??0);if(!quota)continue;if(!label||quota>100000){tableAmbiguous=true;continue;}rows++;const parsed=conditions(line);groups.push({label:label+' · '+headers[i],quota,...parsed,quotes:{...parsed.quotes,quota:line},sourceText:line});}
      continue;
    }
    // Only a trailing informational rowspan can be absent without shifting quota/condition columns.
    const missingSalary=cells.length===headers.length-1&&(/ucret|maas|adres|iletisim|ilan takvimi/.test(fold(headers.at(-1)))||(fold(headers.at(-1))==='toplam'&&count<headers.length-1));
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
    const kpssColumns=headers.map((h,i)=>/kpss (?:puan turu|taban puani|puani)/.test(fold(h))?i:-1).filter(i=>i>=0);
    if(kpssColumns.length){
      const quote=cells.slice(kpssColumns[0],kpssColumns.at(-1)+1).join(' | '),type=quote.match(/\bP\s?\d{1,3}\b/i)?.[0].replace(/\s/g,'').toUpperCase();
      const score=quote.match(/(?:en az|asgari)\s+(\d+(?:[.,]\d+)?)\s*puan/i)?.[1]??quote.match(/\bP\d+\s*\|\s*(\d+(?:[.,]\d+)?)(?:\s|$)/i)?.[1];
      const checked=validateGroups({groups:[{kpssStatus:'required',kpssType:type,kpssScore:score?Number(score.replace(',','.')):null,kpssQuote:quote}]},text)[0];
      if(checked){const quotes={...parsed.quotes,...checked.quotes};Object.assign(parsed,checked,{quotes});}
    }
    groups.push({label,quota,...parsed,quotes:{...parsed.quotes,quota:line},sourceText:line});
  }
  if(groups.length&&!tableAmbiguous){const total=groups.reduce((n,g)=>n+g.quota,0);if(total<=100000)fields.quota={value:total,quote:groups.map(g=>g.sourceText).join('\n')};}
  // ponytail: explicit numbered position headings with a known end only; other layouts retain the complete original document.
  const headings=lines.map((line,i)=>({line,i})).filter(({line})=>!line.includes('|')&&line.length<300&&/^\d+\s*[-.)]\s*/.test(line));
  for(const group of groups){
    if(groups.filter(g=>g.label===group.label).length!==1)continue;
    const starts=headings.filter(h=>fold(h.line).includes(fold(group.label)));if(starts.length!==1)continue;
    const start=starts[0].i,end=headings.find(h=>h.i>start&&(groups.some(g=>fold(h.line).includes(fold(g.label)))||h.line===h.line.toLocaleUpperCase('tr')&&/\p{L}/u.test(h.line)))?.i;
    if(end!==undefined)group.sourceText+='\n\n'+lines.slice(start,end).join('\n').trim();
  }
  const totals=[...text.matchAll(/(?:toplam\s+)?(\d{1,5})\s*(?:\([^)]*\)\s*)?(?:adet\s+)?(?:sözleşmeli\s+)?(?:personel|kişi|işçi)\s+(?:alınacak|alınacaktır|istihdam edilecek)/gi)];
  if(!fields.quota&&totals.length===1)fields.quota={value:Number(totals[0][1]),quote:totals[0][0]};
  if(Number.isSafeInteger(notice.quota)&&notice.quota>0&&notice.quota<=100000&&(!notice.fieldEvidence?.quota||notice.fieldEvidence.quota.origin==='source'))fields.quota={value:notice.quota,quote:notice.quotaQuote??notice.fieldEvidence?.quota?.quote??null,origin:'source'};
  if(notice.deadline&&(!notice.fieldEvidence?.deadline||notice.fieldEvidence.deadline.origin==='source'))fields.deadline={value:notice.deadline,quote:notice.deadlineQuote??notice.fieldEvidence?.deadline?.quote??null,origin:'source'};
  const deadlines=[...columnDeadlines];
  for(const line of lines){
    if(!/son\s*basvuru\s*tarihi|basvuru bitis tarihi|basvurular[^\n]*\d{1,2}[./-]\d{1,2}[./-]20\d{2}[^\n]*tarihleri arasinda/.test(fold(line)))continue;
    const cells=line.split('|'),label=cells.findIndex(c=>/son\s*basvuru\s*tarihi|basvuru bitis tarihi/.test(fold(c)));
    const selected=label>=0?cells.slice(label,label+2).join('|'):line,endpoint=selected.search(/son\s*başvuru\s*tarihi|başvuru bitiş tarihi/i);
    const evidence=endpoint>=0?selected.slice(endpoint).split(/ön değerlendirme|nihai değerlendirme|sonuç açıklama|giriş sınavı/i)[0]:selected;
    const dates=[...evidence.matchAll(datePattern)].map(m=>civilDate(m[1],m[2],m[3])).filter(Boolean);
    const months=['ocak','subat','mart','nisan','mayis','haziran','temmuz','agustos','eylul','ekim','kasim','aralik'];
    for(const m of fold(evidence).matchAll(/\b(\d{1,2})\s+(ocak|subat|mart|nisan|mayis|haziran|temmuz|agustos|eylul|ekim|kasim|aralik)\s+(20\d{2})\b/g)){const date=civilDate(m[1],months.indexOf(m[2])+1,m[3]);if(date)dates.push(date);}
    if(dates.length)deadlines.push({value:dates.at(-1),quote:evidence});
  }
  if(!fields.deadline&&new Set(deadlines.map(d=>d.value)).size===1){fields.deadline={...(deadlines.find(d=>/son\s*başvuru/i.test(d.quote))??deadlines[0])};const time=fields.deadline.quote.match(/(?:saat|mesai bitimi[^\d]*)\s*(\d{1,2})[:.](\d{2})/i);if(time&&Number(time[1])<24&&Number(time[2])<60){const d=new Date(fields.deadline.value);d.setUTCHours(Number(time[1])-3,Number(time[2]),0,0);fields.deadline.value=d.toISOString();}}
  const relative=lines.filter(l=>/(?:yayin|yayim).*itibaren\s+\d+\.?\s*gun/.test(fold(l))&&/basvur|aday|dilekce|teslim/.test(fold(l)));
  const multipleDeadlines=relative.length>0||new Set(deadlines.map(d=>d.value)).size>1;
  // A relative civil-day rule does not establish an inclusive/exclusive counting convention.
  if(multipleDeadlines){fields.applicationPeriods={value:[...deadlines.map(d=>({deadline:d.value,text:d.quote})),...relative.map(text=>({deadline:null,text,reference:notice.gazettePublishedQuote??null}))],quote:null};fields.deadline={value:null,quote:null};}
  if(!groups.length&&!headers){const general=conditions(text);if(Object.keys(general).length)groups.push({...general,label:'Başvuru koşulları'});}
  // Native position documents already have their own scope and quota.
  if(notice.positions?.length){groups.length=0;for(const p of notice.positions){const parsed=conditions(p.text??'');groups.push({label:p.title??p.profession??'Başvuru koşulları',...parsed,...(p.quota>0?{quota:p.quota}:{}),cities:p.places??notice.places??[],occupations:p.profession?[p.profession]:[],sourceText:p.text??''});}if(notice.positions.every(p=>Number.isSafeInteger(p.quota)&&p.quota>0)){const quota=notice.positions.reduce((n,p)=>n+p.quota,0);if(quota<=100000)fields.quota={value:quota,quote:null,origin:'source'};}}
  const general=conditions(shared.join('\n'));
  for(const group of groups){
    const existing={education:group.education?.length||group.educationDescription,kpss:group.kpssStatus,age:group.ageStatus};
    for(const [key,value] of Object.entries(general)){const topic=key.startsWith('education')?'education':key.startsWith('kpss')?'kpss':'age';if(key!=='quotes'&&!existing[topic])group[key]=value;}
    group.quotes={...Object.fromEntries(Object.entries(general.quotes??{}).filter(([key])=>!existing[key])),...group.quotes};
  }
  for(const field of Object.values(fields))field.origin??='mechanical';
  for(const group of groups)group.fieldOrigins=Object.fromEntries(Object.keys(group.quotes??{}).map(key=>[key,'mechanical']));
  return {fields,groups,register,tableAmbiguous,rows,multipleDeadlines,sharedText:shared.join('\n')};
}
export function assessNotice(result,text){
  if(result.kind==='cancellation'||result.kind==='exam')return [];
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
  const canImprove=missing.some(topic=>topic!=='deadline_scope');
  if(canImprove&&!deps.mechanicalOnly&&text.trim().length>=MIN_TEXT&&text.length<=MAX_TEXT){
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
          for(const [key,value] of Object.entries(a)){const topic=key.startsWith('kpss')?'kpss':/Age|^age/.test(key)?'age':key.startsWith('education')?'education':null;if(topic&&accepted[topic]&&group[key]==null){group[key]=value;group.fieldOrigins[topic]='ai';contributed=true;}}
          group.quotes={...accepted,...group.quotes};
        }
      }else if(ai.groups.length){result.groups=ai.groups.map(g=>({...g,fieldOrigins:Object.fromEntries(Object.keys(g.quotes??{}).map(key=>[key,'ai']))}));contributed=true;}
      if(contributed)method=result.rows||Object.keys(mechanicalNotice(notice,text).fields).length?'hybrid':'ai';
      missing=assessNotice(result,text);
    }
  }else if(canImprove&&!deps.mechanicalOnly)response={status:422,body:{error:text.length>MAX_TEXT?'text_oversize':'text_short'}};
  return {...response,result:{fields:result.fields,groups:result.groups.map(({sourceText,...g})=>({...g,...(sourceText?{text:sourceText}:{}),cities:g.cities??notice.places??[]})),extraction:{version:NOTICE_VERSION,method,status:missing.length?'partial':'complete',missing,kind:result.kind??(result.register?'register':'vacancy')}}};
}
