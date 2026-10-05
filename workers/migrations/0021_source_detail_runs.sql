-- Bound failed detail reads per published source revision, across Cron restarts.
CREATE TABLE source_detail_runs (
  listing_id TEXT PRIMARY KEY,
  input_key TEXT NOT NULL,
  attempts INTEGER NOT NULL CHECK(attempts BETWEEN 1 AND 2),
  lease_until TEXT
);
