-- Durable inference ceiling across devices, failures and Worker restarts.
CREATE TABLE extraction_runs (
  hash TEXT PRIMARY KEY,
  attempts INTEGER NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 2),
  lease_until TEXT
);
