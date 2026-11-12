-- The Forever trainer API has no rank text, so several ranks share a name; tell them apart
-- by required level, and keep the trainer's own state (available / unavailable / used).
DROP TABLE trainer_skills;
CREATE TABLE trainer_skills (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  rank INTEGER NOT NULL DEFAULT 0,
  required_level INTEGER NOT NULL DEFAULT 0,
  cost_copper INTEGER NOT NULL DEFAULT 0,
  state TEXT NOT NULL DEFAULT 'unavailable',
  learned INTEGER NOT NULL DEFAULT 0,
  tradeskill INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL,
  UNIQUE (name, rank, required_level)
);
