"""Check the Turkish listing candidate against its source and recorded hashes."""
import hashlib
import re
from pathlib import Path

root = Path(__file__).resolve().parents[2]
source = (root / 'docs/growth/STORE_COPY.md').read_text(encoding='utf-8')
record = (root / 'docs/growth/STORE_TEXT_ACCEPTANCE.md').read_text(encoding='utf-8')
for marker, name, limit in [('Title', 'title', 30), ('ShortA', 'short_description', 80), ('Full', 'full_description', 4000)]:
    matches = re.findall(r'<!-- ' + marker + r' -->\s*\n(.*?)\n<!-- /' + marker + r' -->', source, re.S)
    assert len(matches) == 1, marker
    value = matches[0].strip()
    assert 0 < len(value) <= limit, (marker, len(value))
    data = (root / f'docs/growth/candidate/tr-TR/{name}.txt').read_bytes()
    assert data == (value + '\n').encode('utf-8'), name
    assert hashlib.sha256(data).hexdigest() in record, name
    if marker != 'Full':
        assert not any(word in value.casefold() for word in ['kpss', 'ösym']), name
    else:
        assert all(text in value for text in ['bağımsız', 'hata', 'otomatik yenilenir', 'iptal', 'resmî', 'https://']), name
    print(f'{name}: {len(value)}/{limit}, source/hash PASS')
