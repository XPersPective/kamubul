CREATE TABLE installation_facets (
  key TEXT NOT NULL,
  installation_id TEXT NOT NULL REFERENCES installations(id) ON DELETE CASCADE,
  PRIMARY KEY(key,installation_id)
);
CREATE INDEX installation_facet_owner ON installation_facets(installation_id,key);
-- Existing subscriptions start conservatively broad, then registry refresh replaces
-- their facets. This preserves subscriptions during rollout without a full rewrite.
INSERT INTO installation_facets(key,installation_id)
SELECT DISTINCT '*',s.installation_id FROM saved_searches s JOIN installations i ON i.id=s.installation_id WHERE s.mode!='off' AND i.enabled=1;
ALTER TABLE match_events ADD COLUMN facet_index INTEGER NOT NULL DEFAULT 0;
UPDATE match_events SET cursor='',lease_until=NULL,state='pending'
WHERE state IN ('pending','leased');
CREATE INDEX catalogue_listing_seq ON catalogue_changes(listing_id,seq);
