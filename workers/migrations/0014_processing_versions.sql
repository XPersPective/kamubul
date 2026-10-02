-- Preserve old jobs and checkpoints while allowing explicitly versioned work.
CREATE TABLE processing_jobs_versioned (
  id TEXT PRIMARY KEY, listing_id TEXT NOT NULL REFERENCES listings(id), input_hash TEXT NOT NULL,
  input TEXT NOT NULL CHECK(json_valid(input)), state TEXT NOT NULL DEFAULT 'pending',
  attempts INTEGER NOT NULL DEFAULT 0, due_at TEXT NOT NULL, lease_until TEXT, error_code TEXT,
  contract_key TEXT NOT NULL DEFAULT 'legacy', purpose TEXT NOT NULL DEFAULT 'ingestion' CHECK(purpose IN ('ingestion','reprocess')),
  UNIQUE(listing_id,input_hash,contract_key)
);
INSERT INTO processing_jobs_versioned(id,listing_id,input_hash,input,state,attempts,due_at,lease_until,error_code,contract_key)
SELECT id,listing_id,input_hash,input,state,attempts,due_at,lease_until,error_code,
  CASE WHEN json_type(input,'$.aiContract')='object'
    THEN json_array(json_extract(input,'$.aiContract.provider'),json_extract(input,'$.aiContract.model'),json_extract(input,'$.aiContract.extractionRevision'))
    ELSE 'legacy' END
FROM processing_jobs;
DROP TABLE processing_jobs;
ALTER TABLE processing_jobs_versioned RENAME TO processing_jobs;
CREATE INDEX processing_due ON processing_jobs(state,due_at);
CREATE INDEX processing_listing_lease ON processing_jobs(listing_id,state,lease_until);
ALTER TABLE listings ADD COLUMN processed_contract TEXT;
ALTER TABLE listings ADD COLUMN reprocess_contract TEXT;
UPDATE listings SET processed_contract=CASE WHEN processed_hash IS NULL THEN NULL
  WHEN json_type(payload,'$.aiProvenance')='object'
    THEN json_array(json_extract(payload,'$.aiProvenance.provider'),json_extract(payload,'$.aiProvenance.model'),json_extract(payload,'$.aiProvenance.extractionRevision'))
  ELSE 'legacy' END;
CREATE TRIGGER reprocess_selected AFTER INSERT ON processing_jobs WHEN NEW.purpose='reprocess' BEGIN
  UPDATE listings SET reprocess_contract=NEW.contract_key WHERE id=NEW.listing_id AND content_hash=NEW.input_hash;
END;
