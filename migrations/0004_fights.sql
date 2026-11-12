-- Fights recorded by the in-game addon (one row per combat, aggregated per ability).
CREATE TABLE fights (
  start INTEGER PRIMARY KEY,     -- unix time the fight began
  duration REAL NOT NULL,
  damage INTEGER NOT NULL,
  json TEXT NOT NULL
);
