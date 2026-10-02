const api = 'https://api.kariyerkapisi.gov.tr/api/';
const hosts = new Set(['api.kariyerkapisi.gov.tr','kariyerkapisi.gov.tr','kamuilan.sbb.gov.tr']);
export class SourceError extends Error { constructor(code) {super(code);this.code=code;} }
export async function sourceFetch(url, options={}) {
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
  return new TextDecoder('utf-8',{fatal:true}).decode(bytes);
}
const post = async(route,body)=>JSON.parse(await sourceFetch(api+route,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}));
export const plain = value => String(value??'').replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi,'').replace(/<[^>]*>/g,' ').replace(/\[(?:\/?[a-z]+)(?:=[^\]]*)?\]/gi,'').replace(/&nbsp;|\u00a0/g,' ').replace(/&amp;/g,'&').replace(/&quot;/g,'"').replace(/&#(\d+);/g,(_,v)=>{const n=Number(v);return n>0&&n<=0x10ffff&&!(n>=0xd800&&n<=0xdfff)?String.fromCodePoint(n):'\ufffd';}).replace(/[ \t]+/g,' ').replace(/\n{3,}/g,'\n\n').trim();
const uuid=/^[a-f\d]{8}(?:-[a-f\d]{4}){3}-[a-f\d]{12}$/i;
const iso=value=>{if(typeof value!=='string')return null;const d=new Date(value);return Number.isFinite(+d)?d.toISOString():null;};
export function parseKariyerIndex(raw) {
  if(!Array.isArray(raw?.searchIlan))throw new SourceError('layout_changed');
  return raw.searchIlan.slice(0,200).filter(x=>x&&typeof x.guid==='string'&&uuid.test(x.guid)&&typeof x.ilanBaslik==='string'&&x.ilanTuru!=='Yurt Dışı Eğitim İlanları'&&iso(x.bitTarih)).map(x=>({
    id:'kariyerkapisi:'+x.guid.toLowerCase(),externalId:x.guid.toLowerCase(),sourceId:'kariyerkapisi',
    url:'https://kariyerkapisi.gov.tr/IlanDetay?i='+x.guid.toLowerCase(),title:plain(x.ilanBaslik).slice(0,300),category:plain(x.ilanTuru),deadline:iso(x.bitTarih),publishedAt:null,places:[],requirementGroups:[],summary:[],active:true,
  }));
}
export function parseKariyerRss(xml){
  if(!/<rss\b/i.test(xml))throw new SourceError('rss_layout_changed');
  const value=(body,key)=>plain((body.match(new RegExp('<'+key+'(?:\\s[^>]*)?>([\\s\\S]*?)</'+key+'>','i'))?.[1]??'').replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g,'$1'));
  return [...xml.matchAll(/<item\b[^>]*>([\s\S]*?)<\/item>/gi)].slice(0,200).flatMap(m=>{
    const url=value(m[1],'link');let uri;try{uri=new URL(url);}catch{return [];}
    const guid=uri.searchParams.get('i');if(uri.hostname!=='kariyerkapisi.gov.tr'||uri.protocol!=='https:'||uri.username||uri.password||uri.port||!uuid.test(guid??''))return [];
    const category=value(m[1],'category');if(category==='Yurt Dışı Eğitim İlanları')return [];
    return [{id:'kariyerkapisi:'+guid.toLowerCase(),externalId:guid.toLowerCase(),sourceId:'kariyerkapisi',url,title:value(m[1],'title').slice(0,300),category,deadline:null,publishedAt:iso(value(m[1],'pubDate')),places:[],requirementGroups:[],summary:[],active:true}];
  });
}
export async function fetchKariyerList(){
  try{return parseKariyerIndex(await post('ilan/GetIseAlimPage',{krM_ID:0,searchText:'',il:'0',ilanTuru:'0'}));}
  catch(indexError){try{return parseKariyerRss(await sourceFetch('https://kariyerkapisi.gov.tr/RSS'));}catch{throw indexError;}}
}
export function parseKariyerDetail(main,positions) {
  if(!main||typeof main!=='object'||!Array.isArray(positions))throw new SourceError('detail_layout_changed');
  const groups=positions.slice(0,100).map(x=>({
    title:plain(x.ilanBaslik),profession:plain(x.unvan),text:plain(x.ilanMetni),
    places:[...new Set((Array.isArray(x.kontenjanList)?x.kontenjanList:[]).map(q=>plain(q.il).split(' / ')[0]).filter(Boolean))],
    quota:(Array.isArray(x.kontenjanList)?x.kontenjanList:[]).reduce((n,q)=>n+(Number.isInteger(q.kontenjan)&&q.kontenjan>0?q.kontenjan:0),0),
  }));
  const rawURL=main.eDevletteGorunsun===1?main.eDevletServisURL:main.basvuruLinki;
  return {institution:plain(main.kurumAdi),text:plain(main.ilanMetni),start:iso(main.basTarih),deadline:iso(main.bitTarih),applyUrl:typeof rawURL==='string'&&rawURL.startsWith('https://')?rawURL:null,positions:groups,places:[...new Set(groups.flatMap(g=>g.places))],quota:groups.reduce((n,g)=>n+g.quota,0)};
}
export async function fetchKariyerDetail(id) {return parseKariyerDetail(await post('ilan/GetIlanPreviewPublic',{ilanGuid:id}),await post('altilan/GetAltIlanInfoByIlanIdPublic',{ilanGuid:id}));}
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
    if(!title||!institution)continue;
    const dates=range.split(/[-–]/);const url=new URL(match[1].replace(/&amp;/g,'&'),'https://kamuilan.sbb.gov.tr/');const externalId=url.searchParams.get('kod');
    if(!externalId)continue;
    const start=dates.length===2?sbbDate(dates[0],year):null;
    let deadline=dates.length===2?sbbDate(dates[1],year,true,start):null;
    if(start&&deadline&&deadline<start)deadline=null;
    const upper=title.toLocaleUpperCase('tr');
    rows.push({id:'sbb:'+externalId,externalId,sourceId:'sbb',url:url.href,title,institution,category:upper.includes('SÖZLEŞMELİ')?'Sözleşmeli Personel':upper.includes('İŞÇİ')?'İşçi':'Kamu Personeli',start,deadline,publishedAt:null,places:[],requirementGroups:[],summary:[],active:true});
  }
  if(!rows.length)throw new SourceError('layout_changed');return rows.slice(0,500);
}
export async function fetchSbbList(){
  const home=await sourceFetch('https://kamuilan.sbb.gov.tr/');const form=new URLSearchParams({__EVENTTARGET:'ddl_yil',ddl_yil:String(new Date().getUTCFullYear())});
  for(const name of ['__VIEWSTATE','__VIEWSTATEGENERATOR','__EVENTVALIDATION']) {
    const value=home.match(new RegExp('name="'+name+'"[^>]*value="([^"]*)"'))?.[1];if(value)form.set(name,value);
  }
  if(!form.has('__VIEWSTATE'))throw new SourceError('layout_changed');
  return parseSbbList(await sourceFetch('https://kamuilan.sbb.gov.tr/',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:form.toString()}));
}
