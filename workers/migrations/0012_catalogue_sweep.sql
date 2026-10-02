ALTER TABLE catalogue_retention ADD COLUMN gc_after INTEGER NOT NULL DEFAULT 0
  CHECK(typeof(gc_after)='integer' AND gc_after>=0);
