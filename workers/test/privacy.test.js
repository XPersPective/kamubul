import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';

test('public privacy page is current, readable HTML with actual contact and disclosures',()=>{
  const source=readFileSync(new URL('../../PRIVACY.md',import.meta.url));
  const page=readFileSync(new URL('../public/privacy/index.html',import.meta.url),'utf8');
  assert.ok(page.includes(createHash('sha256').update(source).digest('hex')),'run tool/build-privacy-page.ps1 after changing PRIVACY.md');
  assert.match(page,/<h1\b/);
  for(const text of ['<html lang="tr">','mailto:devcrazypenguin@gmail.com','Google Mobile Ads','120 gün','90 gün'])assert.ok(page.includes(text),text);
  assert.ok(!/<script\b|<form\b|<iframe\b/i.test(page));
});
