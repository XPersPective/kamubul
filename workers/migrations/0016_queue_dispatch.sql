-- Queue is a bounded wake-up transport; work and recovery remain in D1.
ALTER TABLE daily_usage ADD COLUMN queue_jobs INTEGER NOT NULL DEFAULT 0;
CREATE TABLE dispatch_state (
  kind TEXT PRIMARY KEY CHECK(kind IN ('match','send')),
  generation INTEGER NOT NULL DEFAULT 0,
  state TEXT NOT NULL DEFAULT 'idle' CHECK(state IN ('idle','queued','running')),
  lease_until TEXT
);
INSERT INTO dispatch_state(kind) VALUES('match'),('send');
