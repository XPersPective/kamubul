-- ADR-005 katman 2: normalize ilan metni hash'i → doğrulanmış şart grupları.
-- İlan başına tek model çağrısı; boş sonuç da saklanır.
CREATE TABLE IF NOT EXISTS extraction_cache (hash TEXT PRIMARY KEY, groups TEXT NOT NULL, model TEXT, created_at TEXT NOT NULL);
