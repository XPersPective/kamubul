-- Digest is separate from the user's instant-notification cap.
ALTER TABLE installations ADD COLUMN digest_day TEXT;
