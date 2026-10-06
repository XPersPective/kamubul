-- Re-evaluate stored documents once with mechanical-first notice extraction.
-- No source refetch or AI budget reset. Existing public identities remain intact.
UPDATE listings SET conditions_checked=NULL,conditions_due_at='1970-01-01T00:00:00.000Z',conditions_error=NULL
WHERE json_extract(payload,'$.text') IS NOT NULL OR json_array_length(payload,'$.positions')>0;
