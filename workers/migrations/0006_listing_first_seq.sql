-- Keep subscription eligibility independent of catalogue-log retention.
ALTER TABLE listings ADD COLUMN first_seq INTEGER NOT NULL DEFAULT 0;
UPDATE listings SET first_seq=COALESCE(
  (SELECT MIN(seq) FROM catalogue_changes WHERE listing_id=listings.id),0
);
CREATE TRIGGER catalogue_first_seq AFTER INSERT ON catalogue_changes BEGIN
  UPDATE listings SET first_seq=NEW.seq WHERE id=NEW.listing_id AND first_seq=0;
END;
