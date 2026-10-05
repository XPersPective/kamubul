import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parseIskurList,parseIskurDetail,fetchIskurList,fetchIskurDetail} from '../src/sources.js';

const fixture=readFileSync(new URL('../../packages/kamubul_core/test/fixtures/iskur_kamu_grid.html',import.meta.url),'utf8');
const form='<input name="__VIEWSTATE" value="state&amp;data"><input value="kamuRadio" name="ctl04$IsyeriTuruRadios">';
test('Worker reuses captured official İŞKUR public rows and validates both public labels',()=>{
  const items=parseIskurList(fixture);assert.equal(items.length,9);
  assert.equal(items[0].externalId,'00009817965');assert.equal(items[0].title,'Servis Elemanı (Garson)');assert.equal(items[0].institution,'POLİS EVİ');
  assert.equal(items[0].quota,4);assert.deepEqual(items[0].places,['Iğdır']);assert.equal(items[0].deadline,'2026-10-06T20:59:59.000Z');
  assert.equal(items[0].url,'https://esube.iskur.gov.tr/Istihdam/AcikIsIlanDetay.aspx?uiID=00009817965&isyeriTuru=Kamu');
  assert.equal(parseIskurList(fixture.replaceAll('&#39;Kamu&#39;','&#39;Özel&#39;')).length,0);
  assert.equal(parseIskurList(fixture.replaceAll('>Kamu</span>','>Özel</span>')).length,0);
  assert.throws(()=>parseIskurList('<html>login</html>'),/layout_changed/);
  assert.equal(parseIskurList(fixture.replace('6.10.2026','31.2.2026'))[0].deadline,null);
});
test('Worker İŞKUR performs native public WebForms POST with bounded source reads and source cookies',async t=>{
  const original=globalThis.fetch;t.after(()=>globalThis.fetch=original);const calls=[];
  globalThis.fetch=async(url,options)=>{calls.push([url,options]);if(calls.length===1)return new Response(form,{headers:{'Set-Cookie':'ASP.NET_SessionId=session; HttpOnly; Secure'}});return new Response(fixture);};
  assert.equal((await fetchIskurList()).length,9);assert.equal(calls.length,2);assert.equal(calls[1][1].headers.Cookie,'ASP.NET_SessionId=session');
  const posted=new URLSearchParams(calls[1][1].body);assert.equal(posted.get('ctl04$IsyeriTuruRadios'),'kamuRadio');assert.equal(posted.get('__VIEWSTATE'),'state&data');assert.equal(posted.get('__EVENTTARGET'),'ctl04$ctlAcikIsPageCommand$CommandItem_Search');
  assert.equal(calls[1][1].redirect,'manual');
});
test('İŞKUR follows WebForms next pages and rejects a repeated page rather than losing announcements',async t=>{
  const original=globalThis.fetch;t.after(()=>globalThis.fetch=original);
  for(const repeated of [false,true]){
    let calls=0;
    globalThis.fetch=async(_,options)=>{calls++;if(calls===1)return new Response(form);if(calls===2)return new Response(form+fixture+`<a href="javascript:__doPostBack(&#39;ctl04$ctlGridAcikIslerListeDetail&#39;,&#39;Page$2&#39;)">2</a>`);assert.equal(new URLSearchParams(options.body).get('__EVENTARGUMENT'),'Page$2');return new Response(repeated?fixture:fixture.replaceAll('000098','000099'));};
    if(repeated)await assert.rejects(fetchIskurList(),/source_page_repeated/);else assert.equal((await fetchIskurList()).length,18);
  }
});
test('İŞKUR detail retains earlier general terms and table boundaries and rejects arbitrary IDs before HTTP',async t=>{
  assert.equal(parseIskurDetail('<p>Login navigation</p><p>Genel Hususlar</p><p>18 yaş</p><h2>ÖZEL ŞARTLAR</h2><table><tr><td>Lise</td><td>70</td></tr></table>').text,'Genel Hususlar\n18 yaş\nÖZEL ŞARTLAR\nLise | 70');
  assert.throws(()=>parseIskurDetail('<html>login</html>'),/detail_layout_changed/);
  const original=globalThis.fetch;t.after(()=>globalThis.fetch=original);let calls=0;globalThis.fetch=async()=>{calls++;};
  await assert.rejects(fetchIskurDetail('../other'),/source_identity/);assert.equal(calls,0);
});
