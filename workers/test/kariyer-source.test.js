import {test} from 'node:test';
import assert from 'node:assert/strict';
import {plain,parseKariyerIndex,parseKariyerRss,parseKariyerDetail,fetchKariyerDetail} from '../src/sources.js';

const guid=n=>'aaaaaaaa-aaaa-aaaa-aaaa-'+String(n).padStart(12,'0');
test('Kariyer lists and position details retain every row past the former caps and missing dates',()=>{
  const index=Array.from({length:205},(_,n)=>({guid:guid(n),ilanBaslik:'İlan '+n,bitTarih:n?'2026-12-01':null}));
  const list=parseKariyerIndex({searchIlan:index});assert.equal(list.length,205);assert.equal(list[0].deadline,null);
  const rss='<rss>'+index.map(x=>`<item><title>${x.ilanBaslik}</title><link>https://kariyerkapisi.gov.tr/IlanDetay?i=${x.guid}</link></item>`).join('')+'</rss>';
  assert.equal(parseKariyerRss(rss).length,205);
  const detail=parseKariyerDetail({ilanMetni:'<p>Genel koşullar</p>'},Array.from({length:105},(_,i)=>({ilanBaslik:'Kadro '+i,ilanMetni:'<table><tr><th>Eğitim</th><th>Puan</th></tr><tr><td><p>Lisans</p><p>mezunu</p></td><td>70</td></tr></table>',kontenjanList:[{il:'İzmir',kontenjan:1}]})));
  assert.equal(detail.positions.length,105);assert.equal(detail.quota,105);assert.equal(detail.detailState,'available');
  assert.equal(detail.positions.at(-1).text,'Eğitim | Puan\nLisans mezunu | 70');
});
test('official HTML keeps table cells, paragraphs and literal escaped text without executable markup',()=>{
  assert.equal(plain('<style>hide</style><script>bad()</script><p>A &lt; B &#x130;</p><table><tr><td>1</td><td>&lt;örnek&gt; &amp;amp;</td></tr></table><ul><li>Son</li></ul>'),'A < B İ\n1 | <örnek> &amp;\nSon');
});
test('Kariyer malformed applicable row cannot silently disappear; external detail identity is validated',async t=>{
  assert.throws(()=>parseKariyerIndex({searchIlan:[{guid:'bad',ilanBaslik:'İlan'}]}),/layout_changed/);
  assert.deepEqual(parseKariyerIndex({searchIlan:[{ilanTuru:'Yurt Dışı Eğitim İlanları'}]}),[]);
  assert.throws(()=>parseKariyerRss('<rss><item><title>İlan</title><link>bad</link></item></rss>'),/rss_layout_changed/);
  assert.throws(()=>parseKariyerRss('<rss><item><title>İlan</title></rss>'),/rss_layout_changed/);
  const original=globalThis.fetch;t.after(()=>globalThis.fetch=original);let calls=0;globalThis.fetch=async()=>{calls++;};
  await assert.rejects(fetchKariyerDetail('bad'),/source_identity/);assert.equal(calls,0);
});
