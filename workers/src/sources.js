import {cityValues,fold} from './criteria.js';
const api = 'https://api.kariyerkapisi.gov.tr/api/';
const hosts = new Set(['api.kariyerkapisi.gov.tr','kariyerkapisi.gov.tr','kamuilan.sbb.gov.tr','www.ilan.gov.tr','esube.iskur.gov.tr']);
export class SourceError extends Error { constructor(code) {super(code);this.code=code;} }
async function sourceRead(url, options={}) {
  const uri=new URL(url);
  if (uri.protocol!=='https:'||uri.username||uri.password||uri.port||!hosts.has(uri.hostname)) throw new SourceError('host_rejected');
  const response=await fetch(url,{...options,redirect:'manual',signal:AbortSignal.timeout(25000)});
  const reader=response.body?.getReader(); const chunks=[]; let size=0;
  try {
    if(response.status!==200) throw new SourceError([401,403,429].includes(response.status)?'blocked':'source_http_'+response.status);
    if(Number(response.headers.get('content-length')??0)>3*1024*1024) throw new SourceError('source_oversize');
    if(!reader)throw new SourceError('source_empty');
    for(;;) {const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>3*1024*1024)throw new SourceError('source_oversize');chunks.push(value);}
  }
  // Cleanup must not replace a source error or delay durable pipeline retry.
  finally {if(reader)void reader.cancel().catch(()=>{});}
  const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
  return {bytes,response};
}
export async function sourceBytes(url,options={}){return (await sourceRead(url,options)).bytes;}
export async function sourceFetch(url,options={}){return new TextDecoder('utf-8',{fatal:true}).decode(await sourceBytes(url,options));}
const post = async(route,body)=>JSON.parse(await sourceFetch(api+route,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}));
// Keep official row/cell boundaries for reading and extraction; never flatten a quota table into prose.
export const plain = value => String(value??'')
  .replace(/<(script|style)\b[^>]*>[\s\S]*?<\/\1>/gi,'')
  .replace(/<t([dh])\b[^>]*>([\s\S]*?)<\/t\1>/gi,(_,tag,cell)=>'<t'+tag+'>'+plain(cell).replace(/\s+/g,' ').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;')+'</t'+tag+'>')
  .replace(/<\/(?:td|th)>\s*<(?:td|th)\b[^>]*>/gi,' | ')
  .replace(/<br\s*\/?>|<\/(?:p|div|tr|li|h\d)>/gi,'\n').replace(/<[^>]*>/g,' ')
  .replace(/\[(?:\/?[a-z]+)(?:=[^\]]*)?\]/gi,'')
  .replace(/&(nbsp|amp|quot|apos|lt|gt|ndash|mdash);/gi,(_,v)=>({nbsp:' ',amp:'&',quot:'"',apos:"'",lt:'<',gt:'>',ndash:'–',mdash:'—'})[v.toLowerCase()])
  .replace(/&#(x[\da-f]+|\d+);/gi,(_,v)=>{const n=v[0].toLowerCase()==='x'?parseInt(v.slice(1),16):Number(v);return n>0&&n<=0x10ffff&&!(n>=0xd800&&n<=0xdfff)?String.fromCodePoint(n):'\ufffd';})
  .replace(/\u00a0/g,' ').replace(/[ \t]+/g,' ').split('\n').map(line=>line.trim()).filter(line=>!/^\|[|\s]*$/.test(line)).join('\n').replace(/\n{3,}/g,'\n\n').trim();
const uuid=/^[a-f\d]{8}(?:-[a-f\d]{4}){3}-[a-f\d]{12}$/i;
const iso=value=>{if(typeof value!=='string')return null;const d=new Date(value);return Number.isFinite(+d)?d.toISOString():null;};
const ilanGovApi='https://www.ilan.gov.tr/api/api/services/app';
const ilanGovHeaders={'Accept':'text/plain','Content-Type':'application/json-patch+json','X-Requested-With':'XMLHttpRequest','X-Request-Origin':'IGT-UI'};
// ilan.gov.tr also files associations and private schools/dormitories as personnel ads; KamuBul lists public employers.
// ponytail: only names that are unambiguously private; A.Ş. (BOTAŞ, PTT) and vakıf (SYDV) advertisers are public.
export const privateEmployer = name => /\bdernegi\b|\bdernek\b|^ozel\s/.test(fold(name));
export function parseIlanGovList(raw) {
  if(!Array.isArray(raw?.result?.ads)||!Number.isSafeInteger(raw.result.numFound)||raw.result.numFound<0)throw new SourceError('layout_changed');
  const items=raw.result.ads.map(ad=>{
    if(!ad||!/^\d{1,20}$/.test(String(ad.id))||typeof ad.title!=='string'||!plain(ad.title)||typeof ad.urlStr!=='string'||!ad.urlStr.startsWith('/ilan/'))throw new SourceError('layout_changed');
    const url=new URL(ad.urlStr,'https://www.ilan.gov.tr');
    if(url.origin!=='https://www.ilan.gov.tr'||url.username||url.password||url.pathname.split('/')[2]!==String(ad.id))throw new SourceError('layout_changed');
    return {id:'ilangov:'+ad.id,externalId:String(ad.id),sourceId:'ilangov',url:url.href,
      title:plain(ad.title).slice(0,300),institution:plain(ad.advertiserName).slice(0,300),category:'Personel Alımı',
      deadline:null,publishedAt:iso(ad.publishStartDate),places:ad.addressCityName?[plain(ad.addressCityName)]:[],
      requirementGroups:[],summary:[],active:true};
  });
  return {items,total:raw.result.numFound};
}
export async function fetchIlanGovPage(page=0,pageSize=20) {
  // The official API clamps results to 20 even when a larger size is requested.
  if(!Number.isInteger(page)||page<0||page>=1000||pageSize!==20)throw new SourceError('source_page');
  return parseIlanGovList(JSON.parse(await sourceFetch(ilanGovApi+'/Ad/AdsByFilter',{method:'POST',headers:ilanGovHeaders,body:JSON.stringify({keys:{ats:[5]},skipCount:page*pageSize,maxResultCount:pageSize})})));
}
// ponytail: at most 1000 pages; above this explicit failure, move page cursors into D1 instead of dropping rows.
export async function fetchIlanGovList() {
  const items=[],seen=new Set();let expected;
  for(let page=0;page<1000;page++){
    const {items:batch,total}=await fetchIlanGovPage(page);
    expected??=total;if(total!==expected)throw new SourceError('source_total_changed');
    for(const item of batch){if(seen.has(item.id))throw new SourceError('source_page_repeated');seen.add(item.id);items.push(item);}
    if(items.length===total)return items;
    if(items.length>total||batch.length!==20)throw new SourceError('source_incomplete');
  }
  throw new SourceError('source_page_limit');
}
export function parseIlanGovDetail(raw,id) {
  if(typeof raw?.result?.content!=='string')throw new SourceError('layout_changed');
  if(id!==undefined&&raw.result.id!==undefined&&String(raw.result.id)!==String(id))throw new SourceError('source_identity');
  const text=plain(raw.result.content);
  if(!text)throw new SourceError('source_empty');
  const detail={text,detailState:'available'};
  // Only the explicit application deadline is native evidence; publisher endDate is an ad display period.
  for(const [label,field] of [['son basvuru tarihi','deadline'],['resmi gazete yayim tarihi','gazettePublishedAt']]){
    const filters=Array.isArray(raw.result.adTypeFilters)?raw.result.adTypeFilters.filter(f=>fold(f?.key)===label):[];
    if(filters.length!==1||typeof filters[0].value!=='string')continue;
    const date=filters[0].value.trim().match(/^(\d{1,2})\.(\d{1,2})\.(20\d{2})$/);
    if(date){
      const d=new Date(Date.UTC(Number(date[3]),Number(date[2])-1,Number(date[1])));
      if(d.getUTCFullYear()!==Number(date[3])||d.getUTCMonth()!==Number(date[2])-1||d.getUTCDate()!==Number(date[1]))continue;
      detail[field]=field==='deadline'?new Date(+d+21*3600000-1000).toISOString():d.toISOString().slice(0,10);
      if(field==='gazettePublishedAt')detail.gazettePublishedQuote=filters[0].key+': '+filters[0].value;
    }
  }
  return detail;
}
export async function fetchIlanGovDetail(id) {
  if(!/^\d{1,20}$/.test(String(id)))throw new SourceError('source_identity');
  return parseIlanGovDetail(JSON.parse(await sourceFetch(ilanGovApi+'/AdDetail/GetAdDetail?id='+encodeURIComponent(id),{headers:ilanGovHeaders})),id);
}
export function parseKariyerIndex(raw) {
  if(!Array.isArray(raw?.searchIlan))throw new SourceError('layout_changed');
  return raw.searchIlan.filter(x=>x?.ilanTuru!=='Yurt Dışı Eğitim İlanları').map(x=>{
    if(!x||typeof x.guid!=='string'||!uuid.test(x.guid)||typeof x.ilanBaslik!=='string'||!plain(x.ilanBaslik))throw new SourceError('layout_changed');
    return {
    id:'kariyerkapisi:'+x.guid.toLowerCase(),externalId:x.guid.toLowerCase(),sourceId:'kariyerkapisi',
    url:'https://kariyerkapisi.gov.tr/IlanDetay?i='+x.guid.toLowerCase(),title:plain(x.ilanBaslik).slice(0,300),category:plain(x.ilanTuru),deadline:iso(x.bitTarih),publishedAt:null,places:[],requirementGroups:[],summary:[],active:true,
  };});
}
export function parseKariyerRss(xml){
  if(!/<rss\b/i.test(xml)||!/<\/rss\s*>/i.test(xml))throw new SourceError('rss_layout_changed');
  const value=(body,key)=>plain((body.match(new RegExp('<'+key+'(?:\\s[^>]*)?>([\\s\\S]*?)</'+key+'>','i'))?.[1]??'').replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g,'$1'));
  const entries=[...xml.matchAll(/<item\b[^>]*>([\s\S]*?)<\/item>/gi)];
  if(entries.length!==[...xml.matchAll(/<item\b/gi)].length)throw new SourceError('rss_layout_changed');
  return entries.flatMap(m=>{
    const category=value(m[1],'category');if(category==='Yurt Dışı Eğitim İlanları')return [];
    const url=value(m[1],'link');let uri;try{uri=new URL(url);}catch{throw new SourceError('rss_layout_changed');}
    const guid=uri.searchParams.get('i');if(uri.hostname!=='kariyerkapisi.gov.tr'||uri.protocol!=='https:'||uri.username||uri.password||uri.port||!uuid.test(guid??'')||!value(m[1],'title'))throw new SourceError('rss_layout_changed');
    return [{id:'kariyerkapisi:'+guid.toLowerCase(),externalId:guid.toLowerCase(),sourceId:'kariyerkapisi',url,title:value(m[1],'title').slice(0,300),category,deadline:null,publishedAt:iso(value(m[1],'pubDate')),places:[],requirementGroups:[],summary:[],active:true}];
  });
}
export async function fetchKariyerList(){
  try{return parseKariyerIndex(await post('ilan/GetIseAlimPage',{krM_ID:0,searchText:'',il:'0',ilanTuru:'0'}));}
  catch(indexError){if(indexError.code==='layout_changed')throw indexError;try{return parseKariyerRss(await sourceFetch('https://kariyerkapisi.gov.tr/RSS'));}catch{throw indexError;}}
}
export function parseKariyerDetail(main,positions) {
  if(!main||typeof main!=='object'||!Array.isArray(positions))throw new SourceError('detail_layout_changed');
  const groups=positions.map(x=>{if(!x||typeof x!=='object')throw new SourceError('detail_layout_changed');return {
    title:plain(x.ilanBaslik),profession:plain(x.unvan),text:plain(x.ilanMetni),
    places:[...new Set((Array.isArray(x.kontenjanList)?x.kontenjanList:[]).map(q=>plain(q.il).split(' / ')[0]).filter(Boolean))],
    quota:(Array.isArray(x.kontenjanList)?x.kontenjanList:[]).reduce((n,q)=>n+(Number.isInteger(q.kontenjan)&&q.kontenjan>0?q.kontenjan:0),0),
  };});
  const rawURL=main.eDevletteGorunsun===1?main.eDevletServisURL:main.basvuruLinki;
  return {institution:plain(main.kurumAdi),text:plain(main.ilanMetni),detailState:'available',start:iso(main.basTarih),deadline:iso(main.bitTarih),applyUrl:typeof rawURL==='string'&&rawURL.startsWith('https://')?rawURL:null,positions:groups,places:[...new Set(groups.flatMap(g=>g.places))],quota:groups.reduce((n,g)=>n+g.quota,0)};
}
export async function fetchKariyerDetail(id) {if(typeof id!=='string'||!uuid.test(id))throw new SourceError('source_identity');return parseKariyerDetail(await post('ilan/GetIlanPreviewPublic',{ilanGuid:id}),await post('altilan/GetAltIlanInfoByIlanIdPublic',{ilanGuid:id}));}
const months=['ocak','şubat','mart','nisan','mayıs','haziran','temmuz','ağustos','eylül','ekim','kasım','aralık'];
function sbbDate(value,year,end=false,start=null) {
  const m=plain(value).match(/(\d{1,2})\s+([a-zçğıöşüİ]+)(?:\s+(20\d{2}))?/i);
  if(!m)return null;const month=months.indexOf(m[2].toLocaleLowerCase('tr'));
  if(month<0)return null;let y=Number(m[3]??year);const day=Number(m[1]);
  if(!m[3]&&start){
    const civil=new Date(Date.parse(start)+3*3600000);
    y=civil.getUTCFullYear()+(month*100+day<civil.getUTCMonth()*100+civil.getUTCDate()?1:0);
  }
  const d=new Date(Date.UTC(y,month,day));
  return day>=1&&day<=31&&d.getUTCMonth()===month?new Date(+d+(end?21*3600000-1000:-3*3600000)).toISOString():null;
}
export function parseSbbList(html, year=new Date().getUTCFullYear()) {
  const rows=[];
  for(const match of html.matchAll(/<a\s[^>]*href=['"](ilanDetay\.aspx\?kod=[^'"]+)['"][^>]*>([\s\S]*?)<\/a>/gi)) {
    const block=match[2]; const part=cls=>plain(block.match(new RegExp('<(?:span|p)[^>]*class\\s*=\\s*[\\\'\"]'+cls+'[\\\'\"][^>]*>([\\s\\S]*?)<\\/(?:span|p)>','i'))?.[1]??'');
    const institution=part('black')||part('alt_p1');
    const body=block.match(/<p[^>]*class\s*=\s*['"]alt_p2['"][^>]*>([\s\S]*?)<\/p>/i)?.[1]??'';
    const title=part('patrol')||plain(body.split(/<em/i)[0]);
    const range=part('h5date')||plain(body.match(/<em[^>]*>([\s\S]*?)<\/em>/i)?.[1]??'');
    if(!title||!institution)throw new SourceError('layout_changed');
    const dates=range.split(/[-–]/);const url=new URL(match[1].replace(/&amp;/g,'&'),'https://kamuilan.sbb.gov.tr/');const externalId=url.searchParams.get('kod');
    if(!externalId)throw new SourceError('layout_changed');
    const start=dates.length===2?sbbDate(dates[0],year):null;
    let deadline=dates.length===2?sbbDate(dates[1],year,true,start):null;
    if(start&&deadline&&deadline<start)deadline=null;
    const upper=title.toLocaleUpperCase('tr');
    rows.push({id:'sbb:'+externalId,externalId,sourceId:'sbb',url:url.href,title,institution,category:upper.includes('SÖZLEŞMELİ')?'Sözleşmeli Personel':upper.includes('İŞÇİ')?'İşçi':'Kamu Personeli',start,deadline,publishedAt:null,places:[],requirementGroups:[],summary:[],active:true});
  }
  if(!rows.length)throw new SourceError('layout_changed');return rows;
}
export async function fetchSbbList(){
  const home=await sourceFetch('https://kamuilan.sbb.gov.tr/');const form=new URLSearchParams({__EVENTTARGET:'ddl_yil',ddl_yil:String(new Date().getUTCFullYear())});
  for(const name of ['__VIEWSTATE','__VIEWSTATEGENERATOR','__EVENTVALIDATION']) {
    const value=home.match(new RegExp('name="'+name+'"[^>]*value="([^"]*)"'))?.[1];if(value)form.set(name,value);
  }
  if(!form.has('__VIEWSTATE'))throw new SourceError('layout_changed');
  return parseSbbList(await sourceFetch('https://kamuilan.sbb.gov.tr/',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:form.toString()}));
}

const iskurSearch='https://esube.iskur.gov.tr/Istihdam/AcikIsIlanAra.aspx';
const iskurUrl=id=>'https://esube.iskur.gov.tr/Istihdam/AcikIsIlanDetay.aspx?uiID='+id+'&isyeriTuru=Kamu';
export function parseIskurList(html){
  const grid=html.indexOf('ctlGridAcikIslerListeDetail');if(grid<0)throw new SourceError('layout_changed');
  const items=[];
  for(const row of html.slice(grid).split(/<tr\b/i)){
    const link=row.match(/PopupJobDetails\((?:&#39;|')(\d+)(?:&#39;|'),(?:&#39;|')([^&']*)(?:&#39;|')[^>]*>([\s\S]*?)<\/a>/i);
    if(!link){if(/<a\b[^>]*PopupJobDetails\(/i.test(row))throw new SourceError('layout_changed');continue;}
    const span=suffix=>plain(row.match(new RegExp('_'+suffix+'[\'\"][^>]*>([\\s\\S]*?)</span>','i'))?.[1]??'');
    if(link[2]!=='Kamu'||span('ctlIsverenTurDL')!=='Kamu')continue;
    const id=link[1],institution=span('ctlIsverenDL'),title=plain(link[3]);
    if(!/^\d{1,20}$/.test(id)||!institution||!title)throw new SourceError('layout_changed');
    const place=span('ctlCalismaYeriDL').match(/Çalışma Yeri:\s*([^/)]+?)\s*\/\s*([^)]+?)\s*\)/i);
    const date=span('ctlSonBasvuruTarihi').match(/^(\d{1,2})\.(\d{1,2})\.(\d{4})$/),quota=Number(span('Label9'));
    let deadline=null;if(date){const d=new Date(Date.UTC(Number(date[3]),Number(date[2])-1,Number(date[1])));if(d.getUTCFullYear()===Number(date[3])&&d.getUTCMonth()===Number(date[2])-1&&d.getUTCDate()===Number(date[1]))deadline=new Date(+d+21*3600000-1000).toISOString();}
    const city=place?cityValues.find(c=>fold(c.label)===fold(place[1]))?.label:null;
    items.push({id:'iskur:'+id,externalId:id,sourceId:'iskur',url:iskurUrl(id),title,institution,category:'İşçi',deadline,publishedAt:null,places:city?[city]:[],district:place?.[2]?.trim()??null,period:span('ctlCalismaPeriyotDL'),quota:Number.isInteger(quota)&&quota>0?quota:null,requirementGroups:[],summary:[],active:true});
  }
  return items;
}
function iskurForm(html,target,argument=''){
  if(!/value\s*=\s*['"]kamuRadio['"]/.test(html))throw new SourceError('source_public_filter');
  const form=new URLSearchParams({'__EVENTTARGET':target,'__EVENTARGUMENT':argument,'ctl04$IsyeriTuruRadios':'kamuRadio'});
  for(const tag of html.matchAll(/<input\b[^>]*>/gi)){
    const name=tag[0].match(/\bname\s*=\s*['"]([^'"]+)['"]/i)?.[1],value=tag[0].match(/\bvalue\s*=\s*['"]([^'"]*)['"]/i)?.[1];
    if(name?.startsWith('__VIEWSTATE')||name==='__EVENTVALIDATION')form.set(name,plain(value??''));
  }
  if(!form.has('__VIEWSTATE'))throw new SourceError('layout_changed');return form;
}
export async function fetchIskurList(){
  let cookie='';
  const load=async options=>{
    const {bytes,response}=await sourceRead(iskurSearch,{...options,headers:{...options?.headers,...(cookie?{Cookie:cookie}:{})}});
    const cookies=response.headers.getSetCookie?.()??(response.headers.get('set-cookie')??'').split(/,(?=[^;,]+=)/);
    if(cookies.some(Boolean))cookie=cookies.filter(Boolean).map(v=>v.split(';')[0].trim()).join('; ');
    return new TextDecoder('utf-8',{fatal:true}).decode(bytes);
  };
  const home=await load();let form=iskurForm(home,'ctl04$ctlAcikIsPageCommand$CommandItem_Search');const items=[],seen=new Set();
  // ponytail: 50 WebForms pages per run; fail visibly at the ceiling, persist page state in D1 if this grows.
  for(let page=1;page<=50;page++){
    const html=await load({method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:form.toString()});
    for(const item of parseIskurList(html)){if(seen.has(item.id))throw new SourceError('source_page_repeated');seen.add(item.id);items.push(item);}
    // Decode only entities here: stripping HTML would discard the pager's postback attributes.
    const decoded=html.replace(/&#39;|&apos;/gi,"'").replace(/&quot;/gi,'"').replace(/&amp;/gi,'&');
    const links=[...decoded.matchAll(/__doPostBack\('([^']+)','Page\$(Next|\d+)'\)/gi)].filter(m=>m[2]==='Next'||Number(m[2])>page);
    const next=links.find(m=>Number(m[2])===page+1)??links.find(m=>m[2]==='Next');
    if(!next){if(links.length)throw new SourceError('source_incomplete');return items;}
    form=iskurForm(html,next[1],'Page$'+next[2]);
  }
  throw new SourceError('source_page_limit');
}
export function parseIskurDetail(html){
  const text=plain(html),starts=['ÖZEL ŞARTLAR','Genel Hususlar'].map(heading=>text.indexOf(heading)).filter(n=>n>=0);
  if(!starts.length)throw new SourceError('detail_layout_changed');return {text:text.slice(Math.min(...starts)),detailState:'available'};
}
export async function fetchIskurDetail(id){if(typeof id!=='string'||!/^\d{1,20}$/.test(id))throw new SourceError('source_identity');return parseIskurDetail(await sourceFetch(iskurUrl(id)));}
