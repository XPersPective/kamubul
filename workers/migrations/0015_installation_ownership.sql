-- A concurrent first registration must not mutate another installation's searches
-- or outbox. Abort the entire D1 batch, including its dependent writes.
CREATE TRIGGER installation_owner_insert BEFORE INSERT ON installations
WHEN EXISTS (SELECT 1 FROM installations WHERE id=NEW.id AND secret_hash!=NEW.secret_hash)
BEGIN
  SELECT RAISE(ABORT, 'installation_owner_conflict');
END;

CREATE TRIGGER installation_owner_update BEFORE UPDATE OF secret_hash ON installations
WHEN NEW.secret_hash!=OLD.secret_hash
BEGIN
  SELECT RAISE(ABORT, 'installation_owner_conflict');
END;
