-- Kriter asistanı kota sayaçları: gün + kova (global / ip hash / kurulum).
CREATE TABLE IF NOT EXISTS assistant_usage (day TEXT NOT NULL, bucket TEXT NOT NULL, count INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (day, bucket));
