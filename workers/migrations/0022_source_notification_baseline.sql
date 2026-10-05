-- Previously unseen sources must not turn their first snapshot into new-job alerts.
ALTER TABLE sources ADD COLUMN baseline_at TEXT;
UPDATE sources SET baseline_at=(SELECT MIN(first_seen) FROM listings WHERE source_id=sources.id);
