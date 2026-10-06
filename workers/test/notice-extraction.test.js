import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {DatabaseSync} from 'node:sqlite';
import {createHash} from 'node:crypto';
import {mechanicalNotice,assessNotice,extractNotice} from '../src/notice_extraction.js';
import {parseIlanGovDetail} from '../src/sources.js';
import {validateNoticeFields,applicationDeadline} from '../src/extract.js';
import {validateGroups} from '../src/extract.js';
const corpus=JSON.parse(readFileSync(new URL('./fixtures/ilangov-details.json',import.meta.url))).notices;
const quotas={'2242968':1,'2244776':27,'2244748':15,'2244739':5,'2236938':7,'2234989':5};
test('real official table counts ignore degree, exam candidates, duplicated table and specialist serials',()=>{
  for(const item of corpus){const notice={...parseIlanGovDetail({result:item.result},item.id),title:item.result.title};const result=mechanicalNotice(notice,item.text);
    assert.equal(result.fields.quota?.value,quotas[item.id],item.id);
    if(quotas[item.id])assert.equal(result.groups.reduce((n,g)=>n+g.quota,0),quotas[item.id]);
    else {assert.equal(result.register,true);assert.equal(result.groups.some(g=>g.quota),false);}
  }
});
test('ministry numbered special conditions stay with their exact position beyond the summary table',()=>{
  const item=corpus.find(n=>n.id==='2244739'),result=mechanicalNotice({title:item.result.title},item.text),[java,net]=result.groups;
  assert.ok(java.sourceText.includes('Java programlama diliyle'));assert.ok(!java.sourceText.includes('.Net teknolojileri'));
  assert.ok(net.sourceText.includes('.Net teknolojileri'));assert.ok(!net.sourceText.includes('Java programlama diliyle'));
  assert.ok(!net.sourceText.includes('İSTENİLEN BELGELER'));assert.equal(result.fields.quota.value,5);
  assert.ok(result.groups.every(g=>g.kpssStatus==='not_required'&&g.kpssScore===undefined));
  assert.ok(result.groups.every(g=>g.education?.includes('Lisans')));
});
test('application dates retain actual deadlines and time; document delivery/exam/publication are different',()=>{
  const dates={'2242968':'2026-10-16','2244776':'2026-10-20','2244748':'2026-10-19','2244739':'2026-10-11','2236938':'2026-10-12','2234989':'2026-10-12','2243231':'2026-10-31'};
  for(const item of corpus){const result=mechanicalNotice({...parseIlanGovDetail({result:item.result},item.id),title:item.result.title},item.text);if(item.id==='2244776'){assert.equal(result.fields.deadline,undefined);assert.equal(result.fields.deadlineEstimate.value,'2026-10-19T20:59:59.999Z');assert.equal(result.fields.deadlineEstimate.origin,'computed');assert.ok(result.fields.deadlineEstimate.quote.includes('15. gün'));assert.deepEqual(assessNotice(result,item.text),[]);continue;}if(item.id==='2234989'){assert.equal(result.fields.deadline.value,null);assert.ok(assessNotice(result,item.text).includes('deadline_scope'));assert.ok(result.fields.applicationPeriods.value.some(p=>p.deadline?.startsWith('2026-10-12')));continue;}assert.equal(result.fields.deadline?.value.slice(0,10),dates[item.id],item.id);if(item.id==='2236938')assert.equal(result.fields.deadline.value,'2026-10-12T10:00:00.000Z');}
  assert.equal(mechanicalNotice({title:'İlan'},'Son Başvuru Tarihi: 31.02.2026\nSınav Tarihi: 20.03.2026').fields.deadline,undefined);
});
test('complete mechanics and explicit ambiguous calendars do not access a model or database',async()=>{
  for(const id of ['2242968','2244776','2234989']){
    const item=corpus.find(n=>n.id===id),notice={...parseIlanGovDetail({result:item.result},item.id),title:item.result.title};
    const result=await extractNotice(notice,item.text,{DB:{prepare(){assert.fail('no AI database call');}}},{});
    assert.equal(result.status,200);assert.equal(result.result.extraction.method,'mechanical');assert.equal(result.result.extraction.status,id==='2234989'?'partial':'complete');assert.equal(result.result.fields.quota.value,quotas[id]);
  }
});
test('native positions keep independent places, quotas and text rather than a first-document general group',()=>{
  const positions=[{title:'Mühendis',quota:2,places:['Ankara'],profession:'Mühendis',text:'Lisans mezunu olmak.'},{title:'Tekniker',quota:3,places:['İzmir'],profession:'Tekniker',text:'Ön lisans mezunu olmak.'}],notice={title:'Personel',deadline:'2026-10-10T20:59:59.000Z',positions};
  const result=mechanicalNotice(notice,positions.map(p=>p.text).join('\n'));assert.equal(result.fields.quota.value,5);assert.deepEqual(result.groups.map(g=>[g.label,g.quota,g.cities]),[['Mühendis',2,['Ankara']],['Tekniker',3,['İzmir']]]);
  const again=mechanicalNotice({...notice,fieldEvidence:{deadline:{origin:'source'}}},positions.map(p=>p.text).join('\n'));assert.equal(again.fields.deadline.value,notice.deadline);
});
test('missing facts and malformed table stay partial; visible position text keeps special requirements',()=>{
  const result=mechanicalNotice({title:'Personel alımı'},'Unvan | Adet | Şart\nMühendis | belirsiz | Lisans mezunu olmak');
  assert.ok(assessNotice(result,'Lisans mezunu olmak').includes('quota'));
  const empty=mechanicalNotice({title:'Personel alımı'},'Başvuru belgeleri');assert.ok(assessNotice(empty,'Başvuru belgeleri').includes('deadline'));
  const partial=mechanicalNotice({title:'Personel alımı'},'Unvan | Adet | Şart\nMühendis | 2 | Deneyim gerekli\nTekniker | bilinmiyor | Lise mezunu olmak');assert.equal(partial.fields.quota,undefined);assert.equal(partial.tableAmbiguous,true,'valid row subtotal must not masquerade as total');
  const twins=mechanicalNotice({title:'Personel alımı'},'Unvan | Adet | Şart\nMühendis | 2 | Deneyim gerekli\nMühendis | 2 | Deneyim gerekli');assert.equal(twins.fields.quota.value,4,'two rows inside one table are not a repeated table');
});
test('fallback reads full stored text once, rejects foreign-row education, and caches partial quality',async t=>{
  const sql=new DatabaseSync(':memory:');t.after(()=>sql.close());for(const f of ['0017_assistant_usage.sql','0019_extraction_cache.sql','0020_extraction_runs.sql'])sql.exec(readFileSync(new URL('../migrations/'+f,import.meta.url),'utf8'));
  const DB={prepare(q){return {bind(...v){return {first:async()=>sql.prepare(q).get(...v)??null,run:async()=>sql.prepare(q).run(...v)}}}}};
  const text='Unvan | Adet | Şart\nMühendis | 2 | Beş yıl mesleki deneyim gereklidir.\nTekniker | 1 | Lise mezunu olmak.\nUzman | belirsiz | Kaynakta sayı yok.\nSon Başvuru Tarihi: 11.10.2026\n'+'Başvuru belgeleri teslim edilecektir. '.repeat(8);
  let calls=0;const env={DB,EXTRACT_AI_MODEL:'test',AI:{async run(model,input){calls++;assert.equal(input.messages[1].content,text.trim());return {response:JSON.stringify({groups:[{label:'Mühendis',education:['Lise'],educationQuote:'Lise mezunu olmak'}]})};}}};
  const deps={sha256:async s=>createHash('sha256').update(s).digest('hex')};
  const a=await extractNotice({title:'Personel alımı'},text,env,deps),b=await extractNotice({title:'Personel alımı'},text,env,deps);
  assert.equal(a.result.extraction.status,'partial');assert.equal(a.result.groups[0].education,undefined);assert.equal(b.result.extraction.status,'partial');assert.equal(calls,1);assert.ok(a.result.groups[0].text.includes('Beş yıl'));
});
test('AI metadata requires source evidence and valid application date',()=>{
  assert.deepEqual(validateNoticeFields({quota:{value:99,quote:'Toplam 5 personel alınacaktır.'},deadline:{value:'2026-10-22',quote:'Giriş Sınavı Tarihi: 22.10.2026'}},'Toplam 5 personel alınacaktır. Giriş Sınavı Tarihi: 22.10.2026'),{});
  const fields=validateNoticeFields({quota:{value:5,quote:'Toplam 5 personel alınacaktır.'},deadline:{value:'2026-10-11',quote:'Son başvuru tarihi: 11.10.2026'}},'Toplam 5 personel alınacaktır. Son başvuru tarihi: 11.10.2026');assert.equal(fields.quota.value,5);assert.ok(fields.deadline.value.startsWith('2026-10-11'));
});
test('mechanical and AI deadlines share Turkish dates, range endpoints and exact application times',()=>{
  for(const [quote,date,iso] of [
    ['Son Başvuru Tarihi: 14 Ekim 2026 saat 17:30','2026-10-14','2026-10-14T14:30:00.000Z'],
    ['Başvuru Tarihleri: 12/10/2026 – 27/10/2026','2026-10-27','2026-10-27T20:59:59.999Z'],
    ['Başvuru Tarihleri: 16 – 23 Ekim 2026','2026-10-23','2026-10-23T20:59:59.999Z'],
    ['Son Başvuru Tarihi: 14.10.2026 Ön Değerlendirme Sonuç Açıklama Tarihi: 15.10.2026','2026-10-14','2026-10-14T20:59:59.999Z'],
  ]){
    assert.equal(applicationDeadline(quote),iso);assert.equal(mechanicalNotice({title:'İlan'},quote).fields.deadline.value,iso);
    assert.equal(validateNoticeFields({deadline:{value:date,quote}},quote).deadline.value,iso);
  }
  for(const [quote,wrong] of [
    ['Başvuru Tarihleri: 12/10/2026 – 27/10/2026','2026-10-12'],
    ['Son Başvuru Tarihi: 14.10.2026 Ön Değerlendirme Sonuç Açıklama Tarihi: 15.10.2026','2026-10-15'],
    ['Son Başvuru Tarihi: 31 Şubat 2026','2026-02-28'],
    ['Başvuru tarihi yayım tarihinden itibaren 15 gün; 05.10.2026','2026-10-05'],
  ])assert.equal(validateNoticeFields({deadline:{value:wrong,quote}},quote).deadline,undefined);
  assert.equal(applicationDeadline('Son Başvuru Tarihi: 14.10.2026 veya 15.10.2026'),null);
  assert.equal(applicationDeadline('Komisyonumuzca başvurular, 30 Kasım 2026 tarihine kadar değerlendirilecektir.'),null);
  assert.equal(applicationDeadline('Başvurular, komisyon tarafından 30.11.2026 tarihine kadar değerlendirilerek karar verilir.'),null);
  assert.equal(applicationDeadline('Ön başvuru ücretini, 20-23 Ekim 2026 tarihleri arasında yatıracaklardır.'),null);
  assert.equal(applicationDeadline('Başvuru Tarihi: Başvuruları 15.10.2026 günü başlayıp 31.10.2026 günü sona erecektir.'),'2026-10-31T20:59:59.999Z');
  assert.equal(applicationDeadline('Başvurular yayımlandığı tarihten itibaren 28.09.2026/12.10.2026 tarihleri arasında kabul edilir.'),'2026-10-12T20:59:59.999Z');
  const scoped=mechanicalNotice({title:'Personel'},'Mühendis Son Başvuru Tarihi: 14.10.2026 saat 13:00\nTekniker Son Başvuru Tarihi: 14.10.2026 saat 17:00');assert.equal(scoped.fields.deadline.value,null);assert.equal(scoped.fields.applicationPeriods.value.length,2);
});
test('preferred degree is not mandatory and conjunctive degrees are not eligibility alternatives',()=>{
  const preferred='Lisans derecesine sahip olmak ve tercihen tezli yüksek lisans derecesine sahip olmak.';
  assert.deepEqual(validateGroups({groups:[{education:['Lisans','Yüksek lisans'],educationQuote:preferred}]},preferred)[0].education,['Lisans']);
  const both='Lisans ve tezli yüksek lisans mezunu olmak.';
  const group=validateGroups({groups:[{education:['Lisans','Yüksek lisans'],educationQuote:both}]},both)[0];assert.equal(group.education,undefined);assert.equal(group.educationDescription,both);
  const separate='Unvan | Adet | Şart\nDoktor Öğretim Üyesi | 1 | İnşaat Mühendisliği Bölümü lisans mezunu olmak. İnşaat Mühendisliği Anabilim Dalında doktora yapmış olmak.';
  const row=mechanicalNotice({title:'Öğretim Üyesi'},separate).groups[0];assert.equal(row.education,undefined);assert.ok(row.educationDescription.includes('lisans mezunu olmak. İnşaat'));assert.ok(row.educationDescription.includes('doktora yapmış olmak'));
});
test('native vacancy count aliases and labelled KPSS cells do not confuse degree or adjacent result date',()=>{
  for(const header of ['Kadro Adedi','Pozisyon Adedi','Adedi','Sayısı']){
    const text=`Kadro Ünvanı | Kadro Derecesi | ${header} | Niteliği | KPSS Puan Türü | KPSS Taban Puanı\nMühendis | 8 | 1 | Lisans mezunu olmak. | P3 | En az 60 Puan\nMimar | 8 | 2 | Lisans mezunu olmak. | P3 | En az 60 Puan\nSon Başvuru Tarihi: | 16.10.2026 | Sonuç Açıklama Tarihi: | 06.11.2026`;
    const result=mechanicalNotice({title:'Personel'},text);assert.equal(result.fields.quota.value,3);assert.equal(result.fields.deadline.value.slice(0,10),'2026-10-16');
    assert.ok(result.groups.every(g=>g.kpssType==='P3'&&g.kpssScore===60));
  }
});
test('official trailing address/calendar rowspans preserve counts but missing interior cells remain ambiguous',()=>{
  const isparta='İlan Sıra No | Birimi | Bölümü | Anabilim / Anasanat Dalı / Programı | Adet | Der. | Ünvanı | Özel Şartlar | Adres ve İletişim Bilgileri\n1 | Orman Fakültesi | Orman Endüstri Mühendisliği Bölümü | Odun Mekaniği ve Teknolojisi | 1 | 1 | Profesör | Doçent ünvanı almış olmak. | Isparta\n2 | Teknoloji Fakültesi | Biyomedikal Mühendisliği Bölümü | Biyomedikal Mühendisliği | 1 | 1 | Profesör | Doktora yapmış olmak.\nBaşvuru Bitiş Tarihi | 14.10.2026 Çarşamba (Mesai bitimi Saat 17.30)';
  const result=mechanicalNotice({title:'Öğretim Üyesi'},isparta);assert.equal(result.fields.quota.value,2);assert.equal(result.tableAmbiguous,false);assert.equal(result.fields.deadline.value,'2026-10-14T14:30:00.000Z');
  const calendar='Bölüm | Kadro Ünvanı | Kadro Adedi | Aranan Şartlar | İlan Takvimi\nTarih | Öğretim Görevlisi | 1 | Doktora yapmış olmak. | İlk Başvuru Tarihi: 30.09.2026 Son Başvuru Tarihi: 14.10.2026 Ön Değerlendirme Sonuç Açıklama Tarihi: 15.10.2026 Giriş Sınavı Tarihi: 16.10.2026\nDeniz İşletmeciliği | Öğretim Görevlisi | 1 | Yüksek lisans derecesine sahip olmak.';
  const dates=mechanicalNotice({title:'Öğretim Görevlisi'},calendar);assert.equal(dates.fields.quota.value,2);assert.equal(dates.fields.deadline.value.slice(0,10),'2026-10-14');
  const broken=mechanicalNotice({title:'Personel'},'Bölüm | Ünvan | Adet | Şart | Adres\nMühendis | 3 | Lisans mezunu olmak. | Ankara');assert.equal(broken.fields.quota,undefined);assert.equal(broken.tableAmbiguous,true);
});
test('official Bitlis bullet conditions and later calendar are not confused with vacancy rows',()=>{
  const text='POZİSYON KODU | POZİSYON ÜNVANI | KADRO ADEDİ | CİNSİYETİ | MEZUNİYET DURUMU / KPSS PUAN TÜRÜ | ARANAN NİTELİKLER\n001 | Destek Personeli | 7 | Erkek | Ortaöğretim (KPSS P94) | • Ortaöğretim (lise ve dengi) kurumlarından mezun olmak. • 2024 Kamu Personeli Seçme Sınavında (KPSS P94) 60 (altmış) ve üzeri puan almış olmak. • Başvuru bitimi tarihi itibariyle 35 (otuz beş) yaşını bitirmemiş olmak.\n002 | Destek Personeli | 2 | Kadın | Ortaöğretim (KPSS P94) | •Ortaöğretim (lise ve dengi) kurumlarından mezun olmak. •2024 Kamu Personeli Seçme Sınavında (KPSS P94) 60 (altmış) ve üzeri puan almış olmak. •Başvuru bitimi tarihi itibariyle 35 (otuz beş) yaşını bitirmemiş olmak.\n003 | Tekniker | 1 | Erkek | Ön Lisans (KPSS P93) | •Yükseköğretim Kurumlarının Bilgisayar Programcılığı ön lisans programlarından birinden mezun olmak. •2024 Kamu Personeli Seçme Sınavında (KPSS P93) 65 (altmış beş) ve üzeri puan almış olmak. •Başvuru bitimi tarihi itibariyle 35 (otuz beş) yaşını bitirmemiş olmak.\nSIRA NO | KONU | TARİH\n1 | İlan Yayım Tarihi | 22.09.2026\n2 | Başvuru Başlangıç Tarihi | 22.09.2026\n3 | Son Başvuru Tarihi | 06.10.2026\n4 | Nihai Değerlendirme Sonuç İlanı | 16.10.2026';
  const result=mechanicalNotice({title:'Bitlis Personel'},text);assert.equal(result.fields.quota.value,10);assert.equal(result.tableAmbiguous,false);assert.equal(result.fields.deadline.value.slice(0,10),'2026-10-06');
  assert.deepEqual(result.groups.map(g=>[g.quota,g.kpssType,g.kpssScore,g.maxAge]),[[7,'P94',60,34],[2,'P94',60,34],[1,'P93',65,34]]);assert.deepEqual(assessNotice(result,text),[]);
});
test('academic role columns count vacancies independently from degree columns and preserve row dates',()=>{
  const text='Birimi | Bölümü | Prof. | Doç. | Der. | Dr.Öğr.Üyesi | Der. | Açıklama\nTıp | Genel Cerrahi | 2 | 1 | 4 | 3 | 5 | Doktora yapmış olmak.\nTıp | Ortopedi | | | | 1(*) | 4 | Doktora yapmış olmak.';
  const result=mechanicalNotice({title:'Öğretim Üyesi'},text);assert.equal(result.fields.quota.value,7);assert.deepEqual(result.groups.map(g=>g.quota),[2,1,3,1]);assert.ok(result.groups[2].label.endsWith('Dr.Öğr.Üyesi'));
  const table='Fakülte | Bölüm | Ünvan | Kadro | Özel Koşullar | Son Başvuru Tarihi\nEdebiyat | Sosyoloji | Doktor Öğretim Üyesi | 1 | Doktora sahibi olmak. | 16.10.2026';
  const single=mechanicalNotice({title:'Öğretim Üyesi'},table);assert.equal(single.fields.quota.value,1);assert.equal(single.fields.deadline.value.slice(0,10),'2026-10-16');
  const scoped=mechanicalNotice({title:'Öğretim Üyesi'},table+'\nEdebiyat | Tarih | Profesör | 2 | Doçent unvanı almış olmak. | 20.10.2026');assert.equal(scoped.fields.deadline.value,null);assert.equal(scoped.fields.applicationPeriods.value.length,2);assert.ok(assessNotice(scoped,table).includes('deadline_scope'));
  const bad=mechanicalNotice({title:'Öğretim Üyesi'},text+'\nTıp | Histoloji | belirsiz | | | | | Kaynakta sayı yok.');assert.equal(bad.fields.quota,undefined);assert.equal(bad.tableAmbiguous,true);
});
test('explicit cancellation and professional certification exams never consume vacancy extraction credits',async()=>{
  for(const [title,kind] of [['İptal İlanı (Iğdır Üniversitesi Rektörlüğü)','cancellation'],["TÜRMOB'dan Serbest Muhasebeci Mali Müşavirlik Sınav Duyurusu",'exam'],['2026 Yılı Aktüerlik Sınavları İlanı','exam']]){
    const text='Eski kadro ilanındaki şartlar iptal edilmiştir. '+ 'Lisans mezuniyet bilgileri. '.repeat(10),res=await extractNotice({title,text},text,{DB:{prepare(){assert.fail('no model/database for non-vacancy announcement');}}},{});
    assert.equal(res.result.extraction.kind,kind);assert.equal(res.result.fields.quota.value,null);assert.equal(res.result.fields.notificationEligible.value,false);assert.deepEqual(res.result.groups,[]);
  }
  assert.equal(mechanicalNotice({title:'Uzman Yardımcılığı Giriş Sınavı Duyurusu'},'Lisans mezunu olmak.').kind,undefined,'hiring entry exams remain vacancies');
});
test('vertical official position tables retain independent counts and condition scopes',()=>{
  const text='İLAN NO | 20260201\nPOZİSYON ADI | Büro Personeli\nÖĞRENİM | Önlisans\nADEDİ | 2\nARANILAN ŞARTLAR | Yönetim ön lisans programlarından mezun olmak.\nİLAN NO | 20260202\nPOZİSYON ADI | Tekniker\nÖĞRENİM | Önlisans\nADEDİ | 1\nARANILAN ŞARTLAR | Bilgisayar Programcılığı ön lisans mezunu olmak.\nSon Başvuru Tarihi: 12.10.2026';
  const r=mechanicalNotice({title:'Personel'},text);assert.equal(r.fields.quota.value,3);assert.equal(r.tableAmbiguous,false);assert.deepEqual(r.groups.map(g=>[g.label,g.quota]),[['Büro Personeli',2],['Tekniker',1]]);assert.ok(r.groups[0].sourceText.includes('Yönetim'));assert.ok(!r.groups[0].sourceText.includes('Bilgisayar'));assert.deepEqual(assessNotice(r,text),[]);
  assert.equal(mechanicalNotice({title:'Personel'},text.replaceAll('\n','\n\n')).fields.quota.value,3,'official HTML introduces blank lines between keyed rows');
  const long='Mezun olunan programın adı ve ayrıntıları, '.repeat(15)+'yönetim ön lisans programlarından mezun olmak. 2024 yılı KPSS P93 puan türünden sınava girmiş olmak, görevini yapmasına engel sağlık sorunu bulunmamak.';
  const requirement=mechanicalNotice({title:'Personel'},text.replace('Yönetim ön lisans programlarından mezun olmak.',long)).groups[0];assert.equal(requirement.kpssStatus,'required');assert.equal(requirement.kpssType,'P93');assert.equal(requirement.kpssScore,undefined,'a participation requirement does not create a minimum score');
  const partial=mechanicalNotice({title:'Personel'},text.replace('ADEDİ | 1','ADEDİ | belirsiz'));assert.equal(partial.fields.quota,undefined);assert.equal(partial.tableAmbiguous,true);
  const repeated=mechanicalNotice({title:'Personel'},text.replace('ADEDİ | 1','ADEDİ | 1\nADEDİ | 2'));assert.equal(repeated.fields.quota,undefined);
  const exam='Gruplar | Öğrenim Dalları (Lisans) | KPSS Puan Türü | KPSS Taban Puanı | Atama Yapılabilecek Boş Kadro Sayısı | Sözlü Sınava Katılabilecek Azami Aday Sayısı\n1. Grup | Hukuk fakültelerinden mezun olmak. | KPSSP-4 | 80 | 5 | 20';
  assert.equal(mechanicalNotice({title:'Uzman Yardımcılığı'},exam).fields.quota.value,5,'vacancies are independent from invited exam candidates');
});
test('explicit hiring totals include professional titles but never exam attendance or old law numbers',()=>{
  const adalet='1- Bakanlığımızca, yazılı ve sözlü sınavlar ile 150 İcra Müdür ve İcra Müdür Yardımcısı açıktan alınacaktır.';
  assert.equal(mechanicalNotice({title:'Personel'},adalet).fields.quota.value,150);
  const gib='Başkanlığımızca aşağıdaki tabloda belirtilen yerlere atanmak üzere, 860 (sekiz yüz altmış) Gelir Uzman Yardımcısı alınacaktır.';
  assert.equal(mechanicalNotice({title:'Personel'},gib).fields.quota.value,860);
  const exam='657 sayılı Kanuna göre; 800 kişi sınava çağrılacak, 40 adet Uzman Yardımcısı alınacaktır.';
  assert.equal(mechanicalNotice({title:'Personel'},exam).fields.quota.value,40);
  assert.equal(mechanicalNotice({title:'Personel'},'800 kişi sınava çağrılacaktır.').fields.quota,undefined);
  for(const quote of ['En yüksek puanlı 800 kişi sınava çağrılacaktır.','Sınava katılabilecek aday kontenjanı: 800'])assert.equal(validateNoticeFields({quota:{value:800,quote}},quote).quota,undefined);
  assert.equal(validateNoticeFields({quota:{value:860,quote:gib}},gib).quota.value,860);
});

