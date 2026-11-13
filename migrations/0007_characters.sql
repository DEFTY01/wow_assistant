-- Several characters in one deployment. Game data (recipes, loot, items, prices) stays shared;
-- everything about one character gets a character key. Existing rows belong to the owner.
CREATE TABLE characters (
  slug TEXT PRIMARY KEY,
  name TEXT,
  class_id INTEGER,
  level INTEGER,
  faction TEXT,
  ruleset_id INTEGER,
  share_key TEXT UNIQUE,          -- secret in the shared link and the uploader token; NULL for the owner
  is_owner INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  last_sync TEXT
);
INSERT INTO characters (slug, name, is_owner, created_at) VALUES ('defty-graveshade', 'Defty', 1, datetime('now'));

ALTER TABLE snapshots ADD COLUMN slug TEXT NOT NULL DEFAULT 'defty-graveshade';
CREATE INDEX idx_snapshots_slug ON snapshots (slug, kind, id DESC);
ALTER TABLE sync_log ADD COLUMN slug TEXT NOT NULL DEFAULT 'defty-graveshade';

-- Per-character settings are stored as "<slug>:<key>".
UPDATE manual_state SET key = 'defty-graveshade:' || key WHERE key IN ('addon', 'gold_copper', 'buffs');

CREATE TABLE fights_new (
  slug TEXT NOT NULL,
  start INTEGER NOT NULL,
  duration REAL NOT NULL,
  damage INTEGER NOT NULL,
  json TEXT NOT NULL,
  PRIMARY KEY (slug, start)
);
INSERT INTO fights_new SELECT 'defty-graveshade', start, duration, damage, json FROM fights;
DROP TABLE fights;
ALTER TABLE fights_new RENAME TO fights;

CREATE TABLE trainer_new (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  slug TEXT NOT NULL,
  name TEXT NOT NULL,
  rank INTEGER NOT NULL DEFAULT 0,
  required_level INTEGER NOT NULL DEFAULT 0,
  cost_copper INTEGER NOT NULL DEFAULT 0,
  state TEXT NOT NULL DEFAULT 'unavailable',
  learned INTEGER NOT NULL DEFAULT 0,
  tradeskill INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL,
  UNIQUE (slug, name, rank, required_level)
);
INSERT INTO trainer_new (slug, name, rank, required_level, cost_copper, state, learned, tradeskill, updated_at)
  SELECT 'defty-graveshade', name, rank, required_level, cost_copper, state, learned, tradeskill, updated_at FROM trainer_skills;
DROP TABLE trainer_skills;
ALTER TABLE trainer_new RENAME TO trainer_skills;
