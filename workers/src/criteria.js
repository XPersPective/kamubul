export const fold = value => String(value ?? '').toLocaleLowerCase('tr-TR').normalize('NFD').replace(/\p{M}/gu, '').replace(/ı/g, 'i').replace(/\s+/g, ' ').trim();
const oneOf = (wanted, actual) => !wanted?.length || wanted.some(value => actual.map(fold).includes(fold(value)));
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
  if(result.ageAsOf && (!Number.isFinite(Date.parse(result.ageAsOf)) || new Date(result.ageAsOf).toISOString().slice(0,10)!==result.ageAsOf))throw new Error('ageAsOf');
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
  if(filters.yas) { result.age=Number(filters.yas); result.ageAsOf=filters.yasTarih || now.toISOString().slice(0,10); }
  if(filters.kpssPuan) result.kpssScore=Number(filters.kpssPuan);
  if(filters.kategori && filters.kategori!=='0') result.categories=[['','işçi','personel','belediye'][Number(filters.kategori)]];
  if(filters.son30==='1') result.last30=true;
  return validateCriteria(result);
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
    const check=(wanted,actual)=>{
      if(!wanted?.length) return;
      if(!actual?.length) {if(status!=='no_match') status='unknown';}
      else if(!oneOf(wanted,actual)) status='no_match';
    };
    check(criteria.cities,group.cities?.length?group.cities:listing.places);
    check(criteria.occupations,group.occupations);
    check(criteria.education,group.education);
    if(criteria.age!==undefined) {
      const ageDate=new Date(criteria.ageAsOf+'T00:00:00Z');
      if(!Number.isFinite(+ageDate) || now-ageDate>366*86400000 || ageDate>now || !['known','no_restriction'].includes(group.ageStatus)) {if(status!=='no_match')status='unknown';}
      else if((group.maxAge!==null && group.maxAge!==undefined && criteria.age>group.maxAge) || (group.minAge!==null && group.minAge!==undefined && criteria.age<group.minAge)) status='no_match';
    }
    if(criteria.kpssType || criteria.onlyKpss) {
      if(group.kpssStatus==='not_required') {if(criteria.onlyKpss)status='no_match';}
      else if(group.kpssStatus!=='required') {if(status!=='no_match')status='unknown';}
      else if(criteria.kpssType && group.kpssType!==criteria.kpssType) status='no_match';
      else if(criteria.kpssScore!==undefined) {
        if(group.kpssScore===null || group.kpssScore===undefined) {if(status!=='no_match')status='unknown';}
        else if(criteria.kpssScore<group.kpssScore)status='no_match';
      }
      if(group.kpssYear && criteria.kpssYear!==group.kpssYear) {if(status!=='no_match')status='unknown';}
    }
    if(status==='match')return 'match';
    if(status==='unknown')unknown=true;
  }
  return unknown?'unknown':'no_match';
}
