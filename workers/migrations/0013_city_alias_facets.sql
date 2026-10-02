-- Previously stored city IDs used literal anchors; protect them until heartbeat
-- rebuilds the shared city keys. Existing label anchors stay unchanged.
INSERT OR IGNORE INTO installation_facets(key,installation_id)
SELECT '*',f.installation_id FROM installation_facets f
JOIN installations i ON i.id=f.installation_id
WHERE f.key LIKE 'cities:city:%' AND i.enabled=1;
UPDATE match_events SET facet_index=0,cursor='',lease_until=NULL,state='pending'
WHERE state IN ('pending','leased');
