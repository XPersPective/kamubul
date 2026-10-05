import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parseSbbList} from '../src/sources.js';

const fixture='../../packages/kamubul_core/test/fixtures/';
const civilDay=value=>new Date(Date.parse(value)+3*3600000).toISOString().slice(0,10);

test('SBB parser reads captured official HTML and all 55 labeled list rows',()=>{
  assert.equal(parseSbbList(readFileSync(new URL(fixture+'sbb_list.html',import.meta.url),'utf8'),2026).length,3);
  const corpus=readFileSync(new URL(fixture+'eval/sbb.jsonl',import.meta.url),'utf8').trim().split('\n').map(JSON.parse);
  const gold=JSON.parse(readFileSync(new URL(fixture+'eval/gold_sbb.json',import.meta.url),'utf8'));
  assert.equal(corpus.length,55);
  for(const row of corpus){
    const [actual]=parseSbbList(row.raw,row.year),expected=gold[row.id];
    assert.ok(expected,row.id);assert.equal(actual.externalId,row.id);
    for(const field of ['institution','title','category'])assert.equal(actual[field],expected[field].value,row.id+':'+field);
    for(const field of ['start','deadline'])assert.equal(actual[field]?civilDay(actual[field]):null,expected[field].value,row.id+':'+field);
    assert.equal(actual.publishedAt,null,'Logo timestamp is not a publication date');
  }
});

test('SBB application dates use Turkish civil days and validated year rollover',()=>{
  const row=range=>parseSbbList(`<a href="ilanDetay.aspx?kod=test"><p class = 'alt_p1'>Kurum</p><p class = 'alt_p2'>2 işçi alacak<em>(${range})</em></p></a>`,2026)[0];
  const item=row('15 Aralık - 5 Ocak');
  assert.equal(item.start,'2026-12-14T21:00:00.000Z');assert.equal(item.deadline,'2027-01-05T20:59:59.000Z');assert.equal(item.category,'İşçi');
  assert.equal(row('15 Aralık 2027 - 29 Şubat').deadline,'2028-02-29T20:59:59.000Z');
  assert.equal(row('15 Aralık - 5 Ocak 2026').deadline,null,'Explicit conflicting year is not silently changed');
  assert.equal(row('1 Şubat - 30 Şubat').deadline,null);
  assert.equal(row('1 EKİM - 2 EKİM').deadline,'2026-10-02T20:59:59.000Z');
  assert.equal(row('1 Mart - 2 Mart - 3 Mart').deadline,null);
  assert.equal(row('tarih yok').start,null);
});

test('SBB retains every official list row beyond 500; a malformed listing never silently disappears',()=>{
  const row=id=>`<a href="ilanDetay.aspx?kod=${id}"><p class="alt_p1">Kurum</p><p class="alt_p2">İşçi alımı</p></a>`;
  assert.equal(parseSbbList(Array.from({length:505},(_,i)=>row(i)).join('')).length,505);
  assert.throws(()=>parseSbbList(row(1)+'<a href="ilanDetay.aspx?kod=2">Eksik düzen</a>'),/layout_changed/);
});
