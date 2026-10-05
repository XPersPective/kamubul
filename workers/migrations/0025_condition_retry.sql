-- Keep a failed/quota-limited notice from starving the rest of the catalogue.
ALTER TABLE listings ADD COLUMN conditions_due_at TEXT NOT NULL DEFAULT '1970-01-01';
ALTER TABLE listings ADD COLUMN conditions_error TEXT;
CREATE INDEX conditions_due ON listings(active,conditions_due_at,updated_at);
-- Failed HTTP repairs get another bounded episode after a polite cooldown.
ALTER TABLE source_detail_runs ADD COLUMN retry_after TEXT;
UPDATE source_detail_runs SET retry_after='1970-01-01' WHERE attempts>=2;
