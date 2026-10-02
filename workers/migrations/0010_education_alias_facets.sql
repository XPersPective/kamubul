-- Existing label anchors may differ from canonical education keys. Preserve a
-- conservative wildcard until the next authenticated registry update rebuilds them.
INSERT OR IGNORE INTO installation_facets(key,installation_id)
SELECT '*',f.installation_id FROM installation_facets f
JOIN installations i ON i.id=f.installation_id
WHERE f.key LIKE 'education:%' AND i.enabled=1;
-- Anchor keys/order changed; resume partial fanout from its start. Outbox UNIQUE
-- identities still prevent an already-queued notice from being queued twice.
UPDATE match_events SET facet_index=0,cursor='',lease_until=NULL,state='pending'
WHERE state IN ('pending','leased');
