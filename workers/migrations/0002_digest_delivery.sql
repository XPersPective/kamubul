-- A digest has one durable leader; membership stays fixed across FCM retries.
ALTER TABLE notification_outbox ADD COLUMN delivery_id TEXT;
CREATE INDEX outbox_delivery ON notification_outbox(delivery_id,id);
-- Serialize sends for one installation so concurrent Cron runs honor its cap.
ALTER TABLE installations ADD COLUMN send_lease_until TEXT;
CREATE INDEX outbox_installation_pending ON notification_outbox(installation_id,state,delivery_id,due_at,id);
CREATE INDEX listing_deadline ON listings(active,deadline,id);
