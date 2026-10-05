-- Kanonik şart ayıklamasının denetlendiği içerik hash'i (ADR-006). Değişiklik
-- tetikleyicisi payload/active üzerinde olduğundan bu sütun revizyon üretmez.
ALTER TABLE listings ADD COLUMN conditions_checked TEXT;
