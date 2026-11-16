-- Auction house listings scanned in game by the addon: real stats, random suffixes included.
-- Shared by everyone on the same auction house; a new scan replaces the previous one.
CREATE TABLE ah_scan (
  key TEXT PRIMARY KEY,          -- itemId:suffix:itemLevel
  item_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  quality INTEGER,
  req_level INTEGER,
  slot TEXT NOT NULL,            -- inventory type without the INVTYPE_ prefix
  item_class INTEGER NOT NULL,
  subclass INTEGER NOT NULL,
  price INTEGER NOT NULL,        -- cheapest buyout, copper
  listings INTEGER NOT NULL DEFAULT 0,
  stats TEXT NOT NULL,           -- JSON: agi, str, ap, crit, hit, weapon
  scanned_at TEXT NOT NULL,
  slug TEXT NOT NULL             -- who scanned it
);

-- Experience samples from the addon, for XP per hour by zone.
CREATE TABLE xp_samples (
  slug TEXT NOT NULL,
  t INTEGER NOT NULL,            -- unix time
  xp INTEGER NOT NULL,
  level INTEGER NOT NULL,
  xp_max INTEGER NOT NULL,
  zone TEXT NOT NULL DEFAULT '',
  PRIMARY KEY (slug, t)
);

-- What the model said each time the gear or the talents changed, to hold against the
-- damage measured in the fights that followed.
CREATE TABLE model_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  slug TEXT NOT NULL,
  at TEXT NOT NULL,
  equipment_snap INTEGER,
  talents_snap INTEGER,
  model_dps REAL NOT NULL,
  level INTEGER,
  summary TEXT NOT NULL DEFAULT '',   -- what changed since the previous entry
  UNIQUE (slug, equipment_snap, talents_snap)
);
