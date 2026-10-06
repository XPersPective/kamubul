// One server result feeds cards, details and matching. Original text is never rewritten.
import {handleExtract,validateGroups,missingTopics,mentions,vacancyTotals,applicationDeadline,MIN_TEXT,MAX_TEXT} from './extract.js';
import {fold,occupationsOf} from './criteria.js';
export const NOTICE_VERSION='notice-19';
const countHeader=value=>/^(?:ad|adet|adedi|(?:kadro|pozisyon) (?:sayisi|adedi)|kontenjan(?: sayisi)?|personel sayisi|alinacak (?:kisi|personel) sayisi|kisi sayisi|sayi|sayisi|istihdam edilecek (?:personel|uzman) sayisi|acik isci sayisi|alinmasi planlanan kadro sayisi|atama yapilabilecek bos kadro sayisi)$/.test(fold(value).replace(/[:.*]/g,'').trim());
// Rank columns whose cells are counts; "ÖĞR.GÖR. (UYGULAMALI BİRİM)" is the YÖK position type beside "(DERS VERECEK)".
const academicHeader=value=>/^(?:prof|profesor|doc|docent|doktorogretimuyesi|drogretimuyesi|drogruyesi|(?:ogrgor|ogretimgorevlisi)(?:dersverecek|uygulamalibirim)?|arsgor|arastirmagorevlisi)$/.test(fold(value).replace(/[^\p{L}]/gu,''));
const datePattern=/\b(\d{1,2})[./-](\d{1,2})[./-](20\d{2})\b/g;
function civilDate(day,month,year){const d=`${year}-${String(month).padStart(2,'0')}-${String(day).padStart(2,'0')}`;return Number.isFinite(Date.parse(d))&&new Date(d).toISOString().slice(0,10)===d?d+'T20:59:59.999Z':null;}
function conditions(text){
  const raw={},clauses=text.split(/\n|\||•|(?<=[.;])\s+/);
  // ponytail: explicit requirement clauses only; ambiguous/scoped prose goes to Qwen, never inferred from document checklists.
  // "yüksek lisans mezunu olunması ... değerlendirmeye tabi tutulacaktır", "tercih sebebidir": scoring, not a requirement.
  const educationClauses=clauses.filter(s=>/mezunu|mezun (?:olmak|olmus)|derecesine sahip|doktorasini|doktora yapm|lisans.*yapmis|docentlik.*(?:unvan|almi)/.test(fold(s))&&!/degerlendirmeye tabi|dikkate alin|tercih (?:sebebi|nedeni|edil)|ek puan/.test(fold(s)));
  if(educationClauses.length){const clause=educationClauses[0],quote=text.slice(text.indexOf(clause),text.lastIndexOf(educationClauses.at(-1))+educationClauses.at(-1).length),at=clause.search(/lisans|doktora|lise|ortaöğretim|fakülte|ilkokul|ortaokul|ilköğretim/i);raw.education=['İlkokul','Ortaokul','Lise','Ön lisans','Lisans','Yüksek lisans','Doktora'];raw.educationQuote=quote.length<=400?quote:clause.slice(Math.max(0,at-30),Math.max(0,at-30)+400);}
  const k=text.match(/KPSS puanı olmayan[^.\n]{0,300}?dikkate alınır/i)?.[0]??text.match(/KPSS[^.\n|]{0,250}?sınava girmiş olmak/i)?.[0]??clauses.find(s=>/kpss/i.test(s)&&/puan|aranm|istenm|sınav/.test(s));
  if(k&&k.length<=400){raw.kpssQuote=k;raw.kpssStatus=/aranm|istenm|muaf|şartı yok|puanı olmayan/.test(k)?'not_required':'required';raw.kpssType=k.match(/\bP\s?(\d{1,3})\b/i)?.[0].replace(/\s/g,'').toUpperCase();const score=k.match(/(?:en az|asgari)\s+(\d{1,3}(?:[.,]\d+)?)\s*puan/i)??k.match(/\b(\d{1,3}(?:[.,]\d+)?)\s*(?:\([^)]*\)\s*)?ve üzeri puan/i);if(score)raw.kpssScore=Number(score[1].replace(',','.'));}
  const a=clauses.find(s=>/yas/.test(fold(s))&&/doldur|tamamla|bitirmem|gun alm|buyuk|kucuk|asmam/.test(fold(s)));
  if(a&&a.length<=400){const nums=Array.from({length:55},(_,i)=>i+16).filter(n=>mentions(a,n));if(nums.length===1){if(/doldurmam|bitirmem|gun almam|asmam|buyuk olmam/.test(fold(a)))raw.maxAge=nums[0];else if(/doldurmus|tamamlamis|kucuk olmam/.test(fold(a)))raw.minAge=nums[0];}
    else if(nums.length===2){
      // "18 yaşını tamamlamış, ... 32 yaşından gün almamış olmak": a lower and an upper bound in one clause.
      const bound=n=>fold(a).match(new RegExp(`\\b${n}\\b[^\\d]{0,40}?yas\\w*\\s+(doldurmamis|gun almamis|bitirmemis|doldurmus|tamamlamis)`))?.[1]??'';
      if(/doldurmus|tamamlamis/.test(bound(nums[0]))&&/doldurmamis|gun almamis|bitirmemis/.test(bound(nums[1]))){raw.minAge=nums[0];raw.maxAge=nums[1];}
    }
    raw.ageQuote=a;}
  return validateGroups({groups:[raw]},text)[0]??{};
}
// "Resmî Gazete'de yayımından itibaren 15 gün": the publication day counts as day one unless
// the rule says "takip eden/izleyen". ponytail: weekend shift only when the notice mentions holidays;
// official holidays are not modelled, so the value is always presented as an estimate.
const relativePattern=/(?:yayi[mn]\w*|ilan)\s*(?:(?<day>\d{1,2})[./](?<month>\d{1,2})[./](?<year>20\d{2})\s*)?(?:tarih\w*|gun\w*)?[^.]{0,80}?(?<rule>itibaren|itibari\s*(?:ile|yla|yle)|itibariyle|itibariyla|takip eden|izleyen)[^.\d]{0,70}?(?<count>\d{1,2}|on ?bes|yirmi|otuz|on|yedi)\s*(?:\.|['’]?\s*(?:inci|nci|uncu|unci))?\s*(?:\([^)]*\)\s*)?(?:is\s+)?gun/;
const countWords={'on bes':15,onbes:15,yirmi:20,otuz:30,on:10,yedi:7};
export function relativeDeadlines(lines,notice,text){
  const out=[],holiday=/tatil|hafta ?sonu/.test(fold(text));
  const native=/^\d{4}-\d{2}-\d{2}$/.test(notice.gazettePublishedAt??'')?notice.gazettePublishedAt:Number.isFinite(Date.parse(notice.publishedAt))?new Date(Date.parse(notice.publishedAt)+3*3600000).toISOString().slice(0,10):null;
  for(const line of lines){
    const f=fold(line),m=f.match(relativePattern);if(!m)continue;
    const clause=f.slice(f.lastIndexOf('. ',m.index)+1,m.index+m[0].length);
    // "ilandan itibaren 5 gün" after results concerns winners' documents, not the application window.
    if(!(!/yayi[mn]/.test(m[0])?/basvur|muracaat/.test(clause):/basvur|muracaat|aday|dilekce|teslim/.test(f))||/itiraz|sonuc|goreve basla|tebellug|asil|yedek|basarili/.test(clause))continue;
    const {day,month,year,rule,count}=m.groups,days=countWords[count]??Number(count);if(!(days>=1&&days<=90))continue;
    const stated=year?civilDate(day,month,year)?.slice(0,10):null,base=stated??native;
    let value=null;
    if(base){const d=new Date(base+'T00:00:00Z');d.setUTCDate(d.getUTCDate()+days-(/takip eden|izleyen/.test(rule)&&!/dahil/.test(clause)?0:1));if(holiday)while([0,6].includes(d.getUTCDay()))d.setUTCDate(d.getUTCDate()+1);value=d.toISOString().slice(0,10)+'T20:59:59.999Z';}
    const at=Math.max(0,line.search(/itibar|takip eden|izleyen/i));
    out.push({value,quote:line.length<=400?line:line.slice(Math.max(0,at-220),at+160).trim(),base,days});
  }
  // Private university notices often state only the display window next to "Başvurular ... son başvuru tarihine kadar".
  if(!out.length&&/ilan basla(?:ma|ngic) tarihi/.test(fold(text)))for(const line of lines){const m=fold(line).match(/^ilan bitis tarihi\s*[:|]\s*(\d{1,2})[./](\d{1,2})[./](20\d{2})/);const value=m&&civilDate(m[1],m[2],m[3]);if(value)out.push({value,quote:line,base:null,days:null});}
  return out;
}
// Explicit application windows that do not use the words "son başvuru": "19/10/2026-23/10/2026 tarihleri arasında",
// "12.10.2026 tarihinden 19.10.2026 tarihi saat 17:00'a kadar", a split "Son / Başvuru Tarihi" label or a
// "BAŞVURU TARİHLERİ" block. Exam, objection, payment and result windows are excluded.
const windowPatterns=[
  /(?<d1>\d{1,2})[./](?<m1>\d{1,2})[./](?<y1>20\d{2})\s*(?:[-–]|ile|ila)\s*(?<day>\d{1,2})[./](?<month>\d{1,2})[./](?<year>20\d{2})\s*(?:tarih\w*\s*)?arasi/,
  /(?<d1>\d{1,2})[./](?<m1>\d{1,2})[./](?<y1>20\d{2})\s*tarih\w*\s*(?:baslayacak olup,?\s*)?(?<day>\d{1,2})[./](?<month>\d{1,2})[./](?<year>20\d{2})\s*tarihi?\s*(?:saat\s*(?<hour>\d{1,2})[:.](?<minute>\d{2}))?[^.]{0,12}kadar/,
  // "Başvuru süresi, ilan ... itibaren (30/09/2026 – 14/10/2026) 15 gündür": the bracketed range is the window itself.
  /basvuru (?:suresi|tarihleri)[^.()]{0,80}\(\s*(?<d1>\d{1,2})[./](?<m1>\d{1,2})[./](?<y1>20\d{2})\s*[-–]\s*(?<day>\d{1,2})[./](?<month>\d{1,2})[./](?<year>20\d{2})\s*\)/,
];
export function applicationWindows(lines){
  const out=[],filled=lines.filter(l=>l.trim());
  for(const [i,line] of filled.entries()){
    const f=fold(line),previous=filled.slice(Math.max(0,i-3),i);
    if(/\bson$/.test(fold(previous.at(-1)??''))&&/^basvuru tarihi/.test(f)){const value=applicationDeadline('Son '+line);if(value)out.push({value,quote:previous.at(-1).slice(-40)+' '+line});continue;}
    if(/^bitis tarihi\s*[:|]/.test(f)&&previous.some(l=>/basvuru tarihleri/.test(fold(l)))){const m=f.match(/(\d{1,2})[./](\d{1,2})[./](20\d{2})/),value=m&&civilDate(m[1],m[2],m[3]);if(value)out.push({value,quote:line});continue;}
    // Calendar table: "... | Son Başvuru Tarihi | ..." followed by one dated row of the same width.
    const headers=line.split('|').map(c=>fold(c)),column=headers.findIndex(h=>h==='son basvuru tarihi');
    if(column>=0&&headers.length>1){const cells=(filled[i+1]??'').split('|').map(c=>c.trim()),m=cells.length===headers.length&&cells[column].match(/^(\d{1,2})[./](\d{1,2})[./](20\d{2})$/),value=m&&civilDate(m[1],m[2],m[3]);if(value)out.push({value,quote:line+String.fromCharCode(10)+filled[i+1]});continue;}
    for(const pattern of windowPatterns){
      const m=f.match(pattern);if(!m)continue;
      const before=f.slice(f.lastIndexOf('. ',m.index)+1,m.index);
      if(!/basvur|muracaat|ilana cikil/.test(f)||/sinav|itiraz|sonuc|odeme|ucret|kura|mulakat/.test(before))continue;
      const {day,month,year,hour,minute}=m.groups;let value=civilDate(day,month,year);
      if(value&&hour!==undefined&&Number(hour)<24&&Number(minute)<60){const d=new Date(value.slice(0,10)+'T00:00:00Z');d.setUTCHours(Number(hour)-3,Number(minute),0,0);value=d.toISOString();}
      if(value)out.push({value,quote:line.length<=400?line:f.slice(Math.max(0,m.index-120),m.index+m[0].length)});break;
    }
  }
  return out;
}
export function mechanicalNotice(notice,text){
  const title=fold(notice.title),kind=/iptal ilani/.test(title)?'cancellation':/sinav/.test(title)&&/serbest muhasebeci mali musavirlik|yeminli mali musavirlik|aktuerlik/.test(title)?'exam':null;
  if(kind)return {fields:{quota:{value:null,quote:notice.title,origin:'mechanical'},deadline:{value:null,quote:notice.title,origin:'mechanical'},notificationEligible:{value:false,quote:notice.title,origin:'mechanical'}},groups:[],rows:0,kind};
  const fields={}, groups=[], lines=text.split('\n'),seenRows=new Map(),columnDeadlines=[];let headers=null,count=-1,matrix=[],rows=0,tableAmbiguous=false,tableNumber=0,headerLine=-1,subSplit=null;
  const verticalLines=new Set();
  for(let start=0;start<lines.length;start++){
    if(!/^ilan no\s*\|/.test(fold(lines[start])))continue;
    let end=start+1;while(end<lines.length&&(!lines[end].trim()||lines[end].split('|').length===2&&!/^ilan no\s*\|/.test(fold(lines[end]))))end++;
    const block=lines.slice(start,end),cells=block.filter(line=>line.includes('|')).map(line=>line.split('|').map(s=>s.trim())),labels=cells.filter(([key])=>/^(?:pozisyon adi|kadro unvani)$/.test(fold(key))),counts=cells.filter(([key])=>countHeader(key));
    if(!labels.length)continue;
    for(let i=start;i<end;i++)verticalLines.add(i);
    const quota=counts.length===1&&/^\d+$/.test(counts[0][1])?Number(counts[0][1]):0;
    if(labels.length!==1||!labels[0][1]||quota<1||quota>100000){tableAmbiguous=true;continue;}
    const sourceText=block.join('\n'),parsed=conditions(sourceText);groups.push({label:labels[0][1],quota,...parsed,quotes:{...parsed.quotes,quota:counts[0].join(' | ')},sourceText});rows++;
  }
  const tableStart=lines.findIndex(l=>l.split('|').some(countHeader)||l.split('|').filter(academicHeader).length>=2);
  const shared=[];if(tableStart>0)shared.push(lines.slice(0,tableStart).join('\n').split(/\n[^\n]{0,30}ÖZEL ŞARTLAR/i)[0]);
  for(let i=0;i<lines.length;i++)if(lines[i].length<120&&/genel sartlar/.test(fold(lines[i]))){const section=[];for(let j=i+1;j<lines.length;j++){if(lines[j].length<120&&/ozel sart|basvuru|istenilen belg|degerlendirme/.test(fold(lines[j])))break;section.push(lines[j]);}shared.push(section.join('\n'));}
  const register=/tercuman|bilirkisi/.test(fold(notice.title))&&(/liste|basvuru/.test(fold(notice.title))||/(?:tercuman|bilirkisi)[^\n]{0,100}liste/.test(fold(text)));
  for(const [lineIndex,line] of lines.entries()){
    if(verticalLines.has(lineIndex))continue;
    const cells=line.split('|').map(s=>s.trim());
    if(cells.length<2)continue;
    let index=cells.findIndex(countHeader);
    if(index<0&&cells.some(c=>/unvan/.test(fold(c))))index=cells.findIndex(c=>/^(?:kadro|pozisyon)$/.test(fold(c)));
    if(index>=0){headers=cells;count=index;matrix=[];tableNumber++;headerLine=lineIndex;subSplit=null;continue;}
    const academic=cells.map((c,i)=>academicHeader(c)?i:-1).filter(i=>i>=0);
    if(academic.length>=2){headers=cells;matrix=academic;tableNumber++;headerLine=lineIndex;subSplit=null;continue;}
    // A second header row "PUANI | TÜRÜ" splits the score column (ALES) in two; merging the pair back keeps every
    // other column, including the count, at its header position.
    const firstAfterHeader=headerLine>=0&&lines.slice(headerLine+1,lineIndex).every(l=>!l.includes('|'));headerLine=-1;
    if(headers&&firstAfterHeader&&cells.length<=4&&cells.every(c=>c&&!/\d/.test(c)&&c.length<=25&&c===c.toLocaleUpperCase('tr'))){
      const at=headers.findIndex(h=>/\bales\b|\bkpss\b|yabanci dil|\byds\b/.test(fold(h)));if(at>=0)subSplit={at,extra:cells.length-1};continue;
    }
    if(subSplit&&headers&&cells.length===headers.length+subSplit.extra)cells.splice(subSplit.at,subSplit.extra+1,cells.slice(subSplit.at,subSplit.at+subSplit.extra+1).join(' '));
    if(cells.some(c=>fold(c)==='konu')&&cells.some(c=>fold(c)==='tarih')){headers=null;matrix=[];continue;}
    if(!headers){
      // A headerless row "Unvan | 6 (Erkek-Kadın) | ..." still states a headcount: the gender marker makes that cell unambiguous.
      const gendered=cells.map((c,i)=>/^\d{1,5}\s*\((?:erkek|kadin)(?:\s*[-/]\s*(?:erkek|kadin))?\)$/.test(fold(c))?i:-1).filter(i=>i>0);
      if(gendered.length===1&&cells[0]&&!/^\d/.test(cells[0])&&!seenRows.has('headerless\n'+line)){
        const quota=Number(cells[gendered[0]].match(/^\d+/)[0]);
        if(quota>=1&&quota<=100000){seenRows.set('headerless\n'+line,tableNumber);rows++;const parsed=conditions(line);groups.push({label:cells[0],quota,...parsed,quotes:{...parsed.quotes,quota:line},sourceText:line});}
      }
      continue;
    }
    if(/^toplam\b/.test(fold(cells[0])))continue;
    const deadlineColumn=headers.findIndex(h=>/^(?:son basvuru tarihi|basvuru bitis tarihi)/.test(fold(h)));
    if(cells.length===headers.length&&deadlineColumn>=0){const dates=[...cells[deadlineColumn].matchAll(datePattern)];if(dates.length===1){const m=dates[0],value=civilDate(m[1],m[2],m[3]);if(value)columnDeadlines.push({value,quote:cells[deadlineColumn]});}else if(!dates.length){
      // "13 Ekim 2026" under Son Başvuru Tarihi: the shared deadline parser reads Turkish month names.
      const value=applicationDeadline('Son başvuru tarihi '+cells[deadlineColumn]);if(value)columnDeadlines.push({value,quote:cells[deadlineColumn]});}}
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
    const label=cells.filter((s,i)=>i!==count&&/unvan|pozisyon|bolum|program|anabilim|anasanat|meslek adi|ogrenim dal(?:i|lari)|atama yapilacak yer/.test(fold(headers[i]))).join(' · ');
    if(!label){tableAmbiguous=true;continue;}
    const rowKey=headers.join('|')+'\n'+line;
    if(seenRows.has(rowKey)&&seenRows.get(rowKey)<tableNumber)continue;seenRows.set(rowKey,tableNumber);
    rows++;
    const parsed=conditions(line);
    const kpssColumns=headers.map((h,i)=>/kpss (?:puan turu|taban puani|puani)/.test(fold(h))?i:-1).filter(i=>i>=0);
    if(kpssColumns.length){
      // "KPSSP-3 KPSSP-44 KPSSP-45" lists alternative score types of one position.
      const quote=cells.slice(kpssColumns[0],kpssColumns.at(-1)+1).join(' | ');
      const types=[...new Set([...fold(quote).matchAll(/(?:^|[^a-z0-9])(?:kpss\s*)?p\s?-?(\d{1,3})\b/g)].map(m=>'P'+m[1]))],type=types.length===1?types[0]:undefined;
      const score=quote.match(/(?:en az|asgari)\s+(\d+(?:[.,]\d+)?)\s*puan/i)?.[1]??quote.match(/\bP\d+\s*\|\s*(\d+(?:[.,]\d+)?)(?:\s|$)/i)?.[1];
      const checked=validateGroups({groups:[{kpssStatus:'required',kpssType:type,kpssScore:score?Number(score.replace(',','.')):null,kpssQuote:quote}]},text)[0];
      if(checked){const quotes={...parsed.quotes,...checked.quotes};Object.assign(parsed,checked,{quotes},types.length>1?{kpssTypes:types}:{});}
    }
    // "ÖĞRENİM | Ön Lisans", "EĞİTİM DURUMU | Mesleki Lise ve Dengi Okulların; ...": a native education column.
    const educationColumn=headers.findIndex(h=>/^(?:(?:ogrenim|egitim)(?: durumu| seviyesi| duzeyi)?|mezuniyet(?: durumu)?)$/.test(fold(h).replace(/[:.*]/g,'').trim()));
    if(educationColumn>=0&&!parsed.education?.length&&cells[educationColumn]&&cells[educationColumn].length<=400){
      const checked=validateGroups({groups:[{education:['İlkokul','Ortaokul','Lise','Ön lisans','Lisans','Yüksek lisans','Doktora'],educationQuote:cells[educationColumn]}]},text)[0];
      if(checked?.education?.length){parsed.education=checked.education;parsed.quotes={...parsed.quotes,education:checked.quotes.education};}
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
  const totals=vacancyTotals(text);
  if(!fields.quota&&totals.length===1)fields.quota={value:Number(totals[0][1]),quote:totals[0][0]};
  // "1. Mobil Yazılım Geliştirme Uzmanı (2 (iki) kişi - tam zamanlı ...)": numbered position headings carry their counts.
  const headed=groups.some(g=>g.quota)?[]:lines.map(l=>l.match(/^\s*\d{1,2}\s*[-.)]\s*[^()|]{3,90}?\(\s*(\d{1,4})\s*(?:\([^)]*\)\s*)?kişi\b/i)).filter(Boolean);
  if(!fields.quota&&headed.length&&new Set(headed.map(m=>m[0])).size===headed.length){const value=headed.reduce((n,m)=>n+Number(m[1]),0);if(value<=100000)fields.quota={value,quote:headed.map(m=>m[0]).join('\n')};}
  if(Number.isSafeInteger(notice.quota)&&notice.quota>0&&notice.quota<=100000&&(!notice.fieldEvidence?.quota||notice.fieldEvidence.quota.origin==='source'))fields.quota={value:notice.quota,quote:notice.quotaQuote??notice.fieldEvidence?.quota?.quote??null,origin:'source'};
  if(notice.deadline&&(!notice.fieldEvidence?.deadline||notice.fieldEvidence.deadline.origin==='source'))fields.deadline={value:notice.deadline,quote:notice.deadlineQuote??notice.fieldEvidence?.deadline?.quote??null,origin:'source'};
  const deadlines=[...columnDeadlines];
  for(const line of lines){
    const cells=line.split('|'),label=cells.findIndex(c=>/son\s*basvuru|basvuru bitis/.test(fold(c))),evidence=label>=0?cells.slice(label,label+2).join('|'):line;
    const value=applicationDeadline(evidence);if(value)deadlines.push({value,quote:evidence});
    // "31 Ekim 2026 tarihinden sonra yapılan başvurular değerlendirmeye alınmaz" is a deadline too; when it contradicts
    // another stated end ("02 Kasım 2026 ... sona erecektir") no single date is shown.
    const after=/tarihinden\s+sonra/i.test(line)&&fold(line).match(/(\d{1,2})(?:[./](\d{1,2})[./]|\s+(ocak|subat|mart|nisan|mayis|haziran|temmuz|agustos|eylul|ekim|kasim|aralik)\s+)(20\d{2})\s+tarihinden\s+sonra\s+(?:yapilan|yapilacak|gelen|ulasan)\s+(?:basvuru|muracaat)/);
    if(after){const month=after[2]??['ocak','subat','mart','nisan','mayis','haziran','temmuz','agustos','eylul','ekim','kasim','aralik'].indexOf(after[3])+1,value=civilDate(after[1],month,after[4]);if(value)deadlines.push({value,quote:line.length<=400?line:after[0]});}
  }
  if(!deadlines.length&&!fields.deadline)deadlines.push(...applicationWindows(lines));
  const deadlineDays=new Set(deadlines.map(d=>new Date(Date.parse(d.value)+3*3600000).toISOString().slice(0,10)));
  const deadlineTimes=new Set(deadlines.filter(d=>!d.value.endsWith('T20:59:59.999Z')).map(d=>d.value));
  if(!fields.deadline&&deadlineDays.size===1&&deadlineTimes.size<=1)fields.deadline={...(deadlines.find(d=>deadlineTimes.has(d.value))??deadlines.find(d=>/son\s*başvuru/i.test(d.quote))??deadlines[0])};
  const estimates=relativeDeadlines(lines,notice,text),relative=estimates.map(e=>e.quote);
  const estimate=estimates.length&&estimates.every(e=>e.value&&e.value===estimates[0].value)?estimates[0]:null;
  // A native "Son Başvuru Tarihi" outranks a relative rule; a differing explicit date in the text stays a scoped calendar.
  // "en az 15 gündür" without a Gazette date cannot contradict the one stated "Son Başvuru Tarihi : 06.10.2026".
  const uncheckable=deadlineDays.size===1&&estimates.every(e=>!e.value)&&deadlines.some(d=>/son\s*basvuru|basvuru bitis/.test(fold(d.quote)));
  // One day apart is the inclusive/exclusive counting of the same rule (21.09 + 15 days → 05.10 or 06.10): the stated date wins.
  const agrees=estimate&&[...deadlineDays].every(d=>Math.abs(Date.parse(d)-Date.parse(estimate.value.slice(0,10)))<=86400000);
  const relativeConflict=estimates.length>0&&fields.deadline?.origin!=='source'&&(!estimate&&!uncheckable||estimate&&deadlineDays.size>0&&!agrees);
  const multipleDeadlines=relativeConflict||deadlineDays.size>1||deadlineTimes.size>1;
  if(estimate&&!multipleDeadlines&&!fields.deadline)fields.deadlineEstimate={value:estimate.value,quote:estimate.quote,origin:'computed',base:estimate.base,days:estimate.days};
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
  // An age rule outside the general conditions ("Zabıta memuru kadrolarına başvuracaklar için ... 30 yaşını doldurmamış",
  // "Araştırma görevlisi kadrosuna ... 35 yaşını") binds the positions whose canonical occupation it names, or the only
  // position; with several positions and no name its scope stays unknown.
  const sharedText=shared.join('\n');
  for(const line of lines){
    // Cheap raw-text gate before folding/parsing: only lines that state an age limit.
    if(line.includes('|')||!/ya[şs][^.]{0,60}(?:doldur|tamamla|g[üu]n alma|bitirme|b[üu]y[üu]k|k[üu][çc][üu]k)/i.test(line))continue;
    const rule=conditions(line);if(rule.maxAge==null&&rule.minAge==null||sharedText.includes(line))continue;
    const named=occupationsOf(line,true).length?occupationsOf(line,true):occupationsOf(line);
    const targets=named.length?groups.filter(g=>occupationsOf(g.label??'').some(o=>named.includes(o))):groups.length===1?groups:[];
    for(const group of targets)if(group.ageStatus!=='known'){for(const key of ['minAge','maxAge','ageStatus','ageCalculation'])if(rule[key]!=null)group[key]=rule[key];group.quotes={...group.quotes,age:rule.quotes.age};}
  }
  // "Ön lisans mezunları için 2024 KPSSP93 ve Ortaöğretim (Lise) mezunları için KPSSP94 puanı esas alınacaktır":
  // each position takes the score type of its own education level.
  const scoreTypes=new Map();
  for(const line of lines){
    if(line.length>600||!/mezunlar/i.test(line))continue;
    for(const m of fold(line).matchAll(/\b(on ?lisans|ortaogretim|lise|lisans)(?:\s*\([^)]*\))?\s+mezunlari\s+icin[^.;]*?p\s?(\d{1,3})\b/g))
      scoreTypes.set({'on lisans':'Ön lisans',onlisans:'Ön lisans',ortaogretim:'Lise',lise:'Lise',lisans:'Lisans'}[m[1]],{type:'P'+m[2],quote:line});
  }
  if(scoreTypes.size)for(const group of groups){
    const found=[...new Set((group.education??[]).map(e=>scoreTypes.get(e)).filter(Boolean))];
    if(group.kpssType||found.length!==1||new Set(found.map(f=>f.type)).size!==1)continue;
    Object.assign(group,{kpssStatus:'required',kpssType:found[0].type});group.quotes={...group.quotes,kpss:found[0].quote};
  }
  for(const field of Object.values(fields))field.origin??='mechanical';
  for(const group of groups)group.fieldOrigins=Object.fromEntries(Object.keys(group.quotes??{}).map(key=>[key,'mechanical']));
  // A correction notice amends an earlier ad; its application window belongs to the original notice.
  // A correction lists changed or cancelled rows of an earlier notice: their counts are not new vacancies.
  const amendment=/duzeltme ilani/.test(title);if(amendment&&fields.quota?.origin!=='source')delete fields.quota;
  return {fields,groups,register,tableAmbiguous,rows,multipleDeadlines,sharedText:shared.join('\n'),...(amendment?{kind:'amendment'}:{})};
}
export function assessNotice(result,text){
  if(result.kind==='cancellation'||result.kind==='exam')return [];
  const missing=[];
  if(!result.register&&!result.fields.quota&&result.kind!=='amendment')missing.push('quota');
  if(result.multipleDeadlines)missing.push('deadline_scope');
  else if(!result.fields.deadline?.value&&!result.fields.deadlineEstimate?.value&&result.kind!=='amendment')missing.push('deadline');
  if(result.tableAmbiguous)missing.push('table_rows');
  if(!result.groups.length&&/mezun|yaş|kpss|kadro|pozisyon/i.test(text))missing.push('conditions');
  missing.push(...missingTopics(result.groups,text));
  for(const group of result.groups){const scope=group.sourceText||text;for(const topic of missingTopics([group],scope))missing.push(topic);}
  // Faculty titles carry their statutory degree (2547): a missing row-level degree is not a parser failure.
  const academic=result.groups.length&&result.groups.every(g=>/profesor|\bprof\b|docent|\bdoc\b|doktor ogretim uyesi|dr\.? ?ogr/.test(fold(g.label??'')));
  return [...new Set(missing)].filter(topic=>!(academic&&topic==='education'));
}
export async function extractNotice(notice,text,env,deps){
  const result=mechanicalNotice(notice,text);let missing=assessNotice(result,text),method='mechanical',response={status:200};
  const canImprove=missing.some(topic=>topic!=='deadline_scope');
  if(canImprove&&!deps.mechanicalOnly&&text.trim().length>=MIN_TEXT&&text.length<=MAX_TEXT){
    response=await handleExtract({installationId:'0'.repeat(32),text,noticeMode:true},env,{...deps,internal:true});
    if(response.status===200){
      const ai=response.body;let contributed=false;
      for(const [key,field] of Object.entries(ai.fields??{}))if(!result.fields[key]){result.fields[key]={...field,origin:'ai'};contributed=true;}
      // Qwen reads every table row. Its quote-validated rows replace an ambiguous or missing mechanical
      // table, and their distinct per-row counts form the total when no stated total exists.
      const rows=[...new Map(ai.groups.filter(g=>Number.isSafeInteger(g.quota)&&g.quota>0&&g.quotes?.quota).map(g=>[g.quotes.quota,g])).values()];
      const aiTotal=rows.reduce((n,g)=>n+g.quota,0);
      if(ai.groups.length&&(!result.groups.some(g=>g.sourceText)||result.tableAmbiguous&&rows.length>=result.groups.length)){
        result.groups=ai.groups.map(g=>({...g,fieldOrigins:Object.fromEntries(Object.keys(g.quotes??{}).map(key=>[key,'ai']))}));
        if(rows.length)result.tableAmbiguous=false;contributed=true;
      }else if(result.groups.length&&result.groups.some(g=>g.sourceText)){
        for(const group of result.groups){
          const candidates=ai.groups.filter(a=>fold(a.label)===fold(group.label)||Object.entries(a.quotes??{}).some(([key,q])=>key!=='quota'&&group.sourceText.includes(q)));
          if(candidates.length!==1)continue;
          const a=candidates[0],accepted={};
          for(const [key,quote] of Object.entries(a.quotes??{})){const general=a.quoteScopes?.[key]==='general'&&result.sharedText.includes(quote)&&!result.groups.some(g=>g.label&&fold(quote).includes(fold(g.label)));if(key!=='quota'&&(group.sourceText.includes(quote)||general))accepted[key]=quote;}
          for(const [key,value] of Object.entries(a)){const topic=key.startsWith('kpss')?'kpss':/Age|^age/.test(key)?'age':key.startsWith('education')?'education':null;if(topic&&accepted[topic]&&group[key]==null){group[key]=value;group.fieldOrigins[topic]='ai';contributed=true;}}
          group.quotes={...accepted,...group.quotes};
        }
      }
      if(!result.register&&result.kind!=='amendment'&&!result.fields.quota&&rows.length&&aiTotal<=100000){result.fields.quota={value:aiTotal,quote:rows.map(g=>g.quotes.quota).join('\n'),origin:'ai'};contributed=true;}
      if(contributed)method=result.rows||Object.keys(mechanicalNotice(notice,text).fields).length?'hybrid':'ai';
      missing=assessNotice(result,text);
    }
  }else if(canImprove&&!deps.mechanicalOnly)response={status:422,body:{error:text.length>MAX_TEXT?'text_oversize':'text_short'}};
  // Canonical occupations: from each position label, else from the title; structured source professions are kept.
  // Under an academic title only academic ranks count: faculty rows name departments ("Mütercim ve Tercümanlık").
  const title=notice.title??'',titled=occupationsOf(title),academicTitle=occupationsOf(title,true).length>0||/\bogretim elemani|\bakademik personel/.test(fold(title));
  const professions=values=>(values??[]).flatMap(o=>{const c=occupationsOf(o);return c.length?c:[o];});
  const groups=result.groups.map(({sourceText,...g})=>{const own=[...new Set([...occupationsOf(g.label??'',academicTitle),...professions(g.occupations)])];return {...g,...(sourceText?{text:sourceText}:{}),cities:g.cities??notice.places??[],occupations:own.length?own:titled};});
  const occupations=[...new Set(groups.length?groups.flatMap(g=>g.occupations):[...titled,...professions(notice.occupations)])];
  return {...response,result:{fields:result.fields,groups,occupations,extraction:{version:NOTICE_VERSION,method,status:missing.length?'partial':'complete',missing,kind:result.kind??(result.register?'register':'vacancy')}}};
}
