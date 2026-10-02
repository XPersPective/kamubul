CREATE INDEX outbox_accepted_retention ON notification_outbox(accepted_at,id)
WHERE state='accepted';
