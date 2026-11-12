-- One row per changed API response. Unchanged responses only bump last_seen_at.
CREATE TABLE snapshots (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL,            -- profile | equipment | professions | specializations | statistics
  hash TEXT NOT NULL,
  json TEXT NOT NULL,
  fetched_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL
);
CREATE INDEX idx_snapshots_kind ON snapshots (kind, id DESC);

-- Result of every sync attempt per endpoint, so failures are visible on the dashboard.
CREATE TABLE sync_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL,
  status INTEGER NOT NULL,       -- HTTP status, 0 = network/other error
  changed INTEGER NOT NULL,
  message TEXT,
  at TEXT NOT NULL
);
CREATE INDEX idx_sync_log_at ON sync_log (id DESC);

-- Things the API does not expose (gold, later bags), entered by hand or by an addon.
CREATE TABLE manual_state (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- Trainer skills read from screenshots: what can be bought and for how much.
CREATE TABLE trainer_skills (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  rank INTEGER,
  required_level INTEGER,
  cost_copper INTEGER,
  learned INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL,
  UNIQUE (name, rank)
);

CREATE TABLE kv_cache (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  expires_at INTEGER NOT NULL
);
