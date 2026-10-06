import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {DatabaseSync} from 'node:sqlite';
import {createHash} from 'node:crypto';
import {mechanicalNotice,assessNotice,extractNotice} from '../src/notice_extraction.js';
import {parseIlanGovDetail} from '../src/sources.js';
import {validateNoticeFields} from '../src/extract.js';
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
test('application dates retain actual deadlines and time; document delivery/exam/publication are different',()=>{
  const dates={'2242968':'2026-10-16','2244776':'2026-10-20','2244748':'2026-10-19','2244739':'2026-10-11','2236938':'2026-10-12','2234989':'2026-10-12','2243231':'2026-10-31'};
  for(const item of corpus){const result=mechanicalNotice({...parseIlanGovDetail({result:item.result},item.id),title:item.result.title},item.text);if(['2234989','2244776'].includes(item.id)){assert.equal(result.fields.deadline.value,null);assert.ok(assessNotice(result,item.text).includes('deadline_scope'));if(item.id==='2234989')assert.ok(result.fields.applicationPeriods.value.some(p=>p.deadline?.startsWith('2026-10-12')));else assert.ok(result.fields.applicationPeriods.value.some(p=>p.text.includes('15. gün')));continue;}assert.equal(result.fields.deadline?.value.slice(0,10),dates[item.id],item.id);if(item.id==='2236938')assert.equal(result.fields.deadline.value,'2026-10-12T10:00:00.000Z');}
  assert.equal(mechanicalNotice({title:'İlan'},'Son Başvuru Tarihi: 31.02.2026\nSınav Tarihi: 20.03.2026').fields.deadline,undefined);
});
test('mechanically complete notice does not access a model or database',async()=>{
  const item=corpus.find(n=>n.id==='2242968'),notice={...parseIlanGovDetail({result:item.result},item.id),title:item.result.title};
  const result=await extractNotice(notice,item.text,{DB:{prepare(){assert.fail('no AI database call');}}},{});
  assert.equal(result.result.extraction.method,'mechanical');assert.equal(result.result.extraction.status,'complete');assert.equal(result.result.fields.quota.value,1);
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
test('preferred degree is not mandatory and conjunctive degrees are not eligibility alternatives',()=>{
  const preferred='Lisans derecesine sahip olmak ve tercihen tezli yüksek lisans derecesine sahip olmak.';
  assert.deepEqual(validateGroups({groups:[{education:['Lisans','Yüksek lisans'],educationQuote:preferred}]},preferred)[0].education,['Lisans']);
  const both='Lisans ve tezli yüksek lisans mezunu olmak.';
  const group=validateGroups({groups:[{education:['Lisans','Yüksek lisans'],educationQuote:both}]},both)[0];assert.equal(group.education,undefined);assert.equal(group.educationDescription,both);
});

