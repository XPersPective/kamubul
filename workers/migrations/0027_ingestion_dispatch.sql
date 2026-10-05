-- Preserve current delivery leases/generations while adding bounded ingestion wake-ups.
CREATE TABLE dispatch_state_new (
  kind TEXT PRIMARY KEY CHECK(kind IN ('match','send','source','extract')),
  generation INTEGER NOT NULL DEFAULT 0,
  state TEXT NOT NULL DEFAULT 'idle' CHECK(state IN ('idle','queued','running')),
  lease_until TEXT
);
INSERT INTO dispatch_state_new SELECT * FROM dispatch_state;
INSERT INTO dispatch_state_new(kind) VALUES('source'),('extract');
DROP TABLE dispatch_state;
ALTER TABLE dispatch_state_new RENAME TO dispatch_state;
