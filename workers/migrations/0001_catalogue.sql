CREATE TABLE sources (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'pending',
  last_attempt TEXT, last_success TEXT, next_due TEXT NOT NULL DEFAULT '1970-01-01',
  note TEXT, lease_until TEXT, etag TEXT, pending_batch TEXT, batch_offset INTEGER NOT NULL DEFAULT 0
);
INSERT INTO sources(id,name,state,note) VALUES
 ('kariyerkapisi','Kariyer Kapısı','pending',NULL),
 ('sbb','Kamu İlanları (SBB)','pending',NULL),
 ('iskur','İŞKUR','blocked','Herkese açık ilan uç noktası doğrulanmadı; WAF/oturum aşılmaz.'),
 ('ilangov','ilan.gov.tr','blocked','Herkese açık ilan uç noktası doğrulanmadı; WAF/oturum aşılmaz.');
CREATE TABLE listings (
  id TEXT PRIMARY KEY, source_id TEXT NOT NULL REFERENCES sources(id), external_id TEXT NOT NULL,
  content_hash TEXT NOT NULL, processed_hash TEXT, revision INTEGER NOT NULL DEFAULT 1,
  first_seen TEXT NOT NULL, updated_at TEXT NOT NULL, recheck_at TEXT NOT NULL,
  deadline TEXT, active INTEGER NOT NULL DEFAULT 1, payload TEXT NOT NULL CHECK(json_valid(payload)),
  UNIQUE(source_id,external_id)
);
CREATE INDEX listing_recheck ON listings(active,recheck_at,id);
CREATE TABLE processing_jobs (
  id TEXT PRIMARY KEY, listing_id TEXT NOT NULL REFERENCES listings(id), input_hash TEXT NOT NULL,
  input TEXT NOT NULL CHECK(json_valid(input)), state TEXT NOT NULL DEFAULT 'pending',
  attempts INTEGER NOT NULL DEFAULT 0, due_at TEXT NOT NULL, lease_until TEXT, error_code TEXT,
  UNIQUE(listing_id,input_hash)
);
CREATE INDEX processing_due ON processing_jobs(state,due_at);
CREATE TABLE catalogue_changes (
  seq INTEGER PRIMARY KEY AUTOINCREMENT, listing_id TEXT NOT NULL, revision INTEGER NOT NULL,
  operation TEXT NOT NULL, payload TEXT NOT NULL CHECK(json_valid(payload)), committed_at TEXT NOT NULL
);
CREATE TABLE match_events (
  id TEXT PRIMARY KEY, listing_id TEXT NOT NULL, revision INTEGER NOT NULL,
  payload TEXT NOT NULL, created_at TEXT NOT NULL, cursor TEXT NOT NULL DEFAULT '',
  state TEXT NOT NULL DEFAULT 'pending', lease_until TEXT
);
CREATE INDEX match_pending ON match_events(state,created_at);
CREATE TRIGGER listing_insert AFTER INSERT ON listings BEGIN
  INSERT INTO catalogue_changes(listing_id,revision,operation,payload,committed_at)
  VALUES(NEW.id,NEW.revision,'upsert',json_set(NEW.payload,'$.id',NEW.id,'$.revision',NEW.revision),NEW.updated_at);
END;
CREATE TRIGGER listing_update AFTER UPDATE OF payload,active ON listings BEGIN
  INSERT INTO catalogue_changes(listing_id,revision,operation,payload,committed_at)
  VALUES(NEW.id,NEW.revision,CASE WHEN NEW.active=1 THEN 'upsert' ELSE 'tombstone' END,
    json_set(NEW.payload,'$.id',NEW.id,'$.revision',NEW.revision),NEW.updated_at);
END;
CREATE TRIGGER listing_processed AFTER UPDATE OF processed_hash ON listings
WHEN NEW.processed_hash IS NOT NULL AND NEW.processed_hash IS NOT OLD.processed_hash AND NEW.active=1 BEGIN
  INSERT OR IGNORE INTO match_events(id,listing_id,revision,payload,created_at)
  VALUES(NEW.id||':'||NEW.revision,NEW.id,NEW.revision,
    json_set(NEW.payload,'$.id',NEW.id,'$.revision',NEW.revision),NEW.updated_at);
END;
CREATE TABLE installations (
  id TEXT PRIMARY KEY, secret_hash TEXT NOT NULL, token TEXT NOT NULL, platform TEXT NOT NULL,
  preferences TEXT NOT NULL CHECK(json_valid(preferences)), version INTEGER NOT NULL DEFAULT 1,
  updated_at TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1, sent_day TEXT, sent_count INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX installation_stale ON installations(updated_at);
CREATE TABLE saved_searches (
  installation_id TEXT NOT NULL REFERENCES installations(id) ON DELETE CASCADE, id TEXT NOT NULL,
  name TEXT NOT NULL, criteria TEXT NOT NULL CHECK(json_valid(criteria)), mode TEXT NOT NULL,
  effective_after INTEGER NOT NULL, PRIMARY KEY(installation_id,id)
);
CREATE TABLE notification_outbox (
  id TEXT PRIMARY KEY, installation_id TEXT NOT NULL REFERENCES installations(id) ON DELETE CASCADE,
  listing_id TEXT NOT NULL, payload TEXT NOT NULL CHECK(json_valid(payload)),
  state TEXT NOT NULL DEFAULT 'pending', due_at TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0,
  lease_until TEXT, fcm_id TEXT, error_code TEXT, created_at TEXT NOT NULL,
  UNIQUE(installation_id,listing_id)
);
CREATE INDEX outbox_due ON notification_outbox(state,due_at,id);
CREATE INDEX outbox_history ON notification_outbox(installation_id,created_at,id);
CREATE TABLE daily_usage (day TEXT PRIMARY KEY, ai_jobs INTEGER NOT NULL DEFAULT 0);
CREATE TABLE rate_limits (key TEXT PRIMARY KEY, count INTEGER NOT NULL, expires_at TEXT NOT NULL);
