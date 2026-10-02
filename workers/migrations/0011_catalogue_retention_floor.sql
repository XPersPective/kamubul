CREATE TABLE catalogue_retention (
  id INTEGER PRIMARY KEY CHECK(id=1),
  floor INTEGER NOT NULL DEFAULT 0 CHECK(typeof(floor)='integer' AND floor>=0)
);
INSERT INTO catalogue_retention(id,floor) VALUES(1,0);
