-- List paging is separate from detail/AI work: a restart cannot publish half a list.
ALTER TABLE sources ADD COLUMN pending_list TEXT;
ALTER TABLE sources ADD COLUMN list_page INTEGER NOT NULL DEFAULT 0;
ALTER TABLE sources ADD COLUMN list_total INTEGER;
UPDATE sources SET state='pending',next_due='1970-01-01',note=NULL WHERE id='iskur';
-- Resume the already running bootstrap without hiding the unprocessed identities.
INSERT INTO listings(id,source_id,external_id,content_hash,first_seen,updated_at,recheck_at,deadline,payload)
SELECT json_extract(j.value,'$.id'),s.id,json_extract(j.value,'$.externalId'),
  'pending:'||json_extract(j.value,'$.id'),COALESCE(s.last_attempt,s.baseline_at),COALESCE(s.last_attempt,s.baseline_at),
  '1970-01-01',json_extract(j.value,'$.deadline'),
  json_set(j.value,'$.notificationEligible',json('false'),'$.detailState','pending')
FROM sources s,json_each(s.pending_batch) j WHERE s.pending_batch IS NOT NULL
ON CONFLICT(id) DO NOTHING;
