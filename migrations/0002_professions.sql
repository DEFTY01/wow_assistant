-- Recipe metadata the Blizzard API does not expose (skill thresholds, trainer cost).
-- Imported from the Wowhead Forever spell lists.
CREATE TABLE recipe_meta (
  spell_id INTEGER PRIMARY KEY,
  profession_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  orange INTEGER NOT NULL,       -- skill needed to learn
  yellow INTEGER NOT NULL,
  green INTEGER NOT NULL,
  grey INTEGER NOT NULL,
  creates_item INTEGER,
  creates_qty REAL NOT NULL DEFAULT 1,
  reagents TEXT NOT NULL,        -- JSON [[itemId, qty], ...]
  training_cost INTEGER,         -- copper; NULL = not taught by a trainer
  from_trainer INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL
);
CREATE INDEX idx_recipe_meta_prof ON recipe_meta (profession_id);

CREATE TABLE items (
  item_id INTEGER PRIMARY KEY,
  name TEXT,
  vendor_buy INTEGER,            -- copper, from the Blizzard item API (only trusted for known vendor reagents)
  vendor_sell INTEGER,
  api_status INTEGER,            -- last HTTP status of the Blizzard item lookup, NULL = not tried
  updated_at TEXT NOT NULL
);

CREATE TABLE prices (
  item_id INTEGER PRIMARY KEY,
  house_id INTEGER NOT NULL,
  min_price INTEGER NOT NULL,    -- cheapest unit price, copper
  depth_price INTEGER NOT NULL,  -- average unit price for the cheapest DEPTH units
  quantity INTEGER NOT NULL,     -- total units listed
  updated_at TEXT NOT NULL
);
