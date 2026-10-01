ALTER TABLE notification_outbox ADD COLUMN history_seq INTEGER;
ALTER TABLE notification_outbox ADD COLUMN accepted_at TEXT;
CREATE TABLE notification_sequence (id INTEGER PRIMARY KEY CHECK(id=1), seq INTEGER NOT NULL);
INSERT INTO notification_sequence VALUES(1,0);
-- Preserve already accepted events in stable order; future acceptance, not hash
-- identity or creation time, determines the incremental history sequence.
WITH ranked AS (
  SELECT id,ROW_NUMBER() OVER (ORDER BY created_at,id) seq
  FROM notification_outbox WHERE state='accepted'
)
UPDATE notification_outbox SET history_seq=(SELECT seq FROM ranked WHERE ranked.id=notification_outbox.id),accepted_at=created_at
WHERE state='accepted';
UPDATE notification_sequence SET seq=(SELECT COALESCE(MAX(history_seq),0) FROM notification_outbox);
CREATE UNIQUE INDEX notification_history_seq ON notification_outbox(history_seq);
CREATE INDEX installation_history_seq ON notification_outbox(installation_id,history_seq);
CREATE TRIGGER notification_accepted AFTER UPDATE OF state ON notification_outbox
WHEN NEW.state='accepted' AND NEW.history_seq IS NULL BEGIN
  UPDATE notification_sequence SET seq=seq+1 WHERE id=1;
  UPDATE notification_outbox SET history_seq=(SELECT seq FROM notification_sequence WHERE id=1),
    accepted_at=strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id=NEW.id;
END;
CREATE TRIGGER notification_accepted_insert AFTER INSERT ON notification_outbox
WHEN NEW.state='accepted' AND NEW.history_seq IS NULL BEGIN
  UPDATE notification_sequence SET seq=seq+1 WHERE id=1;
  UPDATE notification_outbox SET history_seq=(SELECT seq FROM notification_sequence WHERE id=1),
    accepted_at=strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id=NEW.id;
END;
