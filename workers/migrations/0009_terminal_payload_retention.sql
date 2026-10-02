CREATE INDEX outbox_terminal_retention ON notification_outbox(created_at,id)
WHERE state IN ('failed','cancelled','expired') AND payload!='{}';
