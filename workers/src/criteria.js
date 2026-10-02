const cityLabels = ['Adana', 'Adıyaman', 'Afyonkarahisar', 'Ağrı', 'Aksaray', 'Amasya', 'Ankara', 'Antalya', 'Ardahan', 'Artvin', 'Aydın', 'Balıkesir', 'Bartın', 'Batman', 'Bayburt', 'Bilecik', 'Bingöl', 'Bitlis', 'Bolu', 'Burdur', 'Bursa', 'Çanakkale', 'Çankırı', 'Çorum', 'Denizli', 'Diyarbakır', 'Düzce', 'Edirne', 'Elazığ', 'Erzincan', 'Erzurum', 'Eskişehir', 'Gaziantep', 'Giresun', 'Gümüşhane', 'Hakkari', 'Hatay', 'Iğdır', 'Isparta', 'İstanbul', 'İzmir', 'Kahramanmaraş', 'Karabük', 'Karaman', 'Kars', 'Kastamonu', 'Kayseri', 'Kilis', 'Kırıkkale', 'Kırklareli', 'Kırşehir', 'Kocaeli', 'Konya', 'Kütahya', 'Malatya', 'Manisa', 'Mardin', 'Mersin', 'Muğla', 'Muş', 'Nevşehir', 'Niğde', 'Ordu', 'Osmaniye', 'Rize', 'Sakarya', 'Samsun', 'Siirt', 'Sinop', 'Sivas', 'Şanlıurfa', 'Şırnak', 'Tekirdağ', 'Tokat', 'Trabzon', 'Tunceli', 'Uşak', 'Van', 'Yalova', 'Yozgat', 'Zonguldak'];
export const fold = value => String(value ?? '').toUpperCase().replaceAll('İ','I').replaceAll('Ç','C').replaceAll('Ğ','G').replaceAll('Ö','O').replaceAll('Ş','S').replaceAll('Ü','U').replaceAll('Â','A').replaceAll('Î','I').replaceAll('Û','U').toLowerCase().replace(/\s+/g,' ').trim();
export const educationValues = [
  {id:'education:secondary',label:'Lise',aliases:[]},
  {id:'education:associate',label:'Ön lisans',aliases:['Önlisans']},
  {id:'education:bachelor',label:'Lisans',aliases:[]},
  {id:'education:master',label:'Yüksek lisans',aliases:['Yükseklisans']},
  {id:'education:doctorate',label:'Doktora',aliases:[]}
];
const educationAliases = new Map(educationValues.flatMap(entry=>[entry.id,entry.label,...entry.aliases].map(value=>[fold(value),entry.id.split(':')[1]])));
export const cityValues = cityLabels.map(label=>({id:'city:'+fold(label),label,aliases:[]}));
const cityAliases = new Map(cityValues.flatMap(entry=>[entry.id,entry.label].map(value=>[fold(value),fold(entry.label)])));
const criterionAliases = {education:educationAliases,cities:cityAliases};
const criterionKey = (field,value) => criterionAliases[field]?.get(fold(value))??fold(value);
const oneOf = (wanted, actual, field) => !wanted?.length || wanted.some(value => actual.map(v=>criterionKey(field,v)).includes(criterionKey(field,value)));
export function validateCriteria(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new Error('criteria');
  const allowed = new Set(['version','keyword','cities','categories','occupations','institutions','education','age','ageAsOf','kpssType','kpssScore','kpssYear','onlyKpss','last30','keywordScope']);
  if (Object.keys(raw).some(k => !allowed.has(k))) throw new Error('unknown_criterion');
  if(raw.version!==undefined && raw.version!==2)throw new Error('version');
  const result = {version:2};
  for (const key of ['cities','categories','occupations','institutions','education']) {
    if (raw[key] !== undefined) {
      if (!Array.isArray(raw[key]) || raw[key].length > 10 || raw[key].some(v => typeof v !== 'string' || !v.trim() || v.length > 100)) throw new Error(key);
      result[key] = [...new Set(raw[key].map(v=>v.trim()))];
    }
  }
  for (const key of ['keyword','ageAsOf','kpssType','keywordScope']) if (raw[key] !== undefined) {
    if (typeof raw[key] !== 'string' || raw[key].length > 100) throw new Error(key);
    result[key]=raw[key];
  }
  for (const [key,min,max] of [['age',16,80],['kpssScore',0,100],['kpssYear',2000,2100]]) if (raw[key] !== undefined) {
    if (typeof raw[key] !== 'number' || !Number.isFinite(raw[key]) || raw[key]<min || raw[key]>max || (key!=='kpssScore' && !Number.isInteger(raw[key]))) throw new Error(key);
    result[key]=raw[key];
  }
  if (result.age!==undefined && !/^\d{4}-\d{2}-\d{2}$/.test(result.ageAsOf ?? '')) throw new Error('ageAsOf');
  if(result.ageAsOf!==undefined && (!Number.isFinite(Date.parse(result.ageAsOf)) || new Date(result.ageAsOf).toISOString().slice(0,10)!==result.ageAsOf))throw new Error('ageAsOf');
  if(result.keywordScope && !['title','full'].includes(result.keywordScope))throw new Error('keywordScope');
  if (result.kpssType && !/^P\d{1,3}$/.test(result.kpssType)) throw new Error('kpssType');
  if (result.kpssScore!==undefined && !result.kpssType) throw new Error('kpssType');
  for (const key of ['onlyKpss','last30']) if (raw[key]!==undefined) {
    if (typeof raw[key] !== 'boolean') throw new Error(key);
    result[key]=raw[key];
  }
  return result;
}
export function migrateFilters(filters, now = new Date()) {
  const result={version:2,keywordScope:'title'};
  if(filters.q) result.keyword=filters.q;
  if(filters.sehir) result.cities=[filters.sehir];
  if(filters.egitim) result.education=[filters.egitim];
  if(filters.kpss) result.kpssType=filters.kpss;
  if(filters.yas) { result.age=Number(filters.yas); result.ageAsOf=filters.yasTarih || '1970-01-01'; }
  if(filters.kpssPuan) result.kpssScore=Number(filters.kpssPuan);
  if(filters.kategori && filters.kategori!=='0') result.categories=[['','işçi','personel','belediye'][Number(filters.kategori)]];
  if(filters.son30==='1') result.last30=true;
  return validateCriteria(result);
}
function matchAge(group,criteria,now){
  const date=value=>typeof value==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(value)&&Number.isFinite(Date.parse(value))&&new Date(value).toISOString().slice(0,10)===value?new Date(value):null;
  const asOf=date(criteria.ageAsOf);
  // ageAsOf is a civil date, not midnight UTC. Use the existing Istanbul pilot
  // calendar so today's profile does not become "future" during 00:00–03:00.
  // ponytail: UTC+3 Istanbul pilot; version the shared IANA calendar if source jurisdictions expand.
  const local=new Date(+now+3*3600000),today=new Date(Date.UTC(local.getUTCFullYear(),local.getUTCMonth(),local.getUTCDate()));
  if(!asOf||today-asOf>366*86400000||asOf>today)return 'unknown';
  const fields=['minAge','maxAge','ageReferenceDate','bornOnOrAfter','bornOnOrBefore'];
  if(group.ageStatus==='no_restriction')return fields.some(k=>group[k]!=null)?'unknown':'match';
  if(group.ageStatus!=='known'||!['minAge','maxAge','bornOnOrAfter','bornOnOrBefore'].some(k=>group[k]!=null))return 'unknown';
  if(group.ageCalculation!=null&&group.ageCalculation!=='completed_years')return 'unknown';
  for(const k of ['minAge','maxAge'])if(group[k]!=null&&(!Number.isInteger(group[k])||group[k]<0||group[k]>130))return 'unknown';
  const reference=group.ageReferenceDate==null?asOf:date(group.ageReferenceDate);
  const lower=group.bornOnOrAfter==null?null:date(group.bornOnOrAfter),upper=group.bornOnOrBefore==null?null:date(group.bornOnOrBefore);
  if(!reference||(group.bornOnOrAfter!=null&&!lower)||(group.bornOnOrBefore!=null&&!upper))return 'unknown';
  // Completed years: Feb29 anniversaries occur March1 in a non-leap year.
  // Clamp inverse calendar boundaries; never guess an exact birthday from an age.
  const yearsBack=(day,years)=>{const result=new Date(+day);result.setUTCFullYear(day.getUTCFullYear()-years,day.getUTCMonth(),1);const monthEnd=new Date(+result);monthEnd.setUTCMonth(monthEnd.getUTCMonth()+1,0);result.setUTCDate(Math.min(day.getUTCDate(),monthEnd.getUTCDate()));return +result;};
  const first=yearsBack(asOf,criteria.age+1)+86400000,last=yearsBack(asOf,criteria.age);
  const allowedFirst=Math.max(lower?+lower:-Infinity,group.maxAge==null?-Infinity:yearsBack(reference,group.maxAge+1)+86400000);
  const allowedLast=Math.min(upper?+upper:Infinity,group.minAge==null?Infinity:yearsBack(reference,group.minAge));
  if(allowedFirst>allowedLast)return 'unknown'; // Conflicting source conditions need correction, not a rejection of every candidate.
  if(last<allowedFirst||first>allowedLast)return 'no_match';
  return first>=allowedFirst&&last<=allowedLast?'match':'unknown';
}
export function matchListing(listing, criteria, now = new Date()) {
  if(listing.active===false || (listing.deadline && new Date(listing.deadline)<now) || (listing.publishedAt && new Date(listing.publishedAt)>now)) return 'no_match';
  const words=criteria.keywordScope==='title' ? listing.title : [listing.title,listing.institution,...(listing.occupations??[])].join(' ');
  if(criteria.keyword && !fold(words).includes(fold(criteria.keyword))) return 'no_match';
  if(criteria.categories?.length && !criteria.categories.some(x=>fold(listing.category+' '+listing.title).includes(fold(x)))) return 'no_match';
  if(!oneOf(criteria.institutions,[listing.institution??''])) return 'no_match';
  if(criteria.last30 && (!listing.publishedAt || now-new Date(listing.publishedAt)>30*86400000)) return 'no_match';
  let unknown=false;
  const groups=listing.requirementGroups?.length ? listing.requirementGroups : [{cities:listing.places??[],occupations:listing.occupations??[]}];
  for(const group of groups) {
    let status='match';
    const check=(wanted,actual,field)=>{
      if(!wanted?.length) return;
      if(!actual?.length) {if(status!=='no_match') status='unknown';}
      else if(criterionAliases[field] && !wanted.some(v=>criterionAliases[field].has(fold(v)) && actual.some(a=>criterionAliases[field].has(fold(a)) && criterionKey(field,v)===criterionKey(field,a)))) {
        if(wanted.some(v=>!criterionAliases[field].has(fold(v))) || actual.some(v=>!criterionAliases[field].has(fold(v)))) {if(status!=='no_match')status='unknown';}
        else status='no_match';
      }
      else if(!oneOf(wanted,actual,field)) status='no_match';
    };
    check(criteria.cities,group.cities?.length?group.cities:(groups.length===1?listing.places:[]),'cities');
    check(criteria.occupations,group.occupations);
    check(criteria.education,group.education,'education');
    if(criteria.age!==undefined) {
      const age=matchAge(group,criteria,now);
      if(age==='no_match')status=age;else if(age==='unknown'&&status!=='no_match')status=age;
    }
    if(criteria.kpssType || criteria.onlyKpss) {
      const invalid=(group.kpssStatus==='not_required'&&['kpssType','kpssScore','kpssYear'].some(k=>group[k]!=null))
        ||(group.kpssType!=null&&(typeof group.kpssType!=='string'||!/^P\d{1,3}$/.test(group.kpssType)))
        ||(group.kpssScore!=null&&(typeof group.kpssScore!=='number'||!Number.isFinite(group.kpssScore)||group.kpssScore<0||group.kpssScore>100))
        ||(group.kpssYear!=null&&(!Number.isInteger(group.kpssYear)||group.kpssYear<2000||group.kpssYear>2100));
      if(invalid) {if(status!=='no_match')status='unknown';}
      else {
        if(group.kpssStatus==='not_required') {if(criteria.onlyKpss)status='no_match';}
        else if(group.kpssStatus!=='required') {if(status!=='no_match')status='unknown';}
        else if(criteria.kpssType && !group.kpssType) {if(status!=='no_match')status='unknown';}
        else if(criteria.kpssType && group.kpssType!==criteria.kpssType) status='no_match';
        else if(criteria.kpssScore!==undefined) {
          if(group.kpssScore===null || group.kpssScore===undefined) {if(status!=='no_match')status='unknown';}
          else if(criteria.kpssScore<group.kpssScore)status='no_match';
        }
        if(group.kpssYear){if(criteria.kpssYear===undefined){if(status!=='no_match')status='unknown';}else if(criteria.kpssYear!==group.kpssYear)status='no_match';}
      }
    }
    if(status==='match')return 'match';
    if(status==='unknown')unknown=true;
  }
  return unknown?'unknown':'no_match';
}

// Candidate anchors only prune push recipients; matchListing remains authoritative.
export function searchAnchorKeys(criteria) {
  const fields=['cities','occupations','education','institutions'];
  const field=fields.filter(k=>criteria[k]?.length).sort((a,b)=>criteria[a].length-criteria[b].length)[0];
  return field?[...new Set(criteria[field].map(value=>field+':'+criterionKey(field,value)))].sort():['*'];
}
export function installationAnchorKeys(searches) {
  const keys=new Set(searches.filter(s=>s.mode!=='off').flatMap(s=>searchAnchorKeys(s.criteria)));
  return keys.has('*')?['*']:[...keys].sort();
}
export function listingAnchorKeys(listing) {
  const keys=new Set(['*']);
  if(listing.institution)keys.add('institutions:'+fold(listing.institution));
  const groups=listing.requirementGroups?.length?listing.requirementGroups:[{cities:listing.places??[],occupations:listing.occupations??[]}];
  for(const group of groups) {
    for(const field of ['cities','occupations','education']) {
      const values=field==='cities'?(group.cities?.length?group.cities:(groups.length===1?listing.places??[]:[])):group[field]??[];
      for(const value of values)keys.add(field+':'+criterionKey(field,value));
    }
  }
  return [...keys].sort();
}
